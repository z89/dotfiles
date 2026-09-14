from __future__ import annotations

import sys
import tempfile
import threading
import types
import unittest
from pathlib import Path
from unittest.mock import patch

import core


def payload(*, session="session-a", agent="agent-a", command="risky one", event="PreToolUse"):
    data = {
        "hook_event_name": event, "session_id": session, "agent_id": agent,
        "tool_name": "Bash", "tool_input": {"command": command}, "cwd": "/work",
    }
    if event == "UserPromptSubmit":
        data["prompt"] = command
    return data


class CoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.policy = types.SimpleNamespace(
            classify=lambda event: "changes the visible desktop" if event.get("tool_input", {}).get("command", "").startswith("risky") else None,
            bindings=lambda event: {"script": event.get("tool_input", {}).get("command", "")},
        )
        self.modules = patch.dict(sys.modules, {"policy": self.policy})
        self.modules.start()

    def tearDown(self):
        self.modules.stop()
        self.tmp.cleanup()

    def pre(self, **kwargs):
        return core.handle(payload(**kwargs), "codex", self.root)

    @staticmethod
    def code(result):
        return result["systemMessage"].split("YES DSK-", 1)[1].split()[0]

    def approve(self, code, session="session-a"):
        return core.handle(payload(session=session, command=f" YES DSK-{code} ", event="UserPromptSubmit"), "codex", self.root)

    def test_safe_work_does_not_consume_or_mismatch_pending_permit(self):
        denied = self.pre()
        code = self.code(denied)
        self.assertIsNone(self.pre(command="ordinary source edit"))
        response = self.approve(code)
        self.assertEqual(set(response), {"hookSpecificOutput"})
        self.assertEqual(response["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")
        self.assertNotIn("continue", response)
        self.assertIsNone(self.pre())
        self.assertIsNotNone(self.pre())  # one exact permit was consumed

    def test_known_safe_read_needs_no_state_or_policy(self):
        broken_root = self.root / "not-a-directory"
        broken_root.write_text("x")
        with patch.object(core, "_policy_decision", side_effect=AssertionError("should not import policy")):
            answer = core.handle({"hook_event_name": "PreToolUse", "tool_name": "Read"}, "codex", broken_root)
        self.assertIsNone(answer)

    def test_policy_exception_creates_recoverable_request_and_existing_permit_survives_it(self):
        self.policy.classify = lambda event: (_ for _ in ()).throw(NameError("FILE_TOOLS"))
        denied = self.pre()
        self.assertIn("NameError: FILE_TOOLS", denied["systemMessage"])
        code = self.code(denied)
        self.approve(code)
        self.assertIsNone(self.pre())  # policy is not imported on the exact approved retry

    def test_one_permit_has_one_concurrent_consumer(self):
        denied = self.pre()
        self.approve(self.code(denied))
        barrier = threading.Barrier(3)
        results = []

        def retry():
            barrier.wait()
            results.append(self.pre())

        first = threading.Thread(target=retry)
        second = threading.Thread(target=retry)
        first.start(); second.start(); barrier.wait(); first.join(); second.join()
        self.assertEqual(sum(result is None for result in results), 1)
        self.assertEqual(sum(result is not None for result in results), 1)

    def test_concurrent_identical_requests_share_one_pending_code(self):
        barrier = threading.Barrier(3)
        results = []

        def request():
            barrier.wait()
            results.append(self.pre(command="risky concurrent"))

        first = threading.Thread(target=request)
        second = threading.Thread(target=request)
        first.start(); second.start(); barrier.wait(); first.join(); second.join()
        codes = [self.code(result) for result in results]
        self.assertEqual(codes[0], codes[1])
        self.assertEqual(len(list((self.root / "records").glob("DSK-*.json"))), 1)

    def test_actor_and_session_are_isolated_and_parent_can_confirm(self):
        denied = self.pre(agent="child-a")
        code = self.code(denied)
        # A parent/controller confirmation has the same provider session and need not impersonate the child.
        parent_answer = self.approve(code)
        self.assertIn("approved", parent_answer["hookSpecificOutput"]["additionalContext"].lower())
        other_actor = self.pre(agent="child-b")
        self.assertIsNotNone(other_actor)
        self.assertIsNone(self.pre(agent="child-a"))

        second = self.pre(session="session-b", agent="child-c")
        wrong = self.approve(self.code(second), session="session-a")
        self.assertIn("different session", wrong["hookSpecificOutput"]["additionalContext"])

    def test_missing_actor_never_uses_session_as_approval_scope(self):
        data = payload(); data.pop("agent_id")
        answer = core.handle(data, "codex", self.root)
        code = self.code(answer)
        approved = self.approve(code)
        self.assertIn("operator recovery", approved["hookSpecificOutput"]["additionalContext"])
        self.assertIsNotNone(core.handle(data, "codex", self.root))
        saved = core.json.loads(core._record_path(core.ensure_root(self.root), f"DSK-{code}").read_text())
        self.assertTrue(saved["operator_only"])

    def test_modified_bound_script_revokes_permit_and_reissues(self):
        script = self.root / "approved-script.sh"
        script.write_text("first")
        self.policy.bindings = lambda event: {"scripts": {str(script): core.hashlib.sha256(script.read_bytes()).hexdigest()}}
        denied = self.pre(command="risky script")
        code = self.code(denied)
        self.approve(code)
        script.write_text("changed")
        replacement = self.pre(command="risky script")
        self.assertNotEqual(self.code(replacement), code)
        self.assertIn("bound script or process changed", replacement["systemMessage"])

    def test_operator_cli_run_consumes_only_approved_bash_without_real_execution(self):
        data = payload(); data.pop("agent_id")
        code = self.code(core.handle(data, "codex", self.root))
        self.approve(code)
        with patch.object(sys, "argv", ["core.py", "--root", str(self.root), "run", f"DSK-{code}"]), patch.object(core.subprocess, "run", return_value=types.SimpleNamespace(returncode=0)) as run:
            core.cli()
        run.assert_called_once_with("risky one", shell=True, executable="/bin/bash", cwd="/work", check=False)
        self.assertFalse(core._record_path(core.ensure_root(self.root), f"DSK-{code}").exists())

    def test_operator_cli_run_rejects_changed_bound_script_without_execution(self):
        script = self.root / "operator-script.sh"
        script.write_text("before")
        self.policy.bindings = lambda event: {"scripts": {str(script): core.hashlib.sha256(script.read_bytes()).hexdigest()}}
        data = payload(); data.pop("agent_id")
        code = self.code(core.handle(data, "codex", self.root))
        self.approve(code)
        script.write_text("after")
        with patch.object(sys, "argv", ["core.py", "--root", str(self.root), "run", f"DSK-{code}"]), patch.object(core.subprocess, "run") as run:
            with self.assertRaises(SystemExit):
                core.cli()
        run.assert_not_called()
        self.assertFalse(core._record_path(core.ensure_root(self.root), f"DSK-{code}").exists())

    def test_invalid_cli_code_cannot_escape_records(self):
        outside = self.root / "outside.json"
        outside.write_text("unchanged")
        with patch.object(sys, "argv", ["core.py", "--root", str(self.root), "show", "DSK-../../OUTSIDE"]):
            with self.assertRaises(SystemExit):
                core.cli()
        self.assertEqual(outside.read_text(), "unchanged")

    def test_corrupt_record_is_quarantined_without_losing_valid_records(self):
        valid = self.pre(command="risky valid")
        valid_code = self.code(valid)
        records = self.root / "records"
        (records / "DSK-ABCDEF.json").write_text("not json")
        another = self.pre(command="risky other")
        self.assertIn("quarantined malformed ledger record", another["systemMessage"])
        self.assertTrue((records / f"DSK-{valid_code}.json").exists())
        self.assertTrue(list(records.glob("DSK-ABCDEF.json.corrupt-*")))

    def test_prompt_for_unknown_or_corrupt_record_uses_prompt_shape(self):
        response = self.approve("ABCDEF")
        self.assertEqual(set(response), {"hookSpecificOutput"})
        self.assertEqual(response["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")
        self.assertNotIn("permissionDecision", response["hookSpecificOutput"])

    def test_unrelated_user_prompt_gets_action_scoped_reminder(self):
        response = core.handle(payload(command="tell me more", event="UserPromptSubmit"), "codex", self.root)
        self.assertEqual(response["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")
        self.assertIn("action-scoped", response["hookSpecificOutput"]["additionalContext"])
        self.assertIn("Safe work may continue", response["hookSpecificOutput"]["additionalContext"])

    def test_record_exposes_code_and_full_action(self):
        denied = self.pre(command="risky one; and every byte stays visible")
        code = self.code(denied)
        record = core._record_path(core.ensure_root(self.root), f"DSK-{code}")
        saved = core.json.loads(record.read_text())
        self.assertEqual(saved["request_id"], f"DSK-{code}")
        self.assertIn("every byte stays visible", saved["action"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

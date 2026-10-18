"""Headless checks for autostart workspace urgency and its patch anchor."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


TOOLING = Path(__file__).resolve().parents[1]
PATCHER = TOOLING / "bin/dms-shell-patch"
PATCH = PATCHER.read_text().split("<<'PYSTARTUP'\n", 1)[1].split("\nPYSTARTUP\n", 1)[0]
SOURCE = os.environ.get("DMS_THEME_TEST_SOURCE")


class StartupUrgencyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / "Services/CompositorService.qml"
        self.target.parent.mkdir()
        if SOURCE:
            self.target.write_text((Path(SOURCE) / "Services/CompositorService.qml").read_text())
        else:
            self.target.write_text("""    function workspaceUrgent(record, loadedUrgent) {
        switch (compositor) {
        default:
            return record?.urgent === true;
        }
    }
""")

    def patch(self):
        return subprocess.run(
            ["python3", "-", str(self.root)], input=PATCH,
            text=True, capture_output=True,
        )

    def test_startup_alerts_resume_after_focus_and_preserve_other_windows(self):
        patched = self.patch()
        self.assertEqual(patched.returncode, 0, patched.stderr)
        text = self.target.read_text()
        function = text.split("    function startupWorkspaceUrgent(record) {", 1)[1]
        function = "function startupWorkspaceUrgent(record) {" + function.split(
            "    function workspaceUrgent(record, loadedUrgent)", 1
        )[0]
        script = function + """
const assert = require('node:assert/strict');
const Hyprland = {toplevels: {values: []}};
const workspace = {id: 9, urgent: true};
const startup = {
    workspace: {id: 9}, urgent: true,
    lastIpcObject: {tags: ['startup-quiet*'], focusHistoryID: -1}
};
Hyprland.toplevels.values = [startup];
assert.equal(startupWorkspaceUrgent(workspace), false, 'quiet before first focus');
startup.lastIpcObject.tags = ['startup-quiet'];
assert.equal(startupWorkspaceUrgent(workspace), false, 'static launch tag');
startup.lastIpcObject.focusHistoryID = 0;
assert.equal(startupWorkspaceUrgent(workspace), true, 'alerts resume after focus');
startup.lastIpcObject.focusHistoryID = 7;
assert.equal(startupWorkspaceUrgent(workspace), true, 'alerts remain after leaving');
startup.lastIpcObject.focusHistoryID = -1;
const manual = {
    workspace: {id: 9}, urgent: true,
    lastIpcObject: {tags: [], focusHistoryID: -1}
};
Hyprland.toplevels.values.push(manual);
assert.equal(startupWorkspaceUrgent(workspace), true, 'other urgent window still alerts');
manual.urgent = false;
assert.equal(startupWorkspaceUrgent(workspace), false, 'nonurgent sibling does not alert');
manual.urgent = true;
manual.workspace.id = 10;
assert.equal(startupWorkspaceUrgent(workspace), false, 'other workspace is independent');
assert.equal(startupWorkspaceUrgent({id: 10, urgent: true}), true, 'manual launch alerts');
delete startup.lastIpcObject.focusHistoryID;
assert.equal(startupWorkspaceUrgent(workspace), true, 'unknown focus history preserves alert');
delete startup.lastIpcObject;
assert.equal(startupWorkspaceUrgent(workspace), true, 'unknown metadata preserves alert');
Hyprland.toplevels.values = [];
assert.equal(startupWorkspaceUrgent(workspace), true, 'unknown windows preserve alert');
assert.equal(startupWorkspaceUrgent({id: 9, urgent: false}), false, 'no invented alert');
assert.equal(startupWorkspaceUrgent(null), false, 'missing workspace');
"""
        result = subprocess.run(["node", "-"], input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('case "hyprland":\n            return startupWorkspaceUrgent(record);', text)

    def test_changed_anchor_fails_without_changing_source(self):
        original = self.target.read_text().replace(
            "function workspaceUrgent(record, loadedUrgent)",
            "function workspaceUrgent(record, loadedUrgent, changed)",
        )
        self.target.write_text(original)
        result = self.patch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing partial build", result.stderr)
        self.assertEqual(self.target.read_text(), original)


if __name__ == "__main__":
    unittest.main()

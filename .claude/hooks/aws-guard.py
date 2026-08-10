#!/usr/bin/env python3
"""PreToolUse guard: no AI session makes a state-changing AWS call.

terraform-guard.py already blocks every `apply`, `destroy` and `init`, so
infrastructure cannot be changed through terraform. This closes the other door:
the AWS CLI, which had no guard at all and could delete a bucket, close an
account or rewrite a policy in one line.

It matters most for the MANAGEMENT account, because an SCP cannot restrict the
management account. There is no AWS-side control available for it. Local
enforcement and credential scoping are the only two options that exist, and this
is the first of them.

AN ALLOW-LIST, NOT A DENY-LIST
------------------------------
Enumerating dangerous AWS commands is hopeless: there are tens of thousands of
operations and new ones ship every week. So this permits only read-shaped
operations and blocks everything else by default. A mutating API AWS releases
tomorrow is blocked on the day it ships, because it was never on the list.

The trade, stated plainly: a read-only operation with an unusual verb is blocked
until it is added here. That is the correct direction to fail.

WHAT IS ALLOWED
---------------
Operations beginning `describe-`, `list-`, `get-`, `lookup-`, `search-`,
`head-`, `batch-get-`, `estimate-`, `simulate-` or `validate-`, plus `scan`,
`query`, `select`, `help` and `wait`. `aws s3 ls`. `aws configure list|get`.

WHAT IS BLOCKED, DESPITE LOOKING LIKE A READ
--------------------------------------------
Operations that mint credentials: `sts assume-role`, `sts get-session-token`,
`ecr get-login-password`, `eks get-token`, `sso get-role-credentials` and
friends. They change nothing, but they hand back credentials that can then be
used outside this guard entirely — with curl, or a script file, or any binary
that is not `aws`. Allowing them would make the rest of this file decorative.

`aws configure set|import|sso` is blocked because it writes ~/.aws, which is
where the answer to "which account does a bare command hit" lives.

DELIBERATE LIMITS
-----------------
  * The SDK bypasses this. `python3 -c "import boto3"` reaches AWS with no `aws`
    binary involved. Inline interpreter code mentioning boto3 is blocked below,
    but a boto3 call inside a script FILE is never seen by any hook.
  * Read-only means "does not mutate", not "harmless". A read can still return
    a secret.
  * A bare `aws` command goes wherever the default profile points. That is a
    fact about ~/.aws/config, not something a hook can verify.

Only credential scoping closes all three, because it removes the permission
rather than the command.

Blocking is unconditional. There is deliberately no escape-hatch environment
variable, because an escape hatch is the first thing an agent reaches for when a
command fails. The operator runs these commands themselves.

Exit 0 = allow, exit 2 = block (stderr is returned to Claude).
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _cmdparse import invocations  # noqa: E402

BINARIES = {"aws"}

READ_PREFIXES = (
    "describe-", "list-", "get-", "lookup-", "search-", "head-",
    "batch-get-", "estimate-", "simulate-", "validate-",
)

READ_EXACT = {
    "help", "wait", "scan", "query", "select", "version",
    "decode-authorization-message", "generate-presigned-url",
}

# Match a read prefix but hand back credentials usable outside this guard.
CREDENTIAL_MINTING = {
    "get-session-token": "returns temporary credentials",
    "get-federation-token": "returns temporary credentials",
    "get-login-password": "returns a registry password",
    "get-token": "returns a cluster authentication token",
    "get-credentials": "returns credentials",
    "get-cluster-credentials": "returns database credentials",
    "get-authorization-token": "returns an authorization token",
    "get-role-credentials": "returns role credentials",
    "get-signin-token": "returns a console sign-in token",
    "get-credential-report": "returns a report of every credential in the account",
}

# Services whose command shape is not `service operation`, handled explicitly.
# Anything not listed falls through to the verb rules above.
SERVICE_RULES = {
    # High-level s3 commands are verbs in their own right; only `ls` reads.
    "s3": {"ls"},
    # `configure` writes ~/.aws, which decides where a bare command lands.
    "configure": {"list", "get", "list-profiles"},
    # `sso login`/`logout` write the credential cache.
    "sso": None,   # None = fall through to verb rules, minus credential minting
}

# Applied only to inline code handed to a non-shell interpreter, where proper
# tokenization is impossible. Confined there so it cannot fire on prose.
CODE_PATTERN = re.compile(
    r"\b(?:boto3|botocore|aiobotocore|aws-sdk|aws_sdk|@aws-sdk|aws\.config)\b",
    re.I,
)

ALLOWED_SUMMARY = (
    "Allowed: describe-*, list-*, get-*, lookup-*, search-*, head-*, "
    "batch-get-*, estimate-*, simulate-*, validate-*, plus scan, query, "
    "select, help, wait, `aws s3 ls` and `aws configure list|get`."
)


def block(reason, detail=""):
    sys.stderr.write(
        "BLOCKED by aws-guard: {}\n\n"
        "No AI session makes a state-changing AWS call, in any account, in any "
        "repository. This is a hard block with no override flag. Reads are "
        "permitted; anything that creates, changes or deletes is the operator's "
        "to run in their own terminal.\n\n"
        "{}"
        "{}\n\n"
        "If this command is genuinely read-only and was blocked anyway, say so "
        "and hand it to the operator rather than looking for another way to "
        "issue it.\n".format(reason, (detail + "\n\n") if detail else "",
                             ALLOWED_SUMMARY)
    )
    sys.exit(2)


def is_read_operation(operation):
    if operation in READ_EXACT:
        return True
    return operation.startswith(READ_PREFIXES)


# Global options that consume the following token. Without these,
# `aws --profile management s3 ls` reads `management` as the service and `s3`
# as the operation, and a plain read is blocked for no reason.
GLOBAL_VALUE_FLAGS = {
    "--profile", "--region", "--output", "--endpoint-url", "--query",
    "--ca-bundle", "--cli-read-timeout", "--cli-connect-timeout", "--color",
}


def service_and_operation(args):
    """The service and operation words, stepping over aws's global options."""
    words, index, count = [], 0, len(args)
    while index < count and len(words) < 2:
        token = args[index]
        if token in GLOBAL_VALUE_FLAGS:
            index += 2
            continue
        if token.startswith("-"):
            index += 1          # valueless flag, or --flag=value
            continue
        words.append(token.lower())
        index += 1
    service = words[0] if words else None
    operation = words[1] if len(words) > 1 else None
    return service, operation


def check_invocation(args, command):
    service, operation = service_and_operation(args)
    if service is None:
        return  # bare `aws`, or global flags only

    if operation is None:
        # `aws s3` or `aws ec2` alone prints help and calls nothing. Bare
        # `aws configure` is different: it opens an interactive prompt that
        # rewrites ~/.aws.
        if service == "configure":
            block(
                "`aws configure` rewrites ~/.aws interactively.",
                "That file decides which account a command with no --profile "
                "reaches, so it is never an agent's to change.",
            )
        return

    if operation in CREDENTIAL_MINTING:
        block(
            "`aws {} {}` {}.".format(service, operation,
                                     CREDENTIAL_MINTING[operation]),
            "It changes nothing, but the credentials it returns can be used "
            "outside this guard entirely, which would make the guard "
            "decorative. The operator runs it and supplies the result.",
        )

    if service in SERVICE_RULES:
        allowed = SERVICE_RULES[service]
        if allowed is not None:
            if operation not in allowed:
                block(
                    "`aws {} {}` is not one of the read-only `{}` "
                    "commands.".format(service, operation, service),
                    "Read-only for `{}`: {}.\n\nCommand: {}".format(
                        service, ", ".join(sorted(allowed)), command.strip()),
                )
            return

    if not is_read_operation(operation):
        block(
            "`aws {} {}` is not a read-only operation.".format(
                service, operation),
            "Command: {}".format(command.strip()),
        )


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    if data.get("tool_name", "") != "Bash":
        sys.exit(0)

    command = (data.get("tool_input", {}) or {}).get("command", "") or ""
    if not command:
        sys.exit(0)

    # Cheap pre-filter. A name like `aws_foo` does not match \baws\b because `_` is
    # a word character, so repository paths do not drag every command through the walk.
    if not re.search(r"\baws\b|\bboto3\b|\bbotocore\b", command, re.I):
        sys.exit(0)

    found, code_blobs, parsed_cleanly = invocations(command)

    for blob in code_blobs:
        if CODE_PATTERN.search(blob):
            block(
                "inline code passed to an interpreter uses the AWS SDK.",
                "A hook sees commands, not SDK calls, so it cannot tell a read "
                "from a delete here. Wrapping an AWS call in another language "
                "does not make it a different call. Hand it to the operator.",
            )

    aws_named = re.search(r"(?:^|[\s/'\"])aws(?:\s|$)", command)
    if not parsed_cleanly and aws_named:
        block(
            "the command could not be parsed safely and names `aws`.",
            "Unbalanced quoting means this guard cannot tell which operation "
            "would run, so it fails closed. Rewrite the command with balanced "
            "quotes, or hand it to the operator.",
        )

    for base, args in found:
        if base in BINARIES:
            check_invocation(args, command)

    sys.exit(0)


if __name__ == "__main__":
    main()

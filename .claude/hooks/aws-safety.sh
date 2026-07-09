#!/usr/bin/env bash
# PreToolUse hook — AWS CLI read/write safety
# Default-deny guard on the `aws` CLI: read-only and local/auth commands are
# allowed; anything that mutates live AWS infrastructure is blocked. IaC repos
# manage AWS via Terraform — the agent edits code, runs a read-only plan, and
# opens a PR; humans merge and CI applies with the privileged role.
# stdin: {"tool_name":"Bash","tool_input":{"command":"<cmd>"}}
# Exit 2 + stderr  → command blocked
# Exit 0           → command allowed (also on parse failure — fail open)

set -euo pipefail

INPUT=$(cat)

CMD=$(python3 -c "
import json, sys
try:
    payload = json.loads(sys.argv[1])
    print(payload['tool_input']['command'])
except Exception:
    sys.exit(0)
" "$INPUT") || exit 0

[ -z "${CMD:-}" ] && exit 0

block() {
    printf "BLOCKED: '%s' is forbidden by the aws-safety hook.\n" "$CMD" >&2
    printf "Only read-only AWS calls are allowed; live infrastructure must not be mutated by an AI agent. Manage AWS via Terraform: edit code, run a read-only plan, and open a PR.\n" >&2
    printf "Stop and surface this block to the user. Do not rephrase or work around it.\n" >&2
    exit 2
}

python3 -c "
import re, sys

cmd = sys.argv[1]

# Locate each 'aws' invocation. Allow a leading separator / path prefix
# (e.g. /usr/local/bin/aws) and inline env-var assignments (AWS_PROFILE=prod aws).
# group(1) is the argument string up to the next shell separator.
ANCHOR = r'(?:^|[\s;|&(])(?:\w+=\S+\s+)*(?:[^\s;|&]*/)?aws\b([^\n;|&(]*)'

# Global flags that consume the following token when given as '--flag value'.
# INVARIANT: this list must stay exhaustive. An *unrecognised* global value-flag
# in '--flag value' form shifts the parse so its value is mistaken for the
# service/operation. Here the policy is default-deny, so a shift fails safe
# (blocks) rather than allowing — but keep the list current. The '--flag=value'
# form is unaffected. Add new aws global flags here.
VALUE_FLAGS = {
    '--region', '--profile', '--output', '--endpoint-url', '--ca-bundle',
    '--cli-read-timeout', '--cli-connect-timeout', '--color', '--query',
    '--page-size', '--max-items', '--starting-token', '--cli-binary-format',
}

# Operation verb prefixes that denote a read. Matched as exact token or
# '<prefix>-...'.
READ_PREFIXES = (
    'describe', 'get', 'list', 'lookup', 'search', 'head', 'batch-get',
    'filter', 'estimate', 'simulate', 'preview', 'check', 'generate-presigned',
)
READ_EXACT = {'scan', 'query', 'select', 'wait', 'tail', 'ls'}


def service_op(args):
    toks = args.split()
    svc = op = None
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.startswith('-'):
            if t in VALUE_FLAGS and '=' not in t:
                i += 2
            else:
                i += 1
            continue
        if svc is None:
            svc = t
        elif op is None:
            op = t
            break
        i += 1
    return svc, op


def is_read(op):
    if op is None:
        return True            # no operation token — cannot mutate
    if op in READ_EXACT:
        return True
    return any(op == p or op.startswith(p + '-') for p in READ_PREFIXES)


def allowed(svc, op):
    if svc is None:
        return True            # bare 'aws' / 'aws --version'

    # Explicit local / auth carve-outs (mutating-looking verbs, no infra change)
    if svc == 'eks' and op == 'update-kubeconfig':
        return True
    if svc == 'sso' and op in ('login', 'logout'):
        return True
    if svc == 'configure':     # all configure subcommands are local
        return True
    if svc == 'help':
        return True
    if svc == 'ecr' and op == 'get-login-password':
        return True
    if svc == 'sts' and op in (
        'assume-role', 'assume-role-with-web-identity', 'assume-role-with-saml',
        'get-session-token', 'get-caller-identity', 'get-federation-token',
        'decode-authorization-message',
    ):
        return True

    # s3 high-level commands use a different verb grammar from the API verbs.
    if svc == 's3':
        return op in ('ls', 'presign') or op is None

    return is_read(op)


for m in re.finditer(ANCHOR, cmd):
    svc, op = service_op(m.group(1))
    if not allowed(svc, op):
        sys.exit(1)

sys.exit(0)
" "$CMD" 2>/dev/null || block

exit 0

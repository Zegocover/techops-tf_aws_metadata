#!/usr/bin/env bash
# PreToolUse hook — Argo CD (argocd CLI) infra-mutation safety
# Blocks any AI agent attempt to mutate live Argo CD state via the `argocd` CLI:
# triggering syncs/rollbacks, creating/deleting/editing apps, or changing
# cluster/repo/project/account admin state. The gitops workflow is: edit the
# Application/manifests in git, open a PR; humans merge and Argo CD reconciles.
# Read-only commands (get/list/diff/history/logs/...) and login/logout are
# allowed. Mutating Application CRDs via kubectl/helm is caught by those hooks.
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
    printf "BLOCKED: '%s' is forbidden by the argocd-safety hook.\n" "$CMD" >&2
    printf "Live Argo CD state must not be mutated by an AI agent. Edit the Application/manifests in git and open a PR; humans merge and Argo CD reconciles.\n" >&2
    printf "Stop and surface this block to the user. Do not rephrase or work around it.\n" >&2
    exit 2
}

python3 -c "
import re, sys

cmd = sys.argv[1]

# Locate each 'argocd' invocation. Allow a leading separator / path prefix
# (e.g. /usr/local/bin/argocd) and inline env-var assignments
# (ARGOCD_SERVER=x argocd). group(1) is the args up to the next shell separator.
ANCHOR = r'(?:^|[\s;|&(])(?:\w+=\S+\s+)*(?:[^\s;|&]*/)?argocd\b([^\n;|&(]*)'

# Global flags that consume the following token when given as '--flag value'.
# INVARIANT: this list must stay exhaustive. An *unrecognised* global value-flag
# in '--flag value' form shifts the parse so its value is mistaken for the
# group/verb — a false-allow. The '--flag=value' form is unaffected. Add new
# argocd global flags here.
VALUE_FLAGS = {
    '--server', '--auth-token', '--config', '--grpc-web-root-path',
    '--client-crt', '--client-crt-key', '--server-name',
    '--kube-context', '--logformat', '--loglevel', '--server-crt',
}


def nonflag(args):
    toks = args.split()
    out = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.startswith('-'):
            if t in VALUE_FLAGS and '=' not in t:
                i += 2
            else:
                i += 1
            continue
        out.append(t)
        i += 1
    return out


def is_mutation(toks):
    if not toks:
        return False
    group = toks[0]
    verb = toks[1] if len(toks) > 1 else None
    sub = toks[2] if len(toks) > 2 else None

    if group == 'app':
        if verb == 'actions':
            return sub == 'run'
        return verb in {
            'create', 'delete', 'set', 'unset', 'patch', 'sync', 'rollback',
            'terminate-op', 'edit',
        }
    if group in {'cluster', 'repo', 'repocreds', 'cert', 'gpg'}:
        # 'add', plus cert's 'add-tls'/'add-ssh'
        return bool(verb and (verb.startswith('add') or verb in {'rm', 'remove'}))
    if group == 'proj':
        if verb in {'create', 'delete', 'set'}:
            return True
        return bool(verb and (verb.startswith('add') or verb.startswith('remove')))
    if group == 'account':
        return verb in {'update-password', 'generate-token', 'delete-token'}
    return False


for m in re.finditer(ANCHOR, cmd):
    if is_mutation(nonflag(m.group(1))):
        sys.exit(1)

sys.exit(0)
" "$CMD" 2>/dev/null || block

exit 0

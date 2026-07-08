#!/usr/bin/env bash
# PreToolUse hook — Kubernetes (kubectl) infra-mutation safety
# Blocks any AI agent attempt to mutate live cluster state or exec into / move
# data through live workloads. The gitops workflow is: edit manifests, open a
# PR; humans merge and ArgoCD syncs. Direct mutation by the agent is never the
# workflow. Read-only and diagnostic commands are allowed.
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
    printf "BLOCKED: '%s' is forbidden by the kubernetes-safety hook.\n" "$CMD" >&2
    printf "Live cluster state must not be mutated by an AI agent. Edit manifests and open a PR; humans merge and ArgoCD syncs.\n" >&2
    printf "Stop and surface this block to the user. Do not rephrase or work around it.\n" >&2
    exit 2
}

python3 -c "
import re, sys

cmd = sys.argv[1]

# Locate each 'kubectl' invocation. Allow a leading separator / path prefix
# (e.g. /usr/local/bin/kubectl) and inline env-var assignments
# (KUBECONFIG=x kubectl). group(1) is the args up to the next shell separator.
ANCHOR = r'(?:^|[\s;|&(])(?:\w+=\S+\s+)*(?:[^\s;|&]*/)?kubectl\b([^\n;|&(]*)'

# Global flags that consume the following token when given as '--flag value'.
# INVARIANT: this list must stay exhaustive. An *unrecognised* global value-flag
# in '--flag value' form shifts the parse so its value is mistaken for the verb
# — a false-allow (e.g. 'kubectl --unknown-flag x delete pod web' parses verb
# 'x'). The '--flag=value' form is unaffected. Add new kubectl global flags here.
VALUE_FLAGS = {
    '-n', '--namespace', '--context', '--kubeconfig', '--cluster', '--user',
    '--as', '--as-group', '--as-uid', '--token', '-s', '--server',
    '--request-timeout', '--cache-dir', '--tls-server-name',
    '--client-certificate', '--client-key', '--certificate-authority',
    '--password', '--username', '--profile', '--profile-output',
}

# Verbs that mutate cluster state, or exec into / move data through workloads.
BLOCKED = {
    'apply', 'create', 'replace', 'patch', 'edit', 'set', 'delete',
    'scale', 'rollout', 'autoscale', 'cordon', 'uncordon', 'drain', 'taint',
    'annotate', 'label', 'exec', 'cp', 'port-forward', 'attach', 'debug',
    'run', 'expose', 'proxy',
}


def verb(args):
    toks = args.split()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.startswith('-'):
            if t in VALUE_FLAGS and '=' not in t:
                i += 2
            else:
                i += 1
            continue
        return t
    return None


# Dry-run carve-out: an otherwise-blocked verb is a no-op under --dry-run
# (client/server, or bare). '--dry-run=none' is NOT a carve-out — it applies.
# Evaluated per-invocation against the matched arg segment so a dry-run in one
# kubectl call cannot exempt a later mutating kubectl call in the same compound
# command (e.g. 'kubectl apply --dry-run=client && kubectl delete pod web').
for m in re.finditer(ANCHOR, cmd):
    args = m.group(1)
    dry_run = bool(re.search(r'--dry-run(=(client|server))?(?=\s|$)', args))
    v = verb(args)
    if v in BLOCKED and not dry_run:
        sys.exit(1)

sys.exit(0)
" "$CMD" 2>/dev/null || block

exit 0

#!/usr/bin/env bash
# PreToolUse hook — Helm release-mutation safety
# Blocks any AI agent attempt to install/upgrade/uninstall/rollback a release
# into a live cluster, or push a chart to a remote registry. The gitops
# workflow is: edit chart/values, open a PR; humans merge and ArgoCD syncs.
# Read-only and local commands (template/lint/diff/repo/dependency/...) are
# allowed.
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
    printf "BLOCKED: '%s' is forbidden by the helm-safety hook.\n" "$CMD" >&2
    printf "Live releases must not be mutated by an AI agent. Edit chart/values and open a PR; humans merge and ArgoCD syncs.\n" >&2
    printf "Stop and surface this block to the user. Do not rephrase or work around it.\n" >&2
    exit 2
}

python3 -c "
import re, sys

cmd = sys.argv[1]

# Locate each 'helm' invocation. Allow a leading separator / path prefix
# (e.g. /usr/local/bin/helm) and inline env-var assignments
# (HELM_NAMESPACE=x helm). group(1) is the args up to the next shell separator.
ANCHOR = r'(?:^|[\s;|&(])(?:\w+=\S+\s+)*(?:[^\s;|&]*/)?helm\b([^\n;|&(]*)'

# Global flags that consume the following token when given as '--flag value'.
# INVARIANT: this list must stay exhaustive. An *unrecognised* global value-flag
# in '--flag value' form shifts the parse so its value is mistaken for the verb
# — a false-allow. The '--flag=value' form is unaffected. Add new helm global
# flags here.
VALUE_FLAGS = {
    '-n', '--namespace', '--kube-context', '--kubeconfig', '--kube-apiserver',
    '--kube-token', '--kube-as-user', '--registry-config',
    '--repository-config', '--repository-cache', '--burst-limit',
}

# Verbs that mutate live releases or write to a remote registry.
BLOCKED = {'install', 'upgrade', 'uninstall', 'delete', 'rollback', 'push'}


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


# Dry-run carve-out: install/upgrade under --dry-run mutate nothing.
# Evaluated per-invocation against the matched arg segment so a dry-run in one
# helm call cannot exempt a later mutating helm call in the same compound
# command (e.g. 'helm upgrade rel chart --dry-run && helm uninstall rel').
for m in re.finditer(ANCHOR, cmd):
    args = m.group(1)
    dry_run = bool(re.search(r'--dry-run(=(client|server))?(?=\s|$)', args))
    v = verb(args)
    if v in BLOCKED and not dry_run:
        sys.exit(1)

sys.exit(0)
" "$CMD" 2>/dev/null || block

exit 0

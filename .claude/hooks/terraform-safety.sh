#!/usr/bin/env bash
# PreToolUse hook — Terraform / IaC infra-mutation safety
# Blocks any AI agent attempt to mutate live infrastructure or trigger remote
# pipelines from inside an infrastructure-as-code repo. The agent workflow is:
# edit code, run a read-only plan, open a PR — humans merge and CI applies with
# the privileged role. Direct mutation by the agent is never the workflow.
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
    printf "BLOCKED: '%s' is forbidden by the terraform-safety hook.\n" "$CMD" >&2
    printf "Live infrastructure must not be mutated by an AI agent. Edit code, run a read-only plan, and open a PR; humans merge and CI applies.\n" >&2
    printf "Stop and surface this block to the user. Do not rephrase or work around it.\n" >&2
    exit 2
}

python3 -c "
import re, sys

cmd = sys.argv[1]

# Terraform / OpenTofu / Terragrunt mutating subcommands. Allow global flags
# (e.g. '-chdir=DIR') between the binary and the verb — 'terraform -chdir=env
# apply' is the usual invocation in these repos.
tf = r'(terraform|terragrunt|tofu)'
if re.search(rf'\b{tf}\s+(-\S+\s+)*(apply|destroy|import|taint|untaint|force-unlock)\b', cmd):
    sys.exit(1)
if re.search(rf'\b{tf}\s+(-\S+\s+)*state\s+(rm|push|replace-provider|mv)\b', cmd):
    sys.exit(1)

# Makefile shortcuts that wrap the above. Match the target anywhere after
# 'make' (so 'make WORKSPACE=staging apply' is caught) but stop at a command
# separator so 'make plan && echo apply' is not.
if re.search(r'\bmake\b[^|;&\n]*\b(apply|destroy)\b', cmd):
    sys.exit(1)

# Buildkite agent triggering — only the pipeline itself should call this.
if re.search(r'\bbuildkite-agent\s+(pipeline|annotate|artifact\s+upload|meta-data\s+set)\b', cmd):
    sys.exit(1)

# GitHub Actions: starting workflows, or mutating via the API (an explicit
# method, or field flags — which make 'gh api' a POST).
if re.search(r'\bgh\s+workflow\s+run\b', cmd):
    sys.exit(1)
if re.search(r'\bgh\s+api\b', cmd):
    # Exempt a SINGLE, un-chained gh api call whose endpoint argument is a
    # PR/issue comments|reviews discussion endpoint, even though it carries a
    # mutating method or field flag — these are discussion surfaces, not infra
    # mutation or pipeline triggering. The pattern anchors the WHOLE command
    # (re.match ... $) and its tail permits only space/tab-separated flags,
    # rejecting shell command separators, redirects, process substitution and
    # newlines, so a second command cannot ride along. Every mutating or
    # pipelined gh api call (dispatches, workflow runs, PR merges, branch
    # protection, issue creation) falls through to the method/field blocks
    # below.
    if re.match(
        r'\s*gh\s+api\s+/?repos/[^/\s]+/[^/\s]+/'
        r'(?:pulls|issues)/[^\s?#]*?(?:comments|reviews)(?:/\d+)?'
        r'(?:[ \t]+[^;&|\`$<>()\r\n]*)?$', cmd):
        sys.exit(0)
    if re.search(r'(?i)(-X|--method)(\s+|=)(POST|PATCH|PUT|DELETE)\b', cmd):
        sys.exit(1)
    if re.search(r'(^|\s)(-f|-F|--field|--raw-field|--input)(\s|=)', cmd):
        sys.exit(1)

sys.exit(0)
" "$CMD" 2>/dev/null || block

exit 0

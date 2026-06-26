#!/usr/bin/env bash
# pr-label.sh — ensure repo labels exist and apply them to a PR.
#
# Usage:
#   .claude/scripts/pr-label.sh <pr-ref> <label> [<label> ...]
#
# <pr-ref> is the PR target — a branch, PR number, or PR URL (gh pr edit
# accepts any of these interchangeably as its first positional). Callers
# that already hold the PR URL should pass it to avoid a branch->PR lookup.
#
# The script:
#   1. Validates inputs (a PR target and at least one label name).
#   2. For each label, ensures the repo label exists by its exact name
#      (gh label create --force — create if absent, update if present)
#      using one shared ai-* colour constant and one generic description.
#   3. Adds each label to the PR identified by <pr-ref> (gh pr edit --add-label).
#
# Why this script vs a raw `gh label`/`gh pr edit`:
#   - One allowlist entry covers the "label a skill-created PR" intent.
#   - gh flags are hardcoded — the agent can't inject --force-style PR
#     flags, --draft, credentials, or environment-variable references.
#   - The "never block a PR" resilience lives in one place, shared by
#     both PR-opening paths (create-pr and req-pr.sh).
#
# Resilience (load-bearing):
#   - Every `gh` invocation is wrapped so a non-zero status does not abort
#     the script. A label that cannot be created or applied degrades to a
#     warning, never a failure.
#   - The script always exits 0 for every runtime `gh` outcome, so a
#     label step can never block PR creation.
#
# Safety:
#   - gh flags are hardcoded — no --force-style PR flags, no --draft.
#   - A `--` end-of-options separator precedes the label/pr-ref positionals
#     so a value beginning with `-` is never parsed as a flag.
#   - No credentials, no environment-variable references.
#   - Mirrors req-pr.sh's safety model and validation-exit convention.
#
# Exit codes:
#   0  every label outcome handled (applied, or gh failed and was tolerated)
#   2  malformed call — missing PR target, or zero label arguments

set -uo pipefail

# Shared ai-* family styling. One colour and one generic description for
# every label this script is given — re-runs update idempotently via
# --force and do not churn styling. Do not assign per-label colours.
readonly AI_LABEL_COLOUR="5319e7"
readonly AI_LABEL_DESCRIPTION="Opened by a Zego AI standards skill"

# --- Input validation (caller bug — not retryable) ---

if [[ $# -lt 1 ]]; then
  echo "pr-label: missing PR target argument" >&2
  echo "usage: pr-label.sh <pr-ref> <label> [<label> ...]" >&2
  exit 2
fi

PR_REF="$1"
shift

if [[ -z "$PR_REF" ]]; then
  echo "pr-label: PR target argument is empty" >&2
  echo "usage: pr-label.sh <pr-ref> <label> [<label> ...]" >&2
  exit 2
fi

if [[ $# -lt 1 ]]; then
  echo "pr-label: no label arguments" >&2
  echo "usage: pr-label.sh <pr-ref> <label> [<label> ...]" >&2
  exit 2
fi

# --- Ensure and apply each label independently ---
#
# Each label is handled on its own: a failure ensuring or applying one
# label does not stop the others. All gh outcomes are tolerated.

for label in "$@"; do
  # Ensure the label exists by its exact name. --force creates it if
  # absent and updates it idempotently if present.
  if gh label create \
      --color "$AI_LABEL_COLOUR" \
      --description "$AI_LABEL_DESCRIPTION" \
      --force -- "$label" >/dev/null 2>&1; then
    echo "ensured $label" >&2
  else
    echo "warning: could not ensure label $label — continuing" >&2
  fi

  # Apply the label to the PR. Tolerate failure (e.g. the label is still
  # absent, or the PR cannot be edited) — the PR is simply left unlabelled.
  if gh pr edit --add-label "$label" -- "$PR_REF" >/dev/null 2>&1; then
    echo "applied $label" >&2
  else
    echo "warning: could not apply $label — PR left unlabelled" >&2
  fi
done

exit 0

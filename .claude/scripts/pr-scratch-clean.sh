#!/usr/bin/env bash
# pr-scratch-clean.sh — remove this run's PR reply-draft scratch files.
#
# Usage:
#   .claude/scripts/pr-scratch-clean.sh <pr-number>
#
# Removes `{pr-number}-*.md` from BOTH scratch locations —
# `/tmp/_replies/` (the normal-operation dir) and
# `<repo>/.claude/scripts/_replies/` (the FR-05 fallback dir). The
# glob is prefix-scoped to the supplied PR number, so a concurrent
# run on a different PR is never touched.
#
# Companion to `pr-scratch-write.sh`; run once per `zego-fix-pr-comments`
# run in Stage 11 cleanup.
#
# Safety:
#   - PR number validated as digits-only; the glob is
#     `{pr-number}-*.md` — never an unscoped `*`.
#   - Fallback dir resolved from `git rev-parse --show-toplevel`, so it
#     is correct even where `.claude/scripts` is a symlink.
#   - Absent dirs / no-matching-files are not errors (`rm -f`
#     semantics) — cleanup after a run that never used the fallback
#     still exits 0.
#   - Diagnostics go to stderr.
#
# Environment overrides (for tests only):
#   - PR_SCRATCH_TMP_DIR — overrides the `/tmp/_replies` primary dir
#     (must match the value used by pr-scratch-write.sh in the run).
#
# Exit codes:
#   0  cleanup done (including when nothing matched)
#   2  validation failed (missing arg or non-digit PR number)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: pr-scratch-clean.sh <pr-number>" >&2
  exit 2
fi

PR_NUM="$1"

if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
  echo "pr-scratch-clean: invalid pr-number '$PR_NUM' (digits only)" >&2
  exit 2
fi

TMP_DIR="${PR_SCRATCH_TMP_DIR:-/tmp/_replies}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
FALLBACK_DIR="$REPO_ROOT/.claude/scripts/_replies"

# Prefix-scoped removal from both dirs. Skip a dir that does not exist
# (or is not a directory) so a run that never used the fallback — or a
# `/tmp/_replies` that was never created — is not an error. `rm -f`
# treats a no-match glob as success, so an existing-but-empty dir is
# fine too. The glob is `{PR}-*.md`, never a bare `*`, so another PR's
# drafts are always spared (FR-03).
for dir in "$TMP_DIR" "$FALLBACK_DIR"; do
  [[ -d "$dir" ]] || continue
  rm -f "$dir/${PR_NUM}"-*.md
done

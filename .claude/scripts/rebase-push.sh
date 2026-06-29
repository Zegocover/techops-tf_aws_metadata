#!/usr/bin/env bash
# rebase-push.sh — update a rebased branch on origin with --force-with-lease.
#
# Usage:
#   .claude/scripts/rebase-push.sh <branch>
#
# A rebase rewrites history, so the branch must be force-pushed. This script
# uses --force-with-lease, which REFUSES the push if origin/<branch> has moved
# since you last fetched (i.e. someone else pushed in the meantime) — so you
# never silently clobber commits you haven't seen.
#
# Why this script instead of a raw `git push --force-with-lease`:
#   - One allowlist entry per intent. The push shape is hardcoded, so an agent
#     cannot substitute a bare `--force`/`-f` or push to a different remote via
#     argument injection.
#   - Protected branches (main, master, production, staging, release/*) are
#     refused here as defence-in-depth, independent of the git-safety hook.
#   - The branch argument is cross-checked against the current branch, so a
#     confused caller cannot force-push some other branch.
#
# Exit codes:
#   0  pushed successfully
#   2  invalid branch name, or branch is protected (refused)
#   3  branch argument does not match the current branch (refused)
#   *  git push failed (e.g. stale lease — origin moved); git's stderr is shown

set -euo pipefail

BRANCH="${1:?usage: rebase-push.sh <branch>}"

# Branch names start with an alphanumeric and otherwise use ref punctuation
# (/ . _ -). Reject anything else (spaces, shell-metachar payloads).
if ! [[ "$BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
  echo "rebase-push: invalid branch name '$BRANCH'" >&2
  exit 2
fi

# Never force-push a protected branch. The git-safety hook also blocks this;
# refusing here as well means the script is safe even if the hook is absent.
case "$BRANCH" in
  main|master|production|staging|release/*)
    echo "rebase-push: refusing to force-push protected branch '$BRANCH'" >&2
    exit 2
    ;;
esac

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "$CURRENT_BRANCH" ]]; then
  echo "rebase-push: branch '$BRANCH' does not match the current branch '$CURRENT_BRANCH'" >&2
  echo "  check out the branch you intend to push, or pass the current branch name" >&2
  exit 3
fi

# Hardcoded push shape: always --force-with-lease, always origin, current
# branch only. The default lease checks that origin/<branch> has not moved
# since the last fetch. Do NOT fetch first — that would refresh the lease and
# defeat the safety check.
git push --force-with-lease origin "$BRANCH"

#!/usr/bin/env bash
# req-pr.sh — commit the requirements package, push, and open a PR.
#
# Usage:
#   .claude/scripts/req-pr.sh <ticket> <requirements-file> <body-file> <commit-msg-file>
#
# The script:
#   1. Validates inputs.
#   2. Stages the requirements file.
#   3. Commits with the message from <commit-msg-file>.
#   4. Pushes the current branch to origin.
#   5. Opens a PR via gh pr create (or reports the existing PR if one
#      is already open for the branch).
#
# The PR body comes from <body-file>, which the skill writes to a temp
# file before calling this script — same pattern as pr-reply.sh.
#
# Why this script vs raw `gh pr create`:
#   - One allowlist entry covers the "publish requirements and open PR"
#     intent, instead of a wildcard on `gh` or `git push`.
#   - Body via file — no shell metachar escaping issues.
#   - gh pr create flags are hardcoded — the agent can't inject --force
#     or --draft.
#   - Requirements file path is restricted to docs/requirements/ so the
#     agent can't commit arbitrary files.
#
# Safety:
#   - Ticket validated as PROJ-123 format.
#   - Requirements file must exist and live under docs/requirements/.
#   - Requirements file symlink rejection (same reasoning as pr-reply.sh
#     body-file check).
#   - Body-file symlink rejection, path restriction, size cap (same
#     checks as pr-reply.sh).
#   - Commit-message-file symlink rejection and path restriction.
#   - Refuses to commit or push on main/master or detached HEAD.
#   - No force-push, no --force, no --draft.
#   - If an open PR already exists for the branch, pushes the commit
#     and reports the existing PR URL rather than failing.
#
# Exit codes:
#   0  committed, pushed, and PR created (or existing PR updated)
#   2  validation failed (input is malformed; do not retry)
#   *  any other failure propagates git/gh exit code unchanged

set -euo pipefail

TICKET="${1:?usage: req-pr.sh <ticket> <requirements-file> <body-file> <commit-msg-file>}"
REQ_FILE="${2:?usage: req-pr.sh <ticket> <requirements-file> <body-file> <commit-msg-file>}"
BODY_FILE="${3:?usage: req-pr.sh <ticket> <requirements-file> <body-file> <commit-msg-file>}"
COMMIT_MSG_FILE="${4:?usage: req-pr.sh <ticket> <requirements-file> <body-file> <commit-msg-file>}"

# --- Input validation ---

if ! [[ "$TICKET" =~ ^[A-Z]+-[0-9]+$ ]]; then
  echo "req-pr: invalid ticket '$TICKET' (expected PROJ-123 format)" >&2
  exit 2
fi

if [[ ! -f "$REQ_FILE" ]]; then
  echo "req-pr: requirements file '$REQ_FILE' not found" >&2
  exit 2
fi

# Reject symlinks — same reasoning as pr-reply.sh's body-file check.
# A symlink at docs/requirements/PROJ-123-foo.md -> /etc/passwd would
# pass the prefix check (pwd -P only canonicalises the directory) and
# git add would follow it, committing the target's contents.
if [[ -L "$REQ_FILE" ]]; then
  echo "req-pr: requirements file '$REQ_FILE' is a symlink; refusing to commit" >&2
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Requirements file must be under docs/requirements/ to prevent the
# agent from committing arbitrary files via this script.
REQ_REAL="$(cd "$(dirname "$REQ_FILE")" && pwd -P)/$(basename "$REQ_FILE")"
if [[ "$REQ_REAL" != "$REPO_ROOT/docs/requirements/"* ]]; then
  echo "req-pr: requirements file '$REQ_REAL' is not under docs/requirements/" >&2
  exit 2
fi

# --- Body-file validation (mirrors pr-reply.sh) ---

if [[ ! -f "$BODY_FILE" ]]; then
  echo "req-pr: body file '$BODY_FILE' not found" >&2
  exit 2
fi

if [[ -L "$BODY_FILE" ]]; then
  echo "req-pr: body file '$BODY_FILE' is a symlink; refusing to resolve" >&2
  exit 2
fi

BODY_REAL="$(cd "$(dirname "$BODY_FILE")" && pwd -P)/$(basename "$BODY_FILE")"
if [[ -d "$REPO_ROOT/.claude/scripts/_replies" ]]; then
  REPLIES_REAL="$(cd "$REPO_ROOT/.claude/scripts/_replies" && pwd -P)"
else
  REPLIES_REAL="$REPO_ROOT/.claude/scripts/_replies"
fi

# Allowed body-file locations (same set as pr-reply.sh):
#   - /tmp/                        — scratch space the agent can write
#   - /private/tmp/                — same path on macOS (symlink target)
#   - <repo>/.git/                 — git's own scratch dir
#   - <repo>/.claude/scripts/_replies/     — durable per-repo scratch dir
# REPLIES_REAL is the symlink-resolved form; accepted for repos where
# .claude/scripts is a symlink (e.g. this standards library repo).
if [[ "$BODY_REAL" != /tmp/* \
   && "$BODY_REAL" != /private/tmp/* \
   && "$BODY_REAL" != "$REPO_ROOT/.git/"* \
   && "$BODY_REAL" != "$REPO_ROOT/.claude/scripts/_replies/"* \
   && "$BODY_REAL" != "$REPLIES_REAL/"* ]]; then
  echo "req-pr: body file '$BODY_REAL' is outside the allowed set" >&2
  echo "  allowed: /tmp/*, /private/tmp/*, $REPO_ROOT/.git/*, $REPO_ROOT/.claude/scripts/_replies/*" >&2
  exit 2
fi

BODY_SIZE="$(wc -c < "$BODY_FILE")"
if (( BODY_SIZE > 65000 )); then
  echo "req-pr: body file '$BODY_FILE' is ${BODY_SIZE} bytes, refusing (limit ~65 000 bytes)" >&2
  exit 2
fi

# --- Commit-message-file validation ---

if [[ ! -f "$COMMIT_MSG_FILE" ]]; then
  echo "req-pr: commit message file '$COMMIT_MSG_FILE' not found" >&2
  exit 2
fi

if [[ -L "$COMMIT_MSG_FILE" ]]; then
  echo "req-pr: commit message file '$COMMIT_MSG_FILE' is a symlink; refusing to resolve" >&2
  exit 2
fi

COMMIT_MSG_REAL="$(cd "$(dirname "$COMMIT_MSG_FILE")" && pwd -P)/$(basename "$COMMIT_MSG_FILE")"

if [[ "$COMMIT_MSG_REAL" != /tmp/* \
   && "$COMMIT_MSG_REAL" != /private/tmp/* \
   && "$COMMIT_MSG_REAL" != "$REPO_ROOT/.git/"* \
   && "$COMMIT_MSG_REAL" != "$REPO_ROOT/.claude/scripts/_replies/"* \
   && "$COMMIT_MSG_REAL" != "$REPLIES_REAL/"* ]]; then
  echo "req-pr: commit message file '$COMMIT_MSG_REAL' is outside the allowed set" >&2
  exit 2
fi

COMMIT_MSG_SIZE="$(wc -c < "$COMMIT_MSG_FILE")"
if (( COMMIT_MSG_SIZE > 8000 )); then
  echo "req-pr: commit message file '$COMMIT_MSG_FILE' is ${COMMIT_MSG_SIZE} bytes, refusing (limit ~8 000 bytes)" >&2
  exit 2
fi

# --- Pre-flight checks ---

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "req-pr: detached HEAD state — switch to a branch first" >&2
  exit 2
fi
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  echo "req-pr: refusing to commit and push on '$CURRENT_BRANCH'" >&2
  exit 2
fi

# --- Commit ---

git add "$REQ_FILE"

# If nothing to commit (file already committed on a prior run that
# failed at push or PR creation), skip the commit and proceed to push.
# This makes the script idempotent for the push+PR step.
if git diff --cached --quiet; then
  echo "req-pr: no new changes to commit — proceeding to push"
else
  git commit -F "$COMMIT_MSG_FILE"
fi

# --- Push ---

git push -u origin "$CURRENT_BRANCH"

# --- Create PR (or report existing) ---

EXISTING_PR="$(gh pr list --head "$CURRENT_BRANCH" --state open --json url -q '.[0].url' 2>/dev/null || true)"

if [[ -n "$EXISTING_PR" ]]; then
  echo "Pushed to existing PR: $EXISTING_PR"
else
  DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"

  PR_URL="$(gh pr create \
    --title "${TICKET}: Add requirements package" \
    --base "$DEFAULT_BRANCH" \
    --body-file "$BODY_FILE")"

  echo "$PR_URL"
fi

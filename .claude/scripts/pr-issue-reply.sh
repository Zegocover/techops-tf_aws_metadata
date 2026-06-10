#!/usr/bin/env bash
# pr-issue-reply.sh — post a top-level issue comment to a PR.
#
# Usage:
#   .claude/scripts/pr-issue-reply.sh <pr-number> <body-file>
#
# Body comes from a file rather than stdin or a literal arg so the
# agent can use `Write` to compose the response (preserving newlines,
# markdown, code fences) and the script doesn't need to escape
# shell-metachar payloads at all.
#
# Why this script vs `gh api`:
#   - One allowlist entry per intent.
#   - Body via file → never touches the shell parser.
#   - Hardcoded API path shape — agent can't pivot to a different
#     endpoint by injecting into args.
#
# Why a separate script from pr-reply.sh:
#   - pr-reply.sh posts to `pulls/{pr}/comments` with `in_reply_to`
#     (review comment replies, threaded).
#   - This script posts to `issues/{pr}/comments` (top-level PR
#     conversation comments, flat — no threading or `in_reply_to`).
#   - One-script-one-API-path keeps the allowlist semantics clean.
#
# Safety:
#   - PR number validated as digits-only.
#   - Body-file existence checked, capped at 64KiB.
#   - Body-file symlink rejection — refuses symlinks regardless of
#     target, preventing the `pwd -P` basename bypass where a
#     symlink at `/tmp/evil -> /etc/passwd` would pass the path-
#     prefix check and leak the target's contents.
#   - Body-file path restricted to safe locations (`/tmp/`, repo's
#     `.git/`, repo's `.claude/scripts/_replies/`) so the agent
#     can't read e.g. `~/.ssh/id_rsa` and post it as a comment.
#   - PR number cross-checked against the current branch's open PR;
#     mismatch exits 3 (a distinct, agent-recoverable code) so the
#     caller can confirm with the user instead of silently posting
#     to the wrong PR.
#   - `set -u` turns missing args into errors.
#
# Exit codes:
#   0  posted successfully
#   2  validation failed (input is malformed; do not retry)
#   3  PR-number / branch mismatch (caller should confirm with user)
#   *  any other failure propagates `gh`'s exit code unchanged

set -euo pipefail

PR_NUM="${1:?usage: pr-issue-reply.sh <pr-number> <body-file>}"
BODY_FILE="${2:?usage: pr-issue-reply.sh <pr-number> <body-file>}"

if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
  echo "pr-issue-reply: invalid pr-number '$PR_NUM' (digits only)" >&2
  exit 2
fi

if [[ ! -f "$BODY_FILE" ]]; then
  echo "pr-issue-reply: body file '$BODY_FILE' not found" >&2
  exit 2
fi

# Reject symlinks outright. `pwd -P` only canonicalises the
# *directory* part of the path, so a symlink at the basename
# (e.g. `/tmp/evil -> /etc/passwd`) would otherwise pass the
# /tmp/* prefix check and then leak the symlink target's contents
# through `< "$BODY_FILE"`. The reply scratch flow never legitimately
# needs symlinks, so refusing them is the simplest portable fix.
if [[ -L "$BODY_FILE" ]]; then
  echo "pr-issue-reply: body file '$BODY_FILE' is a symlink; refusing to resolve" >&2
  exit 2
fi

# Resolve to an absolute path so the prefix check below isn't fooled
# by `..` traversal.
BODY_REAL="$(cd "$(dirname "$BODY_FILE")" && pwd -P)/$(basename "$BODY_FILE")"
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [[ -d "$REPO_ROOT/.claude/scripts/_replies" ]]; then
  REPLIES_REAL="$(cd "$REPO_ROOT/.claude/scripts/_replies" && pwd -P)"
else
  REPLIES_REAL="$REPO_ROOT/.claude/scripts/_replies"
fi

# Allowed body-file locations:
#   - /tmp/                        — scratch space the agent can write
#   - /private/tmp/                — same path on macOS (symlink target)
#   - <repo>/.git/                 — git's own scratch dir, always
#                                    inside the repo
#   - <repo>/.claude/scripts/_replies/     — durable per-repo scratch dir
#                                    the skill writes into
# REPLIES_REAL is the symlink-resolved form of .claude/scripts/_replies/
# and is also accepted so the check works in repos where .claude/scripts
# is a symlink (e.g. this standards library repo).
# Anything outside these is refused. Catches the "agent reads
# ~/.ssh/id_rsa as a body" failure mode without blocking the
# legitimate workflows. macOS resolves /tmp -> /private/tmp via
# symlink, so pwd -P returns the /private/tmp form; allow both.
if [[ "$BODY_REAL" != /tmp/* \
   && "$BODY_REAL" != /private/tmp/* \
   && "$BODY_REAL" != "$REPO_ROOT/.git/"* \
   && "$BODY_REAL" != "$REPO_ROOT/.claude/scripts/_replies/"* \
   && "$BODY_REAL" != "$REPLIES_REAL/"* ]]; then
  echo "pr-issue-reply: body file '$BODY_REAL' is outside the allowed set" >&2
  echo "  allowed: /tmp/*, /private/tmp/*, $REPO_ROOT/.git/*, $REPO_ROOT/.claude/scripts/_replies/*" >&2
  exit 2
fi

# Sanity: refuse a body file > 64KiB. GitHub's comment limit
# is 65535 bytes; if the agent has produced more than that, something
# is wrong (a leaked transcript, a paste of the whole PR diff, etc.)
# and we'd rather error than truncate or post nonsense.
BODY_SIZE="$(wc -c < "$BODY_FILE")"
if (( BODY_SIZE > 65000 )); then
  echo "pr-issue-reply: body file '$BODY_FILE' is ${BODY_SIZE} bytes, refusing to post (limit ~65 000 bytes)" >&2
  exit 2
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# Cross-check that the PR number matches the current branch's open
# PR. Mismatch is exit 3 — distinct from validation (2) so the
# caller can decide to confirm with the user rather than abort. We
# don't refuse outright because the agent might legitimately want
# to comment on a different PR (e.g. cross-referencing a fix in a
# stacked PR), but it should be a deliberate, confirmed action.
#
# "No open PR for current branch" is also exit 3, not 0: scripted
# replies don't make sense from a branch without a PR (the typical
# wrong case is the agent on `main` with a stale PR number it
# half-remembers). The caller can still proceed if the user
# explicitly confirms.
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
EXPECTED_PR="$(gh pr list --head "$CURRENT_BRANCH" --state open --json number -q '.[0].number' 2>/dev/null || true)"
if [[ -z "$EXPECTED_PR" ]]; then
  echo "pr-issue-reply: current branch '$CURRENT_BRANCH' has no open PR" >&2
  echo "  refusing to post to PR #$PR_NUM without an explicit branch context;" >&2
  echo "  switch to the branch whose PR you want to comment on, or confirm with the user" >&2
  exit 3
fi
if [[ "$EXPECTED_PR" != "$PR_NUM" ]]; then
  echo "pr-issue-reply: pr-number '$PR_NUM' does not match current branch '$CURRENT_BRANCH' (expected PR #$EXPECTED_PR)" >&2
  echo "  re-run with the correct PR number, or confirm with the user that you intend to comment on a different PR" >&2
  exit 3
fi

# Post via stdin (--field body=@-) so the body content never gets
# parsed by the shell. Issue comments are flat — no in_reply_to.
gh api \
  "repos/${REPO}/issues/${PR_NUM}/comments" \
  -X POST \
  --field body=@- \
  < "$BODY_FILE"

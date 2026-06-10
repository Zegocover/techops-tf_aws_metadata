#!/usr/bin/env bash
# pr-resolve.sh — mark a PR review thread as resolved.
#
# Usage:
#   .claude/scripts/pr-resolve.sh <thread-id> <pr-number>
#
# `<thread-id>` is the GraphQL node id (e.g. `PRRT_kwDOSFazsM5-gFO8`),
# *not* the REST comment id. `pr-comments.sh` returns it as
# `thread_id` on each entry; pass that value through verbatim.
#
# `<pr-number>` is the PR number the thread belongs to. It is
# cross-checked against the open PR for the current branch — if they
# don't match, the script exits 3 (same semantics as `pr-reply.sh`)
# so a confused agent can't silently resolve a thread on the wrong PR.
#
# Why this script vs `gh api graphql`:
#   - One allowlist entry per intent.
#   - The mutation shape is hardcoded — agent can't substitute a
#     different mutation (e.g. `unresolveReviewThread`,
#     `addPullRequestReview`) via arg injection.
#
# Safety:
#   - Thread id validated as `^[A-Za-z0-9_-]+$` (the character class
#     GitHub's base64-ish node ids actually use).
#   - PR number validated as digits-only.
#   - PR number cross-checked against the current branch's open PR
#     (exit 3 on mismatch, matching `pr-reply.sh` behaviour).

set -euo pipefail

THREAD_ID="${1:?usage: pr-resolve.sh <thread-id> <pr-number>}"
PR_NUM="${2:?usage: pr-resolve.sh <thread-id> <pr-number>}"

# GitHub node ids are base64-shaped — letters, digits, underscore,
# dash. Anything else means the agent passed in junk (or shell-
# metachar payload) and we should bail.
if ! [[ "$THREAD_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "pr-resolve: invalid thread-id '$THREAD_ID' (alphanumeric / _ / - only)" >&2
  exit 2
fi

if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
  echo "pr-resolve: invalid pr-number '$PR_NUM' (digits only)" >&2
  exit 2
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
EXPECTED_PR="$(gh pr list --head "$CURRENT_BRANCH" --state open --json number -q '.[0].number' 2>/dev/null || true)"
if [[ -z "$EXPECTED_PR" ]]; then
  echo "pr-resolve: current branch '$CURRENT_BRANCH' has no open PR" >&2
  echo "  refusing to resolve thread without an explicit branch context;" >&2
  echo "  switch to the branch whose PR you want to resolve a thread on, or confirm with the user" >&2
  exit 3
fi
if [[ "$EXPECTED_PR" != "$PR_NUM" ]]; then
  echo "pr-resolve: pr-number '$PR_NUM' does not match current branch '$CURRENT_BRANCH' (expected PR #$EXPECTED_PR)" >&2
  echo "  re-run with the correct PR number, or confirm with the user that you intend to resolve a thread on a different PR" >&2
  exit 3
fi

gh api graphql \
  -f query='
    mutation($threadId: ID!) {
      resolveReviewThread(input: { threadId: $threadId }) {
        thread { isResolved }
      }
    }
  ' \
  -F threadId="$THREAD_ID" \
  --jq '
    if ((.errors // []) | length) > 0
    then error("pr-resolve: GraphQL error: \(.errors[0].message)")
    elif .data.resolveReviewThread.thread.isResolved
    then true
    else error("pr-resolve: thread was not marked resolved (locked, already-unresolvable, or transient API failure)")
    end
  '

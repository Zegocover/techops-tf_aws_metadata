#!/usr/bin/env bash
# pr-comments.sh — fetch all PR feedback: unresolved review threads,
# top-level PR conversation comments, and PR review body text.
#
# Usage:
#   .claude/scripts/pr-comments.sh <pr-number>
#
# Output: JSON array with three entry shapes, each tagged by `type`:
#
#   [
#     {
#       "type":       "review_thread",
#       "thread_id":  "PRRT_kwDOSFazsM5-gFO8",
#       "comment_id": 3162616672,
#       "path":       "src/onboarding_demo/mcp_tools/quote.py",
#       "line":       425,
#       "body":       "**Medium — silent fallback ...\n\n---\n\nActually, do Y instead."
#     },
#     {
#       "type":       "top_level_comment",
#       "comment_id": 12345678,
#       "body":       "Can we also add a retry here?",
#       "author":     "reviewer-login"
#     },
#     {
#       "type":       "review_body",
#       "comment_id": 87654321,
#       "body":       "Overall looks good but a few architectural concerns...",
#       "author":     "reviewer-login"
#     }
#   ]
#
# `body` for review_thread entries contains every comment in the thread
# joined by `\n\n---\n\n` (oldest first). If a reviewer amended or
# retracted their instruction in a follow-up, the fixer agent sees the
# full conversation rather than only the original message.
#
# Filtering:
#   - review_thread: only unresolved threads (existing behaviour)
#   - top_level_comment: deleted-account comments excluded (null author)
#   - review_body: empty or whitespace-only bodies excluded
#
# Why this script vs `gh api` directly:
#   - One allowlist entry covers the whole "show me the PR comments"
#     intent, instead of a wildcard on `gh api *` (which can POST/PUT/
#     DELETE).
#   - Pulls the GraphQL thread IDs and the REST comment IDs together
#     so the agent doesn't have to correlate them itself.
#   - Filters out resolved threads — agents shouldn't be re-replying
#     to threads someone already closed.
#
# Safety:
#   - PR number is validated as digits-only.
#   - Repo is derived from `gh repo view`, not passed in.
#   - No `eval`, no unquoted vars.

set -euo pipefail

PR_NUM="${1:?usage: pr-comments.sh <pr-number>}"

# Validation — the only legal character class for a PR number is
# digits. Anything else is the agent confused or a malicious prompt.
if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
  echo "pr-comments: invalid pr-number '$PR_NUM' (digits only)" >&2
  exit 2
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# Pull all three comment collections via a single GraphQL call:
#   1. reviewThreads — inline code review threads (existing)
#   2. comments      — top-level PR conversation comments
#   3. reviews       — PR review submissions (have optional body text)
#
# `first: 100` is GitHub's max page size without cursor pagination.
# We pull `pageInfo.hasNextPage` for every collection and fail loudly
# if any would be truncated. Pagination is a follow-up.
#
# jq filter quirks worth knowing:
#   - No trailing comma in the object constructor — jq 1.6 (still
#     the default on Ubuntu 22.04 / common CI images) treats
#     trailing commas as a syntax error. jq 1.7+ is permissive.
#   - `error("...")` raises a non-zero exit so the script fails
#     loudly on the truncation guard.
gh api graphql \
  -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            pageInfo { hasNextPage }
            nodes {
              id
              isResolved
              comments(first: 100) {
                nodes {
                  databaseId
                  path
                  body
                  line
                  originalLine
                }
              }
            }
          }
          comments(first: 100) {
            pageInfo { hasNextPage }
            nodes {
              databaseId
              body
              author {
                login
              }
            }
          }
          reviews(first: 100) {
            pageInfo { hasNextPage }
            nodes {
              databaseId
              body
              author {
                login
              }
            }
          }
        }
      }
    }
  ' \
  -F owner="${REPO%/*}" \
  -F repo="${REPO#*/}" \
  -F number="$PR_NUM" \
  --jq '
    .data.repository.pullRequest as $pr

    # ── Truncation guards ────────────────────────────────────────
    | if $pr.reviewThreads.pageInfo.hasNextPage
      then error("pr-comments: PR has more than 100 review threads; pagination not implemented")
      else true end

    | if $pr.comments.pageInfo.hasNextPage
      then error("pr-comments: PR has more than 100 top-level comments; pagination not implemented")
      else true end

    | if $pr.reviews.pageInfo.hasNextPage
      then error("pr-comments: PR has more than 100 reviews; pagination not implemented")
      else true end

    # ── Review threads (existing, now tagged with type) ──────────
    | [
        $pr.reviewThreads.nodes[]
        | select(.isResolved | not)
        | {
            type:       "review_thread",
            thread_id:  .id,
            comment_id: .comments.nodes[0].databaseId,
            path:       .comments.nodes[0].path,
            line:       (.comments.nodes[0].line // .comments.nodes[0].originalLine),
            body:       ([.comments.nodes[].body] | join("\n\n---\n\n"))
          }
      ]

    # ── Top-level PR conversation comments ───────────────────────
    # No bot filtering — the fix-pr-comments skill triages all
    # comments and can classify irrelevant ones as acknowledged.
    + [
        $pr.comments.nodes[]
        | select(.author != null)
        | {
            type:       "top_level_comment",
            comment_id: .databaseId,
            body:       .body,
            author:     (.author.login // "unknown")
          }
      ]

    # ── Review bodies ────────────────────────────────────────────
    # Exclude reviews with empty or whitespace-only bodies.
    + [
        $pr.reviews.nodes[]
        | select(.author != null)
        | select((.body // "") | gsub("\\s"; "") | length > 0)
        | {
            type:       "review_body",
            comment_id: .databaseId,
            body:       .body,
            author:     (.author.login // "unknown")
          }
      ]
  '

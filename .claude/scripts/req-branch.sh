#!/usr/bin/env bash
# req-branch.sh — create or switch to the requirements branch for a ticket.
#
# Usage:
#   .claude/scripts/req-branch.sh <ticket> <feature-slug>
#
# Constructs branch name: {ticket}_{feature-slug}
#
# Behaviour:
#   - Already on the target branch → report and exit 0.
#   - Branch exists locally → switch to it.
#   - Branch exists on remote → track and switch.
#   - Branch does not exist → create from origin's default branch.
#
# Why this script vs raw `git switch` / `git checkout`:
#   - One allowlist entry for the "set up the requirements branch" intent.
#   - Input validation (ticket format, slug format) is centralised.
#   - Anchors new branches to origin's default branch — a PM running the
#     skill from an arbitrary local branch doesn't accidentally fork from
#     stale state.
#   - Refuses to switch with uncommitted changes, giving a clear message
#     rather than a cryptic git error.
#
# Safety:
#   - Ticket validated as PROJ-123 format (uppercase letters, dash, digits).
#   - Slug validated as kebab-case (lowercase letters, digits, hyphens).
#   - Refuses to switch if there are uncommitted changes.
#   - No `eval`, no unquoted vars, no force-checkout.

set -euo pipefail

TICKET="${1:?usage: req-branch.sh <ticket> <feature-slug>}"
SLUG="${2:?usage: req-branch.sh <ticket> <feature-slug>}"

# Validate ticket: PROJ-123 format (one or more uppercase letters, dash,
# one or more digits).
if ! [[ "$TICKET" =~ ^[A-Z]+-[0-9]+$ ]]; then
  echo "req-branch: invalid ticket '$TICKET' (expected PROJ-123 format)" >&2
  exit 2
fi

# Validate slug: kebab-case (lowercase letters, digits, hyphens; must
# start and end with a letter or digit).
if ! [[ "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "req-branch: invalid feature-slug '$SLUG' (kebab-case only)" >&2
  exit 2
fi

BRANCH="${TICKET}_${SLUG}"

# Already on the target branch — nothing to do.
CURRENT="$(git branch --show-current)"
if [[ -z "$CURRENT" ]]; then
  echo "req-branch: detached HEAD state — switch to a branch first" >&2
  exit 2
fi
if [[ "$CURRENT" == "$BRANCH" ]]; then
  echo "Already on branch '$BRANCH'"
  exit 0
fi

# Refuse to switch if there are uncommitted changes — a PM may not know
# how to recover from a dirty-state error, so we catch it early with a
# clear message rather than letting git switch fail cryptically.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "req-branch: uncommitted changes on '$CURRENT' — commit or stash before switching" >&2
  exit 2
fi

# Branch exists locally → switch to it.
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch "$BRANCH"
  echo "Switched to existing local branch '$BRANCH'"
  exit 0
fi

# Fetch to pick up any remote branch that was created elsewhere.
git fetch origin --prune

# Branch exists on remote → track and switch.
if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  git switch --track "origin/$BRANCH"
  echo "Switched to remote-tracking branch '$BRANCH'"
  exit 0
fi

# Create new branch from origin's default branch so the PM doesn't
# accidentally fork from stale local state.
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
git switch -c "$BRANCH" "origin/$DEFAULT_BRANCH"
echo "Created branch '$BRANCH' from 'origin/$DEFAULT_BRANCH'"

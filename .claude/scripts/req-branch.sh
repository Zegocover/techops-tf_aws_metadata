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

# Canonical name for any branch this script CREATES: always the underscore
# form. Detection below is deliberately more permissive — it also matches the
# hyphen form ({TICKET}-{SLUG}) — so that a branch a PM already sits on or that
# was created elsewhere with a hyphen separator is found and reused rather than
# duplicated. This keeps the skill's `^{TICKET}[_-]` match and this script's
# construction reconciled when the match path is routed through here.
BRANCH="${TICKET}_${SLUG}"
BRANCH_HYPHEN="${TICKET}-${SLUG}"

# Detached HEAD is unrecoverable for a PM via this script — bail early with a
# clear message. Done before the fetch because there is no branch to anchor.
CURRENT="$(git branch --show-current)"
if [[ -z "$CURRENT" ]]; then
  echo "req-branch: detached HEAD state — switch to a branch first" >&2
  exit 2
fi

# Fetch on EVERY path before any create/switch decision so the requirements
# branch is always measured against the latest origin/<default>, and any remote
# branch created elsewhere is visible. git fetch is non-destructive (it touches
# only remote-tracking refs, never the working tree), so running it before the
# uncommitted-changes guard is safe and does not change that guard's behaviour.
# A fetch failure (offline / transient) must not block a PM who is already on
# the right branch; degrade to cached remote-tracking refs rather than aborting
# under set -e. The create path below still fails loudly if origin/<default> is
# genuinely unavailable.
git fetch origin --prune || echo "req-branch: fetch failed — proceeding with cached remote-tracking refs" >&2

# Resolve origin's default branch (dynamically — never hardcode). Used both for
# the informational behind-report and, on the create path, as the fork point.
# Resolution may fail when gh is unavailable/unauthenticated or the remote is
# not a GitHub repo; capture that here and degrade gracefully below.
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"

# report_behind: informational only — tell the PM if $1 is behind
# origin/<default>. Never mutates the PM's work (no rebase, no fast-forward).
# Silently skips when the default branch could not be resolved.
report_behind() {
  local ref="$1"
  if [[ -z "$DEFAULT_BRANCH" ]]; then
    return 0
  fi
  if ! git show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH"; then
    return 0
  fi
  local behind
  behind="$(git rev-list --count "${ref}..origin/${DEFAULT_BRANCH}" 2>/dev/null || echo 0)"
  if [[ "$behind" -gt 0 ]]; then
    echo "Note: '$ref' is $behind commit(s) behind 'origin/$DEFAULT_BRANCH' (not rebased — informational only)."
  fi
}

# Already on the target branch (either separator form) — nothing to switch, but
# still report staleness.
if [[ "$CURRENT" == "$BRANCH" || "$CURRENT" == "$BRANCH_HYPHEN" ]]; then
  echo "Already on branch '$CURRENT'"
  report_behind "$CURRENT"
  exit 0
fi

# Refuse to switch if there are uncommitted changes — a PM may not know
# how to recover from a dirty-state error, so we catch it early with a
# clear message rather than letting git switch fail cryptically. (The fetch
# above did not touch the working tree, so this state is exactly as the PM
# left it.)
if [[ -n "$(git status --porcelain)" ]]; then
  echo "req-branch: uncommitted changes on '$CURRENT' — commit or stash before switching" >&2
  exit 2
fi

# Branch exists locally (either separator form) → switch to it, reporting
# whether it is behind so the PM is never silently switched onto stale state.
# Prefer the canonical underscore form when both happen to exist.
for candidate in "$BRANCH" "$BRANCH_HYPHEN"; do
  if git show-ref --verify --quiet "refs/heads/$candidate"; then
    git switch "$candidate"
    echo "Switched to existing local branch '$candidate'"
    report_behind "$candidate"
    exit 0
  fi
done

# Branch exists on remote (either separator form) → track and switch.
for candidate in "$BRANCH" "$BRANCH_HYPHEN"; do
  if git show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
    git switch --track "origin/$candidate"
    echo "Switched to remote-tracking branch '$candidate'"
    report_behind "$candidate"
    exit 0
  fi
done

# Create new branch from origin's default branch so the PM doesn't
# accidentally fork from stale local state. This path REQUIRES the default
# branch — fail with a clear PM-facing message if it could not be resolved.
if [[ -z "$DEFAULT_BRANCH" ]]; then
  echo "req-branch: could not determine origin's default branch (is 'gh' installed and authenticated, and is this a GitHub repo?) — cannot create '$BRANCH'" >&2
  exit 2
fi
if ! git show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH"; then
  echo "req-branch: 'origin/$DEFAULT_BRANCH' is not present locally (fetch may have failed or been skipped) — cannot create '$BRANCH'" >&2
  exit 2
fi
git switch -c "$BRANCH" "origin/$DEFAULT_BRANCH"
echo "Created branch '$BRANCH' from 'origin/$DEFAULT_BRANCH'"

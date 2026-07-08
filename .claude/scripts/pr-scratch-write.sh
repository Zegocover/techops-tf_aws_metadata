#!/usr/bin/env bash
# pr-scratch-write.sh — write a PR reply-draft scratch file, /tmp first.
#
# Usage:
#   .claude/scripts/pr-scratch-write.sh <pr-number> <suffix> < body
#
# Writes the reply body (read from stdin) to a scratch file named
# `{pr-number}-{suffix}.md`, echoing the file's absolute path on
# stdout as a single line. The normal-operation location is
# `/tmp/_replies/`, outside the repo working tree, so a reply draft
# can never be accidentally committed. If `/tmp/_replies/` cannot be
# created or written, the script falls back to
# `<repo>/.claude/scripts/_replies/` (which is gitignored) and still
# exits 0 — so a transient `/tmp` problem no longer stops the run.
#
# Why this script vs the Write tool:
#   - The agent no longer writes the reply body with the Write tool.
#     This script writes it via a shell redirect, so no
#     `Write(/tmp/**)` permission is needed — the whole flow stays
#     non-interactive.
#   - The body arrives on stdin (via a quoted heredoc at the call
#     site), so arbitrary markdown / code fences stay literal and are
#     never re-parsed by the shell.
#   - Callers post by handing the echoed path to the byte-unchanged
#     `pr-reply.sh` / `pr-issue-reply.sh`, whose four-location
#     allowlist already accepts both `/tmp/*` (`/private/tmp/*` on
#     macOS) and `<repo>/.claude/scripts/_replies/*`, and which
#     re-validate the path they are handed.
#
# Safety:
#   - PR number validated as digits-only.
#   - Suffix validated as `^[A-Za-z0-9_-]+$` — no `/` and no `..`, so
#     the suffix cannot escape the scratch directory. Validation runs
#     BEFORE any mkdir or write. The three caller shapes
#     (`{thread_id}`, `toplevel-{comment_id}`, `reviewbody-{comment_id}`)
#     all satisfy it.
#   - Fallback dir resolved from `git rev-parse --show-toplevel`, so it
#     is correct even where `.claude/scripts` is a symlink (as in this
#     standards library repo).
#   - Diagnostics go to stderr; the single stdout line is the written
#     path.
#
# Environment overrides (for tests only):
#   - PR_SCRATCH_TMP_DIR — overrides the `/tmp/_replies` primary dir.
#     Pointing it at an unwritable path exercises the FR-05 fallback.
#
# Exit codes:
#   0  wrote the file to /tmp/_replies/ (or the in-repo fallback)
#   2  validation failed (missing arg, non-digit PR number, or a
#      suffix not matching [A-Za-z0-9_-]+); no path echoed, no file
#   *  both /tmp/_replies/ and the in-repo fallback were unwritable —
#      aborts non-zero under `set -e` (no special code, no swallowing),
#      matching prior behaviour where a failed reply-draft write stops
#      the run

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: pr-scratch-write.sh <pr-number> <suffix> < body" >&2
  exit 2
fi

PR_NUM="$1"
SUFFIX="$2"

if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
  echo "pr-scratch-write: invalid pr-number '$PR_NUM' (digits only)" >&2
  exit 2
fi

# Suffix must be a bare filename fragment — letters, digits, underscore,
# dash. This rejects `/` and `..` outright, so the suffix can never
# escape the scratch directory. Checked before any mkdir or write.
if ! [[ "$SUFFIX" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "pr-scratch-write: invalid suffix '$SUFFIX' (alphanumeric / _ / - only)" >&2
  exit 2
fi

FILENAME="${PR_NUM}-${SUFFIX}.md"

# Read the body once — stdin is a single stream and we may write it to
# either location. The trailing `printf x` + `%x` strip preserves any
# trailing newlines in the body, which a bare `$(cat)` would drop
# (command substitution trims trailing newlines).
BODY="$(cat; printf x)"
BODY="${BODY%x}"

TMP_DIR="${PR_SCRATCH_TMP_DIR:-/tmp/_replies}"

# Primary location: /tmp/_replies/. Try to create it and write the file.
# Any failure (dir cannot be created, or the write fails) drops through
# to the fallback. A pre-existing symlink at either the primary directory
# itself or at the target file also drops through — matching the symlink
# rejection in the sibling `pr-reply.sh` — so a pre-planted symlink (on
# the dir or the leaf) can't redirect the write. The parent-dir test runs
# before the leaf test. The `mkdir`/`printf` are guarded with 2>/dev/null
# so `set -e` doesn't abort before the fallback runs; the `if` consumes
# the non-zero status.
if mkdir -p "$TMP_DIR" 2>/dev/null && [[ ! -L "$TMP_DIR" && ! -L "$TMP_DIR/$FILENAME" ]] && printf '%s' "$BODY" > "$TMP_DIR/$FILENAME" 2>/dev/null; then
  printf '%s\n' "$TMP_DIR/$FILENAME"
  exit 0
fi

# Fallback location: <repo>/.claude/scripts/_replies/. Resolve the repo
# root via git so the symlinked .claude/scripts case is handled. If this
# write also fails (both locations unwritable), the command errors and
# `set -e` aborts non-zero — no swallowing, matching the prior
# behaviour where a failed reply-draft write stops the run.
REPO_ROOT="$(git rev-parse --show-toplevel)"
FALLBACK_DIR="$REPO_ROOT/.claude/scripts/_replies"
mkdir -p "$FALLBACK_DIR"
printf '%s' "$BODY" > "$FALLBACK_DIR/$FILENAME"
printf '%s\n' "$FALLBACK_DIR/$FILENAME"

# Scripts

Narrowly-scoped shell helper scripts that fan out to consumer repos alongside skills. Each script handles one intent, validates its inputs, and avoids broad permissions.

Scripts are installed into `.claude/scripts/` in consumer repos. Skills reference them by relative path (`.claude/scripts/<name>.sh`).

## Scripts in this library

| Script | Usage | Description |
| --- | --- | --- |
| `pr-comments.sh` | `.claude/scripts/pr-comments.sh <pr-number>` | Fetches all PR feedback as a JSON array with three entry types: `review_thread` (`{type, thread_id, comment_id, path, line, body}`), `top_level_comment` (`{type, comment_id, body, author}`), and `review_body` (`{type, comment_id, body, author}`). Review threads are unresolved only; review bodies exclude empty/whitespace-only entries. |
| `pr-issue-reply.sh` | `.claude/scripts/pr-issue-reply.sh <pr-number> <body-file>` | Posts a top-level issue comment to a PR. Body comes from a file to avoid shell-metachar issues. Body-file path must be `/tmp/*`, `/private/tmp/*`, `<repo>/.git/*`, or `<repo>/.claude/scripts/_replies/*`. Exit 3 on PR/branch mismatch. |
| `pr-reply.sh` | `.claude/scripts/pr-reply.sh <pr-number> <comment-id> <body-file>` | Posts a reply to a PR review comment. Body comes from a file to avoid shell-metachar issues. Body-file path must be `/tmp/*`, `/private/tmp/*`, `<repo>/.git/*`, or `<repo>/.claude/scripts/_replies/*`. Exit 3 on PR/branch mismatch. |
| `pr-resolve.sh` | `.claude/scripts/pr-resolve.sh <thread-id> <pr-number>` | Marks a PR review thread resolved via GraphQL mutation. Takes the `thread_id` node ID returned by `pr-comments.sh`. Cross-checks the PR number against the current branch's open PR; exits 3 on mismatch. |
| `req-branch.sh` | `.claude/scripts/req-branch.sh <ticket> <feature-slug>` | Creates or switches to the requirements branch for a ticket. Constructs branch name `{ticket}_{feature-slug}`. If the branch exists locally, switches to it; if on remote, tracks and switches; otherwise creates from origin's default branch. Refuses to switch with uncommitted changes. |
| `req-pr.sh` | `.claude/scripts/req-pr.sh <ticket> <requirements-file> <body-file> <commit-msg-file>` | Commits the requirements package, pushes the current branch, and opens a PR (or reports the existing PR if one is already open). Requirements file must be under `docs/requirements/`. Exit 2 on validation failure. |

## `_replies/`

Scratch directory for reply body files written by `fix-pr-comments` before calling `pr-reply.sh`. Files here are transient — the skill cleans them up after posting. This path is in `pr-reply.sh`'s allowed list.

## PreToolUse Scripts

Hook scripts registered in `.claude/settings.json` under `hooks.PreToolUse`. Each script receives a JSON object on stdin from the Claude Code harness, parses the `tool_input.command` field using `python3`, and exits 2 with a human-readable message if the command matches a blocked pattern. On parse failure the script exits 0 (fail open).

Block message format:
```
BLOCKED: '<matched command>' is forbidden by the Zego AI safety hook.
Stop and surface this block to the user. Do not attempt to rephrase or work around it.
```

| Script | Pattern scope |
| --- | --- |
| `git-safety.sh` | Unconditional: force push (`--force`, `-f`); push to protected branches (`main`, `master`, `production`, `staging`, `release/*`); `git reset --hard`; `git clean -f*`; `git checkout -- .`; `git restore .`; `git branch -D`; `git stash drop`; `git stash clear`; `gh pr merge`. Protected-branch only: `--force-with-lease`, `--force-if-includes`. |
| `filesystem-safety.sh` | `rm -rf` and `rm -fr` (flags in any order or combination) |
| `database-safety.sh` | `DROP TABLE`; `DROP DATABASE`; `TRUNCATE TABLE`; `TRUNCATE <identifier>` (all case-insensitive) |

Manual test:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"<cmd>"}}' | bash .claude/hooks/<name>.sh
echo $?
```

## Safety model

Each script:
- Validates all inputs before use (digits-only for integers, alphanumeric for node IDs)
- Derives the repo from `gh repo view` rather than accepting it as an argument
- Uses a hardcoded API path or mutation shape so agents cannot pivot to a different endpoint via argument injection
- Rejects symlinks on body files (`pr-reply.sh`) to prevent the `pwd -P` basename bypass

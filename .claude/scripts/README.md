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
| `pr-scratch-write.sh` | `.claude/scripts/pr-scratch-write.sh <pr-number> <suffix>` (body on stdin) | Writes a PR reply-draft scratch file `{pr-number}-{suffix}.md` and echoes its absolute path. Writes to `/tmp/_replies/` (outside the working tree) so a draft can never be committed; falls back to `<repo>/.claude/scripts/_replies/` and still exits 0 when `/tmp` is unwritable (FR-05). Suffix must match `[A-Za-z0-9_-]+` (rejects path traversal); exit 2 on validation failure. `zego-fix-pr-comments` pipes the body via a quoted heredoc and passes the echoed path to `pr-reply.sh` / `pr-issue-reply.sh`. |
| `pr-scratch-clean.sh` | `.claude/scripts/pr-scratch-clean.sh <pr-number>` | Removes this run's `{pr-number}-*.md` scratch files from **both** `/tmp/_replies/` and `<repo>/.claude/scripts/_replies/`. Prefix-scoped, so a concurrent run on a different PR is never touched (FR-03). Absent dirs / no matches are not errors; exit 2 only on a non-digit PR number. |
| `req-branch.sh` | `.claude/scripts/req-branch.sh <ticket> <feature-slug>` | Creates or switches to the requirements branch for a ticket. Constructs branch name `{ticket}_{feature-slug}`. If the branch exists locally, switches to it; if on remote, tracks and switches; otherwise creates from origin's default branch. Refuses to switch with uncommitted changes. |
| `req-pr.sh` | `.claude/scripts/req-pr.sh <ticket> <requirements-file> <body-file> <commit-msg-file>` | Commits the requirements package, pushes the current branch, and opens a PR (or reports the existing PR if one is already open). Requirements file must be under `docs/requirements/`. Exit 2 on validation failure. |
| `rebase-push.sh` | `.claude/scripts/rebase-push.sh <branch>` | Updates a rebased branch on origin with `--force-with-lease` (used by `zego-fix-merge-conflict`). Hardcodes the push shape so a bare `--force` cannot be substituted; refuses protected branches (`main`, `master`, `production`, `staging`, `release/*`); cross-checks the arg against the current branch. Exit 2 on invalid/protected branch, exit 3 on branch mismatch. Intentionally **not** in the `settings.json` allow-list, so every force-push prompts. |

## `_replies/`

In-repo **fallback** scratch directory for reply body files. In normal operation `zego-fix-pr-comments` writes reply drafts to `/tmp/_replies/` (outside the working tree) via `pr-scratch-write.sh`; this in-repo dir is used only when `/tmp` is unwritable (FR-05). Files here are transient — `pr-scratch-clean.sh` removes them per run — and the dir is gitignored so an aborted-run fallback draft can never be committed (NFR-01). This path is in `pr-reply.sh`'s and `pr-issue-reply.sh`'s allowed body-file list.

## PreToolUse Scripts

Hook scripts registered in `.claude/settings.json` under `hooks.PreToolUse`. Each script receives a JSON object on stdin from the Claude Code harness, parses the `tool_input.command` field using `python3`, and exits 2 with a human-readable message if the command matches a blocked pattern. On parse failure the script exits 0 (fail open).

Block message format:
```
BLOCKED: '<matched command>' is forbidden by the Zego AI safety hook.
Stop and surface this block to the user. Do not attempt to rephrase or work around it.
```

| Script | Pattern scope |
| --- | --- |
| `git-safety.sh` | Unconditional: force push (`--force`, `-f`); push to protected branches (`main`, `master`, `production`, `staging`, `release/*`); `git reset --hard`; `git clean -f*`; `git checkout -- .`; `git restore .`; `git branch -D`; `git stash drop`; `git stash clear`; `gh pr merge`; `git rebase --exec`/`-x` (arbitrary command execution per replayed commit). Protected-branch only: `--force-with-lease`, `--force-if-includes`. |
| `filesystem-safety.sh` | `rm -rf` and `rm -fr` (flags in any order or combination) |
| `database-safety.sh` | `DROP TABLE`; `DROP DATABASE`; `TRUNCATE TABLE`; `TRUNCATE <identifier>` (all case-insensitive) |
| `terraform-safety.sh` | `terraform`/`tofu`/`terragrunt` `apply`/`destroy`/`import`/`taint`/`untaint`/`force-unlock`; `state rm`/`push`/`mv`/`replace-provider`; `make [...] apply`/`destroy`; `buildkite-agent pipeline`/`annotate`/`artifact upload`/`meta-data set`; `gh workflow run`; mutating `gh api` (`-X POST/PATCH/PUT/DELETE`, field flags), except PR/issue review-and-comment endpoints (`repos/.../(pulls\|issues)/.../(comments\|reviews)`) which are exempt |
| `aws-safety.sh` | Default-deny on the `aws` CLI. Allows read-only operations (`describe-`/`get-`/`list-`/`lookup-`/`search-`/`head-`/`scan`/`query`/`select`/`wait`/`tail`, `s3 ls`/`presign`) and local/auth commands (`eks update-kubeconfig`, `sso login`/`logout`, `configure`, `ecr get-login-password`, `sts assume-role`/`get-session-token`/`get-caller-identity`); blocks everything else, including `s3 cp`/`mv`/`rm`/`sync`/`mb`/`rb` |
| `kubernetes-safety.sh` | `kubectl` mutating verbs (`apply`/`create`/`replace`/`patch`/`edit`/`set`/`delete`/`scale`/`rollout`/`autoscale`/`cordon`/`uncordon`/`drain`/`taint`/`annotate`/`label`) and interactive/exec verbs (`exec`/`cp`/`port-forward`/`attach`/`debug`/`run`/`expose`/`proxy`). Allows reads and any verb under `--dry-run=client/server` |
| `helm-safety.sh` | `helm install`/`upgrade`/`uninstall`/`delete`/`rollback`/`push`. Allows `template`/`lint`/`diff`/`get`/`list`/`show`/`status`/`history`/`search`/`repo`/`dependency`/`pull`, and `install`/`upgrade` under `--dry-run` |
| `argocd-safety.sh` | `argocd` app state (`app sync`/`create`/`delete`/`set`/`unset`/`patch`/`rollback`/`terminate-op`/`edit`/`actions run`) and admin writes (`cluster`/`repo`/`repocreds`/`cert`/`gpg` add/rm; `proj create`/`delete`/`set`/`add-*`/`remove-*`; `account update-password`/`generate-token`/`delete-token`). Allows reads and `login`/`logout` |

Each infra hook (`terraform`/`aws`/`kubernetes`/`helm`/`argocd`) emits a tool-specific block message rather than the generic one above.

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

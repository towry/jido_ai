# Patch Debug Flow

- Intent: keep `deploy` as a patch-only branch. Source analysis / patch generation use a **source tree** that is never the `deploy` working tree itself.
- Do not edit jido_ai source code directly on the `deploy` patch branch.
- Place deploy-ready patch files in `./patches` and update `./patches/series`.
- Do not store local-only agent docs or non-deploy artifacts in `./patches`.
- Do not write tests or run unit tests for this repo on `deploy`; CI applies patches onto `origin/main` and runs `mix test` there.

## Source tree

Paths are relative to **this repository root** (the towry/jido_ai checkout).

Patches target **this fork's `origin/main`** (`towry/jido_ai` `main`). That is the same baseline CI uses.

CI (`.github/workflows/check-patches.yml`) checks out the patch branch, detaches to `origin/main`, restores `patches/` + `scripts/`, then runs `scripts/apply.sh` on that tree. Rebase and apply against that SHA only.

| Role | Path | Notes |
|------|------|--------|
| **Canonical** | `../jido_ai-main` | Detached worktree of **this repo's** `origin/main`. Create with `git fetch origin main && git worktree add --detach ../jido_ai-main origin/main`. |
| **Legacy compat** | `./jido_ai-main` | Gitignored in-repo worktree. Use only if it already exists and is this repo's `origin/main`. |
| Forbidden | `../jido_ai-upstream` or any `agentjido/jido_ai` clone used as the apply baseline | Not the patch baseline. Ignore it even if present. |

Resolve:

1. `git fetch origin main` and record `git rev-parse origin/main`.
2. If `../jido_ai-main` exists and is this repo's `origin/main` → use it.
3. Else if `./jido_ai-main` exists and is this repo's `origin/main` → use it.
4. Else create the sibling worktree: `git worktree add --detach ../jido_ai-main origin/main`.
5. Say which path and which `origin/main` SHA you used.

Hard rules:

- **Never clone `agentjido/jido_ai` as the patch baseline.** These patches are not against latest upstream unless `origin/main` has already been fast-forwarded to it.
- **Never use `../jido_ai-upstream`** as the source tree, even if an old orb left it there.
- Do not create `./jido_ai-main` unless a sibling worktree is impossible.
- Never commit or push from the source worktree. It is read-only analysis / apply scratch.
- Deploy patches land only under `./patches` on this repo (`deploy` branch).
- Done when deploy patches are updated in `./patches`.

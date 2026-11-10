# Fork patches — jido_ai_twpatch (deploy branch)

`deploy` is an orphan branch: **no jido_ai source**. `main` tracks upstream
`agentjido/jido_ai` 1:1. Every fork customization lives only as `.patch`
files in [`patches/`](patches/) on `deploy` and is applied on top of
`origin/main` by CI and by the release workflow.

## Layout

```
deploy  (orphan, this branch)
├── patches/           the ONLY place fork changes to upstream files live
├── tools/patches      patch-stack manager (check/apply/reset/add/rebuild)
├── scripts/apply.sh   series-driven applier used by CI
├── scripts/publish-hex.sh  hex publish with no-overwrite guardrails
└── .github/workflows/{check-patches,publish-hex}.yml
main    = upstream main, verbatim (no fork edits in history)
```

## Commands

| Command | What it does |
|---|---|
| `tools/patches check [ref]` | Verify every patch applies cleanly, in order, against `ref` (default `HEAD` of the `main` worktree). No side effects. |
| `tools/patches apply` | Patch the `main` working tree (`git apply --3way`). Requires a clean tree. |
| `tools/patches reset` | Restore the `main` working tree to clean upstream. |
| `tools/patches add <desc>` | Export the `main` worktree changes as the next `patches/NNNN-desc.patch`. |
| `tools/patches rebuild <n>` | Re-export patch *n* after resolving conflicts, then re-apply the rest. |
| `tools/patches list` | Show the patch stack. |

## Everyday flows

### Make a change

```sh
# In the source tree (a worktree of origin/main, never this deploy tree):
git worktree add --detach ../jido_ai-main origin/main
cd ../jido_ai-main
tools/patches apply   # from the deploy checkout; ensure it is on PATH
# …edit lib/…, run mix test…
tools/patches add "describe the change"
# Copy the new patch file back to the deploy branch and update series:
```bash
cp patches/000N-desc.patch <deploy-checkout>/patches/
# (edit patches/series on deploy)
```

### Sync from upstream

```sh
# main is a fast-forward:
git checkout main && git fetch origin main && git merge --ff-only origin/main
# then rebase the patch stack onto the new base in the deploy checkout:
tools/patches check HEAD        # fails if upstream moved under a patch
tools/patches apply             # stops at the first conflicting patch k
# resolve the conflict markers, then:
tools/patches rebuild k
tools/patches check
# commit the rebuilt patches on deploy
```

### CI (`check-patches.yml`)

Manual dispatch: checkout `deploy` → `git checkout --detach origin/main` →
`git restore --source $SHA -- patches scripts …` → `scripts/apply.sh`.
Patches are always checked against `origin/main`, never against a raw
`agentjido/jido_ai` clone.

### Versioning and publishing — via CI

Fork versions encode **which upstream version they track** plus our own
release counter, expressed as a SemVer prerelease:

```
2.3.0-1    based on upstream 2.3.0, our 1st release
2.3.0-2    same base, our 2nd release
2.4.0-1    after syncing upstream 2.4.0 — the counter resets to 1
```

These are prereleases, so consumers must pin them explicitly
(`== 2.3.0-1`); `mix.lock` keeps the exact pin after the first resolve.

Single source of truth: `@version` in the **patched** `mix.exs`, owned by
`patches/0003-release-version.patch` — the only patch allowed to touch
`@version`. When upstream bumps its own version, that conflict lands here:
resolve to the new base and reset the counter to `-1`.

```sh
# in the source tree:
tools/patches apply
# edit @version in mix.exs, e.g. 2.3.0-1 -> 2.3.0-2
tools/patches rebuild 3
tools/patches check
# copy the rebuilt patch back to deploy and commit
```

Pushing to `deploy` (with `patches/`, `scripts/`, `tools/`, or
`publish-hex.yml` changed) runs `Publish Hex`: it pins `origin/main` +
`deploy` SHAs, applies the stack, verifies the derived tag `v<@version>`
matches, runs `mix test`, builds the tarball with `mix hex.build`, and
publishes with `mix hex.publish --yes` using the `HEX_API_KEY` repository
secret (hex.pm dashboard → Keys → *Generate New Key* → Write:API → store it
with `gh secret set HEX_API_KEY --repo towry/jido_ai`).

No-overwrite guardrails (`scripts/publish-hex.sh`): the release is only
published after patch-apply, tests, build, and the tag/`@version` check all
pass; if the version already exists on hex.pm the tarball checksum is
compared and a mismatch aborts instead of overwriting — `mix hex.publish`
itself would also refuse. A tag pointing at a different commit aborts too.

Manual fallback (a machine already logged in via `mix hex.user auth`):
in the source tree, `tools/patches apply && mix test && mix hex.publish`.

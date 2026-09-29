# Fork patches — jido_ai_twpatch

This repository tracks upstream `agentjido/jido_ai` with **zero modifications
to upstream files in git history**. Every fork customization — including the
hex package rename — exists only as `.patch` files in [`patches/`](patches/).

```
main   = upstream code + additive infra files only
         (.agents/, tools/, patches/, CI, docs → never conflict on sync)
patches/NNNN-desc.patch = the ONLY place fork changes to upstream files live
```

Why: `git merge upstream/main` stays conflict-free; conflicts can only happen
while (re)applying patches, and CI finds them before they surprise you.

## Commands

| Command | What it does |
|---|---|
| `tools/patches check [ref]` | Verify every patch applies cleanly, in order, against `ref` (default `HEAD`). No side effects. |
| `tools/patches apply` | Patch the working tree (`git apply --3way`). Requires a clean tree. |
| `tools/patches reset` | Restore the working tree to clean main. |
| `tools/patches add <desc>` | Export the current patched worktree changes as the next `patches/NNNN-desc.patch`. |
| `tools/patches rebuild <n>` | Re-export patch *n* after resolving conflicts, then re-apply the rest of the stack. |
| `tools/patches list` | Show the patch stack. |

## Everyday flows

### Make a change

```sh
tools/patches apply
# …edit lib/…, run mix test…
tools/patches add "describe the change"
tools/patches reset && tools/patches check
git add patches && git commit
```

### Sync from upstream

```sh
git fetch upstream && git merge upstream/main   # additive-only tree: no conflicts
tools/patches check HEAD                        # fails if upstream moved under a patch
tools/patches apply                             # stops at the first conflicting patch k
# resolve the conflict markers, then:
tools/patches rebuild k
tools/patches reset && tools/patches check
git add patches && git commit
```

### CI is red (`patches` workflow)

The workflow runs on every push/PR touching `patches/` and daily on a
schedule. It checks:

- `check HEAD` — the stack is inconsistent with this repo itself → fix before merging;
- `check upstream/main` — upstream moved under a patch → run the *Sync from
  upstream* flow above and push the re-exported patches.

### Publish to hex (`jido_ai_twpatch`) — via CI

The fork owns an independent version line on hex: it starts at `2.3.1`
(upstream base `2.3.0` + this fork's first release) and the patch segment
increments on every release. The single source of truth is `@version` in
`mix.exs` **of the patched tree**, owned by `patches/0003-release-version.patch`
(the only patch allowed to touch `@version`; when upstream bumps its own
version, that conflict lands here — resolve by keeping the fork's number).

```sh
tools/patches apply            # full stack
# edit @version in mix.exs, e.g. 2.3.1 -> 2.3.2
tools/patches rebuild 3        # re-exports the release patch in place
tools/patches reset && tools/patches check
git add patches && git commit -m "chore: release 2.3.2"
git tag v2.3.2 && git push origin main v2.3.2
```

The `publish` workflow (tag push `v*`) then applies the stack, **verifies the
tag equals the patched `@version`**, runs `mix test`, builds the tarball and
publishes with `mix hex.publish --yes` using the `HEX_API_KEY` repository
secret (hex.pm dashboard → Keys → *Generate New Key* → Write:API → store it
with `gh secret set HEX_API_KEY --repo towry/jido_ai`).

Guards: a tag/`@version` mismatch, a missing secret, failing tests, or a
version already on hex all abort **before** anything is uploaded.

Manual fallback (a machine already logged in via `mix hex.user auth`):
`tools/patches apply && mix test && mix hex.publish && tools/patches reset`.

## Rules

1. Commits on `main` may only **add** files. Never modify an upstream file in
   a commit — edits to `mix.exs`, `lib/**`, upstream CI, etc. belong in
   `patches/`.
2. Patch files must only touch upstream-owned paths, never this workflow's
   infra (`patches/`, `tools/`, `PATCHING.md`, `.agents/`,
   `.github/workflows/patches.yml`) — the exporter excludes them
   automatically.
3. Never hand-edit a `.patch` file: change the code (apply → edit →
   `add`/`rebuild`) and let git regenerate it.

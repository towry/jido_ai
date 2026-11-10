#!/usr/bin/env bash

# Publish to hex.pm only after full verification. Never overwrite an existing
# version (hex.pm itself rejects re-publish; we refuse before running
# `mix hex.publish` if the tarball differs from what is already stored).
set -euo pipefail

: "${HEX_API_KEY:?Set HEX_API_KEY to the hex.pm API key}"
: "${MAIN_SHA:?Set MAIN_SHA to the pinned source commit (origin/main)}"
: "${PATCH_SHA:?Set PATCH_SHA to the pinned deploy commit}"
: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY to owner/repo}"

# Read the patched @version from the (already patched) worktree.
patched="$(sed -nE 's/^ *@version "([^"]+)"/\1/p' mix.exs)"
[[ -n "$patched" ]] || { echo "could not parse @version from mix.exs" >&2; exit 1; }
tag="v${patched}"
echo "patched @version: ${patched} (tag: ${tag})"
echo "source (origin/main): ${MAIN_SHA}"
echo "patches (deploy):      ${PATCH_SHA}"

# A pre-existing tag must point at the exact deploy commit, not a moving branch.
refs="$(gh api "repos/$GITHUB_REPOSITORY/git/matching-refs/tags/$tag")"
if jq -e --arg ref "refs/tags/$tag" 'any(.[]; .ref == $ref)' <<< "$refs" >/dev/null; then
  target="$(gh api "repos/$GITHUB_REPOSITORY/commits/$tag" --jq .sha)"
  if [[ "$target" != "$PATCH_SHA" ]]; then
    echo "Refusing to publish: $tag points to $target, not deploy commit $PATCH_SHA" >&2
    exit 1
  fi
fi

# Build the tarball and checksum it. hex tarballs are deterministic for a
# given tree, so a same-version rebuild must produce the same bytes.
mix hex.build
tarball="$(ls jido_ai_twpatch-*.tar | head -n1)"
[[ -n "$tarball" ]] || { echo "no hex tarball built" >&2; exit 1; }
sha="$(sha256sum "$tarball")"
sha="${sha%% *}"
echo "tarball: ${tarball} (sha256 ${sha})"
echo "${sha}  ${tarball}" > "$GITHUB_STEP_SUMMARY" 2>/dev/null || true

# If this version is already on hex.pm, verify the stored tarball checksum
# matches the one we just built. Mismatch => refuse to overwrite (same
# guardrail as magpie's asset digest check). Match => leave it unchanged.
if mix hex.info "jido_ai_twpatch" 2>/dev/null | grep -q "v${patched}"; then
  echo "version ${patched} already exists on hex.pm; verifying checksum..."
  # `mix hex.info` prints the tarball checksum; compare against our build.
  stored="$(mix hex.info "jido_ai_twpatch" 2>/dev/null | grep -E "^[0-9a-f]{64}  " | awk '{print $1}' | head -n1 || true)"
  if [[ -n "$stored" && "$stored" != "$sha" ]]; then
    echo "Refusing to overwrite: stored tarball sha256 $stored != new build $sha" >&2
    exit 1
  fi
  echo "Release already published; all artifacts match, leaving it unchanged."
  exit 0
fi

echo "Publishing ${patched} to hex.pm..."
mix hex.publish --yes

# Tag points at the deploy commit after publish so reruns are idempotent.
existing_target="$(gh api "repos/$GITHUB_REPOSITORY/git/matching-refs/tags/$tag" --jq '.[] | select(.ref=="refs/tags/'"$tag"'") | .object.sha' || true)"
if [[ -z "$existing_target" ]]; then
  gh api --method POST "repos/$GITHUB_REPOSITORY/git/refs" \
    -f ref="refs/tags/$tag" -f sha="$PATCH_SHA" >/dev/null
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '## Hex publish\n\n- Version: `%s`\n- Source: `%s`\n- Deploy: `%s`\n- Tarball sha256: `%s`\n' \
      "$patched" "$MAIN_SHA" "$PATCH_SHA" "$sha"
  } >> "$GITHUB_STEP_SUMMARY"
fi

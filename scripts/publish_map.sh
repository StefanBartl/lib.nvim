#!/usr/bin/env bash
# Publish the generated module map to the `gh-pages` branch.
#
# The artifacts are committed on `main` too (so `--check` can detect drift and
# so diffs are reviewable), but `gh-pages` is what GitHub Pages serves, and it
# carries *only* the map — no source, no history entanglement with main.
#
# The branch is built as an orphan and force-pushed on every publish. That is
# deliberate: the map is derived output, its history has no value, and letting
# it accumulate would grow the repo for nothing. Nothing but generated files
# ever lives there, so there is nothing to lose.
#
#   scripts/publish_map.sh              publish
#   scripts/publish_map.sh --dry-run    build the tree, print it, push nothing

set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

MAP_DIR="docs/map"
BRANCH="gh-pages"
REMOTE="origin"

if [ ! -f "$MAP_DIR/index.html" ]; then
  echo "error: $MAP_DIR/index.html not found — run :LibMap first." >&2
  exit 1
fi

# Refuse to publish a stale map: whatever gets served should match the source
# it was generated from.
if ! nvim --headless -l scripts/gen_map.lua --check >/dev/null 2>&1; then
  echo "error: module map is stale. Run :LibMap and commit before publishing." >&2
  exit 1
fi

SHA="$(git rev-parse --short HEAD)"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp "$MAP_DIR/index.html" "$STAGING/index.html"
cp "$MAP_DIR/overview.md" "$STAGING/overview.md"
cp "$MAP_DIR/module_map.json" "$STAGING/module_map.json"

# Pages runs Jekyll by default, which skips files and directories beginning
# with an underscore and can rewrite Markdown. The map is already rendered.
touch "$STAGING/.nojekyll"

if [ "$DRY_RUN" = "1" ]; then
  echo "would publish to $BRANCH from $SHA:"
  ls -la "$STAGING"
  exit 0
fi

WORKTREE="$(mktemp -d)"
trap 'rm -rf "$STAGING" "$WORKTREE"; git worktree prune' EXIT

# Start from an orphan branch each time, so the published tree contains
# exactly the files above and nothing carried over from a previous publish.
#
# Checked out under a throwaway name, then pushed to refs/heads/$BRANCH —
# not `git checkout --orphan "$BRANCH"` directly. That fails with "a branch
# named 'gh-pages' already exists" on every publish after the first one on a
# given clone, since the orphan checkout leaves a local branch behind. That
# exact failure shipped once already: silenced by a stray `>/dev/null 2>&1`
# on the checkout, `set -e` unwound the script with no message at all, and
# it went unnoticed until gh-pages was found still serving a stale commit.
# A disposable branch name never collides, and no local $BRANCH is ever
# created to go stale against the remote.
git worktree add --detach "$WORKTREE" >/dev/null
(
  cd "$WORKTREE"
  TMP_BRANCH="publish-map-$$"
  git checkout --orphan "$TMP_BRANCH"
  git rm -rf . >/dev/null 2>&1 || true
  cp -r "$STAGING"/. .
  git add -A
  git commit -q -m "docs(map): publish module map from $SHA"
  git push --force "$REMOTE" "HEAD:refs/heads/$BRANCH"
)

echo "Published $BRANCH from $SHA."
echo "Enable Pages for this branch once, then the map is served at:"
echo "  https://<user>.github.io/lib.nvim/"

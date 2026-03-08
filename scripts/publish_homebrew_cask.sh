#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_SCRIPT="$ROOT_DIR/scripts/render_homebrew_cask.sh"

VERSION="${VERSION:-}"
SHA256="${SHA256:-}"
TAP_REPOSITORY="${TAP_REPOSITORY:-happycodelucky/homebrew-tap}"
TAP_BRANCH="${TAP_BRANCH:-main}"
TAP_CASK_PATH="${TAP_CASK_PATH:-Casks/awake.rb}"
GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-github-actions[bot]}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
HOMEBREW_TAP_GITHUB_TOKEN="${HOMEBREW_TAP_GITHUB_TOKEN:-}"

if [[ -z "$VERSION" || -z "$SHA256" ]]; then
  echo "VERSION and SHA256 must be set." >&2
  exit 1
fi

if [[ -z "$HOMEBREW_TAP_GITHUB_TOKEN" ]]; then
  echo "HOMEBREW_TAP_GITHUB_TOKEN must be set." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

remote_url="https://x-access-token:${HOMEBREW_TAP_GITHUB_TOKEN}@github.com/${TAP_REPOSITORY}.git"

echo "Cloning tap repository ${TAP_REPOSITORY}..."
git clone --branch "$TAP_BRANCH" "$remote_url" "$tmp_dir"

target_path="$tmp_dir/$TAP_CASK_PATH"

echo "Rendering cask to ${TAP_CASK_PATH}..."
"$RENDER_SCRIPT" --version "$VERSION" --sha256 "$SHA256" --output "$target_path"

if command -v brew >/dev/null 2>&1; then
  echo "Running brew audit on rendered cask..."
  HOMEBREW_NO_AUTO_UPDATE=1 brew audit --cask "$target_path"
fi

if git -C "$tmp_dir" diff --quiet -- "$TAP_CASK_PATH"; then
  echo "No tap changes detected."
  exit 0
fi

git -C "$tmp_dir" config user.name "$GIT_AUTHOR_NAME"
git -C "$tmp_dir" config user.email "$GIT_AUTHOR_EMAIL"
git -C "$tmp_dir" add "$TAP_CASK_PATH"
git -C "$tmp_dir" commit -m "awake ${VERSION}"

echo "Pushing tap update..."
git -C "$tmp_dir" push origin "HEAD:${TAP_BRANCH}"

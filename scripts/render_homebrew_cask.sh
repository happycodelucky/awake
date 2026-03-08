#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_PATH="$ROOT_DIR/packaging/homebrew/Casks/awake.rb.template"

VERSION=""
SHA256=""
OUTPUT_PATH=""
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-happycodelucky/awake}"
HOMEPAGE_URL="${HOMEPAGE_URL:-https://github.com/${GITHUB_REPOSITORY}}"
DOWNLOAD_URL=""
VERIFIED_HOST="${VERIFIED_HOST:-github.com/${GITHUB_REPOSITORY}/}"

usage() {
  cat <<'EOF'
Usage: scripts/render_homebrew_cask.sh --version VERSION --sha256 SHA256 [--output PATH]

Renders the Awake Homebrew cask template with a release version and zip checksum.
Defaults assume GitHub Releases hosted at https://github.com/<owner>/<repo>.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --sha256)
      SHA256="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="${2:-}"
      shift 2
      ;;
    --homepage)
      HOMEPAGE_URL="${2:-}"
      shift 2
      ;;
    --verified-host)
      VERIFIED_HOST="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" || -z "$SHA256" ]]; then
  echo "--version and --sha256 are required." >&2
  usage >&2
  exit 1
fi

if [[ -z "$DOWNLOAD_URL" ]]; then
  DOWNLOAD_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/v${VERSION}/Awake.zip"
fi

content="$(<"$TEMPLATE_PATH")"
content="${content//__VERSION__/$VERSION}"
content="${content//__SHA256__/$SHA256}"
content="${content//__URL__/$DOWNLOAD_URL}"
content="${content//__VERIFIED__/$VERIFIED_HOST}"
content="${content//__HOMEPAGE__/$HOMEPAGE_URL}"

if [[ -n "$OUTPUT_PATH" ]]; then
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  printf '%s\n' "$content" > "$OUTPUT_PATH"
else
  printf '%s\n' "$content"
fi

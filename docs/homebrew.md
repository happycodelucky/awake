# Homebrew Tap and Cask Reference

This document describes the Homebrew cask distribution for Awake: the template, the scripts that render and publish it, and how release automation ties everything together.

---

## Overview

Awake is distributed via a [Homebrew](https://brew.sh) cask hosted in a separate tap repository. A tap is a third-party Homebrew repository that users add once:

```bash
brew tap happycodelucky/tap
brew install --cask awake
```

Because Awake ships as an Apple Silicon-only, macOS 15+ app bundle, the cask declares those constraints so Homebrew rejects the install on incompatible machines before attempting to download anything.

The cask file itself is not stored in this repository. Instead, a template lives here and is rendered at release time by the scripts described below, then committed to the tap repository.

---

## Cask Template

**Path:** `packaging/homebrew/Casks/awake.rb.template`

```ruby
cask "awake" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "__URL__",
      verified: "__VERIFIED__"
  name "Awake"
  desc "Menu bar utility that keeps your Mac awake"
  homepage "__HOMEPAGE__"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "Awake.app"
end
```

### Placeholder Tokens

| Token | Description |
|---|---|
| `__VERSION__` | Release version string without the `v` prefix (e.g. `1.2.0`). |
| `__SHA256__` | SHA-256 checksum of `Awake.zip`. Homebrew verifies the download against this before installation. |
| `__URL__` | Full HTTPS URL to the release zip artifact (e.g. the GitHub Releases asset URL). |
| `__VERIFIED__` | The hostname prefix Homebrew uses to lock the download URL to a trusted domain (e.g. `github.com/happycodelucky/awake/`). |
| `__HOMEPAGE__` | Project homepage URL shown to users in `brew info awake`. |

---

## Render Script

**Path:** `scripts/render_homebrew_cask.sh`

Reads the template at `packaging/homebrew/Casks/awake.rb.template`, substitutes all placeholder tokens, and writes the result either to stdout or to a specified output path.

### Flags

| Flag | Description |
|---|---|
| `--version VERSION` | **(Required)** Release version string. Replaces `__VERSION__`. |
| `--sha256 SHA256` | **(Required)** SHA-256 checksum of the zip artifact. Replaces `__SHA256__`. |
| `--output PATH` | Write rendered cask to this file path instead of stdout. Parent directories are created automatically. |
| `--download-url URL` | Override the download URL. Replaces `__URL__`. When omitted, the URL is constructed from `GITHUB_REPOSITORY` and the version. |
| `--homepage URL` | Override the homepage URL. Replaces `__HOMEPAGE__`. Defaults to `HOMEPAGE_URL` or `https://github.com/$GITHUB_REPOSITORY`. |
| `--verified-host HOST` | Override the verified host string. Replaces `__VERIFIED__`. Defaults to `VERIFIED_HOST` or `github.com/$GITHUB_REPOSITORY/`. |

### Environment Variables

These variables supply defaults when the corresponding flags are not passed:

| Variable | Default | Purpose |
|---|---|---|
| `GITHUB_REPOSITORY` | `happycodelucky/awake` | Used to derive the download URL, homepage, and verified host when those flags are absent. |
| `HOMEPAGE_URL` | `https://github.com/$GITHUB_REPOSITORY` | Sets the `__HOMEPAGE__` token. |
| `VERIFIED_HOST` | `github.com/$GITHUB_REPOSITORY/` | Sets the `__VERIFIED__` token. |

---

## Publish Script

**Path:** `scripts/publish_homebrew_cask.sh`

Clones the tap repository, renders the cask into the correct path inside the clone, optionally runs `brew audit`, and pushes a commit back to the tap.

### Steps Performed

1. Clones `TAP_REPOSITORY` at `TAP_BRANCH` into a temporary directory using `HOMEBREW_TAP_GITHUB_TOKEN` for authentication.
2. Calls `scripts/render_homebrew_cask.sh` to write the rendered cask to `TAP_CASK_PATH` inside the clone.
3. If `brew` is present on the PATH, runs `brew audit --cask` against the rendered file to catch obvious issues before publishing.
4. If the cask content is unchanged from the current HEAD, exits cleanly without making a commit.
5. Commits the updated cask file with the message `awake <VERSION>` using the configured author identity.
6. Pushes the commit to `origin HEAD:<TAP_BRANCH>`.

### Environment Variables

All inputs are provided through environment variables. There are no command-line flags.

| Variable | Default | Description |
|---|---|---|
| `VERSION` | *(required)* | Release version string (no `v` prefix). |
| `SHA256` | *(required)* | SHA-256 checksum of `Awake.zip`. |
| `TAP_REPOSITORY` | `happycodelucky/homebrew-tap` | `owner/repo` slug of the tap repository on GitHub. |
| `TAP_BRANCH` | `main` | Branch to clone and push to in the tap repository. |
| `TAP_CASK_PATH` | `Casks/awake.rb` | Relative path inside the tap repository where the cask file is written. |
| `HOMEBREW_TAP_GITHUB_TOKEN` | *(required)* | GitHub personal access token or fine-grained token with write access to the tap repository. |
| `GIT_AUTHOR_NAME` | `github-actions[bot]` | Git author name used for the tap commit. |
| `GIT_AUTHOR_EMAIL` | `41898282+github-actions[bot]@users.noreply.github.com` | Git author email used for the tap commit. |

---

## Tap Repository Setup

### Recommended Repository Name

Name the tap repository using Homebrew's naming convention so users can install with short-form tap names:

```
happycodelucky/homebrew-tap
```

With this name, users add the tap with:

```bash
brew tap happycodelucky/tap
```

### Required Secret

The publish script authenticates to the tap repository using a GitHub token. Add this secret to the **Awake repository** (not the tap repository):

| Secret Name | Description |
|---|---|
| `HOMEBREW_TAP_GITHUB_TOKEN` | A GitHub personal access token (classic or fine-grained) with `contents: write` permission on the tap repository. |

### Optional Repository Variables

These variables customize which tap repository, branch, and cask path the publish script targets. When omitted the defaults shown in the publish script are used.

| Variable Name | Default | Description |
|---|---|---|
| `HOMEBREW_TAP_REPOSITORY` | `happycodelucky/homebrew-tap` | `owner/repo` slug of the tap. Override to point at a fork or a differently named tap. |
| `HOMEBREW_TAP_BRANCH` | `main` | Branch in the tap repository to commit to. |
| `HOMEBREW_TAP_CASK_PATH` | `Casks/awake.rb` | Path to the cask file within the tap repository. |

---

## Local Rendering Example

To preview the rendered cask for a local build without publishing anything:

```bash
# Compute the checksum of the local zip artifact
SHA256="$(shasum -a 256 dist/Awake.zip | awk '{print $1}')"

# Render to stdout
./scripts/render_homebrew_cask.sh --version 1.0.0 --sha256 "$SHA256"
```

To write the rendered cask to a file instead:

```bash
SHA256="$(shasum -a 256 dist/Awake.zip | awk '{print $1}')"

./scripts/render_homebrew_cask.sh \
    --version 1.0.0 \
    --sha256 "$SHA256" \
    --output /tmp/awake.rb
```

To override the repository slug when working from a fork:

```bash
SHA256="$(shasum -a 256 dist/Awake.zip | awk '{print $1}')"

GITHUB_REPOSITORY="myorg/awake" \
./scripts/render_homebrew_cask.sh --version 1.0.0 --sha256 "$SHA256"
```

---

## Release Automation

The release workflow at `.github/workflows/release.yml` calls `scripts/publish_homebrew_cask.sh` as the final step of every release run.

The relevant step:

```yaml
- name: Publish Homebrew cask to tap
  if: ${{ secrets.HOMEBREW_TAP_GITHUB_TOKEN != '' }}
  env:
    VERSION: ${{ inputs.version }}
    SHA256: ${{ env.AWAKE_ZIP_SHA256 }}
    HOMEBREW_TAP_GITHUB_TOKEN: ${{ secrets.HOMEBREW_TAP_GITHUB_TOKEN }}
    TAP_REPOSITORY: ${{ vars.HOMEBREW_TAP_REPOSITORY }}
    TAP_BRANCH: ${{ vars.HOMEBREW_TAP_BRANCH }}
    TAP_CASK_PATH: ${{ vars.HOMEBREW_TAP_CASK_PATH }}
  run: ./scripts/publish_homebrew_cask.sh
```

Key points:

- The step is **skipped** when `HOMEBREW_TAP_GITHUB_TOKEN` is not set, so forks without a tap configured do not fail the release job.
- `VERSION` comes directly from the `workflow_dispatch` input.
- `SHA256` (`AWAKE_ZIP_SHA256`) is computed in an earlier step by running `shasum -a 256 dist/Awake.zip | awk '{print $1}'` and writing the result to `$GITHUB_ENV`.
- The optional repository variables (`HOMEBREW_TAP_REPOSITORY`, `HOMEBREW_TAP_BRANCH`, `HOMEBREW_TAP_CASK_PATH`) are read from GitHub Actions repository variables, so they can be changed without modifying workflow YAML.

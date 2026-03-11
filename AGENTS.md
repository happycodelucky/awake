# Awake Build Notes

- If Xcode is installed but the active developer directory is still Command Line Tools, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` before building.
- `Awake.xcodeproj` is generated from `project.yml` using XcodeGen. Install with `brew install xcodegen`, then run `xcodegen generate` from the repo root after any changes to `project.yml`.
- Build the macOS app bundle with `./scripts/bundle_app.sh`.
- When running `swift build` or other SwiftPM commands in Codex, set `SWIFTPM_MODULECACHE_OVERRIDE` to a module-cache path inside the project directory to avoid sandbox/cache permission issues. Example: `SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"`.
- When asked to compile or rebuild the app, first terminate any running Awake process with `pkill -x Awake`.
- After a successful compile or rebuild, relaunch the fresh app bundle with `open dist/Awake.app`.
- Output artifacts are `dist/Awake.app` and `dist/Awake.zip`.
- Default bundle id is `com.happycodelucky.apps.awake`.
- Default target is Apple Silicon only: `arm64`.
- Default minimum macOS version is `15.0`.
- Ad-hoc signing is enabled by default. To force unsigned output, run `ADHOC_SIGN=0 ./scripts/bundle_app.sh`.

## Required Documentation

- Comment all functions, classes, structs, enums, extensions, initializers, and deinitializers.
- Use SwiftDoc format (`///`) where it fits the declaration being documented.
- Keep comments concrete and useful. Describe behavior, purpose, important parameters, return values, side effects, and constraints. Avoid restating the code mechanically.
- Use `TODO:` for future work that is intentionally deferred.
- Use `FIXME:` for known bugs, incorrect behavior, or implementation problems that still need correction.
- Use `AGENT:` for agent-specific rationale, implementation context, or learned details that will help future agents understand why a decision was made.
- When looking for prior agent reasoning or project-specific learned context, read the existing `AGENT:` comments first before changing related code.

## Agent Review

Agent mistakes are tracked in `AGENT_REVIEW.md`.

## Documentation Maintenance

- When adding new features or changing user-facing behavior, update the relevant guide in `guide/`.
- When changing architecture, build system, integrations, or internal design, update the relevant doc in `docs/`.
- When creating new integrations or subsystems, add a new doc in `docs/`.
- Design plans and brainstorming artifacts go in `docs/plans/`.
- Keep `guide/` written for end users — no developer jargon, no code.
- Keep `docs/` written for agents and developers — include file paths, type names, and implementation details.

# Changelog

All notable changes to **kssh** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Continuous integration (build, test, and `swift-format` lint) on every push and pull request.
- Tag-triggered release workflow that builds the `.app`, zips it, and drafts a GitHub Release.
- `.swift-format` style configuration with `make lint` / `make format` targets.
- `CHANGELOG.md`, `SECURITY.md`, `docs/ARCHITECTURE.md`, `CODEOWNERS`, and Dependabot config.
- Code of conduct.

### Changed

- Refreshed README for the v1.3.0 multi-account features and discoverability.
- Reformatted the codebase with `swift-format`.

## [1.3.0] - 2026-06-22

### Added

- Multi-account remotes: manage multiple GitHub, GitLab, and Bitbucket accounts per service —
  add, label, switch the active one, test the connection, and edit or remove it from the popover.
- Remote account rows with avatar, username, and a profile detail screen including stats and a
  GitHub contribution graph.
- General settings (auto-refresh interval, launch-at-login) and a read-only account summary.

## [1.2.0] - 2026-06-22

### Added

- Full SSH key lifecycle from the menu bar: generate (ed25519 or RSA), rename, delete (to a
  recoverable trash), and upload the active key to a remote.
- Bitbucket remote profile support with an enriched profile display.
- A remote profile detail screen, opened by tapping a remote row.

### Fixed

- Opening the Settings window from the menu bar on macOS 26.

## [1.1.2] - 2026-06-22

### Fixed

- Switching keys now works across sibling `Host` blocks that match the same host, instead of
  only updating the first matching block.

## [1.1.1] - 2026-06-22

### Fixed

- The active SSH key is now tracked by the user's selection rather than inferred from the
  config, so the highlighted identity stays correct after a switch.

## [1.1.0] - 2026-06-22

### Added

- More robust `~/.ssh/config` switching that rewrites only the `Host` blocks referencing the
  switched key.
- Git profile tabs and an explicit ssh-agent "Enable" flow.

### Changed

- Homebrew is now documented as the primary installation method.

## [1.0.0] - 2026-06-21

### Added

- Menu-bar app showing loaded SSH keys, the active identity, Git config, GPG keys, and the
  resolved GitHub/GitLab remote for the active key.
- Quick-switch SSH identities directly from the tray.
- Load and unload keys in the ssh-agent (`ssh-add`).
- Named Git identity profiles with one-tap switching of `user.name` / `user.email`.
- GPG secret-key listing and in-app ed25519 key creation.
- Remote profile resolution from a Personal Access Token (with `~/.netrc` fallback) and
  avatar display, scoped to the active SSH key.
- Copy-to-clipboard for fingerprints, public keys, emails, and key ids.
- README, contributing guide, and issue/PR templates.

[Unreleased]: https://github.com/kitanoyoru/kssh/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/kitanoyoru/kssh/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/kitanoyoru/kssh/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/kitanoyoru/kssh/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/kitanoyoru/kssh/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/kitanoyoru/kssh/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/kitanoyoru/kssh/releases/tag/v1.0.0

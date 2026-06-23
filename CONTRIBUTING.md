# Contributing to kssh

Thanks for your interest in improving kssh! This is a small, focused macOS menu-bar app —
contributions that keep it simple and predictable are very welcome.

## Development setup

Requirements:

- macOS 14 (Sonoma) or later
- Swift toolchain (Xcode 15+ or the Swift command-line tools)
- `git` on your `PATH`; `gnupg` only if you're working on GPG features

Clone and build:

```sh
git clone https://github.com/kitanoyoru/kssh.git
cd kssh
make build      # debug build
make run        # build and launch the app
make test       # run the test suite
make lint       # check formatting/style (swift-format) — same check CI runs
make format     # apply swift-format in place
```

`make release` produces a bundled `.app`; `make install` copies it to `/Applications`.

For a high-level tour of how the code is organized, see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Project layout

```
Sources/kssh/
  ksshApp.swift          App entry, scenes (MenuBarExtra + Settings)
  MenuBarView.swift      The popover UI, in-popover routes, row components
  Theme.swift            Design tokens (Spacing, Radius, StatusColor) + shared atoms
  Models/                Plain data types (SSHKey, SSHIdentity, GitProfile, …)
  Services/              Shell-outs to ssh-add / ssh-keygen / git / gpg + GitHub/GitLab APIs
  ViewModels/            StatusViewModel — refresh loop and all user actions
  Settings/              SettingsStore (Keychain/UserDefaults) + SettingsView
  Utils/                 ProcessRunner, KeychainManager, NetrcReader, Clipboard
Tests/ksshTests/         XCTest unit tests
```

## Code style

Style is enforced with [`swift-format`](https://github.com/swiftlang/swift-format) against the
repo's `.swift-format` config. Run `make format` before committing, and `make lint` to verify —
CI fails on style violations. Beyond formatting:

- **SwiftUI + design tokens.** Use the `Spacing` / `Radius` / `StatusColor` tokens and the
  existing reusable views (`SectionCard`, `KeyValueRow`, `MenuActionButtonStyle`, …) rather
  than ad-hoc values, so the UI stays visually consistent.
- **All shell-outs go through `ProcessRunner`.** Never invoke a shell directly; pass
  arguments as an array (no manual quoting).
- **Service errors are `LocalizedError`s** surfaced through `StatusViewModel.error` and the
  in-popover error banner.
- **ViewModel actions** follow the guard → set loading state → `defer` reset → `do/catch`
  into `error` → `await refresh()` pattern (see `switchIdentity`, `switchGitProfile`).
- **Favor pure, testable functions** for logic that touches files or external formats
  (e.g. `SSHIdentityService.transform`, `NetrcReader.password`, `GitService.configArguments`).
  These have unit tests — please add tests when you add or change such logic.

## Tests

Run `make test` (or `swift test`). Add unit tests for any new pure logic — config parsing,
argument building, matching, normalization. UI/animation and live tool behavior
(`ssh-add`, real `gpg`, network calls) are verified manually; note in your PR what you
tested and how.

## Pull requests

1. Branch from `master`.
2. Keep each PR focused on one change.
3. `make build && make test && make lint` must pass before you open the PR.
4. Add an entry under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for user-facing changes.
5. Describe **what** changed and **how you verified it** (including any manual testing).
6. If your change affects the UI, a screenshot or short clip is appreciated.

## Reporting bugs

Open an issue with your macOS version, what you did, what you expected, and what happened.
For SSH/Git config issues, a redacted snippet of the relevant `~/.ssh/config` block (with
secrets removed) is extremely helpful — several real bugs have come from unusual but valid
config shapes.

## Releasing (maintainers)

kssh is distributed through a Homebrew tap at
[kitanoyoru/homebrew-kssh](https://github.com/kitanoyoru/homebrew-kssh), whose formula
builds from a tagged source tarball. To cut a release:

1. Bump `VERSION` in the `Makefile`, and move the `[Unreleased]` entries in
   [CHANGELOG.md](CHANGELOG.md) under a new `vX.Y.Z` heading.
2. Tag and push:

   ```sh
   git tag -a vX.Y.Z -m "kssh vX.Y.Z"
   git push origin vX.Y.Z
   ```

   The [release workflow](.github/workflows/release.yml) builds the `.app`, attaches a zipped
   build, and opens a **draft** GitHub Release with generated notes. Review and publish it.

3. Compute the source tarball's checksum (the Homebrew formula builds from source):

   ```sh
   curl -sL https://github.com/kitanoyoru/kssh/archive/refs/tags/vX.Y.Z.tar.gz \
     | shasum -a 256
   ```

4. In the tap repo, update `Formula/kssh.rb` — bump the `url` tag and the `sha256` — then
   verify before pushing:

   ```sh
   brew audit --strict kitanoyoru/kssh/kssh
   brew install --build-from-source kitanoyoru/kssh/kssh
   brew test kitanoyoru/kssh/kssh
   ```

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE).

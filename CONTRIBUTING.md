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
```

`make release` produces a bundled `.app`; `make install` copies it to `/Applications`.

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
3. `make build && make test` must pass before you open the PR.
4. Describe **what** changed and **how you verified it** (including any manual testing).
5. If your change affects the UI, a screenshot or short clip is appreciated.

## Reporting bugs

Open an issue with your macOS version, what you did, what you expected, and what happened.
For SSH/Git config issues, a redacted snippet of the relevant `~/.ssh/config` block (with
secrets removed) is extremely helpful — several real bugs have come from unusual but valid
config shapes.

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE).

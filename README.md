# kssh

> SSH, Git, and GPG identity management from the macOS menu bar.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://www.apple.com/macos/)
[![Language](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**kssh** lives in your menu bar and shows — at a glance — which SSH keys are loaded, which
identity is active, your Git config, GPG keys, and which remote (GitHub / GitLab) the
active key belongs to. Switch SSH identities and Git profiles in one click, without
hand-editing `~/.ssh/config` or running `git config`.

<p align="center">
  <img src="docs/preview.png" alt="kssh menu bar popover" width="320">
</p>

## Features

- **SSH keys at a glance** — see every keypair in `~/.ssh` and which are loaded in the
  agent. Each key shows its config-active state (✓) and agent-loaded state (⚡).
- **Switch identities** — pick a key to make it the active `IdentityFile`. kssh rewrites
  only the `Host` blocks that reference that key (never clobbering unrelated hosts) and
  reloads the agent. A timestamped backup is written before any edit.
- **Load / unload keys** — add a key to the agent (`ssh-add`) or remove it (`ssh-add -d`)
  without touching your config.
- **Git profiles** — define named identities (Work, Personal, …) and switch `user.name` /
  `user.email` globally in one tap. The active profile is highlighted.
- **GPG** — view your secret keys and create a new one (ed25519) from an in-app form.
- **Remote status** — resolves the GitHub/GitLab profile your token belongs to (username +
  avatar), and shows it **only when the active SSH key is registered on that account**.
  Tokens come from Settings or fall back to `~/.netrc`.
- **Copy to clipboard** — right-click any key fingerprint, public key, email, or key id.
- **Stays out of your way** — menu-bar only (no Dock icon), with in-popover navigation for
  profile and GPG management (no extra windows).

## Requirements

- macOS 14 (Sonoma) or later
- Swift toolchain / Xcode command-line tools (to build)
- `git` on `PATH`; `gnupg` optional (only for GPG features — `brew install gnupg`)

## Install

```sh
git clone https://github.com/kitanoyoru/kssh.git
cd kssh
make install        # builds a release .app and copies it to /Applications
```

Then launch **kssh** from `/Applications`. The key icon appears in your menu bar.

To uninstall: `make uninstall`.

## Build from source

```sh
make build          # debug build
make run            # build and run
make release        # release build + bundled .app under .build/release
make test           # run the test suite
```

## Usage

Click the menu-bar key icon to open the popover:

- **Keys** — tap a key to make it the active identity; use the ⚡/⬇ control on the right to
  load/unload it in the agent.
- **Git** — tap a profile to switch your global Git identity; **Manage profiles…** to add
  or edit them.
- **GPG** — **Create GPG key…** to generate one (requires `gnupg`).
- **Remote** — appears when the active key is linked to a GitHub/GitLab account. Add a
  Personal Access Token in **Settings**, or kssh will use the token in `~/.netrc` for the host.

## How it works

kssh shells out to the standard tools you already use — `ssh-add`, `ssh-keygen`, `git`,
`gpg` — and reads/writes `~/.ssh/config` and your global Git config directly. There is no
daemon and no telemetry; everything runs locally on demand. Personal Access Tokens are
stored in the macOS Keychain.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for dev setup, build/test
commands, code style, and the PR process. In short:

1. Fork and branch from `master`.
2. `make build && make test` must pass.
3. Keep changes focused; match the existing SwiftUI + design-token style.
4. Open a PR describing the change.

## License

[MIT](LICENSE) © Alexandr Rutkowski

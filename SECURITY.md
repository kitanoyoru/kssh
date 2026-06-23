# Security Policy

kssh manages SSH keys, Git configuration, GPG keys, and the Personal Access Tokens for your
GitHub / GitLab / Bitbucket accounts on your machine. Security reports are taken seriously.

## Supported versions

Security fixes are applied to the latest released version. Please upgrade to the most recent
release before reporting an issue.

| Version | Supported |
| ------- | --------- |
| 1.3.x   | ✅        |
| < 1.3   | ❌        |

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately through GitHub's
[security advisories](https://github.com/kitanoyoru/kssh/security/advisories/new). Include:

- a description of the issue and its impact,
- steps to reproduce (a redacted `~/.ssh/config` snippet is helpful for config-handling bugs),
- the kssh version and your macOS version.

You can expect an initial response within a few days. Once a fix is available, a new release
will be cut and the advisory published with credit to the reporter (unless anonymity is
requested).

## Scope and design notes

- kssh runs entirely locally. There is no backend, no telemetry, and no network calls other
  than the GitHub/GitLab/Bitbucket API requests made to resolve the profiles for your accounts.
- Personal Access Tokens are stored in the macOS Keychain, never in plaintext config.
- All external commands are invoked through `ProcessRunner` with argument arrays (no shell
  string interpolation), and a timestamped backup of `~/.ssh/config` is written before any edit.

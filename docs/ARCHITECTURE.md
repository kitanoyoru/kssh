# Architecture

kssh is a small SwiftUI menu-bar app. It has no backend, no database, and no daemon: it reads
and writes the same files and runs the same command-line tools you would use by hand
(`ssh-add`, `ssh-keygen`, `git`, `gpg`), and reflects the result back in the UI.

## Design philosophy

- **Shell out to the tools you already trust.** kssh never reimplements key or config logic.
  Every external action goes through `ProcessRunner`, which launches a process with an
  argument array — no shell, no manual quoting.
- **Local and transparent.** The only network calls are GitHub/GitLab/Bitbucket API requests
  to resolve the profiles for your accounts. There is no telemetry.
- **Pure logic is testable.** File parsing, argument building, and matching live in small pure
  functions (e.g. `SSHIdentityService.transform`, `NetrcReader.password`,
  `GitService.configArguments`) that are unit-tested without touching the system.

## Layers

```
ksshApp.swift            App entry. MenuBarExtra(.window) + Settings scenes; .accessory
                         activation policy (menu-bar only, no Dock icon).
        │  owns
        ▼
StatusViewModel          @MainActor ObservableObject. The single source of truth for the UI:
(ViewModels/)            @Published state, the refresh loop, and every user action.
        │  calls
        ▼
Services/                Stateless gateways to the outside world:
                           SSHService / SSHIdentityService — ~/.ssh/config + ssh-agent + key
                                                             lifecycle (generate/rename/delete)
                           GitService                      — global git config
                           GPGService                      — gpg secret keys + key creation
                           GitHubService / GitLabService /
                           BitbucketService                — remote account/profile lookup
                           RemoteKeyError                  — shared remote error type
        │  uses
        ▼
Utils/                   ProcessRunner (process launch), KeychainManager (token storage),
                         NetrcReader (~/.netrc parsing), Clipboard, LoginItem
                         (launch-at-login), WindowActivator.
```

Supporting pieces:

- **Models/** — plain value types (`SSHKey`, `SSHIdentity`, `GitProfile`, `GitIdentity`,
  `GPGIdentity`, `RemoteAccount`, `RemoteUser`, `RemoteProfileDetail`, `ContributionGraph`).
  No behavior beyond simple derivation.
- **Settings/** — `SettingsStore` persists account tokens (Keychain) and preferences
  (UserDefaults, e.g. auto-refresh interval and launch-at-login); `SettingsView` is the
  preferences window. The store instance is shared with the view model so the menu and
  settings observe the same state.
- **Theme.swift** — design tokens (`Spacing`, `Radius`, `StatusColor`) and shared view atoms
  (`SectionCard`, `KeyValueRow`, `MenuActionButtonStyle`). UI code composes these rather than
  using ad-hoc values.
- **MenuBarView.swift** — the popover UI and its in-popover routes (profile management, GPG
  key creation, remote-account management, and the remote profile detail screen), so no extra
  windows are needed.

## Data flow

1. **Read.** `StatusViewModel.refresh()` asks the services to enumerate keys, read the Git/GPG
   config, and resolve each configured remote account. Each service shells out via
   `ProcessRunner` or makes an API call, returns a Model, and the view model publishes it.
2. **Render.** `MenuBarView` observes the `@Published` state and draws the popover.
3. **Act.** A user action (switch identity, load/unload or generate/rename/delete a key, switch
   Git profile, create a GPG key, add/switch/remove a remote account) follows a consistent
   pattern in the view model: guard → set a busy flag → `defer` reset → `do/catch` mapping
   errors into `error` → `await refresh()`. Services surface failures as `LocalizedError`s
   shown in the in-popover banner.
4. **Refresh.** After an action completes, `refresh()` re-reads system state so the UI always
   reflects reality rather than an optimistic guess.

## Where to make changes

- **New surfaced data** → add a Model, extend the relevant Service to produce it, publish it
  from `StatusViewModel`, render it in `MenuBarView`.
- **New action** → add a Service method (pure helpers for any parsing/argument building, with
  tests), then a view-model action following the guard/defer/refresh pattern.
- **New remote provider** → add a `Service` alongside `GitHubService` / `GitLabService` /
  `BitbucketService` and surface it through the remote-account flow.
- **New external tool interaction** → route it through `ProcessRunner`; never invoke a shell
  directly.

import Foundation
import Combine

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var sshKeys: [SSHKey] = []
    @Published var gitIdentity: GitIdentity?
    @Published var gpgIdentity: GPGIdentity?
    @Published var githubUser: RemoteUser?
    @Published var gitlabUser: RemoteUser?
    @Published var bitbucketUser: RemoteUser?
    @Published var isLoading = false
    @Published var agentRunning = false
    @Published var agentSocket: String?
    @Published var error: String?
    /// Non-error, informational message (e.g. a switch that only changed the agent
    /// because the key isn't referenced in ~/.ssh/config). Shown in a neutral banner.
    @Published var notice: String?

    /// Keypairs discovered on disk under ~/.ssh, and which one is currently active.
    @Published var availableIdentities: [SSHIdentity] = []
    @Published var activeIdentity: SSHIdentity?
    @Published var switchingIdentity: String?
    /// Identity currently being loaded into the agent — separate from `switchingIdentity`
    /// so loading and switching don't lock each other out.
    @Published var loadingIdentity: String?

    /// GPG availability and key-creation state.
    @Published var gpgAvailable = false
    @Published var creatingGPGKey = false
    @Published var gpgCreateError: String?

    /// Git profile (work/study) currently being applied.
    @Published var switchingProfile: String?

    /// SSH key generation state (in-popover Create-key form).
    @Published var generatingKey = false
    @Published var keygenError: String?

    /// Id of the on-disk identity currently being deleted or renamed (for row spinner +
    /// disabling), and the last delete/rename failure.
    @Published var mutatingKey: String?
    @Published var keyActionError: String?

    /// The remote service the active key is currently being uploaded to, if any.
    @Published var addingKeyToRemote: RemoteService?

    /// Remote-account lifecycle busy state (mirrors the SSH-key flags). Each is keyed by
    /// the account id (or service, for add) so a row can show its own spinner.
    @Published var switchingAccount: String?
    @Published var mutatingAccount: String?
    @Published var addingAccount: RemoteService?
    @Published var testingAccount: String?
    /// Last delete/rename/secret-update or add error, surfaced inline on the screen.
    @Published var accountActionError: String?
    /// Per-account validation result from `testAccount`, keyed by account id.
    @Published var accountTestResult: [String: AccountTestState] = [:]
    /// Resolved profile (avatar + username) per account id, populated each refresh so every
    /// row shows its own avatar/username and any row can open its detail screen.
    @Published var accountUsers: [String: RemoteUser] = [:]

    /// Outcome of a per-account "Test" (validate credential) action.
    enum AccountTestState: Equatable {
        case valid(String)   // associated value: the resolved display name / username
        case invalid
    }

    /// True while an ssh-agent is being started (Enable button busy state).
    @Published var startingAgent = false

    /// Shared so the menu and the Manage-profiles window observe the same instance.
    let store = SettingsStore()
    private var refreshTask: Task<Void, Never>?

    /// The stored profile whose name+email match the current global git config, if any.
    var activeProfile: GitProfile? {
        GitProfile.active(in: store.gitProfiles, matching: gitIdentity)
    }

    /// Started from `MenuBarView.onAppear` and cancelled on `onDisappear`. Because
    /// `MenuBarExtra(.window)` tears down the view when the popover closes, this loop is
    /// intentionally bound to popover visibility: every open triggers an immediate
    /// `refresh()`, and no background work (ssh-add/ssh-keygen/network) runs while closed.
    /// The 60s loop only keeps data current during a long-open popover.
    func startAutoRefresh() {
        refreshTask = Task {
            await refresh()
            while !Task.isCancelled {
                // Interval is user-configurable; 0 means manual-only (no polling).
                let interval = store.refreshInterval
                guard interval > 0 else { break }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        async let sshResult = loadSSH()
        async let gitResult = loadGit()
        async let gpgResult = loadGPG()
        async let gpgAvailableResult = GPGService.isAvailable()

        let (keys, git, gpg, gpgAvail) = await (sshResult, gitResult, gpgResult, gpgAvailableResult)

        sshKeys = keys
        gitIdentity = git
        gpgIdentity = gpg
        gpgAvailable = gpgAvail

        // Resolve remote profiles, scoped to the ACTIVE SSH key: a remote is shown only
        // if the currently-active key is registered on the token's account. Switching to
        // a key that isn't on that account hides the row (see remoteSection's gate).
        // Token priority: the PAT set in Settings, falling back to the ~/.netrc password
        // for the host so existing git users work without re-entering a token.
        let githubToken = token(for: .github) ?? ""
        let gitlabToken = token(for: .gitlab) ?? ""

        // The loaded key matching the active config identity (by fingerprint). Only this
        // key is checked against each account; if there's no active loaded key, the remote
        // services see no keys and report 0 matches, which hides the rows.
        let activeKeys = activeKey(in: keys).map { [$0] } ?? []

        let bitbucketCreds = store.activeAccount(for: .bitbucket).flatMap { store.bitbucketCredentials(id: $0.id) }
        async let githubResult = GitHubService.user(forKeys: activeKeys, pat: githubToken)
        async let gitlabResult = GitLabService.user(forKeys: activeKeys, pat: gitlabToken, instance: store.activeGitlabInstance)
        async let bitbucketResult = BitbucketService.user(forKeys: activeKeys, username: bitbucketCreds?.username ?? "", appPassword: bitbucketCreds?.appPassword ?? "")
        let (gh, gl, bb) = await (githubResult, gitlabResult, bitbucketResult)
        githubUser = gh
        gitlabUser = gl
        bitbucketUser = bb

        if let signingKeyId = git?.signingKey {
            gpgIdentity = GPGIdentity(secretKeys: gpg?.secretKeys ?? [], signingKeyId: signingKeyId)
        }

        await resolveAccountUsers(activeKeys: activeKeys)

        isLoading = false
    }

    /// Resolves a `RemoteUser` (avatar + username + key-match) for EVERY configured account,
    /// using each account's own secret — so every row in the Remote list shows the right
    /// profile, not just the active one. Cached in `accountUsers` by account id.
    /// `matchedKeyCount` is computed against the active key, so a positive count marks the
    /// account that holds the currently-active SSH key.
    private func resolveAccountUsers(activeKeys: [SSHKey]) async {
        let refs: [(service: RemoteService, account: RemoteAccount)] =
            RemoteService.allCases.flatMap { service in
                store.accounts(for: service).map { (service, $0) }
            }

        let resolved = await withTaskGroup(of: (String, RemoteUser?).self) { group -> [String: RemoteUser] in
            for ref in refs {
                let service = ref.service
                let account = ref.account
                group.addTask { [self] in
                    (account.id, await user(for: service, account: account, activeKeys: activeKeys))
                }
            }
            var map: [String: RemoteUser] = [:]
            for await (id, user) in group where user != nil {
                map[id] = user
            }
            return map
        }
        accountUsers = resolved
    }

    /// Resolves the profile a specific account's credential belongs to.
    private func user(for service: RemoteService, account: RemoteAccount, activeKeys: [SSHKey]) async -> RemoteUser? {
        switch service {
        case .github:
            let pat = store.secret(for: .github, id: account.id) ?? ""
            return await GitHubService.user(forKeys: activeKeys, pat: pat)
        case .gitlab:
            let pat = store.secret(for: .gitlab, id: account.id) ?? ""
            let host = (account.instance?.isEmpty == false) ? account.instance! : "gitlab.com"
            return await GitLabService.user(forKeys: activeKeys, pat: pat, instance: host)
        case .bitbucket:
            guard let creds = store.bitbucketCredentials(id: account.id) else { return nil }
            return await BitbucketService.user(forKeys: activeKeys, username: creds.username, appPassword: creds.appPassword)
        }
    }

    private func loadSSH() async -> [SSHKey] {
        let running = await SSHService.isAgentRunning()
        agentRunning = running
        agentSocket = await SSHService.agentPid()

        // Discover on-disk keypairs and the active one regardless of agent state —
        // the config can be switched even when the agent is stopped.
        let identities = await SSHIdentityService.discover()
        availableIdentities = identities
        activeIdentity = SSHIdentityService.activeIdentity(among: identities, selectedPath: store.activeIdentityPath)

        // When the agent is off, the UI shows a dedicated "Agent off" section with an
        // Enable button instead of the normal sections, so no error banner is needed here.
        guard running else { return [] }

        return await SSHService.loadedKeys()
    }

    /// Switches the active SSH identity: rewrites ~/.ssh/config and reloads the
    /// agent, then refreshes all derived state.
    func switchIdentity(_ identity: SSHIdentity) async {
        guard switchingIdentity == nil else { return }
        switchingIdentity = identity.id
        error = nil
        notice = nil
        defer { switchingIdentity = nil }

        do {
            let result = try await SSHIdentityService.activate(identity)
            // Remember the explicit choice so the active highlight follows it, even when
            // the config layout (separate Host per key) can't express a single active key.
            store.activeIdentityPath = identity.privateKeyPath
            if result == .agentOnly {
                notice = "Switched in the agent only — \(identity.displayName) isn't referenced in ~/.ssh/config, so the file was left unchanged."
            }
        } catch {
            self.error = error.localizedDescription
            return
        }
        await refresh()
    }

    /// Starts a fresh ssh-agent and refreshes so the normal sections appear. Surfaces a
    /// failure via `error`.
    func startAgent() async {
        guard !startingAgent else { return }
        startingAgent = true
        error = nil
        defer { startingAgent = false }

        guard await SSHService.startAgent() else {
            error = "Could not start the SSH agent."
            return
        }
        await refresh()
    }

    /// Applies a git profile to global git config (user.name/user.email), then refreshes.
    /// Mirrors switchIdentity. A partial write surfaces via `error`; the refresh re-reads
    /// the real config so the active highlight stays truthful.
    func switchGitProfile(_ profile: GitProfile) async {
        guard switchingProfile == nil else { return }
        switchingProfile = profile.id
        error = nil
        defer { switchingProfile = nil }

        do {
            try await GitService.setIdentity(name: profile.name, email: profile.email)
        } catch {
            self.error = error.localizedDescription
            return
        }
        await refresh()
    }

    /// True when this on-disk identity is currently loaded in the agent. Both
    /// ssh-keygen and ssh-add report the same `SHA256:…` fingerprint, so a direct
    /// comparison is reliable.
    func isLoaded(_ identity: SSHIdentity) -> Bool {
        sshKeys.contains { $0.fingerprint == identity.fingerprint }
    }

    /// The loaded agent key corresponding to the active config identity (matched by
    /// fingerprint). Used to scope the Remote section to the active key only. Returns
    /// nil when no identity is active or its key isn't loaded.
    func activeKey(in keys: [SSHKey]) -> SSHKey? {
        guard let activeFingerprint = activeIdentity?.fingerprint else { return nil }
        return keys.first { $0.fingerprint == activeFingerprint }
    }

    /// Loads a single key into the agent (ssh-add) without rewriting ~/.ssh/config,
    /// then refreshes so the loaded-keys list reflects it.
    func loadIdentityIntoAgent(_ identity: SSHIdentity) async {
        guard loadingIdentity == nil else { return }
        loadingIdentity = identity.id
        error = nil
        defer { loadingIdentity = nil }

        do {
            try await SSHIdentityService.loadIntoAgent(identity)
        } catch {
            self.error = error.localizedDescription
            return
        }
        await refresh()
    }

    /// Unloads a single key from the agent (ssh-add -d) without rewriting config, then
    /// refreshes. `ssh-add -d` exits non-zero when the key isn't loaded, so a failure is
    /// only surfaced if the key is *still* loaded after refresh (a genuine failure) —
    /// otherwise it was an out-of-band race and is treated as success.
    func unloadIdentityFromAgent(_ identity: SSHIdentity) async {
        guard loadingIdentity == nil else { return }
        loadingIdentity = identity.id
        error = nil
        defer { loadingIdentity = nil }

        var unloadError: String?
        do {
            try await SSHIdentityService.unloadFromAgent(identity)
        } catch {
            unloadError = error.localizedDescription
        }
        await refresh()
        if let unloadError, isLoaded(identity) {
            self.error = unloadError
        }
    }

    /// Creates a new GPG key and refreshes to pick it up. Returns true on success.
    func createGPGKey(name: String, email: String, passphrase: String) async -> Bool {
        guard !creatingGPGKey else { return false }
        creatingGPGKey = true
        gpgCreateError = nil
        defer { creatingGPGKey = false }

        do {
            _ = try await GPGService.createKey(name: name, email: email, passphrase: passphrase)
        } catch {
            gpgCreateError = error.localizedDescription
            return false
        }
        await refresh()
        return true
    }

    // MARK: - SSH key lifecycle

    /// Generates a new SSH keypair (create-only — not loaded into the agent, not written to
    /// config) and refreshes so it appears in the Keys list. Returns true on success.
    func generateSSHKey(type: SSHIdentityService.KeyType, comment: String, passphrase: String) async -> Bool {
        guard !generatingKey else { return false }
        generatingKey = true
        keygenError = nil
        defer { generatingKey = false }

        do {
            _ = try await SSHIdentityService.generateKey(type: type, comment: comment, passphrase: passphrase)
        } catch {
            keygenError = error.localizedDescription
            return false
        }
        await refresh()
        return true
    }

    /// Deletes a key (unload from agent + move its files to a recoverable backup dir), then
    /// refreshes. Surfaces failures via `keyActionError`; a success sets a neutral `notice`.
    func deleteKey(_ identity: SSHIdentity) async {
        guard mutatingKey == nil else { return }
        mutatingKey = identity.id
        keyActionError = nil
        defer { mutatingKey = nil }

        do {
            try await SSHIdentityService.deleteKey(identity, trashSuffix: trashSuffix())
        } catch {
            keyActionError = error.localizedDescription
            return
        }
        notice = "Moved \(identity.name) to ~/.ssh/.kssh-trash (recoverable)."
        await refresh()
    }

    /// Renames a key's files in ~/.ssh, then refreshes. Returns true on success; failures
    /// (invalid name, name taken, key referenced in config) surface via `keyActionError`.
    func renameKey(_ identity: SSHIdentity, to newName: String) async -> Bool {
        guard mutatingKey == nil else { return false }
        mutatingKey = identity.id
        keyActionError = nil
        defer { mutatingKey = nil }

        do {
            _ = try await SSHIdentityService.renameKey(identity, to: newName)
        } catch {
            keyActionError = error.localizedDescription
            return false
        }
        await refresh()
        return true
    }

    /// Uploads the active key's public key to the given remote, reusing the same token
    /// resolution as `refresh()` (Settings PAT → ~/.netrc fallback). Refreshes afterwards so
    /// the Remote section's matched-key state updates. Returns true on success.
    func addActiveKeyToRemote(_ service: RemoteService) async -> Bool {
        guard addingKeyToRemote == nil else { return false }
        guard let active = activeIdentity, !active.publicKeyPath.isEmpty,
              let pub = try? String(contentsOfFile: active.publicKeyPath, encoding: .utf8) else {
            error = "No active key with a public key file to upload."
            return false
        }
        let publicKey = pub.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = token(for: service), !token.isEmpty else {
            error = "No \(service.rawValue) token. Add one in Settings."
            return false
        }

        addingKeyToRemote = service
        error = nil
        defer { addingKeyToRemote = nil }

        let title = active.comment.isEmpty ? "kssh — \(active.name)" : active.comment
        let result: Result<Void, RemoteKeyError>
        switch service {
        case .github:
            result = await GitHubService.addKey(title: title, publicKey: publicKey, pat: token)
        case .gitlab:
            result = await GitLabService.addKey(title: title, publicKey: publicKey, pat: token, instance: store.activeGitlabInstance)
        case .bitbucket:
            error = "Adding keys to Bitbucket isn't supported yet."
            return false
        }

        switch result {
        case .success:
            notice = "Added \(active.name) to \(service.rawValue)."
            await refresh()
            return true
        case .failure(let err):
            error = err.localizedDescription
            return false
        }
    }

    /// The token for a remote, resolved exactly as `refresh()` does: the Settings PAT,
    /// falling back to the `~/.netrc` password for the host. Returns nil for Bitbucket
    /// (token-based upload isn't supported).
    func token(for service: RemoteService) -> String? {
        switch service {
        case .github:
            let pat = store.activeAccount(for: .github).flatMap { store.secret(for: .github, id: $0.id) } ?? ""
            return pat.isEmpty ? NetrcReader.password(forMachine: "github.com") : pat
        case .gitlab:
            let host = store.activeGitlabInstance
            let pat = store.activeAccount(for: .gitlab).flatMap { store.secret(for: .gitlab, id: $0.id) } ?? ""
            return pat.isEmpty ? NetrcReader.password(forMachine: host) : pat
        case .bitbucket:
            return nil
        }
    }

    /// Extended profile detail for a SPECIFIC account, fetched lazily when its detail screen
    /// opens. Uses that account's own secret so any account (not just the active one) opens.
    func remoteProfileDetail(for service: RemoteService, account: RemoteAccount) async -> RemoteProfileDetail? {
        switch service {
        case .github:
            let pat = store.secret(for: .github, id: account.id) ?? ""
            return pat.isEmpty ? nil : await GitHubService.profileDetail(pat: pat)
        case .gitlab:
            let pat = store.secret(for: .gitlab, id: account.id) ?? ""
            let host = (account.instance?.isEmpty == false) ? account.instance! : "gitlab.com"
            return pat.isEmpty ? nil : await GitLabService.profileDetail(pat: pat, instance: host)
        case .bitbucket:
            guard let creds = store.bitbucketCredentials(id: account.id) else { return nil }
            return await BitbucketService.profileDetail(username: creds.username, appPassword: creds.appPassword)
        }
    }

    /// The contribution calendar for a specific GitHub account (nil for other services /
    /// failures), using that account's secret.
    func contributionGraph(for service: RemoteService, account: RemoteAccount) async -> ContributionGraph? {
        guard service == .github else { return nil }
        let pat = store.secret(for: .github, id: account.id) ?? ""
        return pat.isEmpty ? nil : await GitHubService.contributionGraph(pat: pat)
    }

    // MARK: - Remote account lifecycle
    //
    // Thin wrappers over the SettingsStore CRUD that add the same guard+defer busy-state
    // and post-mutation refresh as the SSH-key actions. The store does the Keychain work.

    /// Makes `account` the active one for its service, then refreshes derived remote state.
    func switchAccount(_ account: RemoteAccount, for service: RemoteService) async {
        guard switchingAccount == nil else { return }
        switchingAccount = account.id
        error = nil
        defer { switchingAccount = nil }
        store.setActive(id: account.id, for: service)
        await refresh()
    }

    /// Adds a GitHub/GitLab account (PAT). Returns true on success.
    func addAccount(label: String, secret: String, instance: String?, for service: RemoteService) async -> Bool {
        guard addingAccount == nil else { return false }
        addingAccount = service
        accountActionError = nil
        defer { addingAccount = nil }
        guard store.addAccount(label: label, secret: secret, instance: instance, for: service) != nil else {
            accountActionError = "Couldn’t add the account (limit reached?)."
            return false
        }
        await refresh()
        return true
    }

    /// Adds a Bitbucket account (username + app password). Returns true on success.
    func addBitbucketAccount(label: String, username: String, appPassword: String) async -> Bool {
        guard addingAccount == nil else { return false }
        addingAccount = .bitbucket
        accountActionError = nil
        defer { addingAccount = nil }
        guard store.addBitbucketAccount(label: label, username: username, appPassword: appPassword) != nil else {
            accountActionError = "Couldn’t add the account (limit reached?)."
            return false
        }
        await refresh()
        return true
    }

    /// Renames an account and (optionally) updates its secret/instance in one save.
    /// `secret`/`instance`/`username` nil means "leave unchanged". Returns true on success.
    func saveAccount(
        _ account: RemoteAccount,
        for service: RemoteService,
        label: String,
        secret: String? = nil,
        instance: String? = nil,
        username: String? = nil,
        appPassword: String? = nil
    ) async -> Bool {
        guard mutatingAccount == nil else { return false }
        mutatingAccount = account.id
        accountActionError = nil
        defer { mutatingAccount = nil }

        store.renameAccount(id: account.id, to: label, for: service)
        if let instance, service == .gitlab {
            store.updateInstance(id: account.id, instance: instance, for: service)
        }
        if service == .bitbucket {
            if let username, let appPassword {
                store.updateBitbucketSecret(id: account.id, username: username, appPassword: appPassword)
            }
        } else if let secret, !secret.isEmpty {
            store.updateSecret(id: account.id, secret: secret, for: service)
        }
        await refresh()
        return true
    }

    /// Deletes an account (purging its Keychain entries via the store) and refreshes.
    func deleteAccount(_ account: RemoteAccount, for service: RemoteService) async {
        guard mutatingAccount == nil else { return }
        mutatingAccount = account.id
        accountActionError = nil
        defer { mutatingAccount = nil }
        store.deleteAccount(id: account.id, for: service)
        notice = "Removed \(account.displayLabel) from \(service.rawValue)."
        await refresh()
    }

    /// Validates an account's stored credential by calling the provider's profile endpoint
    /// (non-nil result = valid). Stores the outcome in `accountTestResult[account.id]`.
    func testAccount(_ account: RemoteAccount, for service: RemoteService) async {
        guard testingAccount == nil else { return }
        testingAccount = account.id
        defer { testingAccount = nil }

        let detail: RemoteProfileDetail?
        switch service {
        case .github:
            let pat = store.secret(for: .github, id: account.id) ?? ""
            detail = pat.isEmpty ? nil : await GitHubService.profileDetail(pat: pat)
        case .gitlab:
            let pat = store.secret(for: .gitlab, id: account.id) ?? ""
            let host = (account.instance?.isEmpty == false) ? account.instance! : "gitlab.com"
            detail = pat.isEmpty ? nil : await GitLabService.profileDetail(pat: pat, instance: host)
        case .bitbucket:
            if let creds = store.bitbucketCredentials(id: account.id) {
                detail = await BitbucketService.profileDetail(username: creds.username, appPassword: creds.appPassword)
            } else {
                detail = nil
            }
        }
        accountTestResult[account.id] = detail.map { .valid($0.fullName ?? "Valid") } ?? .invalid
    }

    /// The resolved profile (avatar + username) for an account, if it was reachable on the
    /// last refresh. Every row uses this for its avatar/username and for opening detail.
    func accountUser(_ account: RemoteAccount) -> RemoteUser? {
        accountUsers[account.id]
    }

    /// Whether the active SSH key is registered on this account (drives the "linked" dot).
    func isKeyLinked(_ account: RemoteAccount) -> Bool {
        accountUsers[account.id]?.belongsToActiveKey ?? false
    }

    /// Whether `account` is the active one for its service.
    func isActiveAccount(_ account: RemoteAccount, for service: RemoteService) -> Bool {
        store.activeAccount(for: service)?.id == account.id
    }

    /// A unique-ish backup subdirectory name. `Date()` is intentionally read here (the app
    /// layer), keeping the pure service code testable.
    private func trashSuffix() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private func loadGit() async -> GitIdentity? {
        await GitService.identity()
    }

    private func loadGPG() async -> GPGIdentity? {
        await GPGService.identity()
    }
}

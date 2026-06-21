import Foundation
import Combine

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var sshKeys: [SSHKey] = []
    @Published var gitIdentity: GitIdentity?
    @Published var gpgIdentity: GPGIdentity?
    @Published var githubUser: RemoteUser?
    @Published var gitlabUser: RemoteUser?
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
                try? await Task.sleep(for: .seconds(60))
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
        let gitlabHost = store.gitlabInstance.isEmpty ? "gitlab.com" : store.gitlabInstance
        let githubToken = store.githubPat.isEmpty ? (NetrcReader.password(forMachine: "github.com") ?? "") : store.githubPat
        let gitlabToken = store.gitlabPat.isEmpty ? (NetrcReader.password(forMachine: gitlabHost) ?? "") : store.gitlabPat

        // The loaded key matching the active config identity (by fingerprint). Only this
        // key is checked against each account; if there's no active loaded key, the remote
        // services see no keys and report 0 matches, which hides the rows.
        let activeKeys = activeKey(in: keys).map { [$0] } ?? []

        async let githubResult = GitHubService.user(forKeys: activeKeys, pat: githubToken)
        async let gitlabResult = GitLabService.user(forKeys: activeKeys, pat: gitlabToken, instance: store.gitlabInstance)
        let (gh, gl) = await (githubResult, gitlabResult)
        githubUser = gh
        gitlabUser = gl

        if let signingKeyId = git?.signingKey {
            gpgIdentity = GPGIdentity(secretKeys: gpg?.secretKeys ?? [], signingKeyId: signingKeyId)
        }

        isLoading = false
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

    private func loadGit() async -> GitIdentity? {
        await GitService.identity()
    }

    private func loadGPG() async -> GPGIdentity? {
        await GPGService.identity()
    }
}

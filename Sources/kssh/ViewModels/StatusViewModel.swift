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

    private let store = SettingsStore()
    private var refreshTask: Task<Void, Never>?

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

        if !keys.isEmpty {
            async let githubResult = GitHubService.user(forKeys: keys, pat: store.githubPat)
            async let gitlabResult = GitLabService.user(forKeys: keys, pat: store.gitlabPat, instance: store.gitlabInstance)
            let (gh, gl) = await (githubResult, gitlabResult)
            githubUser = gh
            gitlabUser = gl
        }

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
        activeIdentity = SSHIdentityService.activeIdentity(among: identities)

        guard running else {
            error = "SSH agent not running. Start it with: eval \"$(ssh-agent -s)\""
            return []
        }

        return await SSHService.loadedKeys()
    }

    /// Switches the active SSH identity: rewrites ~/.ssh/config and reloads the
    /// agent, then refreshes all derived state.
    func switchIdentity(_ identity: SSHIdentity) async {
        guard switchingIdentity == nil else { return }
        switchingIdentity = identity.id
        error = nil
        defer { switchingIdentity = nil }

        do {
            try await SSHIdentityService.activate(identity)
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

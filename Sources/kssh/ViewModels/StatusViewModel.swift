import Combine
import Foundation

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var sshKeys: [SSHKey] = []
    @Published var gitIdentity: GitIdentity?
    @Published var gpgIdentity: GPGIdentity?
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
        activeIdentity = SSHIdentityService.activeIdentity(
            among: identities, selectedPath: store.activeIdentityPath)

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
                notice =
                    "Switched in the agent only — \(identity.displayName) isn't referenced in ~/.ssh/config, so the file was left unchanged."
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
    func generateSSHKey(
        type: SSHIdentityService.KeyType, comment: String, passphrase: String
    ) async -> Bool {
        guard !generatingKey else { return false }
        generatingKey = true
        keygenError = nil
        defer { generatingKey = false }

        do {
            _ = try await SSHIdentityService.generateKey(
                type: type, comment: comment, passphrase: passphrase)
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

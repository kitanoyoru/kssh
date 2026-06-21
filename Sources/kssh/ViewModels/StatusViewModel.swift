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

    private let store = SettingsStore()
    private var refreshTask: Task<Void, Never>?

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

        let (keys, git, gpg) = await (sshResult, gitResult, gpgResult)

        sshKeys = keys
        gitIdentity = git
        gpgIdentity = gpg

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

        guard running else {
            error = "SSH agent not running. Start it with: eval \"$(ssh-agent -s)\""
            return []
        }

        return await SSHService.loadedKeys()
    }

    private func loadGit() async -> GitIdentity? {
        await GitService.identity()
    }

    private func loadGPG() async -> GPGIdentity? {
        await GPGService.identity()
    }
}

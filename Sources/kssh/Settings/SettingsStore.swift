import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    @Published var githubPat: String {
        didSet { KeychainManager.save(key: "githubPat", value: githubPat) }
    }
    @Published var gitlabPat: String {
        didSet { KeychainManager.save(key: "gitlabPat", value: gitlabPat) }
    }
    @AppStorage("gitlabInstance") var gitlabInstance = "gitlab.com"

    init() {
        self.githubPat = KeychainManager.read(key: "githubPat") ?? ""
        self.gitlabPat = KeychainManager.read(key: "gitlabPat") ?? ""
    }

    var hasGitHubToken: Bool { !githubPat.isEmpty }
    var hasGitLabToken: Bool { !gitlabPat.isEmpty }
}

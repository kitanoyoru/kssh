import Foundation

enum RemoteService: String, CaseIterable {
    case github = "GitHub"
    case gitlab = "GitLab"
}

struct RemoteUser: Equatable {
    let service: RemoteService
    let username: String
    let matchedKeyCount: Int

    var displayName: String {
        "@\(username)"
    }
}

import Foundation

enum RemoteService: String, CaseIterable {
    case github = "GitHub"
    case gitlab = "GitLab"
    case bitbucket = "Bitbucket"
}

struct RemoteUser: Equatable {
    let service: RemoteService
    let username: String
    let matchedKeyCount: Int
    let avatarUrl: URL?
    /// Full display name from the provider profile (e.g. "John Doe"). Nil when the
    /// provider doesn't return one or it's the same as the username.
    let displayNameFull: String?
    /// Canonical profile URL — opened in the browser when the row is tapped.
    let profileUrl: URL?

    var displayName: String {
        "@\(username)"
    }

    /// True when the active SSH key is registered on this account. `matchedKeyCount` is
    /// computed against the active key only (0 or 1), so a positive count means the
    /// remote belongs to the currently-active key and should be shown.
    var belongsToActiveKey: Bool {
        matchedKeyCount >= 1
    }
}

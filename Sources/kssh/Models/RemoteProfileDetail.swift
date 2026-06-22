import Foundation

/// Extended profile info for a remote account, fetched lazily when the user opens a
/// remote's detail screen (kept out of the per-refresh fetch to avoid extra API calls).
/// Every field is optional: each provider fills only what its API returns, and the UI
/// omits anything missing. `RemoteUser` already carries username/avatar/profile URL.
struct RemoteProfileDetail: Equatable {
    var fullName: String?
    var bio: String?
    var company: String?
    var location: String?
    var publicRepos: Int?
    var followers: Int?
    var following: Int?
    /// Account creation date, displayed as the "joined" year/date.
    var joinedAt: Date?
}

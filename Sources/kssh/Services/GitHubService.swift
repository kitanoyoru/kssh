import Foundation

struct GitHubService {
    /// Resolves the profile the token belongs to (username + avatar). Returns nil when
    /// the token is empty or doesn't resolve (no profile, 401, network error) — the UI
    /// hides the GitHub row in that case. `matchedKeyCount` is a secondary detail: how
    /// many of the local SSH keys are registered on that account.
    static func user(forKeys localKeys: [SSHKey], pat: String) async -> RemoteUser? {
        guard !pat.isEmpty else { return nil }

        guard let profile = await fetchProfile(pat: pat) else { return nil }
        let matchedCount = await matchedKeyCount(forKeys: localKeys, pat: pat)

        return RemoteUser(
            service: .github,
            username: profile.login,
            matchedKeyCount: matchedCount,
            avatarUrl: URL(string: profile.avatarUrl ?? "")
        )
    }

    private static func fetchProfile(pat: String) async -> GitHubUser? {
        guard let url = URL(string: "https://api.github.com/user") else { return nil }
        guard let data = await get(url, pat: pat) else { return nil }
        return try? JSONDecoder().decode(GitHubUser.self, from: data)
    }

    /// Counts local SSH keys that are registered on the account. Best-effort: returns 0
    /// if the keys endpoint fails (it must not block showing the resolved profile).
    private static func matchedKeyCount(forKeys localKeys: [SSHKey], pat: String) async -> Int {
        guard !localKeys.isEmpty,
              let url = URL(string: "https://api.github.com/user/keys"),
              let data = await get(url, pat: pat),
              let keys = try? JSONDecoder().decode([GitHubKey].self, from: data) else {
            return 0
        }
        let localPublicKeys = Set(localKeys.map { normalizeKey($0.publicKey) })
        return keys.filter { localPublicKeys.contains(normalizeKey($0.key)) }.count
    }

    /// GET helper returning the body only on HTTP 200, nil otherwise.
    private static func get(_ url: URL, pat: String) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("kssh", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return data
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
}

private struct GitHubKey: Decodable {
    let id: Int
    let key: String
}

private struct GitHubUser: Decodable {
    let login: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

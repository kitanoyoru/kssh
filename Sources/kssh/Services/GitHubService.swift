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
            avatarUrl: URL(string: profile.avatarUrl ?? ""),
            displayNameFull: profile.name,
            profileUrl: profile.htmlUrl.flatMap(URL.init)
        )
    }

    private static func fetchProfile(pat: String) async -> GitHubUser? {
        guard let url = URL(string: "https://api.github.com/user") else { return nil }
        guard let data = await get(url, pat: pat) else { return nil }
        return try? JSONDecoder().decode(GitHubUser.self, from: data)
    }

    /// Extended profile detail (bio, repo/follower counts, join date) for the detail
    /// screen. Fetched lazily on tap, not during the per-refresh resolution. Returns nil
    /// on empty token or any failure.
    static func profileDetail(pat: String) async -> RemoteProfileDetail? {
        guard !pat.isEmpty, let profile = await fetchProfile(pat: pat) else { return nil }
        return RemoteProfileDetail(
            fullName: profile.name,
            bio: profile.bio,
            company: profile.company,
            location: profile.location,
            publicRepos: profile.publicRepos,
            followers: profile.followers,
            following: profile.following,
            joinedAt: ISO8601DateFormatter().date(from: profile.createdAt ?? "")
        )
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

    /// Registers `publicKey` on the token's account via `POST /user/keys`. 201 = created;
    /// a 422 (GitHub's "key is already in use") maps to `.alreadyExists` so the UI can show
    /// a friendly message instead of a raw status code.
    static func addKey(title: String, publicKey: String, pat: String) async -> Result<Void, RemoteKeyError> {
        guard !pat.isEmpty else { return .failure(.noToken) }
        guard let request = addKeyRequest(title: title, publicKey: publicKey, pat: pat) else {
            return .failure(.network)
        }

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .failure(.network)
        }
        switch http.statusCode {
        case 201: return .success(())
        case 422: return .failure(.alreadyExists)
        default: return .failure(.http(http.statusCode))
        }
    }

    /// Pure, testable builder for the add-key request (URL, method, headers, JSON body), so
    /// the request shape can be asserted without hitting the network.
    static func addKeyRequest(title: String, publicKey: String, pat: String) -> URLRequest? {
        guard let url = URL(string: "https://api.github.com/user/keys") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("kssh", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": title, "key": publicKey])
        request.timeoutInterval = 10
        return request
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

    /// Normalizes an OpenSSH public key for comparison to just `<type> <base64-blob>`,
    /// dropping the trailing comment. GitHub's /user/keys returns keys without a comment,
    /// while `ssh-add -L` includes one (e.g. "… user@host") — so comparing the full line
    /// never matched. Two keys are equal iff their type + blob match.
    static func normalizeKey(_ key: String) -> String {
        let fields = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
        return fields.prefix(2).joined(separator: " ")
    }
}

private struct GitHubKey: Decodable {
    let id: Int
    let key: String
}

private struct GitHubUser: Decodable {
    let login: String
    let avatarUrl: String?
    let name: String?
    let htmlUrl: String?
    let bio: String?
    let company: String?
    let location: String?
    let publicRepos: Int?
    let followers: Int?
    let following: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
        case name
        case htmlUrl = "html_url"
        case bio
        case company
        case location
        case publicRepos = "public_repos"
        case followers
        case following
        case createdAt = "created_at"
    }
}

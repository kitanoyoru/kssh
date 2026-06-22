import Foundation

struct GitLabService {
    /// Resolves the profile the token belongs to (username + avatar) on the configured
    /// instance. Returns nil when the token is empty or doesn't resolve — the UI hides
    /// the GitLab row then. `matchedKeyCount` is a secondary detail.
    static func user(forKeys localKeys: [SSHKey], pat: String, instance: String) async -> RemoteUser? {
        guard !pat.isEmpty else { return nil }

        let host = instance.isEmpty ? "gitlab.com" : instance
        guard let profile = await fetchProfile(pat: pat, instance: host) else { return nil }
        let matchedCount = await matchedKeyCount(forKeys: localKeys, pat: pat, instance: host)

        return RemoteUser(
            service: .gitlab,
            username: profile.username,
            matchedKeyCount: matchedCount,
            avatarUrl: URL(string: profile.avatarUrl ?? ""),
            displayNameFull: profile.name,
            profileUrl: profile.webUrl.flatMap(URL.init)
        )
    }

    private static func fetchProfile(pat: String, instance: String) async -> GitLabUser? {
        guard let url = URL(string: "https://\(instance)/api/v4/user") else { return nil }
        guard let data = await get(url, pat: pat) else { return nil }
        return try? JSONDecoder().decode(GitLabUser.self, from: data)
    }

    /// Extended profile detail for the detail screen. GitLab's user endpoint returns
    /// name, bio, organization, location, and join date; it does NOT return follower or
    /// repo counts, so those stay nil and the UI omits them. Fetched lazily on tap.
    static func profileDetail(pat: String, instance: String) async -> RemoteProfileDetail? {
        guard !pat.isEmpty else { return nil }
        let host = instance.isEmpty ? "gitlab.com" : instance
        guard let profile = await fetchProfile(pat: pat, instance: host) else { return nil }
        return RemoteProfileDetail(
            fullName: profile.name,
            bio: profile.bio,
            company: profile.organization,
            location: profile.location,
            publicRepos: nil,
            followers: nil,
            following: nil,
            joinedAt: ISO8601DateFormatter().date(from: profile.createdAt ?? "")
        )
    }

    /// Best-effort count of local SSH keys registered on the account; 0 on any failure.
    private static func matchedKeyCount(forKeys localKeys: [SSHKey], pat: String, instance: String) async -> Int {
        guard !localKeys.isEmpty,
              let url = URL(string: "https://\(instance)/api/v4/user/keys"),
              let data = await get(url, pat: pat),
              let keys = try? JSONDecoder().decode([GitLabKey].self, from: data) else {
            return 0
        }
        let localPublicKeys = Set(localKeys.map { normalizeKey($0.publicKey) })
        return keys.filter { localPublicKeys.contains(normalizeKey($0.key)) }.count
    }

    /// Registers `publicKey` on the token's account via `POST /api/v4/user/keys`. 201 =
    /// created; a 400 (GitLab's "fingerprint has already been taken") maps to
    /// `.alreadyExists` for a friendly message.
    static func addKey(title: String, publicKey: String, pat: String, instance: String) async -> Result<Void, RemoteKeyError> {
        guard !pat.isEmpty else { return .failure(.noToken) }
        guard let request = addKeyRequest(title: title, publicKey: publicKey, pat: pat, instance: instance) else {
            return .failure(.network)
        }

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .failure(.network)
        }
        switch http.statusCode {
        case 201: return .success(())
        case 400: return .failure(.alreadyExists)
        default: return .failure(.http(http.statusCode))
        }
    }

    /// Pure, testable builder for the add-key request, instance-aware. Lets tests assert
    /// the URL/method/headers/body without a network call.
    static func addKeyRequest(title: String, publicKey: String, pat: String, instance: String) -> URLRequest? {
        let host = instance.isEmpty ? "gitlab.com" : instance
        guard let url = URL(string: "https://\(host)/api/v4/user/keys") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": title, "key": publicKey])
        request.timeoutInterval = 10
        return request
    }

    /// GET helper returning the body only on HTTP 200, nil otherwise.
    private static func get(_ url: URL, pat: String) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return data
    }

    /// Normalizes an OpenSSH public key to `<type> <base64-blob>`, dropping the trailing
    /// comment — GitLab's API omits it while `ssh-add -L` includes one, so full-line
    /// comparison never matched.
    private static func normalizeKey(_ key: String) -> String {
        let fields = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
        return fields.prefix(2).joined(separator: " ")
    }
}

private struct GitLabKey: Decodable {
    let id: Int
    let key: String
}

private struct GitLabUser: Decodable {
    let username: String
    let avatarUrl: String?
    let name: String?
    let webUrl: String?
    let bio: String?
    let organization: String?
    let location: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case username
        case avatarUrl = "avatar_url"
        case name
        case webUrl = "web_url"
        case bio
        case organization
        case location
        case createdAt = "created_at"
    }
}

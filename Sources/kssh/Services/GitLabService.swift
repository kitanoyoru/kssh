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
            avatarUrl: URL(string: profile.avatarUrl ?? "")
        )
    }

    private static func fetchProfile(pat: String, instance: String) async -> GitLabUser? {
        guard let url = URL(string: "https://\(instance)/api/v4/user") else { return nil }
        guard let data = await get(url, pat: pat) else { return nil }
        return try? JSONDecoder().decode(GitLabUser.self, from: data)
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

    enum CodingKeys: String, CodingKey {
        case username
        case avatarUrl = "avatar_url"
    }
}

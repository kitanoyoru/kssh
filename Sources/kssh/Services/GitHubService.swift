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

    /// The viewer's contribution calendar (last year) via the GraphQL API. Fetched lazily
    /// for the detail screen. Returns nil on empty token, non-200, or any GraphQL error so
    /// the caller simply hides the graph — it must never block the rest of the screen.
    static func contributionGraph(pat: String) async -> ContributionGraph? {
        guard !pat.isEmpty else { return nil }
        guard let data = await postGraphQL(query: contributionQuery, pat: pat) else { return nil }
        return parseContributionCalendar(data)
    }

    private static let contributionQuery = """
        query { viewer { contributionsCollection { contributionCalendar { \
        weeks { contributionDays { date contributionCount } } } } } }
        """

    /// Pure, testable decoder for the GraphQL contribution-calendar response. Maps each
    /// day's count into a 0–4 level via `ContributionGraph.level(forCount:)`. Returns nil
    /// if the payload is missing the expected shape or carries `errors`.
    static func parseContributionCalendar(_ data: Data) -> ContributionGraph? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if root["errors"] != nil { return nil }
        guard let dataObj = root["data"] as? [String: Any],
            let viewer = dataObj["viewer"] as? [String: Any],
            let collection = viewer["contributionsCollection"] as? [String: Any],
            let calendar = collection["contributionCalendar"] as? [String: Any],
            let weeksRaw = calendar["weeks"] as? [[String: Any]]
        else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let weeks: [[ContributionDay]] = weeksRaw.map { week in
            let days = (week["contributionDays"] as? [[String: Any]]) ?? []
            return days.compactMap { day -> ContributionDay? in
                guard let dateStr = day["date"] as? String,
                    let date = formatter.date(from: dateStr),
                    let count = day["contributionCount"] as? Int
                else { return nil }
                return ContributionDay(
                    date: date, count: count, level: ContributionGraph.level(forCount: count))
            }
        }
        return ContributionGraph(weeks: weeks)
    }

    /// POSTs a GraphQL query to the GitHub v4 endpoint. Sibling to `get(_:pat:)` for the
    /// REST v3 calls; reuses the same Bearer/User-Agent headers. Body is `{"query": …}`.
    private static func postGraphQL(query: String, pat: String) async -> Data? {
        guard let url = URL(string: "https://api.github.com/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("kssh", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            return nil
        }
        return data
    }

    /// Counts local SSH keys that are registered on the account. Best-effort: returns 0
    /// if the keys endpoint fails (it must not block showing the resolved profile).
    private static func matchedKeyCount(forKeys localKeys: [SSHKey], pat: String) async -> Int {
        guard !localKeys.isEmpty,
            let url = URL(string: "https://api.github.com/user/keys"),
            let data = await get(url, pat: pat),
            let keys = try? JSONDecoder().decode([GitHubKey].self, from: data)
        else {
            return 0
        }
        let localPublicKeys = Set(localKeys.map { normalizeKey($0.publicKey) })
        return keys.filter { localPublicKeys.contains(normalizeKey($0.key)) }.count
    }

    /// Registers `publicKey` on the token's account via `POST /user/keys`. 201 = created;
    /// a 422 (GitHub's "key is already in use") maps to `.alreadyExists` so the UI can show
    /// a friendly message instead of a raw status code.
    static func addKey(
        title: String, publicKey: String, pat: String
    ) async -> Result<Void, RemoteKeyError> {
        guard !pat.isEmpty else { return .failure(.noToken) }
        guard let request = addKeyRequest(title: title, publicKey: publicKey, pat: pat) else {
            return .failure(.network)
        }

        guard let (_, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse
        else {
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "title": title, "key": publicKey,
        ])
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
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
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

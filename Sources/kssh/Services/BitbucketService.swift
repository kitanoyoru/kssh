import Foundation

struct BitbucketService {
    /// Resolves the Bitbucket Cloud profile for the given credentials, scoped to the
    /// active SSH key. Returns nil when credentials are empty, the profile can't be
    /// resolved, or a network/auth error occurs — the UI hides the row in that case.
    static func user(forKeys localKeys: [SSHKey], username: String, appPassword: String) async -> RemoteUser? {
        guard !username.isEmpty, !appPassword.isEmpty else { return nil }

        let auth = basicAuth(username: username, password: appPassword)
        guard let profile = await fetchProfile(auth: auth) else { return nil }
        let matchedCount = await matchedKeyCount(forKeys: localKeys, accountId: profile.accountId, auth: auth)

        return RemoteUser(
            service: .bitbucket,
            username: profile.displayName,
            matchedKeyCount: matchedCount,
            avatarUrl: profile.links.avatar.flatMap { URL(string: $0.href) },
            displayNameFull: nil,
            profileUrl: profile.links.html.flatMap { URL(string: $0.href) }
        )
    }

    private static func fetchProfile(auth: String) async -> BitbucketUser? {
        guard let url = URL(string: "https://api.bitbucket.org/2.0/user") else { return nil }
        guard let data = await get(url, auth: auth) else { return nil }
        return try? JSONDecoder().decode(BitbucketUser.self, from: data)
    }

    /// Extended profile detail for the detail screen. Bitbucket's user endpoint is sparse:
    /// it returns the display name, location, and creation date — no follower or repo
    /// counts — so those stay nil and the UI omits them. Fetched lazily on tap.
    static func profileDetail(username: String, appPassword: String) async -> RemoteProfileDetail? {
        guard !username.isEmpty, !appPassword.isEmpty else { return nil }
        let auth = basicAuth(username: username, password: appPassword)
        guard let profile = await fetchProfile(auth: auth) else { return nil }
        return RemoteProfileDetail(
            fullName: profile.displayName,
            bio: nil,
            company: nil,
            location: profile.location,
            publicRepos: nil,
            followers: nil,
            following: nil,
            joinedAt: profile.createdOn.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    /// Best-effort count of local SSH keys registered on the account; 0 on any failure.
    /// Follows Bitbucket's cursor-based pagination (up to 10 pages).
    private static func matchedKeyCount(forKeys localKeys: [SSHKey], accountId: String, auth: String) async -> Int {
        guard !localKeys.isEmpty else { return 0 }
        let localPublicKeys = Set(localKeys.map { normalizeKey($0.publicKey) })

        var nextUrl: URL? = URL(string: "https://api.bitbucket.org/2.0/users/\(accountId)/ssh-keys")
        var matched = 0
        var pageLimit = 10

        while let url = nextUrl, pageLimit > 0 {
            pageLimit -= 1
            guard let data = await get(url, auth: auth),
                  let page = try? JSONDecoder().decode(BitbucketPage<BitbucketKey>.self, from: data) else {
                break
            }
            matched += page.values.filter { localPublicKeys.contains(normalizeKey($0.key)) }.count
            nextUrl = page.next.flatMap(URL.init)
        }
        return matched
    }

    private static func get(_ url: URL, auth: String) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("kssh", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return data
    }

    private static func basicAuth(username: String, password: String) -> String {
        let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    /// Normalizes an OpenSSH public key to `<type> <base64-blob>`, dropping the trailing
    /// comment — Bitbucket's API may omit it while `ssh-add -L` includes one.
    private static func normalizeKey(_ key: String) -> String {
        let fields = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
        return fields.prefix(2).joined(separator: " ")
    }
}

private struct BitbucketPage<T: Decodable>: Decodable {
    let values: [T]
    let next: String?
}

private struct BitbucketKey: Decodable {
    let key: String
}

private struct BitbucketUser: Decodable {
    let accountId: String
    let displayName: String
    let location: String?
    let createdOn: String?
    let links: BitbucketLinks

    struct BitbucketLinks: Decodable {
        let avatar: BitbucketHref?
        let html: BitbucketHref?
        struct BitbucketHref: Decodable { let href: String }
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case displayName = "display_name"
        case location
        case createdOn = "created_on"
        case links
    }
}

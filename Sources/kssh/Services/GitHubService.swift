import Foundation

struct GitHubService {
    static func user(forKeys localKeys: [SSHKey], pat: String) async -> RemoteUser? {
        guard !pat.isEmpty, !localKeys.isEmpty else { return nil }

        guard let url = URL(string: "https://api.github.com/user/keys") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("kssh", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let keys = try JSONDecoder().decode([GitHubKey].self, from: data)
            let localPublicKeys = Set(localKeys.map { normalizeKey($0.publicKey) })
            let matched = keys.filter { localPublicKeys.contains(normalizeKey($0.key)) }

            if !matched.isEmpty {
                let username = try await fetchUsername(pat: pat)
                return RemoteUser(service: .github, username: username, matchedKeyCount: matched.count)
            }
        } catch {
            return nil
        }

        return nil
    }

    private static func fetchUsername(pat: String) async throws -> String {
        guard let url = URL(string: "https://api.github.com/user") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("kssh", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        let user = try JSONDecoder().decode(GitHubUser.self, from: data)
        return user.login
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
}

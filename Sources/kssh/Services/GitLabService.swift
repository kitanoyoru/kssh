import Foundation

struct GitLabService {
    static func user(forKeys localKeys: [SSHKey], pat: String, instance: String) async -> RemoteUser? {
        guard !pat.isEmpty, !localKeys.isEmpty else { return nil }

        let host = instance.isEmpty ? "gitlab.com" : instance
        guard let url = URL(string: "https://\(host)/api/v4/user/keys") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let keys = try JSONDecoder().decode([GitLabKey].self, from: data)
            let localPublicKeys = Set(localKeys.map { normalizeKey($0.publicKey) })
            let matched = keys.filter { localPublicKeys.contains(normalizeKey($0.key)) }

            if !matched.isEmpty {
                let username = try await fetchUsername(pat: pat, instance: host)
                return RemoteUser(service: .gitlab, username: username, matchedKeyCount: matched.count)
            }
        } catch {
            return nil
        }

        return nil
    }

    private static func fetchUsername(pat: String, instance: String) async throws -> String {
        guard let url = URL(string: "https://\(instance)/api/v4/user") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        let user = try JSONDecoder().decode(GitLabUser.self, from: data)
        return user.username
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
}

private struct GitLabKey: Decodable {
    let id: Int
    let key: String
}

private struct GitLabUser: Decodable {
    let username: String
}

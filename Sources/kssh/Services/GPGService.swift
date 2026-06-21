import Foundation

struct GPGService {
    static func identity() async -> GPGIdentity? {
        let gpgAvailable = await ProcessRunner.checkAvailable("gpg")
        guard gpgAvailable else { return nil }

        let result = await ProcessRunner.run("gpg", arguments: ["--list-secret-keys", "--keyid-format", "LONG"])
        guard let output = result, output.exitCode == 0 else { return nil }

        var keys: [GPGKey] = []
        var currentKeyId: String?
        var currentUserId: String?

        for line in output.output.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("sec") {
                if let keyId = currentKeyId, let userId = currentUserId {
                    keys.append(GPGKey(keyId: keyId, userId: userId))
                }
                let parts = trimmed.split(separator: "/")
                if parts.count >= 2 {
                    currentKeyId = String(parts[1].split(separator: " ").first ?? "")
                }
                currentUserId = nil
            } else if trimmed.hasPrefix("uid") {
                var uid = trimmed
                uid = uid.replacingOccurrences(of: "[trust]", with: "")
                    .replacingOccurrences(of: "[ultimate]", with: "")
                    .replacingOccurrences(of: "[full]", with: "")
                    .replacingOccurrences(of: "[unknown]", with: "")
                if let bracketRange = uid.range(of: "]") {
                    uid = String(uid[bracketRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                } else if let spaceIndex = uid.firstIndex(of: " ") {
                    uid = String(uid[spaceIndex...]).trimmingCharacters(in: .whitespaces)
                }
                currentUserId = uid
            }
        }

        if let keyId = currentKeyId, let userId = currentUserId {
            keys.append(GPGKey(keyId: keyId, userId: userId))
        }

        return GPGIdentity(secretKeys: keys, signingKeyId: nil)
    }
}

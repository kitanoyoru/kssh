import Foundation

struct GPGService {
    static func identity() async -> GPGIdentity? {
        let gpgAvailable = await ProcessRunner.checkAvailable("gpg")
        guard gpgAvailable else { return nil }

        let result = await ProcessRunner.run(
            "gpg", arguments: ["--list-secret-keys", "--keyid-format", "LONG"])
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
                    uid = String(uid[bracketRange.upperBound...]).trimmingCharacters(
                        in: .whitespaces)
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

    // MARK: - Availability

    static func isAvailable() async -> Bool {
        await ProcessRunner.checkAvailable("gpg")
    }

    static func homebrewAvailable() async -> Bool {
        await ProcessRunner.checkAvailable("brew")
    }

    // MARK: - Key creation

    enum GPGServiceError: LocalizedError {
        case notInstalled
        case generationFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "gpg is not installed. Install it with: brew install gnupg"
            case .generationFailed(let msg):
                return "GPG key generation failed: \(msg)"
            case .timedOut:
                return
                    "GPG key generation timed out. Move the mouse or type to generate entropy, then retry."
            }
        }
    }

    /// Pure, testable builder for the `gpg --quick-generate-key` argument vector.
    /// `expiryYears <= 0` means no expiry ("0"). An empty passphrase produces an
    /// unprotected key (passed inline with loopback pinentry — no interactive prompt).
    static func gpgKeygenArguments(
        name: String, email: String, passphrase: String, expiryYears: Int = 0
    ) -> [String] {
        let userId = "\(name) <\(email)>"
        let expiry = expiryYears <= 0 ? "0" : "\(expiryYears)y"
        return [
            "--batch",
            "--pinentry-mode", "loopback",
            "--passphrase", passphrase,
            "--quick-generate-key", userId,
            "ed25519",
            "cert,sign",
            expiry,
        ]
    }

    /// Creates a new GPG key non-interactively, then re-reads the keyring and returns
    /// the newly created key. Uses a long timeout because keygen needs entropy and
    /// routinely exceeds the default.
    static func createKey(name: String, email: String, passphrase: String) async throws -> GPGKey {
        guard await isAvailable() else { throw GPGServiceError.notInstalled }

        let args = gpgKeygenArguments(name: name, email: email, passphrase: passphrase)
        guard let result = await ProcessRunner.run("gpg", arguments: args, timeout: 120) else {
            throw GPGServiceError.timedOut
        }
        guard result.exitCode == 0 else {
            throw GPGServiceError.generationFailed(
                result.output.isEmpty ? "exit \(result.exitCode)" : result.output)
        }

        let refreshed = await identity()
        if let match = refreshed?.secretKeys.first(where: { $0.userId.contains(email) }) {
            return match
        }
        return GPGKey(keyId: "", userId: "\(name) <\(email)>")
    }
}

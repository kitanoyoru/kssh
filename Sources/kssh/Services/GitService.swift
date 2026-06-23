import Foundation

struct GitService {
    static func identity() async -> GitIdentity? {
        let gitAvailable = await ProcessRunner.checkAvailable("git")
        guard gitAvailable else { return nil }

        async let name = getConfig("user.name")
        async let email = getConfig("user.email")
        async let signingKey = getConfig("user.signingkey")
        async let gpgsign = getConfig("commit.gpgsign")

        let (nameVal, emailVal, keyVal, signVal) = await (name, email, signingKey, gpgsign)

        guard nameVal != nil || emailVal != nil else { return nil }

        return GitIdentity(
            name: nameVal,
            email: emailVal,
            signingKey: keyVal,
            signCommits: signVal == "true"
        )
    }

    private static func getConfig(_ key: String) async -> String? {
        let result = await ProcessRunner.run(
            "git", arguments: ["config", "--global", "--get", key])
        guard let output = result, output.exitCode == 0, !output.output.isEmpty else {
            return nil
        }
        return output.output
    }

    // MARK: - Write path (git profiles)

    enum GitServiceError: LocalizedError {
        case gitUnavailable
        case writeFailed(key: String, message: String)
        case partialWrite(succeeded: String, failed: String, message: String)

        var errorDescription: String? {
            switch self {
            case .gitUnavailable:
                return "git is not installed"
            case .writeFailed(let key, let message):
                return "Failed to set \(key): \(message)"
            case .partialWrite(let succeeded, let failed, let message):
                return
                    "Partially applied profile: \(succeeded) was set but \(failed) failed (\(message)). Git config may be inconsistent."
            }
        }
    }

    /// Pure, testable argument builder for a single `git config --global` write.
    /// Arguments pass to argv directly (no shell), so values with spaces are safe.
    static func configArguments(key: String, value: String) -> [String] {
        ["config", "--global", key, value]
    }

    /// Writes user.name then user.email to *global* git config. If the email write fails
    /// after user.name succeeded, throws `.partialWrite` so the UI can warn that the
    /// config is half-applied (no rollback — the next refresh shows the real config).
    static func setIdentity(name: String, email: String) async throws {
        guard await ProcessRunner.checkAvailable("git") else {
            throw GitServiceError.gitUnavailable
        }

        let nameResult = await ProcessRunner.run(
            "git", arguments: configArguments(key: "user.name", value: name))
        guard let nameResult, nameResult.exitCode == 0 else {
            throw GitServiceError.writeFailed(
                key: "user.name", message: nameResult?.output ?? "git did not run")
        }

        let emailResult = await ProcessRunner.run(
            "git", arguments: configArguments(key: "user.email", value: email))
        guard let emailResult, emailResult.exitCode == 0 else {
            throw GitServiceError.partialWrite(
                succeeded: "user.name",
                failed: "user.email",
                message: emailResult?.output ?? "git did not run"
            )
        }
    }
}

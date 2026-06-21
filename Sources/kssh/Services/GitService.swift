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
        let result = await ProcessRunner.run("git", arguments: ["config", "--global", "--get", key])
        guard let output = result, output.exitCode == 0, !output.output.isEmpty else {
            return nil
        }
        return output.output
    }
}

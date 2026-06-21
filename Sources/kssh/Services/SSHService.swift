import Foundation

struct SSHService {
    static func loadedKeys() async -> [SSHKey] {
        var keys: [SSHKey] = []

        let fingerprintResult = await ProcessRunner.run("ssh-add", arguments: ["-l"])
        let publicKeyResult = await ProcessRunner.run("ssh-add", arguments: ["-L"])

        guard let fpOutput = fingerprintResult,
              let pkOutput = publicKeyResult,
              fpOutput.exitCode == 0,
              pkOutput.exitCode == 0
        else {
            return keys
        }

        let fpLines = fpOutput.output.split(separator: "\n").map(String.init)
        let pkLines = pkOutput.output.split(separator: "\n").map(String.init)

        for (index, fpLine) in fpLines.enumerated() {
            guard !fpLine.isEmpty else { continue }
            let parts = fpLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { continue }

            let keyType = fpLine.contains("(") ?
                String(fpLine.split(separator: "(").last?.dropLast() ?? "") : ""

            let fingerprint = String(parts[1])
            let comment = parts.count >= 3 ? String(parts[2]).replacingOccurrences(of: " (\(keyType))", with: "") : ""

            let publicKey = index < pkLines.count ? pkLines[index] : ""

            keys.append(SSHKey(
                keyType: keyType.isEmpty ? String(parts[0]) : keyType,
                fingerprint: fingerprint,
                comment: comment,
                publicKey: publicKey
            ))
        }

        return keys
    }

    static func isAgentRunning() async -> Bool {
        let result = await ProcessRunner.run("ssh-add", arguments: ["-l"])
        guard let output = result else { return false }
        // `ssh-add -l` exit codes:
        //   0 -> agent reachable, has identities
        //   1 -> agent reachable, no identities ("The agent has no identities.")
        //   2 -> could not connect to the agent (not running / wrong SSH_AUTH_SOCK)
        // The agent is "running" for 0 and 1; only 2 means it's unavailable.
        return output.exitCode == 0 || output.exitCode == 1
    }

    static func agentPid() async -> String? {
        guard let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] else {
            return nil
        }
        return sshAuthSock
    }
}

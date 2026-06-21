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

    /// Starts a fresh ssh-agent via `ssh-agent -s` and points subsequent child processes at
    /// its socket. Returns true when an agent started and its socket was captured.
    @discardableResult
    static func startAgent() async -> Bool {
        guard let result = await ProcessRunner.run("ssh-agent", arguments: ["-s"]),
              result.exitCode == 0,
              let socket = parseAgentSocket(from: result.output) else {
            return false
        }
        ProcessRunner.useAgentSocket(socket)
        return true
    }

    /// Extracts the `SSH_AUTH_SOCK` value from `ssh-agent -s` output (Bourne-shell form:
    /// `SSH_AUTH_SOCK=/path/agent.123; export SSH_AUTH_SOCK; …`). Pure and testable.
    static func parseAgentSocket(from output: String) -> String? {
        for segment in output.components(separatedBy: ";") {
            let token = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.hasPrefix("SSH_AUTH_SOCK=") else { continue }
            let value = String(token.dropFirst("SSH_AUTH_SOCK=".count))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

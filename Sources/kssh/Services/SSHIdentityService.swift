import Foundation

/// Discovers SSH keypairs under `~/.ssh` and switches the active identity by
/// rewriting `~/.ssh/config` (persistent) and reloading the ssh-agent (live).
struct SSHIdentityService {
    private static var sshDir: String { (NSHomeDirectory() as NSString).appendingPathComponent(".ssh") }
    private static var configPath: String { (sshDir as NSString).appendingPathComponent("config") }

    // MARK: - Discovery

    /// Scans `~/.ssh` for private keys and reads each one's type, comment, and
    /// fingerprint via `ssh-keygen -lf`. A matching `.pub` is used when present but
    /// is NOT required — `ssh-keygen -lf` reads private keys directly, so a key
    /// referenced by config without a checked-in `.pub` still appears.
    static func discover() async -> [SSHIdentity] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: sshDir) else { return [] }

        let pubs = Set(entries.filter { $0.hasSuffix(".pub") })
        var identities: [SSHIdentity] = []

        for entry in entries.sorted() {
            // Skip public keys and non-key artifacts; everything else is a private
            // key candidate that ssh-keygen will validate (non-keys are rejected).
            guard !entry.hasSuffix(".pub"),
                  entry != "config",
                  !entry.hasPrefix("known_hosts"),
                  entry != "authorized_keys",
                  !entry.hasPrefix(".") else { continue }

            let priv = (sshDir as NSString).appendingPathComponent(entry)
            let pub = pubs.contains("\(entry).pub") ? "\(priv).pub" : ""

            // Read identity info from the .pub if present (no passphrase prompt),
            // otherwise fall back to the private key file itself.
            guard let info = await fingerprintInfo(forKeyFile: pub.isEmpty ? priv : pub) else { continue }
            identities.append(SSHIdentity(
                privateKeyPath: priv,
                publicKeyPath: pub,
                keyType: info.keyType,
                comment: info.comment,
                fingerprint: info.fingerprint
            ))
        }
        return identities
    }

    /// Parses `ssh-keygen -lf <file>` → "<bits> SHA256:<fp> <comment> (<TYPE>)".
    /// Works for both public and unencrypted private key files.
    private static func fingerprintInfo(forKeyFile file: String) async -> (keyType: String, comment: String, fingerprint: String)? {
        guard let result = await ProcessRunner.run("ssh-keygen", arguments: ["-lf", file]),
              result.exitCode == 0 else { return nil }

        let line = result.output
        let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        let fingerprint = parts[1]
        var keyType = ""
        var comment = ""
        if parts.count >= 3 {
            let rest = parts[2]
            if let open = rest.lastIndex(of: "(") {
                keyType = String(rest[rest.index(after: open)...].dropLast())
                comment = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
            } else {
                comment = rest
            }
        }
        // Comment is "no comment" when ssh-keygen finds none — treat as empty.
        if comment == "no comment" { comment = "" }
        return (keyType, comment, fingerprint)
    }

    // MARK: - Active identity

    /// The identity currently active in `~/.ssh/config` (the first uncommented
    /// IdentityFile across all Host blocks), matched against `identities`.
    static func activeIdentity(among identities: [SSHIdentity]) -> SSHIdentity? {
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else { return nil }
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            guard let path = identityFilePath(in: line) else { continue }
            let expanded = expand(path)
            if let match = identities.first(where: { $0.privateKeyPath == expanded }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Activation

    enum ActivationError: LocalizedError {
        case configUnreadable
        case configUnwritable
        case agentReloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .configUnreadable: return "Could not read ~/.ssh/config"
            case .configUnwritable: return "Could not write ~/.ssh/config"
            case .agentReloadFailed(let msg): return "Agent reload failed: \(msg)"
            }
        }
    }

    /// Switches to `identity` by (1) rewriting `~/.ssh/config` so it is the active
    /// IdentityFile for every Host block, then (2) clearing and reloading the agent.
    /// A timestamped backup of the config is written before any edit.
    static func activate(_ identity: SSHIdentity) async throws {
        try rewriteConfig(activating: identity)
        try await reloadAgent(with: identity)
    }

    // MARK: - Config rewrite

    private static func rewriteConfig(activating identity: SSHIdentity) throws {
        let fm = FileManager.default

        // Read existing config (an empty/missing file is valid — we'll create one).
        let original: String
        if fm.fileExists(atPath: configPath) {
            guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
                throw ActivationError.configUnreadable
            }
            original = contents
        } else {
            original = ""
        }

        let rewritten = transform(config: original, activating: identity)
        guard rewritten != original else { return } // no-op, nothing to write

        // Back up before mutating, preserving the original permissions on the new file.
        if fm.fileExists(atPath: configPath) {
            let backup = "\(configPath).kssh.bak"
            try? fm.removeItem(atPath: backup)
            try? fm.copyItem(atPath: configPath, toPath: backup)
        }

        do {
            try rewritten.write(toFile: configPath, atomically: true, encoding: .utf8)
            // ssh refuses a world-readable config; keep it user-only.
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath)
        } catch {
            throw ActivationError.configUnwritable
        }
    }

    /// Pure string transform (testable): make `identity` the single active
    /// IdentityFile in each Host block, commenting out the others. If a Host block
    /// has no IdentityFile for it (active or commented), one is inserted.
    static func transform(config: String, activating identity: SSHIdentity) -> String {
        let target = identity.privateKeyPath
        let newline = "\n"
        var lines = config.components(separatedBy: newline)

        // Identify Host block boundaries: a block starts at a "Host " line and runs
        // until the next "Host " line or EOF.
        var blockStarts: [Int] = []
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("host ") || line.lowercased() == "host" {
                blockStarts.append(i)
            }
        }
        guard !blockStarts.isEmpty else { return config } // nothing to touch

        // Process blocks back-to-front so insertions don't shift earlier indices.
        for (idx, start) in blockStarts.enumerated().reversed() {
            let end = (idx + 1 < blockStarts.count) ? blockStarts[idx + 1] : lines.count
            var matchedTarget = false

            for i in start..<end {
                let raw = lines[i]
                let stripped = raw.trimmingCharacters(in: .whitespaces)
                let uncommented = stripped.hasPrefix("#")
                    ? String(stripped.dropFirst()).trimmingCharacters(in: .whitespaces)
                    : stripped

                guard let path = identityFilePath(in: uncommented) else { continue }
                let indent = leadingWhitespace(of: raw)

                if expand(path) == target {
                    // Activate (uncomment / normalize) the chosen key's line.
                    lines[i] = "\(indent)IdentityFile \(path)"
                    matchedTarget = true
                } else if !stripped.hasPrefix("#") {
                    // Comment out any other active IdentityFile.
                    lines[i] = "\(indent)#IdentityFile \(path)"
                }
            }

            // No line referenced the target in this block — insert one after the
            // Host line (using the indentation of the following line if present).
            if !matchedTarget {
                let insertAt = start + 1
                let indent = insertAt < end ? leadingWhitespace(of: lines[min(insertAt, lines.count - 1)]) : "  "
                lines.insert("\(indent)IdentityFile \(identity.configPath)", at: insertAt)
            }
        }

        return lines.joined(separator: newline)
    }

    // MARK: - Agent reload

    private static func reloadAgent(with identity: SSHIdentity) async throws {
        // Clear all loaded identities, then add the chosen one.
        _ = await ProcessRunner.run("ssh-add", arguments: ["-D"])
        guard let add = await ProcessRunner.run("ssh-add", arguments: [identity.privateKeyPath]) else {
            throw ActivationError.agentReloadFailed("ssh-add did not run")
        }
        if add.exitCode != 0 {
            throw ActivationError.agentReloadFailed(add.output.isEmpty ? "exit \(add.exitCode)" : add.output)
        }
    }

    // MARK: - Parsing helpers

    /// Returns the path argument of an `IdentityFile <path>` directive, or nil.
    private static func identityFilePath(in line: String) -> String? {
        let lower = line.lowercased()
        guard lower.hasPrefix("identityfile") else { return nil }
        let after = line.dropFirst("identityfile".count).trimmingCharacters(in: .whitespaces)
        // Strip surrounding quotes ssh allows around paths.
        let unquoted = after.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return unquoted.isEmpty ? nil : unquoted
    }

    private static func leadingWhitespace(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    /// Expands a leading `~` to the home directory for path comparison.
    private static func expand(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") {
            return (NSHomeDirectory() as NSString).appendingPathComponent(String(path.dropFirst(2)))
        }
        return (path as NSString).expandingTildeInPath
    }
}

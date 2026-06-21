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

    /// The identity currently active in `~/.ssh/config`, matched against `identities`.
    static func activeIdentity(among identities: [SSHIdentity]) -> SSHIdentity? {
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else { return nil }
        return activeIdentity(among: identities, in: contents)
    }

    /// Pure, testable scope-aware resolver. Returns the uncommented `IdentityFile`
    /// from the most specific scope: a match inside a specific `Host` block wins over
    /// one from a `Host *` default or a global (pre-block) directive. Falls back to a
    /// wildcard/global match when no specific block references a known identity.
    static func activeIdentity(among identities: [SSHIdentity], in config: String) -> SSHIdentity? {
        let newline = config.contains("\r\n") ? "\r\n" : "\n"
        let lines = config.components(separatedBy: newline)
        let ranges = blockRanges(in: lines)

        func match(at i: Int) -> SSHIdentity? {
            let stripped = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.hasPrefix("#"),
                  let path = identityFilePath(in: stripped) else { return nil }
            let expanded = expand(path)
            return identities.first { $0.privateKeyPath == expanded }
        }

        // Global directives before the first Host/Match block apply to all hosts:
        // treat them (and `Host *` blocks) as low-priority wildcard matches.
        var wildcardMatch: SSHIdentity?
        let firstStart = ranges.first?.lowerBound ?? lines.count
        for i in 0..<firstStart where wildcardMatch == nil {
            wildcardMatch = match(at: i)
        }
        for range in ranges {
            let isWildcard = isWildcardHostBlock(lines[range.lowerBound])
            for i in range {
                guard let m = match(at: i) else { continue }
                if isWildcard {
                    if wildcardMatch == nil { wildcardMatch = m }
                } else {
                    return m   // specific host block wins immediately
                }
            }
        }
        return wildcardMatch
    }

    // MARK: - Activation

    /// Outcome of an `activate` call, so callers can tell a persisted config switch
    /// apart from one that only changed the running agent.
    enum ActivationResult {
        /// The key is referenced by at least one Host/Match block, so `~/.ssh/config`
        /// reflects the switch.
        case configUpdated
        /// The key is not referenced anywhere in `~/.ssh/config`; only the agent changed.
        case agentOnly
    }

    enum ActivationError: LocalizedError {
        case configUnreadable
        case configUnwritable
        case agentReloadFailed(String)
        case agentLoadFailed(String)
        case agentUnloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .configUnreadable: return "Could not read ~/.ssh/config"
            case .configUnwritable: return "Could not write ~/.ssh/config"
            case .agentReloadFailed(let msg): return "Agent reload failed: \(msg)"
            case .agentLoadFailed(let msg): return "Could not load key into agent: \(msg)"
            case .agentUnloadFailed(let msg): return "Could not unload key from agent: \(msg)"
            }
        }
    }

    /// Switches to `identity` by (1) rewriting `~/.ssh/config` and (2) clearing and
    /// reloading the agent. The rewrite is conservative: within each Host/Match block
    /// that already references the key it uncomments that `IdentityFile` and comments
    /// the others; blocks that don't mention the key are left untouched and no new
    /// lines are inserted. A backup of the config is written before any edit.
    ///
    /// Returns `.agentOnly` when the key isn't referenced anywhere in the config (so
    /// only the agent changed), letting the caller surface that to the user.
    @discardableResult
    static func activate(_ identity: SSHIdentity) async throws -> ActivationResult {
        let referenced = configReferences(identity.privateKeyPath, in: currentConfigText())
        try rewriteConfig(activating: identity)
        try await reloadAgent(with: identity)
        return referenced ? .configUpdated : .agentOnly
    }

    /// Reads `~/.ssh/config`, returning "" when it's missing or unreadable. (An
    /// unreadable-but-present file is reported separately by `rewriteConfig`.)
    private static func currentConfigText() -> String {
        (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
    }

    /// True when any Host/Match block references `target` (commented or not).
    static func configReferences(_ target: String, in config: String) -> Bool {
        let newline = config.contains("\r\n") ? "\r\n" : "\n"
        let lines = config.components(separatedBy: newline)
        for range in blockRanges(in: lines) {
            for i in range {
                guard let path = identityFilePath(in: uncomment(lines[i])) else { continue }
                if expand(path) == target { return true }
            }
        }
        return false
    }

    /// Additively loads a single key into the running agent via `ssh-add <path>`,
    /// WITHOUT touching `~/.ssh/config` and WITHOUT clearing other loaded keys.
    /// Runs non-interactively so a passphrase-protected key fails fast instead of
    /// hanging the subprocess waiting on a TTY/askpass prompt.
    static func loadIntoAgent(_ identity: SSHIdentity) async throws {
        let nonInteractive = [
            "SSH_ASKPASS_REQUIRE": "never",
            "SSH_ASKPASS": "/usr/bin/false",
            "DISPLAY": ""
        ]
        guard let add = await ProcessRunner.run(
            "ssh-add",
            arguments: [identity.privateKeyPath],
            timeout: 10,
            environment: nonInteractive
        ) else {
            throw ActivationError.agentLoadFailed("ssh-add did not run")
        }
        if add.exitCode != 0 {
            throw ActivationError.agentLoadFailed(
                add.output.isEmpty ? "exit \(add.exitCode) (key may be passphrase-protected)" : add.output
            )
        }
    }

    /// Removes a single key from the running agent via `ssh-add -d <path>`, WITHOUT
    /// touching `~/.ssh/config`. Note: `ssh-add -d` exits non-zero when the key is not
    /// currently loaded ("agent refused operation") — callers should treat that as benign.
    static func unloadFromAgent(_ identity: SSHIdentity) async throws {
        guard let del = await ProcessRunner.run(
            "ssh-add",
            arguments: unloadArguments(for: identity),
            timeout: 10
        ) else {
            throw ActivationError.agentUnloadFailed("ssh-add did not run")
        }
        if del.exitCode != 0 {
            throw ActivationError.agentUnloadFailed(
                del.output.isEmpty ? "exit \(del.exitCode)" : del.output
            )
        }
    }

    /// Pure, testable argument builder for `ssh-add -d`.
    static func unloadArguments(for identity: SSHIdentity) -> [String] {
        ["-d", identity.privateKeyPath]
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

    /// Pure string transform (testable). Activates `identity` ONLY within Host blocks
    /// that already reference it (active or commented `IdentityFile`): the target's line
    /// is uncommented and the other `IdentityFile` lines in that same block are commented
    /// out. Blocks that don't mention the target are left completely untouched — so
    /// switching a github key never clobbers an unrelated host (e.g. gitlab.rentateam.ru).
    /// No new lines are ever inserted; this only toggles comments on existing lines.
    static func transform(config: String, activating identity: SSHIdentity) -> String {
        let target = identity.privateKeyPath
        // Preserve the file's newline style so a rewrite round-trips byte-for-byte and
        // values don't carry a stray trailing `\r` on CRLF configs.
        let newline = config.contains("\r\n") ? "\r\n" : "\n"
        var lines = config.components(separatedBy: newline)

        let ranges = blockRanges(in: lines)
        guard !ranges.isEmpty else { return config }

        for range in ranges {
            // Collect this block's IdentityFile lines and whether any references the target.
            var identityLineIndices: [Int] = []
            var referencesTarget = false
            for i in range {
                guard let path = identityFilePath(in: uncomment(lines[i])) else { continue }
                identityLineIndices.append(i)
                if expand(path) == target { referencesTarget = true }
            }

            // Only rewrite blocks that actually reference the target key.
            guard referencesTarget else { continue }

            for i in identityLineIndices {
                let stripped = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let path = identityFilePath(in: uncomment(lines[i])) else { continue }
                let indent = leadingWhitespace(of: lines[i])

                if expand(path) == target {
                    lines[i] = "\(indent)IdentityFile \(path)"          // activate
                } else if !stripped.hasPrefix("#") {
                    lines[i] = "\(indent)#IdentityFile \(path)"         // deactivate others
                }
            }
        }

        return lines.joined(separator: newline)
    }

    /// Host/Match block ranges over `lines`. A `Host …` or `Match …` line starts a block
    /// that runs to the next such line or EOF. Lines before the first block (e.g. global
    /// Include directives) are not part of any range and are never rewritten.
    private static func blockRanges(in lines: [String]) -> [Range<Int>] {
        var starts: [Int] = []
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if line.hasPrefix("host ") || line == "host"
                || line.hasPrefix("match ") || line == "match" {
                starts.append(i)
            }
        }
        return starts.enumerated().map { idx, start in
            let end = (idx + 1 < starts.count) ? starts[idx + 1] : lines.count
            return start..<end
        }
    }

    /// True for a `Host *` block (its only pattern is `*`). Such defaults are treated as
    /// lower priority than a specific host when resolving the active identity.
    private static func isWildcardHostBlock(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasPrefix("host") else { return false }
        let patterns = lower.dropFirst("host".count).split { $0 == " " || $0 == "\t" }
        return patterns == ["*"]
    }

    /// Strips a leading `#` comment marker (and surrounding space) from a config line.
    private static func uncomment(_ line: String) -> String {
        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.hasPrefix("#")
            ? String(stripped.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            : stripped
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

    /// Returns the path argument of an `IdentityFile <path>` directive, or nil — parsed
    /// the way OpenSSH reads it: keyword, an optional `=` separator, then a single
    /// (optionally quoted) token. So `IdentityFile=~/.ssh/k`, `IdentityFile "~/.ssh/k"`,
    /// and `IdentityFile ~/.ssh/k  # note` all yield `~/.ssh/k`. Tilde is left for `expand`.
    private static func identityFilePath(in line: String) -> String? {
        guard line.lowercased().hasPrefix("identityfile") else { return nil }
        var rest = line.dropFirst("identityfile".count)
        // The keyword must be followed by a separator (whitespace or `=`), not more
        // letters — otherwise this is a different keyword like `IdentityFileFoo`.
        if let first = rest.first, first != " ", first != "\t", first != "=" { return nil }

        rest = rest.drop { $0 == " " || $0 == "\t" }
        if rest.first == "=" { rest = rest.dropFirst() }
        rest = rest.drop { $0 == " " || $0 == "\t" }
        guard let opener = rest.first else { return nil }

        let token: Substring
        if opener == "\"" || opener == "'" {
            let body = rest.dropFirst()
            token = body.firstIndex(of: opener).map { body[..<$0] } ?? body
        } else {
            token = rest.prefix { $0 != " " && $0 != "\t" && $0 != "\r" && $0 != "\n" }
        }
        return token.isEmpty ? nil : String(token)
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

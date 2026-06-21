import Foundation

enum ProcessRunner {
    struct Result {
        let output: String
        let exitCode: Int32
    }

    /// A menu-bar app is launched by launchd, not your shell, so it does NOT inherit
    /// `SSH_AUTH_SOCK`, a Homebrew `PATH`, etc. We rebuild a usable environment once and
    /// reuse it for every child process so ssh-add / git / gpg can actually be found and
    /// can reach the running ssh-agent.
    private static let resolvedEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment

        // Resolve the ssh-agent socket when our own environment is missing it
        // (the common GUI-launch case). Try the launchd user domain first, then
        // fall back to discovering the macOS native ssh-agent socket on disk.
        if env["SSH_AUTH_SOCK"]?.isEmpty ?? true {
            if let sock = launchctlGetenv("SSH_AUTH_SOCK") {
                env["SSH_AUTH_SOCK"] = sock
            } else if let sock = nativeAgentSocket() {
                env["SSH_AUTH_SOCK"] = sock
            }
        }

        // Ensure common tool locations are on PATH (Homebrew on Apple Silicon / Intel).
        let basePath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var seen = Set(basePath.split(separator: ":").map(String.init))
        var merged = basePath
        for path in extraPaths where !seen.contains(path) {
            merged += ":\(path)"
            seen.insert(path)
        }
        env["PATH"] = merged

        return env
    }()

    /// Overrides `SSH_AUTH_SOCK` for every subsequent child process. Set after starting a
    /// fresh agent (see `SSHService.startAgent`), whose socket isn't known when
    /// `resolvedEnvironment` is first computed. `nil` means "use the resolved base".
    private static var agentSocketOverride: String?

    /// Point future child processes at `socket` (a newly started agent). Also mirrors it
    /// into the process environment so `SSHService.agentPid` reflects it.
    static func useAgentSocket(_ socket: String) {
        agentSocketOverride = socket
        setenv("SSH_AUTH_SOCK", socket, 1)
    }

    /// Reads a variable from the launchd user domain (where the GUI session keeps
    /// `SSH_AUTH_SOCK`). Returns nil if unset or empty.
    private static func launchctlGetenv(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["getenv", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// Discovers the macOS native ssh-agent socket, which launchd injects into shell
    /// sessions as `/private/tmp/com.apple.launchd.XXXX/Listeners` but does NOT expose
    /// via `launchctl getenv`. A GUI-launched app therefore can't see it through the
    /// environment, so we probe the well-known directory directly. Returns the most
    /// recently created `Listeners` socket, or nil if none is found.
    private static func nativeAgentSocket() -> String? {
        let base = "/private/tmp"
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: base) else { return nil }

        let candidates = entries
            .filter { $0.hasPrefix("com.apple.launchd.") }
            .map { "\(base)/\($0)/Listeners" }
            .filter { fm.fileExists(atPath: $0) }

        // Prefer the newest socket if several launchd dirs linger after re-logins.
        return candidates.max { lhs, rhs in
            let lDate = (try? fm.attributesOfItem(atPath: lhs)[.creationDate]) as? Date ?? .distantPast
            let rDate = (try? fm.attributesOfItem(atPath: rhs)[.creationDate]) as? Date ?? .distantPast
            return lDate < rDate
        }
    }

    /// Runs `command` with `arguments`. `environment` is an optional per-call overlay
    /// merged over the resolved base environment — used to pass non-interactive flags
    /// (e.g. SSH_ASKPASS_REQUIRE) or longer-lived settings without mutating the shared base.
    static func run(_ command: String, arguments: [String] = [], timeout: TimeInterval = 5, environment: [String: String] = [:]) async -> Result? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
            var env = resolvedEnvironment
            if let socket = agentSocketOverride { env["SSH_AUTH_SOCK"] = socket }
            for (key, value) in environment { env[key] = value }
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            let deadline = DispatchTime.now() + timeout
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { _ in
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: Result(
                    output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                    exitCode: process.terminationStatus
                ))
            }
        }
    }

    static func checkAvailable(_ command: String) async -> Bool {
        let result = await run("/bin/sh", arguments: ["-c", "command -v \(command)"])
        return result?.exitCode == 0 && !(result?.output ?? "").isEmpty
    }
}

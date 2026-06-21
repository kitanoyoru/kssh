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

        // Resolve the ssh-agent socket from the launchd user domain when our own
        // environment is missing it (the common GUI-launch case).
        if (env["SSH_AUTH_SOCK"]?.isEmpty ?? true),
           let sock = launchctlGetenv("SSH_AUTH_SOCK") {
            env["SSH_AUTH_SOCK"] = sock
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

    static func run(_ command: String, arguments: [String] = [], timeout: TimeInterval = 5) async -> Result? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
            process.environment = resolvedEnvironment

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

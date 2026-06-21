import Foundation

/// Reads tokens from `~/.netrc` as a fallback credential source for the Remote section.
/// `.netrc` is a whitespace/newline-separated stream of keyword/value tokens, e.g.:
///
///     machine github.com login me password ghp_xxx
///
/// We only need the `password` for a given `machine`. `default` entries and unrelated
/// keywords are ignored. Comments (`#…`) are stripped.
enum NetrcReader {
    private static var defaultPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".netrc")
    }

    /// Returns the `password` for `machine` in `~/.netrc`, or nil if the file is absent,
    /// the machine isn't listed, or it has no password.
    static func password(forMachine machine: String, path: String = defaultPath) -> String? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return password(forMachine: machine, contents: contents)
    }

    /// Pure parser over `.netrc` contents (testable without touching disk).
    static func password(forMachine machine: String, contents: String) -> String? {
        let tokens = tokenize(contents)
        var index = 0
        var currentMachine: String?

        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "machine":
                index += 1
                currentMachine = index < tokens.count ? tokens[index] : nil
            case "default":
                // A `default` block applies to any machine not matched above; treat it
                // as a wildcard machine so its password can serve as a last resort.
                currentMachine = "default"
            case "password":
                index += 1
                if index < tokens.count,
                   currentMachine == machine || currentMachine == "default" {
                    return tokens[index]
                }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    /// Splits into tokens on whitespace/newlines, dropping `#` comment lines.
    private static func tokenize(_ contents: String) -> [String] {
        contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                // Strip an inline/whole-line comment.
                if let hash = line.firstIndex(of: "#") { return line[..<hash] }
                return line
            }
            .flatMap { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }) }
            .map(String.init)
    }
}

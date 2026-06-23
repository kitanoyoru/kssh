import Foundation

/// A named git identity preset (user.name + user.email). No signing key or SSH-key
/// linkage — switching a profile writes these two values to the *global* git config.
struct GitProfile: Codable, Identifiable, Equatable {
    /// Stable across edits so the active-row highlight doesn't jump when a profile is renamed.
    let id: String
    var name: String
    var email: String

    init(id: String = UUID().uuidString, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }

    var displayName: String {
        name.isEmpty ? email : name
    }

    /// True when this profile's name+email equal a configured git identity. Both sides
    /// are trimmed: `git config --get` output is already trimmed by ProcessRunner, but
    /// stored values may carry user-entered trailing whitespace.
    func matches(_ identity: GitIdentity?) -> Bool {
        guard let identity, let configName = identity.name, let configEmail = identity.email else {
            return false
        }
        return configName.trimmingCharacters(in: .whitespacesAndNewlines)
            == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && configEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                == email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pure matcher (testable): the first stored profile that matches the current identity.
    static func active(in profiles: [GitProfile], matching identity: GitIdentity?) -> GitProfile? {
        profiles.first { $0.matches(identity) }
    }
}

import Foundation

/// A named credential for a remote git provider (GitHub/GitLab/Bitbucket). This is
/// metadata only — it serializes to UserDefaults JSON like `GitProfile`, so it must
/// NOT carry secrets. The PAT / app-password lives in the Keychain, keyed by `id` via
/// `keychainKey(service:field:id:)`. One account per service is "active" and used for
/// token resolution (see `SettingsStore.activeAccount(for:)`).
struct RemoteAccount: Codable, Identifiable, Equatable {
    /// Stable across rename so the active highlight doesn't jump and the Keychain key
    /// (which uses this id as its suffix) stays valid when the label changes.
    let id: String
    var label: String
    /// GitLab self-hosted host (e.g. "gitlab.example.com"). Nil/ignored for GitHub and
    /// Bitbucket. Empty/nil resolves to "gitlab.com".
    var instance: String?

    init(id: String = UUID().uuidString, label: String, instance: String? = nil) {
        self.id = id
        self.label = label
        self.instance = instance
    }

    var displayLabel: String {
        label.isEmpty ? "Untitled" : label
    }

    // MARK: - Keychain key derivation (single source of truth)

    /// Field identifiers for the per-account secrets stored in the Keychain.
    enum Field: String {
        case pat
        case username
        case appPassword = "apppassword"
    }

    /// The Keychain account-key for a given service/field/account. Pure and deterministic
    /// so secrets are never orphaned by an inconsistent scheme. The dotted form is
    /// collision-free against the legacy flat keys ("githubPat", "bitbucketUsername", …),
    /// which lets migration keep both during the transition. Examples:
    /// `github.pat.<id>`, `gitlab.pat.<id>`, `bitbucket.username.<id>`,
    /// `bitbucket.apppassword.<id>`.
    static func keychainKey(service: RemoteService, field: Field, id: String) -> String {
        "\(servicePrefix(service)).\(field.rawValue).\(id)"
    }

    /// Lowercased, stable prefix per service. Uses a fixed mapping (not `rawValue`, which
    /// is the display string "GitHub") so the key scheme never shifts if display names change.
    private static func servicePrefix(_ service: RemoteService) -> String {
        switch service {
        case .github: return "github"
        case .gitlab: return "gitlab"
        case .bitbucket: return "bitbucket"
        }
    }
}

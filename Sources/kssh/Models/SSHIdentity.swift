import Foundation

/// A keypair discovered on disk under `~/.ssh` (a private key file with a matching
/// `.pub`). Distinct from `SSHKey`, which represents an identity already loaded into
/// the running ssh-agent. An `SSHIdentity` may or may not be loaded/active.
struct SSHIdentity: Identifiable, Equatable {
    /// Absolute path to the private key file; also serves as the stable identity.
    let privateKeyPath: String
    let publicKeyPath: String
    let keyType: String
    let comment: String
    /// SHA256 fingerprint as reported by `ssh-keygen -lf`, e.g. "SHA256:abcd…".
    let fingerprint: String

    var id: String { privateKeyPath }

    /// `~`-relative form used inside `~/.ssh/config` IdentityFile lines.
    var configPath: String {
        let home = NSHomeDirectory()
        if privateKeyPath.hasPrefix(home) {
            return "~" + privateKeyPath.dropFirst(home.count)
        }
        return privateKeyPath
    }

    /// File name without directory, e.g. "id_ed25519".
    var name: String {
        (privateKeyPath as NSString).lastPathComponent
    }

    var displayName: String {
        comment.isEmpty ? name : comment
    }
}

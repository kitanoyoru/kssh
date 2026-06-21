import Foundation

struct SSHKey: Identifiable, Equatable {
    let id = UUID()
    let keyType: String
    let fingerprint: String
    let comment: String
    let publicKey: String

    var isLoaded: Bool { true }

    var shortFingerprint: String {
        let parts = fingerprint.split(separator: ":")
        guard parts.count >= 2 else { return fingerprint }
        return parts.dropFirst().joined(separator: ":")
    }

    var fingerprintPrefix: String {
        String(shortFingerprint.prefix(16))
    }
}

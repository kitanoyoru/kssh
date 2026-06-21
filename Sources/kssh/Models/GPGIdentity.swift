import Foundation

struct GPGKey: Identifiable, Equatable {
    let id = UUID()
    let keyId: String
    let userId: String
}

struct GPGIdentity: Equatable {
    let secretKeys: [GPGKey]
    let signingKeyId: String?

    var isConfigured: Bool {
        !secretKeys.isEmpty
    }

    var activeSigningKey: GPGKey? {
        guard let keyId = signingKeyId else { return nil }
        return secretKeys.first { $0.keyId.hasSuffix(keyId) || keyId.hasSuffix($0.keyId) }
    }
}

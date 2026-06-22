import Foundation

/// Failure modes for uploading an SSH public key to a remote provider (GitHub/GitLab).
/// Shared by the `addKey` methods so the ViewModel can present one friendly message.
enum RemoteKeyError: LocalizedError {
    case noToken
    case alreadyExists
    case http(Int)
    case network

    var errorDescription: String? {
        switch self {
        case .noToken: return "No token. Add one in Settings."
        case .alreadyExists: return "That key is already registered on this account."
        case .http(let code): return "The provider returned HTTP \(code)."
        case .network: return "Could not reach the provider. Check your connection."
        }
    }
}

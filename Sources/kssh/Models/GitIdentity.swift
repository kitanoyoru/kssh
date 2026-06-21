import Foundation

struct GitIdentity: Equatable {
    let name: String?
    let email: String?
    let signingKey: String?
    let signCommits: Bool

    var isConfigured: Bool {
        name != nil && email != nil
    }
}

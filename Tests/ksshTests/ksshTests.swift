import XCTest
@testable import kssh

final class SSHKeyTests: XCTestCase {
    func testShortFingerprint() {
        let key = SSHKey(keyType: "ED25519", fingerprint: "SHA256:viBhKYLkY2AqOzOjBcjoJcLqLL3IHDdq1AKeBa+iikg", comment: "test@host", publicKey: "ssh-ed25519 AAA...")
        XCTAssertEqual(key.shortFingerprint, "viBhKYLkY2AqOzOjBcjoJcLqLL3IHDdq1AKeBa+iikg")
    }

    func testFingerprintPrefix() {
        let key = SSHKey(keyType: "ED25519", fingerprint: "SHA256:viBhKYLkY2AqOzOjBcjoJcLqLL3IHDdq1AKeBa+iikg", comment: "test@host", publicKey: "ssh-ed25519 AAA...")
        XCTAssertEqual(key.fingerprintPrefix, "viBhKYLkY2AqOzOj")
    }

    func testIsLoaded() {
        let key = SSHKey(keyType: "ED25519", fingerprint: "SHA256:abc123", comment: "", publicKey: "")
        XCTAssertTrue(key.isLoaded)
    }
}

final class SSHServiceTests: XCTestCase {
    func testParseFingerprintLine() async {
        let keys = await SSHService.loadedKeys()
        XCTAssertNotNil(keys)
    }
}

final class GitIdentityTests: XCTestCase {
    func testIsConfigured() {
        let configured = GitIdentity(name: "Test", email: "test@test.com", signingKey: nil, signCommits: false)
        XCTAssertTrue(configured.isConfigured)

        let notConfigured = GitIdentity(name: nil, email: nil, signingKey: nil, signCommits: false)
        XCTAssertFalse(notConfigured.isConfigured)

        let partialName = GitIdentity(name: "Test", email: nil, signingKey: nil, signCommits: false)
        XCTAssertFalse(partialName.isConfigured)
    }
}

final class GPGIdentityTests: XCTestCase {
    func testActiveSigningKey() {
        let key = GPGKey(keyId: "ABCDEF0123456789", userId: "Test <test@test.com>")
        let identity = GPGIdentity(secretKeys: [key], signingKeyId: "ABCDEF0123456789")
        XCTAssertNotNil(identity.activeSigningKey)
        XCTAssertEqual(identity.activeSigningKey?.keyId, "ABCDEF0123456789")
    }

    func testNoActiveSigningKey() {
        let key = GPGKey(keyId: "ABCDEF0123456789", userId: "Test <test@test.com>")
        let identity = GPGIdentity(secretKeys: [key], signingKeyId: nil)
        XCTAssertNil(identity.activeSigningKey)
    }
}

final class SSHIdentityTransformTests: XCTestCase {
    private func identity(_ name: String) -> SSHIdentity {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".ssh/\(name)")
        return SSHIdentity(privateKeyPath: path, publicKeyPath: "", keyType: "ED25519", comment: "", fingerprint: "x")
    }

    private let config = """
    Host github.com
    \tUser git
      #IdentityFile ~/.ssh/aliaksandrrutkouski
      IdentityFile ~/.ssh/id_ed25519
    """

    func testActivatesCommentedKeyAndCommentsActive() {
        let result = SSHIdentityService.transform(config: config, activating: identity("aliaksandrrutkouski"))
        XCTAssertTrue(result.contains("  IdentityFile ~/.ssh/aliaksandrrutkouski"))
        XCTAssertTrue(result.contains("  #IdentityFile ~/.ssh/id_ed25519"))
    }

    func testActivatingAlreadyActiveIsNoOp() {
        let result = SSHIdentityService.transform(config: config, activating: identity("id_ed25519"))
        XCTAssertEqual(result, config)
    }

    func testSwitchRoundTripRestoresOriginal() {
        let once = SSHIdentityService.transform(config: config, activating: identity("aliaksandrrutkouski"))
        let back = SSHIdentityService.transform(config: once, activating: identity("id_ed25519"))
        XCTAssertEqual(back, config)
    }

    func testInsertsIdentityFileWhenBlockHasNone() {
        let cfg = "Host example.com\n\tUser deploy"
        let result = SSHIdentityService.transform(config: cfg, activating: identity("id_ed25519"))
        XCTAssertTrue(result.contains("IdentityFile ~/.ssh/id_ed25519"))
        XCTAssertTrue(result.contains("User deploy"))
    }

    func testPreservesIndentation() {
        let result = SSHIdentityService.transform(config: config, activating: identity("aliaksandrrutkouski"))
        // The two-space indent of the original IdentityFile lines is kept.
        XCTAssertTrue(result.contains("\n  IdentityFile ~/.ssh/aliaksandrrutkouski"))
    }
}

final class RemoteUserTests: XCTestCase {
    func testDisplayName() {
        let user = RemoteUser(service: .github, username: "testuser", matchedKeyCount: 1)
        XCTAssertEqual(user.displayName, "@testuser")
    }

    func testServiceCases() {
        XCTAssertEqual(RemoteService.allCases.count, 2)
        XCTAssertTrue(RemoteService.allCases.contains(.github))
        XCTAssertTrue(RemoteService.allCases.contains(.gitlab))
    }
}

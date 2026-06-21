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

    func testDoesNotInsertIntoBlockWithoutTheKey() {
        // A block that never references the target is left untouched — no line inserted.
        let cfg = "Host example.com\n\tUser deploy"
        let result = SSHIdentityService.transform(config: cfg, activating: identity("id_ed25519"))
        XCTAssertEqual(result, cfg)
        XCTAssertFalse(result.contains("IdentityFile"))
    }

    func testLeavesUnrelatedHostBlocksUntouched() {
        // Regression: switching a github key must NOT rewrite gitlab's working config.
        let cfg = """
        Host github.com
          IdentityFile ~/.ssh/id_ed25519
          #IdentityFile ~/.ssh/innowise_rsa

        Host gitlab.rentateam.ru
          IdentityFile ~/.ssh/id_ed25519
          #IdentityFile ~/.ssh/gitlab_rsa
        """
        let result = SSHIdentityService.transform(config: cfg, activating: identity("innowise_rsa"))
        // github block: innowise activated, id_ed25519 commented.
        XCTAssertTrue(result.contains("  IdentityFile ~/.ssh/innowise_rsa"))
        XCTAssertTrue(result.contains("  #IdentityFile ~/.ssh/id_ed25519"))
        // gitlab block: completely unchanged (still active id_ed25519, commented gitlab_rsa).
        XCTAssertTrue(result.contains("  IdentityFile ~/.ssh/id_ed25519"))
        XCTAssertTrue(result.contains("  #IdentityFile ~/.ssh/gitlab_rsa"))
    }

    func testIncludeDirectivesPreservedAndIgnored() {
        let cfg = """
        Include ~/.orbstack/ssh/config

        Host github.com
          IdentityFile ~/.ssh/id_ed25519
          #IdentityFile ~/.ssh/innowise_rsa
        """
        let result = SSHIdentityService.transform(config: cfg, activating: identity("innowise_rsa"))
        XCTAssertTrue(result.contains("Include ~/.orbstack/ssh/config"))
        XCTAssertTrue(result.contains("  IdentityFile ~/.ssh/innowise_rsa"))
        XCTAssertTrue(result.contains("  #IdentityFile ~/.ssh/id_ed25519"))
    }

    func testPreservesIndentation() {
        let result = SSHIdentityService.transform(config: config, activating: identity("aliaksandrrutkouski"))
        // The two-space indent of the original IdentityFile lines is kept.
        XCTAssertTrue(result.contains("\n  IdentityFile ~/.ssh/aliaksandrrutkouski"))
    }
}

final class GPGKeygenArgumentTests: XCTestCase {
    func testBuildsQuickGenerateArgs() {
        let args = GPGService.gpgKeygenArguments(name: "Ada", email: "ada@x.io", passphrase: "")
        XCTAssertEqual(args, [
            "--batch", "--pinentry-mode", "loopback",
            "--passphrase", "",
            "--quick-generate-key", "Ada <ada@x.io>",
            "ed25519", "cert,sign", "0"
        ])
    }

    func testExpiryFormatting() {
        let noExpiry = GPGService.gpgKeygenArguments(name: "A", email: "a@b.c", passphrase: "", expiryYears: 0)
        XCTAssertEqual(noExpiry.last, "0")
        let twoYears = GPGService.gpgKeygenArguments(name: "A", email: "a@b.c", passphrase: "", expiryYears: 2)
        XCTAssertEqual(twoYears.last, "2y")
    }

    func testUserIdComposition() {
        let args = GPGService.gpgKeygenArguments(name: "Grace Hopper", email: "grace@navy.mil", passphrase: "x")
        XCTAssertTrue(args.contains("Grace Hopper <grace@navy.mil>"))
    }

    func testPassphrasePassedThrough() {
        let args = GPGService.gpgKeygenArguments(name: "A", email: "a@b.c", passphrase: "s3cret")
        let idx = args.firstIndex(of: "--passphrase")!
        XCTAssertEqual(args[idx + 1], "s3cret")
    }

    func testNotInstalledErrorMentionsBrew() {
        let desc = GPGService.GPGServiceError.notInstalled.errorDescription ?? ""
        XCTAssertTrue(desc.contains("brew install gnupg"))
    }
}

@MainActor
final class StatusViewModelLoadedTests: XCTestCase {
    func testIsLoadedMatchesFingerprint() {
        let vm = StatusViewModel()
        vm.sshKeys = [SSHKey(keyType: "ED25519", fingerprint: "SHA256:abc", comment: "", publicKey: "")]
        let match = SSHIdentity(privateKeyPath: "/k", publicKeyPath: "", keyType: "ED25519", comment: "", fingerprint: "SHA256:abc")
        let other = SSHIdentity(privateKeyPath: "/k2", publicKeyPath: "", keyType: "ED25519", comment: "", fingerprint: "SHA256:zzz")
        XCTAssertTrue(vm.isLoaded(match))
        XCTAssertFalse(vm.isLoaded(other))
    }

    func testActiveKeyResolvesByFingerprint() {
        let vm = StatusViewModel()
        let loaded = [
            SSHKey(keyType: "ED25519", fingerprint: "SHA256:abc", comment: "", publicKey: "ssh-ed25519 AAA"),
            SSHKey(keyType: "RSA", fingerprint: "SHA256:def", comment: "", publicKey: "ssh-rsa BBB")
        ]
        vm.activeIdentity = SSHIdentity(privateKeyPath: "/k", publicKeyPath: "", keyType: "ED25519", comment: "", fingerprint: "SHA256:def")
        XCTAssertEqual(vm.activeKey(in: loaded)?.fingerprint, "SHA256:def")

        // No active identity → nil.
        vm.activeIdentity = nil
        XCTAssertNil(vm.activeKey(in: loaded))

        // Active identity whose key isn't loaded → nil.
        vm.activeIdentity = SSHIdentity(privateKeyPath: "/k", publicKeyPath: "", keyType: "ED25519", comment: "", fingerprint: "SHA256:notloaded")
        XCTAssertNil(vm.activeKey(in: loaded))
    }
}

final class SSHAddArgumentTests: XCTestCase {
    private func identity(_ name: String) -> SSHIdentity {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".ssh/\(name)")
        return SSHIdentity(privateKeyPath: path, publicKeyPath: "", keyType: "ED25519", comment: "", fingerprint: "x")
    }

    func testUnloadArguments() {
        let id = identity("id_ed25519")
        XCTAssertEqual(SSHIdentityService.unloadArguments(for: id), ["-d", id.privateKeyPath])
    }

    func testUnloadFailedErrorMessage() {
        let desc = SSHIdentityService.ActivationError.agentUnloadFailed("nope").errorDescription ?? ""
        XCTAssertTrue(desc.contains("unload"))
    }
}

final class ClipboardSelectionTests: XCTestCase {
    func testCopyFullKeyIdNotTruncated() {
        // Display shows suffix(16); copy must use the full id.
        let key = GPGKey(keyId: "ABCDEF0123456789AABB", userId: "T <t@t>")
        XCTAssertEqual(key.keyId, "ABCDEF0123456789AABB")
        XCTAssertNotEqual(key.keyId, String(key.keyId.suffix(16)))
    }

    func testCopyEmptyIsNoOp() {
        // Clipboard.copy("") must not clobber the pasteboard.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("sentinel", forType: .string)
        Clipboard.copy("")
        XCTAssertEqual(pb.string(forType: .string), "sentinel")
    }
}

final class NetrcReaderTests: XCTestCase {
    func testSingleMachineOnOneLine() {
        let netrc = "machine github.com login me password ghp_abc123"
        XCTAssertEqual(NetrcReader.password(forMachine: "github.com", contents: netrc), "ghp_abc123")
    }

    func testMultiLineMachine() {
        let netrc = """
        machine github.com
          login me
          password ghp_token
        machine gitlab.com
          login other
          password glpat_token
        """
        XCTAssertEqual(NetrcReader.password(forMachine: "github.com", contents: netrc), "ghp_token")
        XCTAssertEqual(NetrcReader.password(forMachine: "gitlab.com", contents: netrc), "glpat_token")
    }

    func testUnknownMachineReturnsNil() {
        let netrc = "machine github.com login me password ghp_abc"
        XCTAssertNil(NetrcReader.password(forMachine: "example.com", contents: netrc))
    }

    func testCommentsIgnored() {
        let netrc = """
        # my creds
        machine github.com login me password ghp_xyz  # inline note
        """
        XCTAssertEqual(NetrcReader.password(forMachine: "github.com", contents: netrc), "ghp_xyz")
    }

    func testDefaultActsAsFallback() {
        let netrc = "machine github.com login me password ghp_specific\ndefault login anon password fallback_tok"
        // Specific machine wins (matched first).
        XCTAssertEqual(NetrcReader.password(forMachine: "github.com", contents: netrc), "ghp_specific")
        // An unlisted machine falls through to default.
        XCTAssertEqual(NetrcReader.password(forMachine: "gitlab.com", contents: netrc), "fallback_tok")
    }

    func testEmptyContents() {
        XCTAssertNil(NetrcReader.password(forMachine: "github.com", contents: ""))
    }
}

final class GitProfileTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let profile = GitProfile(id: "abc", name: "Ada Lovelace", email: "ada@x.io")
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.id, "abc")
    }

    func testMatches() {
        let profile = GitProfile(name: "Ada", email: "ada@x.io")
        XCTAssertTrue(profile.matches(GitIdentity(name: "Ada", email: "ada@x.io", signingKey: nil, signCommits: false)))
        XCTAssertFalse(profile.matches(GitIdentity(name: "Bob", email: "ada@x.io", signingKey: nil, signCommits: false)))
        XCTAssertFalse(profile.matches(nil))
        XCTAssertFalse(profile.matches(GitIdentity(name: "Ada", email: nil, signingKey: nil, signCommits: false)))
    }

    func testMatchesTrimsWhitespace() {
        let profile = GitProfile(name: "Ada ", email: " ada@x.io")
        XCTAssertTrue(profile.matches(GitIdentity(name: "Ada", email: "ada@x.io", signingKey: nil, signCommits: false)))
    }

    func testActiveInList() {
        let a = GitProfile(name: "Work", email: "me@work.com")
        let b = GitProfile(name: "Study", email: "me@uni.edu")
        let identity = GitIdentity(name: "Study", email: "me@uni.edu", signingKey: nil, signCommits: false)
        XCTAssertEqual(GitProfile.active(in: [a, b], matching: identity)?.id, b.id)
        XCTAssertNil(GitProfile.active(in: [a, b], matching: GitIdentity(name: "X", email: "x@x.com", signingKey: nil, signCommits: false)))
        XCTAssertNil(GitProfile.active(in: [], matching: identity))
    }
}

final class SettingsStoreProfileTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let defaults = UserDefaults(suiteName: "kssh.test.\(UUID().uuidString)")!
        let profiles = [GitProfile(name: "Work", email: "w@x.com"), GitProfile(name: "Study", email: "s@x.com")]
        let data = SettingsStore.encodeProfiles(profiles)!
        defaults.set(data, forKey: "gitProfiles")
        XCTAssertEqual(SettingsStore.loadProfiles(from: defaults), profiles)
    }

    func testLoadProfilesEmptyOnMissing() {
        let defaults = UserDefaults(suiteName: "kssh.test.\(UUID().uuidString)")!
        XCTAssertEqual(SettingsStore.loadProfiles(from: defaults), [])
    }

    func testLoadProfilesEmptyOnGarbage() {
        let defaults = UserDefaults(suiteName: "kssh.test.\(UUID().uuidString)")!
        defaults.set(Data("not json".utf8), forKey: "gitProfiles")
        XCTAssertEqual(SettingsStore.loadProfiles(from: defaults), [])
    }
}

final class GitServiceArgumentTests: XCTestCase {
    func testConfigArguments() {
        XCTAssertEqual(
            GitService.configArguments(key: "user.name", value: "Ada Lovelace"),
            ["config", "--global", "user.name", "Ada Lovelace"]
        )
    }

    func testPartialWriteErrorMentionsBothKeys() {
        let desc = GitService.GitServiceError.partialWrite(succeeded: "user.name", failed: "user.email", message: "x").errorDescription ?? ""
        XCTAssertTrue(desc.contains("user.name"))
        XCTAssertTrue(desc.contains("user.email"))
        XCTAssertTrue(desc.contains("inconsistent"))
    }
}

final class RemoteUserTests: XCTestCase {
    func testDisplayName() {
        let user = RemoteUser(service: .github, username: "testuser", matchedKeyCount: 1, avatarUrl: nil)
        XCTAssertEqual(user.displayName, "@testuser")
    }

    func testServiceCases() {
        XCTAssertEqual(RemoteService.allCases.count, 2)
        XCTAssertTrue(RemoteService.allCases.contains(.github))
        XCTAssertTrue(RemoteService.allCases.contains(.gitlab))
    }

    func testBelongsToActiveKey() {
        // matchedKeyCount is scoped to the active key: >=1 means the row should show.
        let linked = RemoteUser(service: .github, username: "u", matchedKeyCount: 1, avatarUrl: nil)
        let unlinked = RemoteUser(service: .github, username: "u", matchedKeyCount: 0, avatarUrl: nil)
        XCTAssertTrue(linked.belongsToActiveKey)
        XCTAssertFalse(unlinked.belongsToActiveKey)
    }
}

final class KeyNormalizationTests: XCTestCase {
    func testStripsCommentForMatching() {
        // ssh-add -L includes a comment; GitHub/GitLab return the key without one.
        // Both must normalize to the same "<type> <blob>".
        let withComment = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabc123 kitanoyoru@protonmail.com"
        let withoutComment = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabc123"
        XCTAssertEqual(GitHubService.normalizeKey(withComment), GitHubService.normalizeKey(withoutComment))
        XCTAssertEqual(GitHubService.normalizeKey(withComment), "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabc123")
    }

    func testDifferentBlobsDoNotMatch() {
        XCTAssertNotEqual(
            GitHubService.normalizeKey("ssh-ed25519 AAAA1111 a@b"),
            GitHubService.normalizeKey("ssh-ed25519 AAAA2222 a@b")
        )
    }

    func testHandlesExtraWhitespace() {
        XCTAssertEqual(
            GitHubService.normalizeKey("  ssh-ed25519   AAAA1111   me@host  "),
            "ssh-ed25519 AAAA1111"
        )
    }
}

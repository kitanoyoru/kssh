import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    // MARK: - Remote accounts (multi-account per service)
    //
    // Metadata (label, instance, ordering) lives in UserDefaults as JSON, mirroring the
    // `gitProfiles` pattern. Secrets (PAT / app-password / Bitbucket username) live in the
    // Keychain, keyed by account id via `RemoteAccount.keychainKey(...)`, and are read
    // lazily — only the active account's secret is ever needed for resolution, so there's
    // no benefit to mirroring N secrets into `@Published` strings at init.

    @Published var githubAccounts: [RemoteAccount] {
        didSet { Self.persist(githubAccounts, for: .github) }
    }
    @Published var gitlabAccounts: [RemoteAccount] {
        didSet { Self.persist(gitlabAccounts, for: .gitlab) }
    }
    @Published var bitbucketAccounts: [RemoteAccount] {
        didSet { Self.persist(bitbucketAccounts, for: .bitbucket) }
    }

    /// Active account id per service, persisted under `activeAccount.<service>`. Stored as
    /// the id (not an index) so it survives reorder/delete. `@Published` so the UI's
    /// active radio updates; `didSet` re-persists.
    @Published private var activeAccountIds: [RemoteService: String] {
        didSet { Self.persistActiveIds(activeAccountIds) }
    }

    /// Auto-refresh interval (seconds) for the popover polling loop; 0 means manual-only.
    @AppStorage("refreshInterval") var refreshInterval: Int = 60

    /// User-defined git identity presets, persisted as JSON in UserDefaults (names/emails
    /// are non-sensitive, so no Keychain). `@Published`+`didSet` mirrors the account pattern;
    /// `@AppStorage` is avoided here because it doesn't reliably republish from a non-View
    /// ObservableObject.
    @Published var gitProfiles: [GitProfile] {
        didSet { Self.persist(gitProfiles) }
    }

    private static let gitProfilesKey = "gitProfiles"
    private static let activeIdentityKey = "activeIdentityPath"
    private static let activeAccountIdsKey = "activeAccountIds"
    private static let migratedFlagKey = "migratedToMultiAccount"

    /// Absolute path of the SSH key the user last switched to, persisted so the active
    /// highlight survives relaunch and reflects the user's choice even in configs that
    /// can't express a single active identity (separate Host per key). See
    /// `SSHIdentityService.activeIdentity(among:selectedPath:)`.
    var activeIdentityPath: String? {
        get { UserDefaults.standard.string(forKey: Self.activeIdentityKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.activeIdentityKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeIdentityKey)
            }
        }
    }

    /// Upper bound on stored git profiles, enforced by `addProfile` and surfaced in the UI.
    static let maxProfiles = 5

    /// Upper bound on accounts per service.
    static let maxAccounts = 5

    /// Pure, testable cap check: whether another profile may be added given a count.
    static func canAdd(profileCount: Int) -> Bool { profileCount < maxProfiles }

    /// Pure, testable cap check: whether another account may be added given a count.
    static func canAdd(accountCount: Int) -> Bool { accountCount < maxAccounts }

    /// Whether the user may add another profile (under `maxProfiles`).
    var canAddProfile: Bool { Self.canAdd(profileCount: gitProfiles.count) }

    init() {
        // Migrate legacy single-PAT keys BEFORE loading the account blobs, so a fresh
        // multi-account install seeded from old keys is visible to the loads below. The
        // migration is idempotent (gated on a flag + "no blob yet").
        Self.migrateLegacyAccounts(
            in: .standard,
            readKeychain: { KeychainManager.read(key: $0) },
            writeKeychain: { KeychainManager.save(key: $0, value: $1) }
        )

        self.githubAccounts = Self.loadAccounts(.github)
        self.gitlabAccounts = Self.loadAccounts(.gitlab)
        self.bitbucketAccounts = Self.loadAccounts(.bitbucket)
        self.activeAccountIds = Self.loadActiveIds()
        // Assigned after the stored properties above; `didSet` does not fire on the
        // initial assignment in init, so this does not re-persist on launch.
        self.gitProfiles = Self.loadProfiles()
    }

    // MARK: - Account access

    func accounts(for service: RemoteService) -> [RemoteAccount] {
        switch service {
        case .github: return githubAccounts
        case .gitlab: return gitlabAccounts
        case .bitbucket: return bitbucketAccounts
        }
    }

    private func setAccounts(_ accounts: [RemoteAccount], for service: RemoteService) {
        switch service {
        case .github: githubAccounts = accounts
        case .gitlab: gitlabAccounts = accounts
        case .bitbucket: bitbucketAccounts = accounts
        }
    }

    /// The active account for a service: the one matching the stored active id, else the
    /// first account, else none. Pure resolution rule shared with tests.
    func activeAccount(for service: RemoteService) -> RemoteAccount? {
        Self.resolveActive(in: accounts(for: service), activeId: activeAccountIds[service])
    }

    /// Pure: resolve the active account from a list + an optional explicit id.
    static func resolveActive(in accounts: [RemoteAccount], activeId: String?) -> RemoteAccount? {
        if let activeId, let match = accounts.first(where: { $0.id == activeId }) {
            return match
        }
        return accounts.first
    }

    var activeAccountId: (RemoteService) -> String? { { self.activeAccountIds[$0] } }

    func canAddAccount(for service: RemoteService) -> Bool {
        Self.canAdd(accountCount: accounts(for: service).count)
    }

    // MARK: - Lazy secret access (Keychain)

    /// The PAT for a specific account (GitHub/GitLab). Read on demand from the Keychain.
    func secret(for service: RemoteService, id: String) -> String? {
        KeychainManager.read(key: RemoteAccount.keychainKey(service: service, field: .pat, id: id))
    }

    /// The Bitbucket username + app password pair for a specific account.
    func bitbucketCredentials(id: String) -> (username: String, appPassword: String)? {
        let user = KeychainManager.read(key: RemoteAccount.keychainKey(service: .bitbucket, field: .username, id: id)) ?? ""
        let pass = KeychainManager.read(key: RemoteAccount.keychainKey(service: .bitbucket, field: .appPassword, id: id)) ?? ""
        guard !user.isEmpty, !pass.isEmpty else { return nil }
        return (user, pass)
    }

    // MARK: - Convenience for token resolution

    /// Active GitLab instance host, defaulting to "gitlab.com".
    var activeGitlabInstance: String {
        let instance = activeAccount(for: .gitlab)?.instance ?? ""
        return instance.isEmpty ? "gitlab.com" : instance
    }

    var hasGitHubToken: Bool {
        guard let id = activeAccount(for: .github)?.id else { return false }
        return !(secret(for: .github, id: id) ?? "").isEmpty
    }
    var hasGitLabToken: Bool {
        guard let id = activeAccount(for: .gitlab)?.id else { return false }
        return !(secret(for: .gitlab, id: id) ?? "").isEmpty
    }
    var hasBitbucketCredentials: Bool {
        guard let id = activeAccount(for: .bitbucket)?.id else { return false }
        return bitbucketCredentials(id: id) != nil
    }

    // MARK: - Account CRUD

    /// Adds a GitHub/GitLab account, writing its PAT to the Keychain. Becomes active if it
    /// is the first account for that service. Returns the created account, or nil if capped.
    @discardableResult
    func addAccount(label: String, secret: String, instance: String? = nil, for service: RemoteService) -> RemoteAccount? {
        guard canAddAccount(for: service) else { return nil }
        let account = RemoteAccount(label: label, instance: instance)
        KeychainManager.save(key: RemoteAccount.keychainKey(service: service, field: .pat, id: account.id), value: secret)
        appendAccount(account, for: service)
        return account
    }

    /// Adds a Bitbucket account, writing username + app password to the Keychain.
    @discardableResult
    func addBitbucketAccount(label: String, username: String, appPassword: String) -> RemoteAccount? {
        guard canAddAccount(for: .bitbucket) else { return nil }
        let account = RemoteAccount(label: label)
        KeychainManager.save(key: RemoteAccount.keychainKey(service: .bitbucket, field: .username, id: account.id), value: username)
        KeychainManager.save(key: RemoteAccount.keychainKey(service: .bitbucket, field: .appPassword, id: account.id), value: appPassword)
        appendAccount(account, for: .bitbucket)
        return account
    }

    private func appendAccount(_ account: RemoteAccount, for service: RemoteService) {
        var list = accounts(for: service)
        let wasEmpty = list.isEmpty
        list.append(account)
        setAccounts(list, for: service)
        if wasEmpty { activeAccountIds[service] = account.id }
    }

    /// Renames an account. Metadata-only — never touches the Keychain.
    func renameAccount(id: String, to label: String, for service: RemoteService) {
        var list = accounts(for: service)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].label = label
        setAccounts(list, for: service)
    }

    /// Updates a GitLab account's instance host. Metadata-only.
    func updateInstance(id: String, instance: String, for service: RemoteService) {
        var list = accounts(for: service)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].instance = instance
        setAccounts(list, for: service)
    }

    /// Overwrites an existing account's PAT in the Keychain (GitHub/GitLab).
    func updateSecret(id: String, secret: String, for service: RemoteService) {
        KeychainManager.save(key: RemoteAccount.keychainKey(service: service, field: .pat, id: id), value: secret)
    }

    /// Overwrites a Bitbucket account's username + app password in the Keychain.
    func updateBitbucketSecret(id: String, username: String, appPassword: String) {
        KeychainManager.save(key: RemoteAccount.keychainKey(service: .bitbucket, field: .username, id: id), value: username)
        KeychainManager.save(key: RemoteAccount.keychainKey(service: .bitbucket, field: .appPassword, id: id), value: appPassword)
    }

    /// Marks an account active for its service.
    func setActive(id: String, for service: RemoteService) {
        guard accounts(for: service).contains(where: { $0.id == id }) else { return }
        activeAccountIds[service] = id
    }

    /// Deletes an account: purges every Keychain key for it, removes the metadata, and
    /// re-points the active id to the new first account (or clears it). Purging the
    /// Keychain is mandatory — metadata-only removal would orphan the secret.
    func deleteAccount(id: String, for service: RemoteService) {
        for field in keychainFields(for: service) {
            KeychainManager.delete(key: RemoteAccount.keychainKey(service: service, field: field, id: id))
        }
        var list = accounts(for: service)
        list.removeAll { $0.id == id }
        setAccounts(list, for: service)
        if activeAccountIds[service] == id {
            activeAccountIds[service] = list.first?.id
        }
    }

    private func keychainFields(for service: RemoteService) -> [RemoteAccount.Field] {
        service == .bitbucket ? [.username, .appPassword] : [.pat]
    }

    // MARK: - Git profile CRUD

    func addProfile(_ profile: GitProfile) {
        guard canAddProfile else { return }
        gitProfiles.append(profile)
    }

    func updateProfile(_ profile: GitProfile) {
        if let index = gitProfiles.firstIndex(where: { $0.id == profile.id }) {
            gitProfiles[index] = profile
        }
    }

    func deleteProfile(_ profile: GitProfile) {
        gitProfiles.removeAll { $0.id == profile.id }
    }

    // MARK: - Persistence helpers (pure / testable)

    static func loadProfiles(from defaults: UserDefaults = .standard) -> [GitProfile] {
        guard let data = defaults.data(forKey: gitProfilesKey) else { return [] }
        return (try? JSONDecoder().decode([GitProfile].self, from: data)) ?? []
    }

    static func encodeProfiles(_ profiles: [GitProfile]) -> Data? {
        try? JSONEncoder().encode(profiles)
    }

    private static func persist(_ profiles: [GitProfile], to defaults: UserDefaults = .standard) {
        if let data = encodeProfiles(profiles) {
            defaults.set(data, forKey: gitProfilesKey)
        }
    }

    static func accountsKey(for service: RemoteService) -> String {
        switch service {
        case .github: return "accounts.github"
        case .gitlab: return "accounts.gitlab"
        case .bitbucket: return "accounts.bitbucket"
        }
    }

    static func loadAccounts(_ service: RemoteService, from defaults: UserDefaults = .standard) -> [RemoteAccount] {
        guard let data = defaults.data(forKey: accountsKey(for: service)) else { return [] }
        return (try? JSONDecoder().decode([RemoteAccount].self, from: data)) ?? []
    }

    static func encodeAccounts(_ accounts: [RemoteAccount]) -> Data? {
        try? JSONEncoder().encode(accounts)
    }

    static func persist(_ accounts: [RemoteAccount], for service: RemoteService, to defaults: UserDefaults = .standard) {
        if let data = encodeAccounts(accounts) {
            defaults.set(data, forKey: accountsKey(for: service))
        }
    }

    static func loadActiveIds(from defaults: UserDefaults = .standard) -> [RemoteService: String] {
        guard let raw = defaults.dictionary(forKey: activeAccountIdsKey) as? [String: String] else { return [:] }
        var result: [RemoteService: String] = [:]
        for service in RemoteService.allCases {
            if let id = raw[service.rawValue] { result[service] = id }
        }
        return result
    }

    static func persistActiveIds(_ ids: [RemoteService: String], to defaults: UserDefaults = .standard) {
        var raw: [String: String] = [:]
        for (service, id) in ids { raw[service.rawValue] = id }
        defaults.set(raw, forKey: activeAccountIdsKey)
    }

    // MARK: - Migration

    /// One-time migration of the legacy single-PAT Keychain keys into one "Default" account
    /// per service. Idempotent: gated on the `migratedToMultiAccount` flag AND "no accounts
    /// blob yet" for each service, so a relaunch never clobbers post-migration accounts.
    /// Keychain access is injected so this is unit-testable without the real keychain.
    /// Legacy keys are intentionally NOT deleted (downgrade/recovery safety).
    static func migrateLegacyAccounts(
        in defaults: UserDefaults,
        readKeychain: (String) -> String?,
        writeKeychain: (String, String) -> Void
    ) {
        guard !defaults.bool(forKey: migratedFlagKey) else { return }

        // GitHub
        if defaults.data(forKey: accountsKey(for: .github)) == nil {
            let pat = readKeychain("githubPat") ?? ""
            if !pat.isEmpty {
                let account = RemoteAccount(label: "Default")
                writeKeychain(RemoteAccount.keychainKey(service: .github, field: .pat, id: account.id), pat)
                persist([account], for: .github, to: defaults)
                setMigratedActive(account.id, for: .github, in: defaults)
            }
        }

        // GitLab — seed instance from the legacy global gitlabInstance AppStorage value.
        if defaults.data(forKey: accountsKey(for: .gitlab)) == nil {
            let pat = readKeychain("gitlabPat") ?? ""
            if !pat.isEmpty {
                let instance = defaults.string(forKey: "gitlabInstance")
                let account = RemoteAccount(label: "Default", instance: instance)
                writeKeychain(RemoteAccount.keychainKey(service: .gitlab, field: .pat, id: account.id), pat)
                persist([account], for: .gitlab, to: defaults)
                setMigratedActive(account.id, for: .gitlab, in: defaults)
            }
        }

        // Bitbucket — both username and app password must be present.
        if defaults.data(forKey: accountsKey(for: .bitbucket)) == nil {
            let user = readKeychain("bitbucketUsername") ?? ""
            let pass = readKeychain("bitbucketAppPassword") ?? ""
            if !user.isEmpty, !pass.isEmpty {
                let account = RemoteAccount(label: "Default")
                writeKeychain(RemoteAccount.keychainKey(service: .bitbucket, field: .username, id: account.id), user)
                writeKeychain(RemoteAccount.keychainKey(service: .bitbucket, field: .appPassword, id: account.id), pass)
                persist([account], for: .bitbucket, to: defaults)
                setMigratedActive(account.id, for: .bitbucket, in: defaults)
            }
        }

        defaults.set(true, forKey: migratedFlagKey)
    }

    /// Writes an active id during migration, merging into the persisted dictionary.
    private static func setMigratedActive(_ id: String, for service: RemoteService, in defaults: UserDefaults) {
        var raw = (defaults.dictionary(forKey: activeAccountIdsKey) as? [String: String]) ?? [:]
        raw[service.rawValue] = id
        defaults.set(raw, forKey: activeAccountIdsKey)
    }
}

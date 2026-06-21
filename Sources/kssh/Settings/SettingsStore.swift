import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    @Published var githubPat: String {
        didSet { KeychainManager.save(key: "githubPat", value: githubPat) }
    }
    @Published var gitlabPat: String {
        didSet { KeychainManager.save(key: "gitlabPat", value: gitlabPat) }
    }
    @AppStorage("gitlabInstance") var gitlabInstance = "gitlab.com"

    /// User-defined git identity presets, persisted as JSON in UserDefaults (names/emails
    /// are non-sensitive, so no Keychain). `@Published`+`didSet` mirrors the PAT pattern;
    /// `@AppStorage` is avoided here because it doesn't reliably republish from a non-View
    /// ObservableObject.
    @Published var gitProfiles: [GitProfile] {
        didSet { Self.persist(gitProfiles) }
    }

    private static let gitProfilesKey = "gitProfiles"

    /// Upper bound on stored git profiles, enforced by `addProfile` and surfaced in the UI.
    static let maxProfiles = 5

    /// Pure, testable cap check: whether another profile may be added given a count.
    static func canAdd(profileCount: Int) -> Bool { profileCount < maxProfiles }

    /// Whether the user may add another profile (under `maxProfiles`).
    var canAddProfile: Bool { Self.canAdd(profileCount: gitProfiles.count) }

    init() {
        self.githubPat = KeychainManager.read(key: "githubPat") ?? ""
        self.gitlabPat = KeychainManager.read(key: "gitlabPat") ?? ""
        // Assigned after the stored properties above; `didSet` does not fire on the
        // initial assignment in init, so this does not re-persist on launch.
        self.gitProfiles = Self.loadProfiles()
    }

    var hasGitHubToken: Bool { !githubPat.isEmpty }
    var hasGitLabToken: Bool { !gitlabPat.isEmpty }

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
}

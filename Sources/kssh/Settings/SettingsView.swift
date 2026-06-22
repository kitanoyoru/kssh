import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = SettingsStore()

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AccountsTab(store: store, service: .github)
                .tabItem {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }

            AccountsTab(store: store, service: .gitlab)
                .tabItem {
                    Label("GitLab", systemImage: "chevron.left.forwardslash.chevron.right")
                }

            AccountsTab(store: store, service: .bitbucket)
                .tabItem {
                    Label("Bitbucket", systemImage: "chevron.left.forwardslash.chevron.right")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 460, height: 420)
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker("Auto-refresh", selection: $store.refreshInterval) {
                    Text("Every 30 seconds").tag(30)
                    Text("Every minute").tag(60)
                    Text("Every 5 minutes").tag(300)
                    Text("Manual only").tag(0)
                }
                Text("How often the menu refreshes while the popover is open.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Refresh")
            }

            Section {
                LaunchAtLoginToggle()
            } header: {
                Text("Startup")
            }

            Section {
                Text("All tokens are stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Security")
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        Form {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Self.appVersion)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("License")
                    Spacer()
                    Text("MIT")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("kssh")
            }
        }
        .formStyle(.grouped)
    }

    /// App version from the bundle's `CFBundleShortVersionString`, so the About tab tracks
    /// the real release instead of a hardcoded string. Falls back if unavailable.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

/// Launch-at-login toggle backed by `SMAppService`. Reads the live status on appear so it
/// reflects external changes (e.g. the user removing it in System Settings).
private struct LaunchAtLoginToggle: View {
    @State private var enabled = LoginItem.isEnabled

    var body: some View {
        Toggle("Launch kssh at login", isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                // Sync to the actual resulting state in case registration failed.
                enabled = LoginItem.setEnabled(newValue)
            }
            .onAppear { enabled = LoginItem.isEnabled }
    }
}

// MARK: - Accounts tab

/// Lists the stored accounts for one service, with add / pick-active and per-row edit,
/// delete, and a "Test" connection button. Replaces the old single-`SecureField` tab.
private struct AccountsTab: View {
    @ObservedObject var store: SettingsStore
    let service: RemoteService

    @State private var showingAdd = false

    var body: some View {
        Form {
            Section {
                let accounts = store.accounts(for: service)
                if accounts.isEmpty {
                    Text("No accounts yet. Add one to authenticate with \(service.rawValue).")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(accounts) { account in
                        AccountRow(store: store, service: service, account: account)
                    }
                }

                Button {
                    showingAdd = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .disabled(!store.canAddAccount(for: service))
            } header: {
                Text("\(service.rawValue) Accounts")
            } footer: {
                Text(scopesHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAdd) {
            AddAccountSheet(store: store, service: service)
        }
    }

    private var scopesHint: String {
        switch service {
        case .github:
            return "Create a token at github.com/settings/tokens with read:public_key and read:user scopes."
        case .gitlab:
            return "Create a token at <instance>/-/user_settings/personal_access_tokens with read_api scope."
        case .bitbucket:
            return "Create an App Password at bitbucket.org/account/settings/app-passwords with Account: Read and SSH keys: Read."
        }
    }
}

/// A single account row: active radio, label, expandable editor, and Test/Delete actions.
private struct AccountRow: View {
    @ObservedObject var store: SettingsStore
    let service: RemoteService
    let account: RemoteAccount

    @State private var expanded = false
    @State private var testState: TestState = .idle

    private var isActive: Bool { store.activeAccount(for: service)?.id == account.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    store.setActive(id: account.id, for: service)
                } label: {
                    Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(isActive ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isActive ? "Active account" : "Make active")

                Text(account.displayLabel)
                    .fontWeight(isActive ? .semibold : .regular)

                if let instance = account.instance, !instance.isEmpty, service == .gitlab {
                    Text(instance)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                testStatusView

                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                AccountEditor(store: store, service: service, account: account)

                HStack {
                    Button("Test") { Task { await test() } }
                        .disabled(testState == .testing)
                    if testState == .testing {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteAccount(id: account.id, for: service)
                    } label: {
                        Text("Delete")
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle, .testing:
            EmptyView()
        case .valid(let who):
            Label(who, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
                .labelStyle(.titleAndIcon)
        case .invalid:
            Label("Invalid", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .labelStyle(.titleAndIcon)
        }
    }

    /// Validates the stored credential by calling the provider's profile endpoint, which
    /// authenticates without needing the user's SSH keys. A non-nil result means the token
    /// works; we surface the profile's full name when present.
    private func test() async {
        testState = .testing
        let detail: RemoteProfileDetail?
        switch service {
        case .github:
            let pat = store.secret(for: .github, id: account.id) ?? ""
            detail = pat.isEmpty ? nil : await GitHubService.profileDetail(pat: pat)
        case .gitlab:
            let pat = store.secret(for: .gitlab, id: account.id) ?? ""
            let host = (account.instance?.isEmpty == false ? account.instance! : "gitlab.com")
            detail = pat.isEmpty ? nil : await GitLabService.profileDetail(pat: pat, instance: host)
        case .bitbucket:
            if let creds = store.bitbucketCredentials(id: account.id) {
                detail = await BitbucketService.profileDetail(username: creds.username, appPassword: creds.appPassword)
            } else {
                detail = nil
            }
        }
        if let detail {
            testState = .valid(detail.fullName ?? "Valid")
        } else {
            testState = .invalid
        }
    }

    private enum TestState: Equatable {
        case idle, testing, valid(String), invalid
    }
}

/// Inline editor for a row: rename, secret(s), and (GitLab) instance. Secrets are not
/// `@Published` on the store, so this loads them from the Keychain on appear and saves on
/// commit (field exit / submit) rather than keystroke-by-keystroke.
private struct AccountEditor: View {
    @ObservedObject var store: SettingsStore
    let service: RemoteService
    let account: RemoteAccount

    @State private var label = ""
    @State private var instance = ""
    @State private var secret = ""
    @State private var username = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Label", text: $label)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.renameAccount(id: account.id, to: label, for: service) }

            if service == .gitlab {
                TextField("Instance (e.g. gitlab.com)", text: $instance)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.updateInstance(id: account.id, instance: instance, for: service) }
            }

            if service == .bitbucket {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("App Password", text: $secret)
                    .textFieldStyle(.roundedBorder)
                Button("Save Credentials") {
                    store.updateBitbucketSecret(id: account.id, username: username, appPassword: secret)
                }
            } else {
                SecureField("Personal Access Token", text: $secret)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.updateSecret(id: account.id, secret: secret, for: service) }
                Button("Save Token") {
                    store.updateSecret(id: account.id, secret: secret, for: service)
                    if !label.isEmpty { store.renameAccount(id: account.id, to: label, for: service) }
                    if service == .gitlab { store.updateInstance(id: account.id, instance: instance, for: service) }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        label = account.label
        instance = account.instance ?? ""
        if service == .bitbucket {
            let creds = store.bitbucketCredentials(id: account.id)
            username = creds?.username ?? ""
            secret = creds?.appPassword ?? ""
        } else {
            secret = store.secret(for: service, id: account.id) ?? ""
        }
    }
}

/// Sheet to create a new account.
private struct AddAccountSheet: View {
    @ObservedObject var store: SettingsStore
    let service: RemoteService
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var instance = "gitlab.com"
    @State private var secret = ""
    @State private var username = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add \(service.rawValue) Account")
                .font(.headline)

            TextField("Label (e.g. Work)", text: $label)
                .textFieldStyle(.roundedBorder)

            if service == .gitlab {
                TextField("Instance", text: $instance)
                    .textFieldStyle(.roundedBorder)
            }

            if service == .bitbucket {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("App Password", text: $secret)
                    .textFieldStyle(.roundedBorder)
            } else {
                SecureField("Personal Access Token", text: $secret)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    add()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var canAdd: Bool {
        guard !label.isEmpty else { return false }
        if service == .bitbucket { return !username.isEmpty && !secret.isEmpty }
        return !secret.isEmpty
    }

    private func add() {
        switch service {
        case .bitbucket:
            store.addBitbucketAccount(label: label, username: username, appPassword: secret)
        case .gitlab:
            store.addAccount(label: label, secret: secret, instance: instance, for: .gitlab)
        case .github:
            store.addAccount(label: label, secret: secret, for: .github)
        }
    }
}

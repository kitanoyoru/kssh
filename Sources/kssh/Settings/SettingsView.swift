import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = SettingsStore()

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            accountsTab
                .tabItem {
                    Label("Accounts", systemImage: "person.2")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 460, height: 360)
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

    /// Read-only summary of configured remote accounts. Management (add / edit / switch /
    /// test / delete) now lives in the menu bar's Remote section, alongside SSH keys — this
    /// tab just reflects what's stored and points there.
    private var accountsTab: some View {
        Form {
            ForEach(RemoteService.allCases, id: \.self) { service in
                Section {
                    let accounts = store.accounts(for: service)
                    if accounts.isEmpty {
                        Text("No accounts.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        let activeId = store.activeAccount(for: service)?.id
                        ForEach(accounts) { account in
                            HStack {
                                Text(account.displayLabel)
                                if account.id == activeId {
                                    Text("Active")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if service == .gitlab, let instance = account.instance, !instance.isEmpty {
                                    Text(instance)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(service.rawValue)
                }
            }

            Section {
                Text("Add, edit, switch, test, or remove accounts from the menu bar — click the kssh key icon, then the Remote section.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

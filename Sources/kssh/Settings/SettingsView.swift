import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = SettingsStore()

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
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

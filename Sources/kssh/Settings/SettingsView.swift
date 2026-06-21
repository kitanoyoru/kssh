import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = SettingsStore()

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            githubTab
                .tabItem {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }

            gitlabTab
                .tabItem {
                    Label("GitLab", systemImage: "chevron.left.forwardslash.chevron.right")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 280)
    }

    private var generalTab: some View {
        Form {
            Section {
                Text("kssh monitors your SSH, Git, and GPG configuration from the menu bar.")
                    .font(.body)
                    .padding(.vertical, 8)

                Text("Click the key icon in the menu bar to view your current status.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } header: {
                Text("About kssh")
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

    private var githubTab: some View {
        Form {
            Section {
                SecureField("Personal Access Token", text: $store.githubPat)
                    .textFieldStyle(.roundedBorder)

                Text("Create a token at github.com/settings/tokens with **read:public_key** and **read:user** scopes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("GitHub Authentication")
            }
        }
        .formStyle(.grouped)
    }

    private var gitlabTab: some View {
        Form {
            Section {
                SecureField("Personal Access Token", text: $store.gitlabPat)
                    .textFieldStyle(.roundedBorder)

                TextField("Instance", text: $store.gitlabInstance)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Text("Create a token at \(store.gitlabInstance)/-/user_settings/personal_access_tokens with **read_api** scope.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("GitLab Authentication")
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
                    Text("1.0.0")
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
}

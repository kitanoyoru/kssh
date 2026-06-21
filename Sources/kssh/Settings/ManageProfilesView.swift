import SwiftUI

/// CRUD for git identity profiles. Lives in a dedicated Window (not a sheet) because a
/// sheet over the menu-bar popover dismisses unreliably. Binds directly to the shared
/// SettingsStore so changes appear live in the menu's Git section.
struct ManageProfilesView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var editingID: String?

    private var canSave: Bool {
        !name.isEmpty && email.contains("@")
    }

    var body: some View {
        Form {
            Section("Profiles") {
                if store.gitProfiles.isEmpty {
                    Text("No profiles yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.gitProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(.callout)
                                Text(profile.email)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { beginEdit(profile) } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit profile")

                            Button(role: .destructive) { store.deleteProfile(profile) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete profile")
                        }
                    }
                }
            }

            Section(editingID == nil ? "Add Profile" : "Edit Profile") {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                HStack {
                    if editingID != nil {
                        Button("Cancel") { resetForm() }
                    }
                    Spacer()
                    Button(editingID == nil ? "Add" : "Save") { commit() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
        .navigationTitle("Manage Git Profiles")
    }

    private func beginEdit(_ profile: GitProfile) {
        editingID = profile.id
        name = profile.name
        email = profile.email
    }

    private func resetForm() {
        editingID = nil
        name = ""
        email = ""
    }

    private func commit() {
        if let id = editingID {
            store.updateProfile(GitProfile(id: id, name: name, email: email))
        } else {
            store.addProfile(GitProfile(name: name, email: email))
        }
        resetForm()
    }
}

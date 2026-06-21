import SwiftUI

/// A simple form for creating a GPG key (ed25519, sign+certify, no expiry). Lives in a
/// dedicated Window scene rather than a sheet, because a sheet over the menu-bar popover
/// (.menuBarExtraStyle(.window)) dismisses unreliably when the popover loses focus.
struct CreateGPGKeyView: View {
    @ObservedObject var viewModel: StatusViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var passphrase = ""

    private var canCreate: Bool {
        viewModel.gpgAvailable && !name.isEmpty && email.contains("@") && !viewModel.creatingGPGKey
    }

    var body: some View {
        Form {
            if !viewModel.gpgAvailable {
                Section {
                    Label("gpg is not installed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(StatusColor.warning)
                    Text("Install with: brew install gnupg")
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }

            Section("Identity") {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                SecureField("Passphrase (optional)", text: $passphrase)
            }

            Section("Key") {
                LabeledContent("Algorithm", value: "ed25519")
                LabeledContent("Usage", value: "sign, certify")
                LabeledContent("Expiry", value: "never")
            }

            if let err = viewModel.gpgCreateError {
                Section {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(StatusColor.destructive)
                }
            }

            Section {
                HStack {
                    Spacer()
                    if viewModel.creatingGPGKey {
                        ProgressView().controlSize(.small)
                    }
                    Button("Create Key") {
                        Task {
                            let ok = await viewModel.createGPGKey(name: name, email: email, passphrase: passphrase)
                            if ok { dismiss() }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 340)
        .navigationTitle("Create GPG Key")
    }
}

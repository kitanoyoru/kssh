import SwiftUI

/// In-popover navigation. Detail routes replace the whole popover content (their own
/// back header instead of the main header/actions). A `NavigationStack` isn't used: a
/// MenuBarExtra(.window) popover doesn't host nav-bar chrome well, and the depth here is
/// shallow (main → profiles list → profile form; main → create GPG).
private enum Route: Equatable {
    case main
    case profilesList
    case profileForm(editing: GitProfile?)   // nil = add
    case createGPGKey

    /// Where the back button returns to.
    var parent: Route {
        switch self {
        case .main, .profilesList, .createGPGKey: return .main
        case .profileForm: return .profilesList
        }
    }

    var title: String {
        switch self {
        case .main: return "kssh"
        case .profilesList: return "Git Profiles"
        case .profileForm(let editing): return editing == nil ? "Add Profile" : "Edit Profile"
        case .createGPGKey: return "Create GPG Key"
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var viewModel: StatusViewModel
    @ObservedObject var store: SettingsStore
    @State private var route: Route = .main

    var body: some View {
        ZStack {
            switch route {
            case .main:
                mainContent
                    .transition(.move(edge: .leading))
            case .profilesList:
                routeScreen { profilesListScreen }
                    .transition(.move(edge: .trailing))
            case .profileForm(let editing):
                routeScreen {
                    ProfileFormScreen(store: store, editing: editing) {
                        withAnimation { route = .profilesList }
                    }
                }
                .transition(.move(edge: .trailing))
            case .createGPGKey:
                routeScreen {
                    CreateGPGScreen(viewModel: viewModel) {
                        withAnimation { route = .main }
                    }
                }
                .transition(.move(edge: .trailing))
            }
        }
        .frame(width: 300)
        .clipped()
        .animation(.easeInOut(duration: 0.22), value: route)
        .onAppear { viewModel.startAutoRefresh() }
        .onDisappear {
            viewModel.stopAutoRefresh()
            route = .main   // ephemeral popover: fresh open, discard unsaved form text
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.horizontal, Spacing.md)

            if let error = viewModel.error {
                ErrorBanner(message: error) { viewModel.error = nil }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
            }

            if let notice = viewModel.notice {
                NoticeBanner(message: notice) { viewModel.notice = nil }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
            }

            if viewModel.isLoading && viewModel.sshKeys.isEmpty {
                loadingView
            } else if !viewModel.agentRunning {
                // Agent off: hide every section and offer a single Enable action.
                VStack(spacing: Spacing.sm) {
                    agentOffSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            } else {
                VStack(spacing: Spacing.sm) {
                    keysSection
                    gitSection
                    gpgSection
                    remoteSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }

            Divider()
                .padding(.horizontal, Spacing.md)

            actionsSection
        }
    }

    // MARK: - Route chrome

    /// Wraps a detail screen with a back header + divider, matching mainContent's rhythm.
    @ViewBuilder
    private func routeScreen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            DetailHeader(title: route.title) {
                withAnimation { route = route.parent }
            }
            Divider()
                .padding(.horizontal, Spacing.md)
            content()
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Profiles list screen

    private var profilesListScreen: some View {
        VStack(spacing: Spacing.sm) {
            if store.gitProfiles.isEmpty {
                EmptyRow(text: "No profiles yet")
            } else {
                ForEach(store.gitProfiles) { profile in
                    HStack(spacing: Spacing.sm) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(profile.name).font(.callout).lineLimit(1)
                            Text(profile.email)
                                .font(.caption2)
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: Spacing.xs)
                        Button { withAnimation { route = .profileForm(editing: profile) } } label: {
                            Image(systemName: "pencil").font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit profile")
                        Button(role: .destructive) { store.deleteProfile(profile) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(StatusColor.destructive)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete profile")
                    }
                    .padding(.horizontal, Spacing.xs + 2)
                    .padding(.vertical, Spacing.xs + 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
            if store.canAddProfile {
                Button { withAnimation { route = .profileForm(editing: nil) } } label: {
                    actionLabelRow("Add profile", systemImage: "plus.circle")
                }
                .buttonStyle(MenuActionButtonStyle())
            } else {
                Text("Maximum of \(SettingsStore.maxProfiles) profiles reached.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.xxs)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("kssh")
                    .font(.headline)
                Text("Created by @kitanoyoru")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            StatusPill(
                text: viewModel.agentRunning ? "Agent on" : "Agent off",
                color: viewModel.agentRunning ? StatusColor.active : StatusColor.inactive
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md - 2)
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Loading identities…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg + Spacing.sm)
    }

    // MARK: - Agent off

    /// Shown in place of every section when the ssh-agent isn't running: a status pill plus
    /// a single Enable button that starts the agent.
    private var agentOffSection: some View {
        SectionCard(
            icon: "powerplug",
            title: "SSH Agent",
            accessory: { StatusPill(text: "Agent off", color: StatusColor.inactive) }
        ) {
            Text("The SSH agent isn't running. Enable it to manage and load your keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { Task { await viewModel.startAgent() } } label: {
                if viewModel.startingAgent {
                    HStack(spacing: Spacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Enabling…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    actionLabelRow("Enable agent", systemImage: "power")
                }
            }
            .buttonStyle(MenuActionButtonStyle())
            .disabled(viewModel.startingAgent)
        }
    }

    // MARK: - Keys (SSH identities + agent state, merged)

    /// One row per on-disk key. Each row carries both states: active-in-config
    /// (check/radio + switch) and loaded-in-agent (bolt / load button), so the
    /// separate "SSH Agent" card is no longer needed.
    private var keysSection: some View {
        SectionCard(
            icon: "key.horizontal",
            title: "Keys",
            accessory: {
                if !viewModel.availableIdentities.isEmpty {
                    CountBadge(count: viewModel.availableIdentities.count)
                }
            }
        ) {
            if viewModel.availableIdentities.isEmpty {
                EmptyRow(text: viewModel.agentRunning ? "No keys found in ~/.ssh" : "Agent not running")
            } else {
                ForEach(viewModel.availableIdentities) { identity in
                    IdentitySwitchRow(
                        identity: identity,
                        isActive: identity.id == viewModel.activeIdentity?.id,
                        isSwitching: identity.id == viewModel.switchingIdentity,
                        disabled: viewModel.switchingIdentity != nil,
                        isLoaded: viewModel.isLoaded(identity),
                        isLoading: identity.id == viewModel.loadingIdentity,
                        onLoad: { Task { await viewModel.loadIdentityIntoAgent(identity) } },
                        onUnload: { Task { await viewModel.unloadIdentityFromAgent(identity) } }
                    ) {
                        Task { await viewModel.switchIdentity(identity) }
                    }
                    .contextMenu {
                        Button { Clipboard.copy(identity.fingerprint) } label: {
                            Label("Copy fingerprint", systemImage: "doc.on.doc")
                        }
                        if !identity.publicKeyPath.isEmpty {
                            Button {
                                if let pub = try? String(contentsOfFile: identity.publicKeyPath, encoding: .utf8) {
                                    Clipboard.copy(pub.trimmingCharacters(in: .whitespacesAndNewlines))
                                }
                            } label: {
                                Label("Copy public key", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                // Surface any agent keys that aren't on disk (loaded elsewhere),
                // so merging away the SSH section doesn't hide them.
                ForEach(orphanLoadedKeys) { key in
                    IdentityRow(
                        title: key.comment.isEmpty ? key.keyType : key.comment,
                        badge: "AGENT",
                        detail: key.shortFingerprint
                    )
                    .copyable(key.publicKey.isEmpty ? key.fingerprint : key.publicKey,
                              label: key.publicKey.isEmpty ? "Copy fingerprint" : "Copy public key")
                }
            }
        }
    }

    /// Loaded agent keys with no matching on-disk identity (by fingerprint).
    private var orphanLoadedKeys: [SSHKey] {
        let knownFingerprints = Set(viewModel.availableIdentities.map(\.fingerprint))
        return viewModel.sshKeys.filter { !knownFingerprints.contains($0.fingerprint) }
    }

    // MARK: - Git

    private var gitSection: some View {
        SectionCard(icon: "arrow.triangle.branch", title: "Git") {
            if let git = viewModel.gitIdentity, git.isConfigured {
                if let name = git.name {
                    KeyValueRow(label: "user.name", value: name)
                }
                if let email = git.email {
                    KeyValueRow(label: "user.email", value: email)
                        .copyable(email, label: "Copy email")
                }
                if let key = git.signingKey {
                    KeyValueRow(label: "signingkey", value: key, mono: true)
                        .copyable(key, label: "Copy signing key")
                }
            } else {
                EmptyRow(text: "Not configured")
            }

            if !store.gitProfiles.isEmpty {
                Divider().padding(.vertical, Spacing.xxs)
                ProfileTabs(
                    profiles: store.gitProfiles,
                    activeId: viewModel.activeProfile?.id,
                    switchingId: viewModel.switchingProfile,
                    disabled: viewModel.switchingProfile != nil
                ) { profile in
                    Task { await viewModel.switchGitProfile(profile) }
                }
            }
            manageProfilesButton
        }
    }

    private var manageProfilesButton: some View {
        Button(action: { withAnimation { route = .profilesList } }) {
            HStack(spacing: Spacing.xs + 1) {
                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: 11, weight: .semibold))
                Text("Manage profiles…")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.xxs)
        .accessibilityLabel("Manage git profiles")
    }

    // MARK: - GPG

    private var gpgSection: some View {
        SectionCard(
            icon: "lock.shield",
            title: "GPG",
            accessory: {
                if let git = viewModel.gitIdentity {
                    StatusPill(
                        text: git.signCommits ? "signing" : "off",
                        color: git.signCommits ? StatusColor.active : StatusColor.inactive
                    )
                }
            }
        ) {
            if let gpg = viewModel.gpgIdentity, !gpg.secretKeys.isEmpty {
                if let signingKey = gpg.activeSigningKey {
                    IdentityRow(
                        title: signingKey.userId,
                        badge: "ACTIVE",
                        detail: String(signingKey.keyId.suffix(16))
                    )
                    .copyable(signingKey.keyId, label: "Copy key id")
                } else {
                    ForEach(gpg.secretKeys) { key in
                        IdentityRow(
                            title: key.userId,
                            detail: String(key.keyId.suffix(16))
                        )
                        .copyable(key.keyId, label: "Copy key id")
                    }
                }
                createGPGKeyButton
            } else if !viewModel.gpgAvailable {
                EmptyRow(text: "GPG not installed")
                Text("Install with: brew install gnupg")
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyRow(text: "No secret keys")
                createGPGKeyButton
            }
        }
    }

    private var createGPGKeyButton: some View {
        Button(action: { withAnimation { route = .createGPGKey } }) {
            HStack(spacing: Spacing.xs + 1) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text("Create GPG key…")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.xxs)
    }

    // MARK: - Remote

    @ViewBuilder
    private var remoteSection: some View {
        // Show a service's row only when the ACTIVE SSH key is registered on that
        // account (matchedKeyCount >= 1). The remote fetch is already scoped to the
        // active key, so a resolved profile with 0 matches means "this remote isn't for
        // the active key" → hide it. The whole section hides when neither qualifies.
        let github    = viewModel.githubUser.flatMap    { $0.belongsToActiveKey ? $0 : nil }
        let gitlab    = viewModel.gitlabUser.flatMap    { $0.belongsToActiveKey ? $0 : nil }
        let bitbucket = viewModel.bitbucketUser.flatMap { $0.belongsToActiveKey ? $0 : nil }
        if github != nil || gitlab != nil || bitbucket != nil {
            SectionCard(icon: "globe", title: "Remote") {
                if let github    { RemoteRow(user: github) }
                if let gitlab    { RemoteRow(user: gitlab) }
                if let bitbucket { RemoteRow(user: bitbucket) }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 0) {
            Button(action: { Task { await viewModel.refresh() } }) {
                actionLabel("Refresh", systemImage: "arrow.clockwise", spin: viewModel.isLoading)
            }
            .buttonStyle(MenuActionButtonStyle())
            .disabled(viewModel.isLoading)

            settingsButton

            Button(role: .destructive, action: { NSApplication.shared.terminate(nil) }) {
                actionLabel("Quit kssh", systemImage: "power")
            }
            .buttonStyle(MenuActionButtonStyle(role: .destructive))
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm - 2)
    }

    private var settingsButton: some View {
        // As an accessory app we must promote + activate before opening Settings, or the
        // window opens behind everything with no focus. Activate, then trigger Settings
        // via the standard selector (works across macOS 14/15 where SettingsLink alone
        // won't surface for an LSUIElement app).
        Button(action: {
            WindowActivator.activate()
            if #available(macOS 14.0, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }) {
            actionLabel("Settings…", systemImage: "gearshape")
        }
        .buttonStyle(MenuActionButtonStyle())
    }

    private func actionLabel(_ title: String, systemImage: String, spin: Bool = false) -> some View {
        HStack(spacing: Spacing.sm + 2) {
            SpinningIcon(systemImage: systemImage, spinning: spin)
            Text(title)
            Spacer()
        }
    }
}

// MARK: - Route chrome & screens

/// A label row matching `MenuBarView.actionLabel`, usable from the file-private screen
/// structs (which can't call the instance method). No spinner — screens don't need it.
private func actionLabelRow(_ title: String, systemImage: String) -> some View {
    HStack(spacing: Spacing.sm + 2) {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 16)
        Text(title)
        Spacer()
    }
}

/// Back header for detail routes: a chevron button + title, mirroring the main header.
private struct DetailHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text(title)
                .font(.headline)
            Spacer(minLength: Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md - 2)
    }
}

/// Add/edit form for a single git profile. `@State` seeds from `editing` in init, so a
/// new instance per route (distinct `editing`) shows the right values.
private struct ProfileFormScreen: View {
    @ObservedObject var store: SettingsStore
    let editing: GitProfile?
    let onDone: () -> Void

    @State private var name: String
    @State private var email: String

    init(store: SettingsStore, editing: GitProfile?, onDone: @escaping () -> Void) {
        self.store = store
        self.editing = editing
        self.onDone = onDone
        _name = State(initialValue: editing?.name ?? "")
        _email = State(initialValue: editing?.email ?? "")
    }

    private var canSave: Bool { !name.isEmpty && email.contains("@") }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
            Button {
                if let editing {
                    store.updateProfile(GitProfile(id: editing.id, name: name, email: email))
                } else {
                    store.addProfile(GitProfile(name: name, email: email))
                }
                onDone()
            } label: {
                actionLabelRow(editing == nil ? "Add profile" : "Save changes", systemImage: "checkmark.circle")
            }
            .buttonStyle(MenuActionButtonStyle())
            .disabled(!canSave)
        }
    }
}

/// Create-GPG-key form, ported narrow for the popover. Navigates back on success.
private struct CreateGPGScreen: View {
    @ObservedObject var viewModel: StatusViewModel
    let onDone: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var passphrase = ""

    private var canCreate: Bool {
        viewModel.gpgAvailable && !name.isEmpty && email.contains("@") && !viewModel.creatingGPGKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !viewModel.gpgAvailable {
                Label("gpg is not installed", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(StatusColor.warning)
                Text("Install with: brew install gnupg")
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Email", text: $email).textFieldStyle(.roundedBorder)
            SecureField("Passphrase (optional)", text: $passphrase).textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                KeyValueRow(label: "Algorithm", value: "ed25519")
                KeyValueRow(label: "Usage", value: "sign, certify")
                KeyValueRow(label: "Expiry", value: "never")
            }

            if let err = viewModel.gpgCreateError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(StatusColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                if viewModel.creatingGPGKey {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task {
                        let ok = await viewModel.createGPGKey(name: name, email: email, passphrase: passphrase)
                        if ok { onDone() }
                    }
                } label: {
                    actionLabelRow("Create key", systemImage: "plus.circle")
                }
                .buttonStyle(MenuActionButtonStyle())
                .disabled(!canCreate)
            }
        }
    }
}

// MARK: - Section Container

private struct SectionCard<Content: View, Accessory: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        icon: String,
        title: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            HStack(spacing: Spacing.xs + 2) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer(minLength: Spacing.sm)
                accessory()
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                content()
            }
        }
        .padding(Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Rows

/// A single identity entry: a primary title, an optional type/state badge, and a
/// monospace detail (fingerprint, key id). Used by the SSH and GPG sections so every
/// list row shares the same metrics, alignment, and truncation behavior.
private struct IdentityRow: View {
    let title: String
    var badge: String? = nil
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: Spacing.xs + 1) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                Text(detail)
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A dismissible inline error shown below the header. Only rendered when an error
/// exists, so it never affects the layout in the normal (no-error) case.
private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StatusColor.destructive)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(StatusColor.destructive.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(StatusColor.destructive.opacity(0.25), lineWidth: 1)
        )
    }
}

/// A dismissible inline notice for informational (non-error) messages, e.g. a switch
/// that only updated the agent. Neutral accent styling distinguishes it from `ErrorBanner`.
private struct NoticeBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notice")
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}

/// A selectable identity row in the switcher. The radio/check (and tap) switches the
/// *active config* identity; a separate trailing control loads the key into the agent.
/// These are two orthogonal states: active-in-config vs loaded-in-agent.
private struct IdentitySwitchRow: View {
    let identity: SSHIdentity
    let isActive: Bool
    let isSwitching: Bool
    let disabled: Bool
    let isLoaded: Bool
    let isLoading: Bool
    let onLoad: () -> Void
    let onUnload: () -> Void
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Primary switch — wraps only the indicator + labels so the trailing
            // load control stays independently tappable (no button-in-button).
            Button(action: action) {
                HStack(spacing: Spacing.sm) {
                    leadingIndicator
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(identity.displayName)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: Spacing.xs + 1) {
                            Text(identity.keyType.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            Text(identity.name)
                                .font(.caption2)
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: Spacing.xs)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled || isActive)

            trailingLoadControl
        }
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, Spacing.xs + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(StatusColor.active.opacity(isActive ? 0.4 : 0), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if isSwitching {
            ProgressView().controlSize(.small).frame(width: 16)
        } else if isActive {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(StatusColor.active)
                .frame(width: 16)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.5))
                .frame(width: 16)
        }
    }

    /// Loaded-in-agent state: spinner while busy; when loaded, a tappable bolt that
    /// turns into an eject glyph on hover to signal it unloads (ssh-add -d); otherwise a
    /// load button (ssh-add). None of these change the active config identity.
    @ViewBuilder
    private var trailingLoadControl: some View {
        if isLoading {
            ProgressView().controlSize(.small).frame(width: 18)
        } else if isLoaded {
            Button(action: onUnload) {
                Image(systemName: isHovering ? "eject.circle.fill" : "bolt.horizontal.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(isHovering ? StatusColor.warning : StatusColor.active)
            }
            .buttonStyle(.plain)
            .frame(width: 18)
            .disabled(disabled)
            .help("Loaded in agent — click to unload (ssh-add -d)")
            .accessibilityLabel("Unload key from agent")
        } else {
            Button(action: onLoad) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 18)
            .disabled(disabled)
            .help("Load this key into the agent (ssh-add)")
            .accessibilityLabel("Load key into agent")
        }
    }

    private var rowFill: Color {
        if isActive { return StatusColor.active.opacity(0.16) }
        if isHovering && !disabled { return Color.primary.opacity(0.06) }
        return .clear
    }
}

private struct KeyValueRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(mono ? .caption2 : .callout)
                .monospaced(mono)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(mono ? .middle : .tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RemoteRow: View {
    let user: RemoteUser

    var body: some View {
        HStack(spacing: Spacing.sm) {
            avatar
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(user.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let fullName = user.displayNameFull, !fullName.isEmpty {
                    Text(fullName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if user.matchedKeyCount > 1 {
                    Text("\(user.matchedKeyCount) keys linked")
                        .font(.caption2)
                        .foregroundStyle(StatusColor.active)
                } else {
                    Text("active key linked")
                        .font(.caption2)
                        .foregroundStyle(StatusColor.active)
                }
            }
            Spacer(minLength: Spacing.sm)
            Text(user.service.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = user.profileUrl {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// The profile avatar, with a placeholder while loading / on failure so the row
    /// height never shifts (reserved space).
    @ViewBuilder
    private var avatar: some View {
        AsyncImage(url: user.avatarUrl) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Git profiles rendered as a wrapping strip of selectable "tab" chips. The active
/// profile is highlighted; tapping another switches to it. Wraps to multiple lines so
/// up to `SettingsStore.maxProfiles` profiles fit the narrow popover regardless of name length.
private struct ProfileTabs: View {
    let profiles: [GitProfile]
    let activeId: String?
    let switchingId: String?
    let disabled: Bool
    let onSelect: (GitProfile) -> Void

    var body: some View {
        FlowLayout(spacing: Spacing.xs) {
            ForEach(profiles) { profile in
                ProfileTab(
                    profile: profile,
                    isActive: profile.id == activeId,
                    isSwitching: profile.id == switchingId,
                    disabled: disabled
                ) { onSelect(profile) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One profile chip in `ProfileTabs`: name + active/switching indicator, green-highlighted
/// when active (matching the SSH key row's selected styling).
private struct ProfileTab: View {
    let profile: GitProfile
    let isActive: Bool
    let isSwitching: Bool
    let disabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs + 1) {
                if isSwitching {
                    ProgressView().controlSize(.small)
                } else if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(StatusColor.active)
                }
                Text(profile.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled || isActive)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(StatusColor.active.opacity(isActive ? 0.4 : 0), lineWidth: 1))
        .help(profile.email)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    private var fill: Color {
        if isActive { return StatusColor.active.opacity(0.16) }
        if isHovering && !disabled { return Color.primary.opacity(0.08) }
        return Color.primary.opacity(0.04)
    }
}

/// Minimal left-to-right wrapping layout for chips/tabs (macOS 13+ `Layout`).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, x - spacing)
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, x - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Refresh glyph that rotates continuously while `spinning` is true (macOS 14 compatible).
private struct SpinningIcon: View {
    let systemImage: String
    let spinning: Bool
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 16)
            .rotationEffect(.degrees(angle))
            .onChange(of: spinning) { _, isSpinning in
                if isSpinning {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { angle = 0 }
                }
            }
    }
}

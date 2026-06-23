import SwiftUI

/// In-popover navigation. Detail routes replace the whole popover content (their own
/// back header instead of the main header/actions). A `NavigationStack` isn't used: a
/// MenuBarExtra(.window) popover doesn't host nav-bar chrome well, and the depth here is
/// shallow (main → profiles list → profile form; main → create GPG).
private enum Route: Equatable {
    case main
    case profilesList
    case profileForm(editing: GitProfile?)  // nil = add
    case createGPGKey
    case createSSHKey
    case renameKey(identity: SSHIdentity)
    case remoteDetail(user: RemoteUser, service: RemoteService, account: RemoteAccount)
    case addAccount(service: RemoteService?)  // nil = pick service on the screen
    case editAccount(service: RemoteService, account: RemoteAccount)

    /// Where the back button returns to.
    var parent: Route {
        switch self {
        case .main, .profilesList, .createGPGKey, .createSSHKey, .renameKey, .remoteDetail,
            .addAccount, .editAccount:
            return .main
        case .profileForm: return .profilesList
        }
    }

    var title: String {
        switch self {
        case .main: return "kssh"
        case .profilesList: return "Git Profiles"
        case .profileForm(let editing): return editing == nil ? "Add Profile" : "Edit Profile"
        case .createGPGKey: return "Create GPG Key"
        case .createSSHKey: return "Generate SSH Key"
        case .renameKey: return "Rename Key"
        case .remoteDetail(let user, _, _): return user.service.rawValue
        case .addAccount(let service):
            return service.map { "Add \($0.rawValue) Account" } ?? "Add Account"
        case .editAccount: return "Edit Account"
        }
    }
}

/// A service + account pair, identified by the account id, for driving the delete dialog
/// and the flat remote account list.
private struct AccountRef: Identifiable, Equatable {
    let service: RemoteService
    let account: RemoteAccount
    var id: String { account.id }
}

extension RemoteService {
    /// The provider's brand color, used as the lettermark badge fill.
    var brandColor: Color {
        switch self {
        case .github: return Color(red: 0.14, green: 0.16, blue: 0.18)  // GitHub near-black
        case .gitlab: return Color(red: 0.89, green: 0.36, blue: 0.16)  // GitLab orange
        case .bitbucket: return Color(red: 0.16, green: 0.40, blue: 0.86)  // Bitbucket blue
        }
    }

    /// Two-letter monogram for the lettermark badge (SF Symbols has no brand logos, and
    /// hand-drawn vector marks were inaccurate — a brand-colored monogram is honest and clear).
    var monogram: String {
        switch self {
        case .github: return "GH"
        case .gitlab: return "GL"
        case .bitbucket: return "BB"
        }
    }
}

/// A small rounded-square badge with the provider's monogram in its brand color.
private struct ProviderBadge: View {
    let service: RemoteService
    var side: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(service.brandColor)
            .frame(width: side, height: side)
            .overlay(
                Text(service.monogram)
                    .font(.system(size: side * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .accessibilityLabel(service.rawValue)
    }
}

struct MenuBarView: View {
    @ObservedObject var viewModel: StatusViewModel
    @ObservedObject var store: SettingsStore
    @Environment(\.openSettings) private var openSettingsAction
    @State private var route: Route = .main
    /// The identity pending delete confirmation (drives the destructive dialog).
    @State private var keyPendingDelete: SSHIdentity?
    /// The remote account pending delete confirmation (service + account).
    @State private var accountPendingDelete: AccountRef?

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
            case .createSSHKey:
                routeScreen {
                    CreateSSHKeyScreen(viewModel: viewModel) {
                        withAnimation { route = .main }
                    }
                }
                .transition(.move(edge: .trailing))
            case .renameKey(let identity):
                routeScreen {
                    RenameKeyScreen(viewModel: viewModel, identity: identity) {
                        withAnimation { route = .main }
                    }
                }
                .transition(.move(edge: .trailing))
            case .remoteDetail(let user, let service, let account):
                routeScreen {
                    RemoteDetailScreen(
                        viewModel: viewModel, user: user, service: service, account: account)
                }
                .transition(.move(edge: .trailing))
            case .addAccount(let service):
                routeScreen {
                    AddAccountScreen(viewModel: viewModel, service: service) {
                        withAnimation { route = .main }
                    }
                }
                .transition(.move(edge: .trailing))
            case .editAccount(let service, let account):
                routeScreen {
                    EditAccountScreen(viewModel: viewModel, service: service, account: account) {
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
            route = .main  // ephemeral popover: fresh open, discard unsaved form text
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
                // Agent off: the SSH-dependent sections need the agent, so offer a single
                // Enable action in their place — but remote account management is
                // independent of the agent, so keep the Remote section available.
                VStack(spacing: Spacing.sm) {
                    agentOffSection
                    remoteSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            } else {
                // Height is controlled by collapsible sections (Keys open by default; Git
                // is compact; GPG collapsed; Remote collapsible) — no scrolling.
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
                        Button {
                            withAnimation { route = .profileForm(editing: profile) }
                        } label: {
                            Image(systemName: "pencil").font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit profile")
                        Button(role: .destructive) {
                            store.deleteProfile(profile)
                        } label: {
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
                Button {
                    withAnimation { route = .profileForm(editing: nil) }
                } label: {
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

            Button {
                Task { await viewModel.startAgent() }
            } label: {
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
            collapsible: true,
            accessory: {
                if !viewModel.availableIdentities.isEmpty {
                    CountBadge(count: viewModel.availableIdentities.count)
                }
            }
        ) {
            if viewModel.availableIdentities.isEmpty {
                EmptyRow(
                    text: viewModel.agentRunning ? "No keys found in ~/.ssh" : "Agent not running")
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
                    .contextMenu { keyContextMenu(for: identity) }
                }
                // Surface any agent keys that aren't on disk (loaded elsewhere),
                // so merging away the SSH section doesn't hide them.
                ForEach(orphanLoadedKeys) { key in
                    IdentityRow(
                        title: key.comment.isEmpty ? key.keyType : key.comment,
                        badge: "AGENT",
                        detail: key.shortFingerprint
                    )
                    .copyable(
                        key.publicKey.isEmpty ? key.fingerprint : key.publicKey,
                        label: key.publicKey.isEmpty ? "Copy fingerprint" : "Copy public key")
                }
            }
            generateKeyButton
        }
        .confirmationDialog(
            "Delete \(keyPendingDelete?.name ?? "key")?",
            isPresented: Binding(
                get: { keyPendingDelete != nil },
                set: { if !$0 { keyPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to backup", role: .destructive) {
                if let identity = keyPendingDelete {
                    Task { await viewModel.deleteKey(identity) }
                }
                keyPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { keyPendingDelete = nil }
        } message: {
            Text(
                "The key files move to ~/.ssh/.kssh-trash (recoverable). It is also unloaded from the agent."
            )
        }
    }

    private var generateKeyButton: some View {
        Button(action: { withAnimation { route = .createSSHKey } }) {
            HStack(spacing: Spacing.xs + 1) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Generate key…")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.xxs)
        .accessibilityLabel("Generate a new SSH key")
    }

    /// Per-key context menu: copy, rename, add-to-remote, delete. Extracted so the
    /// `keysSection` body stays readable.
    @ViewBuilder
    private func keyContextMenu(for identity: SSHIdentity) -> some View {
        Button {
            Clipboard.copy(identity.fingerprint)
        } label: {
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

        // Add-to-remote: only for the active key (remote scoping is active-key based) and
        // only for services with a resolvable token.
        if identity.id == viewModel.activeIdentity?.id {
            Menu("Add to remote") {
                if viewModel.token(for: .github)?.isEmpty == false {
                    Button {
                        Task { await viewModel.addActiveKeyToRemote(.github) }
                    } label: {
                        Label("GitHub", systemImage: "arrow.up.circle")
                    }
                }
                if viewModel.token(for: .gitlab)?.isEmpty == false {
                    Button {
                        Task { await viewModel.addActiveKeyToRemote(.gitlab) }
                    } label: {
                        Label("GitLab", systemImage: "arrow.up.circle")
                    }
                }
            }
            .disabled(viewModel.addingKeyToRemote != nil)
        }

        Divider()

        Button {
            withAnimation { route = .renameKey(identity: identity) }
        } label: {
            Label("Rename…", systemImage: "pencil")
        }
        .disabled(viewModel.mutatingKey != nil)
        Button(role: .destructive) {
            keyPendingDelete = identity
        } label: {
            Label("Delete…", systemImage: "trash")
        }
        .disabled(viewModel.mutatingKey != nil)
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
            collapsible: true,
            expandedByDefault: false,
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

    /// The Remote section is the management surface for PAT/app-password accounts, modeled
    /// on `keysSection`: every configured account per service is listed (NOT gated by
    /// active-key match), with an active radio, a context menu (test/edit/set-active/delete),
    /// and a per-service add button. The "active key linked" badge + profile tap-through is
    /// an additive indicator on whichever account is active and key-linked.
    @ViewBuilder
    private var remoteSection: some View {
        // Flat list of ALL accounts across services (each row carries a provider glyph), so
        // there are no per-service headers and a single "Add account…" button. A fresh
        // install shows just the empty hint + the add button.
        let all: [AccountRef] = RemoteService.allCases.flatMap { service in
            viewModel.store.accounts(for: service).map { AccountRef(service: service, account: $0) }
        }
        SectionCard(
            icon: "globe",
            title: "Remote",
            collapsible: true,
            accessory: { if !all.isEmpty { CountBadge(count: all.count) } }
        ) {
            if all.isEmpty {
                EmptyRow(text: "No accounts yet.")
            }
            ForEach(all) { ref in
                AccountSwitchRow(
                    account: ref.account,
                    service: ref.service,
                    isActive: viewModel.isActiveAccount(ref.account, for: ref.service),
                    isSwitching: viewModel.switchingAccount == ref.account.id,
                    isTesting: viewModel.testingAccount == ref.account.id,
                    disabled: viewModel.switchingAccount != nil || viewModel.mutatingAccount != nil,
                    testResult: viewModel.accountTestResult[ref.account.id],
                    user: viewModel.accountUser(ref.account),
                    onSwitch: {
                        Task { await viewModel.switchAccount(ref.account, for: ref.service) }
                    },
                    onOpen: { user in
                        withAnimation {
                            route = .remoteDetail(
                                user: user, service: ref.service, account: ref.account)
                        }
                    }
                )
                .contextMenu { accountContextMenu(ref.account, service: ref.service) }
            }
            addAccountButton
        }
        .confirmationDialog(
            "Remove \(accountPendingDelete?.account.displayLabel ?? "account")?",
            isPresented: Binding(
                get: { accountPendingDelete != nil },
                set: { if !$0 { accountPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let ref = accountPendingDelete {
                    Task { await viewModel.deleteAccount(ref.account, for: ref.service) }
                }
                accountPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { accountPendingDelete = nil }
        } message: {
            Text("The token is deleted from the Keychain. This doesn’t revoke it on the provider.")
        }
    }

    /// Single add button → the add screen, which starts with a service picker.
    private var addAccountButton: some View {
        Button(action: { withAnimation { route = .addAccount(service: nil) } }) {
            HStack(spacing: Spacing.xs + 1) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add account…")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.xxs)
        .accessibilityLabel("Add a remote account")
    }

    /// Per-account context menu: test, edit, set-active, delete.
    @ViewBuilder
    private func accountContextMenu(_ account: RemoteAccount, service: RemoteService) -> some View {
        Button {
            Task { await viewModel.testAccount(account, for: service) }
        } label: {
            Label("Test connection", systemImage: "checkmark.shield")
        }
        .disabled(viewModel.testingAccount != nil)
        Button {
            withAnimation { route = .editAccount(service: service, account: account) }
        } label: {
            Label("Edit…", systemImage: "pencil")
        }
        .disabled(viewModel.mutatingAccount != nil)
        if !viewModel.isActiveAccount(account, for: service) {
            Button {
                Task { await viewModel.switchAccount(account, for: service) }
            } label: {
                Label("Set active", systemImage: "largecircle.fill.circle")
            }
            .disabled(viewModel.switchingAccount != nil)
        }
        Divider()
        Button(role: .destructive) {
            accountPendingDelete = AccountRef(service: service, account: account)
        } label: {
            Label("Remove…", systemImage: "trash")
        }
        .disabled(viewModel.mutatingAccount != nil)
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
        // Opening the Settings scene from a MenuBarExtra accessory app is famously fragile:
        // both the private `showSettingsWindow:` selector AND SwiftUI's `openSettings`/
        // `SettingsLink` silently do nothing on macOS 26 (Tahoe), because there's no live
        // SwiftUI render tree for the Settings scene to initialize against while the app is
        // .accessory. The reliable fix is ORDER: promote to .regular and activate FIRST
        // (which establishes the AppKit/SwiftUI context), then trigger Settings on the next
        // runloop tick. `SettingsLink` alone, tried before this, opened nothing.
        Button(action: openSettings) {
            actionLabel("Settings…", systemImage: "gearshape")
        }
        .buttonStyle(MenuActionButtonStyle())
    }

    private func openSettings() {
        WindowActivator.activate()
        // Defer so the activation-policy change has taken effect before we ask to surface
        // the Settings window; firing synchronously races the policy switch. Once the app
        // is .regular and active, the supported `openSettings` environment action has the
        // SwiftUI render-tree context it needs to actually open the scene.
        DispatchQueue.main.async {
            openSettingsAction()
        }
    }

    private func actionLabel(_ title: String, systemImage: String, spin: Bool = false) -> some View
    {
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

/// Centered icon+title for a primary CTA, used with `PrimaryActionButtonStyle` on form
/// screens (no leading `Spacer`, so the label sits centered on the filled button).
private func primaryActionLabel(_ title: String, systemImage: String) -> some View {
    HStack(spacing: Spacing.xs + 2) {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
        Text(title)
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
                primaryActionLabel(
                    editing == nil ? "Add profile" : "Save changes", systemImage: "checkmark.circle"
                )
            }
            .buttonStyle(PrimaryActionButtonStyle())
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
                        let ok = await viewModel.createGPGKey(
                            name: name, email: email, passphrase: passphrase)
                        if ok { onDone() }
                    }
                } label: {
                    primaryActionLabel("Create key", systemImage: "plus.circle")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canCreate)
            }
        }
    }
}

/// Generate-SSH-key form (create-only: the new key is not loaded or written to config).
/// Mirrors `CreateGPGScreen`. Navigates back on success.
private struct CreateSSHKeyScreen: View {
    @ObservedObject var viewModel: StatusViewModel
    let onDone: () -> Void

    @State private var keyType: SSHIdentityService.KeyType = .ed25519
    @State private var comment: String
    @State private var passphrase = ""

    init(viewModel: StatusViewModel, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDone = onDone
        // Seed the comment with the configured git email — the conventional key comment.
        _comment = State(initialValue: viewModel.gitIdentity?.email ?? "")
    }

    private var canCreate: Bool { !viewModel.generatingKey }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("Type", selection: $keyType) {
                Text("Ed25519").tag(SSHIdentityService.KeyType.ed25519)
                Text("RSA (4096)").tag(SSHIdentityService.KeyType.rsa)
            }
            .pickerStyle(.segmented)

            TextField("Comment (e.g. you@host)", text: $comment).textFieldStyle(.roundedBorder)
            SecureField("Passphrase (optional)", text: $passphrase).textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                KeyValueRow(label: "Saved to", value: "~/.ssh/id_\(keyType.rawValue)")
                KeyValueRow(label: "After create", value: "not loaded — load it manually")
            }

            if let err = viewModel.keygenError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(StatusColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                if viewModel.generatingKey {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task {
                        let ok = await viewModel.generateSSHKey(
                            type: keyType, comment: comment, passphrase: passphrase)
                        if ok { onDone() }
                    }
                } label: {
                    primaryActionLabel("Generate key", systemImage: "plus.circle")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canCreate)
            }
        }
    }
}

/// Rename a key's files in ~/.ssh. One-field form like `ProfileFormScreen`; navigates back
/// on success. Failures (invalid name, name taken, key referenced in config) show inline.
private struct RenameKeyScreen: View {
    @ObservedObject var viewModel: StatusViewModel
    let identity: SSHIdentity
    let onDone: () -> Void

    @State private var newName: String

    init(viewModel: StatusViewModel, identity: SSHIdentity, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.identity = identity
        self.onDone = onDone
        _newName = State(initialValue: identity.name)
    }

    private var canSave: Bool {
        SSHIdentityService.isValidKeyName(newName)
            && newName != identity.name
            && viewModel.mutatingKey == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KeyValueRow(label: "Current", value: identity.name)
            TextField("New name", text: $newName).textFieldStyle(.roundedBorder)
            Text("Renames both the private key and its .pub in ~/.ssh.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let err = viewModel.keyActionError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(StatusColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                if viewModel.mutatingKey == identity.id {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task {
                        let ok = await viewModel.renameKey(identity, to: newName)
                        if ok { onDone() }
                    }
                } label: {
                    primaryActionLabel("Rename", systemImage: "checkmark.circle")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canSave)
            }
        }
    }
}

/// Add a remote account in the popover. If no service is preselected, a compact segmented
/// picker chooses one first. Fields branch on service: GitHub/GitLab take a label + PAT
/// (GitLab also an instance); Bitbucket takes label + username + app password.
private struct AddAccountScreen: View {
    @ObservedObject var viewModel: StatusViewModel
    let onDone: () -> Void

    @State private var service: RemoteService
    @State private var label = ""
    @State private var instance = "gitlab.com"
    @State private var secret = ""
    @State private var username = ""

    init(viewModel: StatusViewModel, service: RemoteService?, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDone = onDone
        _service = State(initialValue: service ?? .github)
    }

    private var canAdd: Bool {
        guard !label.isEmpty, viewModel.addingAccount == nil else { return false }
        if service == .bitbucket { return !username.isEmpty && !secret.isEmpty }
        return !secret.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("Provider", selection: $service) {
                ForEach(RemoteService.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Label (e.g. Work)", text: $label).textFieldStyle(.roundedBorder)

            if service == .gitlab {
                TextField("Instance", text: $instance).textFieldStyle(.roundedBorder)
            }
            if service == .bitbucket {
                TextField("Username", text: $username).textFieldStyle(.roundedBorder)
                SecureField("App Password", text: $secret).textFieldStyle(.roundedBorder)
            } else {
                SecureField("Personal Access Token", text: $secret).textFieldStyle(.roundedBorder)
            }

            Text(scopesHint).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let err = viewModel.accountActionError {
                Text(err).font(.caption).foregroundStyle(StatusColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                if viewModel.addingAccount == service { ProgressView().controlSize(.small) }
                Button {
                    Task {
                        let ok: Bool
                        if service == .bitbucket {
                            ok = await viewModel.addBitbucketAccount(
                                label: label, username: username, appPassword: secret)
                        } else {
                            ok = await viewModel.addAccount(
                                label: label, secret: secret,
                                instance: service == .gitlab ? instance : nil, for: service)
                        }
                        if ok { onDone() }
                    }
                } label: {
                    primaryActionLabel("Add account", systemImage: "plus.circle")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canAdd)
            }
        }
    }

    private var scopesHint: String {
        switch service {
        case .github:
            return
                "github.com/settings/tokens — read:public_key, read:user (and read:user for the graph)."
        case .gitlab: return "\(instance)/-/user_settings/personal_access_tokens — read_api."
        case .bitbucket: return "bitbucket.org App Password — Account: Read, SSH keys: Read."
        }
    }
}

/// Edit a remote account: rename + replace the secret (and GitLab instance). Secrets load
/// from the Keychain on appear and are written only on Save. Ports the Settings `AccountEditor`.
private struct EditAccountScreen: View {
    @ObservedObject var viewModel: StatusViewModel
    let service: RemoteService
    let account: RemoteAccount
    let onDone: () -> Void

    @State private var label = ""
    @State private var instance = ""
    @State private var secret = ""
    @State private var username = ""

    private var canSave: Bool { !label.isEmpty && viewModel.mutatingAccount == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TextField("Label", text: $label).textFieldStyle(.roundedBorder)

            if service == .gitlab {
                TextField("Instance", text: $instance).textFieldStyle(.roundedBorder)
            }
            if service == .bitbucket {
                TextField("Username", text: $username).textFieldStyle(.roundedBorder)
                SecureField("App Password", text: $secret).textFieldStyle(.roundedBorder)
            } else {
                SecureField("Personal Access Token", text: $secret).textFieldStyle(.roundedBorder)
            }

            Text("Leave the token unchanged to keep the stored one.")
                .font(.caption2).foregroundStyle(.secondary)

            if let err = viewModel.accountActionError {
                Text(err).font(.caption).foregroundStyle(StatusColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                if viewModel.mutatingAccount == account.id { ProgressView().controlSize(.small) }
                Button {
                    Task {
                        let ok = await viewModel.saveAccount(
                            account, for: service, label: label,
                            secret: service == .bitbucket ? nil : secret,
                            instance: service == .gitlab ? instance : nil,
                            username: service == .bitbucket ? username : nil,
                            appPassword: service == .bitbucket ? secret : nil
                        )
                        if ok { onDone() }
                    }
                } label: {
                    primaryActionLabel("Save", systemImage: "checkmark.circle")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canSave)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        label = account.label
        instance = account.instance ?? ""
        if service == .bitbucket {
            let creds = viewModel.store.bitbucketCredentials(id: account.id)
            username = creds?.username ?? ""
            secret = creds?.appPassword ?? ""
        } else {
            secret = viewModel.store.secret(for: service, id: account.id) ?? ""
        }
    }
}

/// Remote profile detail screen: avatar + name/username, follower/following/repo counts,
/// bio, location/company/joined, and an "Open profile" button. The extended detail is
/// fetched lazily on appear (not during the per-refresh resolution); counts/fields the
/// provider doesn't return are simply omitted. The username/avatar come from the already-
/// resolved `RemoteUser`, so the header renders instantly while the rest loads.
private struct RemoteDetailScreen: View {
    @ObservedObject var viewModel: StatusViewModel
    let user: RemoteUser
    let service: RemoteService
    let account: RemoteAccount

    @State private var detail: RemoteProfileDetail?
    @State private var loading = true
    /// GitHub contribution calendar, loaded independently of the profile so a slow/failed
    /// graph never delays the rest of the screen. Nil = not loaded / unavailable.
    @State private var graph: ContributionGraph?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            if loading {
                HStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Loading profile…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.md)
            } else if let detail {
                stats(detail)

                if let bio = detail.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Only show the graph when there's actual activity — an all-grey grid for
                // an account with no contributions reads as broken.
                if let graph, graph.totalContributions > 0 {
                    ContributionGraphView(graph: graph)
                }

                let hasFields =
                    (detail.company?.isEmpty == false)
                    || (detail.location?.isEmpty == false)
                if hasFields {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        fields(detail)
                    }
                    .padding(Spacing.sm + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            } else {
                Text("Couldn’t load extended profile.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.md)
            }

            Spacer(minLength: 0)

            if let url = user.profileUrl {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    primaryActionLabel(
                        "Open on \(service.rawValue)", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .task(id: account.id) {
            loading = true
            detail = await viewModel.remoteProfileDetail(for: service, account: account)
            loading = false
        }
        .task(id: account.id) {
            // Independent of the profile load: GitHub-only, fails silently to no graph.
            graph = await viewModel.contributionGraph(for: service, account: account)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            avatar

            VStack(alignment: .leading, spacing: 1) {
                if let full = detail?.fullName ?? user.displayNameFull, !full.isEmpty {
                    Text(full).font(.headline).lineLimit(1)
                }
                Text(user.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// Real avatar; falls back to the provider's brand monogram badge (matching the account
    /// rows) rather than a generic grey person icon.
    private var avatar: some View {
        AsyncImage(url: user.avatarUrl) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                ProviderBadge(service: service, side: 52)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    /// The follower / following / repos counts, each shown only when the provider returned
    /// it (GitLab/Bitbucket return none, so this row collapses for them).
    @ViewBuilder
    private func stats(_ d: RemoteProfileDetail) -> some View {
        let items: [(String, Int)] = [
            ("Repos", d.publicRepos),
            ("Followers", d.followers),
            ("Following", d.following),
        ].compactMap { label, value in value.map { (label, $0) } }

        if !items.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Divider().frame(height: 24)
                    }
                    VStack(spacing: 1) {
                        Text("\(item.1)")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Text(item.0)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    @ViewBuilder
    private func fields(_ d: RemoteProfileDetail) -> some View {
        if let company = d.company, !company.isEmpty {
            KeyValueRow(label: "Company", value: company)
        }
        if let location = d.location, !location.isEmpty {
            KeyValueRow(label: "Location", value: location)
        }
    }

}

/// GitHub-style contribution heatmap: one column per week, seven rows (Sun→Sat), cells
/// colored by 0–4 intensity. Sized to fit the fixed 300pt popover (already trimmed to ~13
/// weeks by the caller), so cells stay legible without horizontal scroll.
private struct ContributionGraphView: View {
    let graph: ContributionGraph

    private let gap: CGFloat = 3
    /// Comfortable, legible cell size; the number of weeks shown is derived to fit the width
    /// at this size (rather than shrinking cells to cram in the whole year).
    private let cell: CGFloat = 10

    var body: some View {
        // Pick the trailing N weeks that fit the available width at a fixed cell size.
        GeometryReader { geo in
            let fit = max(1, Int((geo.size.width + gap) / (cell + gap)))
            let weeks = Array(graph.weeks.suffix(fit))
            let shown = weeks.flatMap { $0 }.reduce(0) { $0 + $1.count }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(shown) contributions in the last \(fit) weeks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(color(for: day.level))
                                    .frame(width: cell, height: cell)
                                    .help(
                                        "\(day.count) on \(Self.dayFormatter.string(from: day.date))"
                                    )
                            }
                        }
                    }
                }
            }
        }
        .frame(height: gridHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Reserved height: caption line + the 7-row grid at the fixed cell size.
    private var gridHeight: CGFloat {
        let captionLine: CGFloat = 14 + Spacing.xs
        return captionLine + cell * 7 + gap * 6
    }

    /// Maps a 0–4 level to a green of increasing opacity (the `StatusColor.active` hue),
    /// with a neutral base for empty days — adapts to light/dark like the rest of the app.
    private func color(for level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.08)
        case 1: return StatusColor.active.opacity(0.3)
        case 2: return StatusColor.active.opacity(0.5)
        case 3: return StatusColor.active.opacity(0.7)
        default: return StatusColor.active
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

// MARK: - Section Container

private struct SectionCard<Content: View, Accessory: View>: View {
    let icon: String
    let title: String
    /// When true, the header is a toggle and the body collapses; open/closed persists in
    /// AppStorage keyed by title so it survives popover reopen. Default off so existing
    /// always-open sections are unchanged.
    let collapsible: Bool
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    @AppStorage private var isExpanded: Bool

    init(
        icon: String,
        title: String,
        collapsible: Bool = false,
        expandedByDefault: Bool = true,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.collapsible = collapsible
        self.accessory = accessory
        self.content = content
        _isExpanded = AppStorage(wrappedValue: expandedByDefault, "section.expanded.\(title)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            headerRow

            if !collapsible || isExpanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    content()
                }
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

    @ViewBuilder
    private var headerRow: some View {
        let header = HStack(spacing: Spacing.xs + 2) {
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
            if collapsible {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .contentShape(Rectangle())

        if collapsible {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) section, \(isExpanded ? "expanded" : "collapsed")")
        } else {
            header
        }
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
    /// Tapping the row opens the in-popover detail screen.
    let onTap: () -> Void

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
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
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

/// A remote-account row in the manageable Remote section. Layout (leading→trailing):
/// provider icon · avatar · username + label tag · status · active radio. Tapping the row
/// (when a profile resolved) opens its detail screen; the radio switches the active account.
private struct AccountSwitchRow: View {
    let account: RemoteAccount
    let service: RemoteService
    let isActive: Bool
    let isSwitching: Bool
    let isTesting: Bool
    let disabled: Bool
    let testResult: StatusViewModel.AccountTestState?
    /// The resolved profile for THIS account (avatar/username). Nil while loading or if the
    /// token didn't resolve — the row then falls back to the label only.
    let user: RemoteUser?
    let onSwitch: () -> Void
    let onOpen: (RemoteUser) -> Void

    @State private var isHovering = false

    /// Primary text is the resolved username; the label shows as a secondary tag.
    private var primaryText: String { user?.username ?? account.displayLabel }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Provider monogram badge.
            ProviderBadge(service: service, side: 18)

            // Avatar.
            avatar

            // Username + label tag.
            HStack(spacing: Spacing.xs + 1) {
                Text(primaryText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                LabelTag(text: account.displayLabel)
            }

            trailingStatus

            Spacer(minLength: Spacing.xs)

            // Active radio (the only control that doesn't open detail).
            Button(action: onSwitch) { radio }
                .buttonStyle(.plain)
                .disabled(disabled || isActive)
        }
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, Spacing.xs + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(rowFill)
        )
        .contentShape(Rectangle())
        .onTapGesture { if let user { onOpen(user) } }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    /// Transient test feedback (✓/✗) or spinner, inline after the name.
    @ViewBuilder
    private var trailingStatus: some View {
        if isTesting {
            ProgressView().controlSize(.small)
        } else if let testResult {
            switch testResult {
            case .valid:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(StatusColor.active)
                    .help("Connection valid")
            case .invalid:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(StatusColor.destructive)
                    .help("Token invalid")
            }
        }
    }

    @ViewBuilder
    private var radio: some View {
        if isSwitching {
            ProgressView().controlSize(.small).frame(width: 16)
        } else if isActive {
            Image(systemName: "largecircle.fill.circle")
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

    private var avatar: some View {
        AsyncImage(url: user?.avatarUrl) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
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

    private var rowFill: Color {
        // No active-state tint — the filled radio alone marks the active account.
        if isHovering && !disabled { return Color.primary.opacity(0.06) }
        return .clear
    }
}

/// A small pill tag for the account's user-given label (e.g. "Work").
private struct LabelTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.14)))
            .lineLimit(1)
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
        .overlay(
            Capsule().strokeBorder(StatusColor.active.opacity(isActive ? 0.4 : 0), lineWidth: 1)
        )
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

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
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

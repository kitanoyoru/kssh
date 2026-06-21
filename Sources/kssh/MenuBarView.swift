import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: StatusViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.horizontal, Spacing.md)

            if let error = viewModel.error {
                ErrorBanner(message: error) { viewModel.error = nil }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
            }

            if viewModel.isLoading && viewModel.sshKeys.isEmpty {
                loadingView
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
        .frame(width: 300)
        .onAppear { viewModel.startAutoRefresh() }
        .onDisappear { viewModel.stopAutoRefresh() }
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
        }
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
        Button(action: { openWindow(id: "create-gpg-key") }) {
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
        // Only render a service's row when its token resolved to a profile; hide the
        // whole section when neither did (no tokens configured / none valid).
        if viewModel.githubUser != nil || viewModel.gitlabUser != nil {
            SectionCard(icon: "globe", title: "Remote") {
                if let github = viewModel.githubUser {
                    RemoteRow(user: github)
                }
                if let gitlab = viewModel.gitlabUser {
                    RemoteRow(user: gitlab)
                }
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

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                actionLabel("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(MenuActionButtonStyle())
        } else {
            Button(action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                actionLabel("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(MenuActionButtonStyle())
        }
    }

    private func actionLabel(_ title: String, systemImage: String, spin: Bool = false) -> some View {
        HStack(spacing: Spacing.sm + 2) {
            SpinningIcon(systemImage: systemImage, spinning: spin)
            Text(title)
            Spacer()
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
        if isActive { return StatusColor.active.opacity(0.10) }
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
                Text(matchedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.sm)
            Text(user.service.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var matchedText: String {
        switch user.matchedKeyCount {
        case 0: return "no keys matched"
        case 1: return "1 key matched"
        default: return "\(user.matchedKeyCount) keys matched"
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

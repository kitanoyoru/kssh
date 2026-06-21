import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: StatusViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.horizontal, Spacing.md)

            if viewModel.isLoading && viewModel.sshKeys.isEmpty {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: Spacing.sm) {
                        sshSection
                        gitSection
                        gpgSection
                        remoteSection
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
                .frame(maxHeight: 460)
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
                Text("Identity status")
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

    // MARK: - SSH

    private var sshSection: some View {
        SectionCard(
            icon: "key.horizontal",
            title: "SSH Agent",
            accessory: {
                StatusPill(
                    text: viewModel.agentRunning ? "running" : "stopped",
                    color: viewModel.agentRunning ? StatusColor.active : StatusColor.inactive
                )
            }
        ) {
            if viewModel.sshKeys.isEmpty {
                EmptyRow(text: viewModel.agentRunning ? "No identities loaded" : "Agent not running")
            } else {
                ForEach(viewModel.sshKeys) { key in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(key.comment.isEmpty ? key.keyType : key.comment)
                            .font(.callout)
                            .lineLimit(1)
                        HStack(spacing: Spacing.xs + 1) {
                            Text(key.keyType.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.secondary.opacity(0.12))
                                )
                            Text(key.shortFingerprint)
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
        }
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
                }
                if let key = git.signingKey {
                    KeyValueRow(label: "signingkey", value: key, mono: true)
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
                    KeyValueRow(label: "Signing key", value: String(signingKey.keyId.suffix(16)), mono: true)
                    Text(signingKey.userId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(gpg.secretKeys) { key in
                        HStack {
                            Text(key.userId)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: Spacing.sm)
                            Text(String(key.keyId.suffix(16)))
                                .font(.caption2)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                EmptyRow(text: viewModel.gpgIdentity == nil ? "GPG not available" : "No secret keys")
            }
        }
    }

    // MARK: - Remote

    private var remoteSection: some View {
        SectionCard(icon: "globe", title: "Remote") {
            if viewModel.sshKeys.isEmpty {
                EmptyRow(text: "Load SSH keys to check")
            } else {
                RemoteRow(name: "GitHub", user: viewModel.githubUser)
                RemoteRow(name: "GitLab", user: viewModel.gitlabUser)
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

            VStack(alignment: .leading, spacing: Spacing.xs + 1) {
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

private struct KeyValueRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .font(mono ? .caption2 : .callout)
                .monospaced(mono)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(mono ? .middle : .tail)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RemoteRow: View {
    let name: String
    let user: RemoteUser?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            StatusDot(color: user != nil ? StatusColor.active : StatusColor.inactive)
            Text(name)
                .font(.callout)
            Spacer(minLength: Spacing.sm)
            Text(user?.displayName ?? "not linked")
                .font(.caption)
                .foregroundStyle(user != nil ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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

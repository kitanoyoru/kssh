import SwiftUI

// MARK: - Design Tokens

/// Consistent 4/8pt spacing rhythm used across the menu.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

/// Corner radii for the elevation scale (rows < cards < panel).
enum Radius {
    static let row: CGFloat = 6
    static let card: CGFloat = 10
    static let pill: CGFloat = 100
}

/// Semantic status colors. These adapt automatically to light/dark mode.
enum StatusColor {
    static let active = Color.green
    static let inactive = Color.secondary
    static let warning = Color.orange
    static let destructive = Color.red
}

// MARK: - Reusable Atoms

/// A small colored indicator dot with a subtle matching halo.
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: size * 2.1, height: size * 2.1)
            )
            .accessibilityHidden(true)
    }
}

/// A compact capsule used for state ("running" / "stopped", "linked", etc.).
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xs + 1) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}

/// A small monochrome count pill (e.g. number of loaded SSH keys) shown as a
/// section accessory. Distinct from `StatusPill`, which carries semantic color.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.sm - 2)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
            )
            .accessibilityLabel("\(count) keys")
    }
}

// MARK: - Button Styles

/// A full-width action row with smooth hover highlight and press feedback.
struct MenuActionButtonStyle: ButtonStyle {
    var role: ButtonRole? = nil

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, role: role)
    }

    private struct Row: View {
        let configuration: Configuration
        let role: ButtonRole?
        @State private var isHovering = false

        private var tint: Color {
            role == .destructive ? StatusColor.destructive : Color.primary
        }

        var body: some View {
            configuration.label
                .font(.callout)
                .foregroundStyle(role == .destructive ? StatusColor.destructive : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm - 1)
                .background(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.16 : (isHovering ? 0.08 : 0)))
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                }
        }
    }
}

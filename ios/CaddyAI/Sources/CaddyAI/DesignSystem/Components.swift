import SwiftUI
import UIKit

// MARK: - Cards

/// Standard elevated card. Use everywhere for grouped content.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.l
    var content: () -> Content

    init(padding: CGFloat = Theme.Spacing.l, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .themeShadow()
    }
}

/// Hero card with the brand gradient — used on Home and confirmations.
struct HeroCard<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Palette.heroGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(.white)
            .themeShadow(Theme.Shadow.hero)
    }
}

// MARK: - Buttons

/// Full-width pill, brand-primary, haptic on tap.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.primary
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Type.bodyStrong)
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, Theme.Spacing.m + 2)
            .padding(.horizontal, Theme.Spacing.xl)
            .background(
                Capsule().fill(tint)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary tonal button — same shape, muted surface.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Type.bodyStrong)
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, Theme.Spacing.m + 2)
            .padding(.horizontal, Theme.Spacing.xl)
            .background(
                Capsule().fill(Theme.Palette.surfaceMuted)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryPill: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primaryPill(tint: Color, fullWidth: Bool = true) -> PrimaryButtonStyle {
        PrimaryButtonStyle(tint: tint, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondaryPill: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondaryPill(fullWidth: Bool = true) -> SecondaryButtonStyle {
        SecondaryButtonStyle(fullWidth: fullWidth)
    }
}

// MARK: - Metric tile

/// A large number + small label — used on Home and Swing review.
struct MetricTile: View {
    let label: String
    let value: String
    var unit: String?
    var trend: Trend?
    var icon: String?

    enum Trend {
        case up, down, neutral
        var symbol: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "equal"
            }
        }
        var color: Color {
            switch self {
            case .up: return Theme.Palette.success
            case .down: return Theme.Palette.danger
            case .neutral: return Theme.Palette.textSecondary
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.primary)
                }
                Text(label.uppercased())
                    .font(Theme.Type.micro)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .tracking(0.6)
                Spacer()
                if let trend {
                    Image(systemName: trend.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(trend.color)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Type.metricSmall)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let unit {
                    Text(unit)
                        .font(Theme.Type.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .themeShadow()
    }
}

// MARK: - Chips / pills

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.Palette.primary

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
            }
            Text(text).font(Theme.Type.caption)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
    }
}

struct StatusPill: View {
    enum Level { case ok, warn, err, neutral }
    let text: String
    let level: Level

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(Theme.Type.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private var color: Color {
        switch level {
        case .ok: return Theme.Palette.success
        case .warn: return Theme.Palette.warning
        case .err: return Theme.Palette.danger
        case .neutral: return Theme.Palette.textSecondary
        }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var action: (label: String, handler: () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Type.title2).foregroundStyle(Theme.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
            if let action {
                Button(action.label, action: action.handler)
                    .font(Theme.Type.caption)
                    .foregroundStyle(Theme.Palette.primary)
            }
        }
    }
}

// MARK: - Action row

/// Large tappable row used on Home for the key flows.
struct ActionRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var tint: Color = Theme.Palette.primary

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Type.bodyStrong).foregroundStyle(Theme.Palette.textPrimary)
                Text(subtitle).font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(Theme.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .themeShadow()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

// MARK: - Labeled row (Bag, Settings)

struct LabeledRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Palette.primary.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.primary)
                }
                .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Type.body).foregroundStyle(Theme.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }
}

// MARK: - Divider

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Palette.divider)
            .frame(height: 0.5)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Screen scaffold

/// Applies the app's standard background + safe-area padding for
/// scrolling feature screens. Use instead of a bare ScrollView so every
/// screen matches.
struct Screen<Content: View>: View {
    var title: String?
    var content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let title {
                        Text(title).font(Theme.Type.title)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .padding(.top, Theme.Spacing.s)
                    }
                    content()
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
    }
}

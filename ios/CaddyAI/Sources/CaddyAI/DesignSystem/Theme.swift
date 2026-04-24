import SwiftUI

// MARK: - Design tokens
//
// A single source of truth for colors, typography, spacing, and radii.
// Every feature view consumes these so the app has one cohesive look.
// Tokens are defined against both light and dark modes so the system
// picks the right value automatically.

enum Theme {
    // MARK: Colors

    enum Palette {
        /// Brand primary — deep fairway green. Used for key CTAs and hero
        /// surfaces. Light mode = richer, dark mode = slightly desaturated
        /// so it doesn't vibrate against OLED blacks.
        static let primary = Color("BrandPrimary", bundle: nil, fallback: .init(
            light: Color(red: 0.10, green: 0.36, blue: 0.26),
            dark:  Color(red: 0.29, green: 0.72, blue: 0.52)
        ))

        /// Accent — warm gold, reserved for highlights and trophy states.
        static let accent = Color.fallback(
            light: Color(red: 0.82, green: 0.62, blue: 0.16),
            dark:  Color(red: 0.98, green: 0.78, blue: 0.33)
        )

        /// App background.
        static let background = Color.fallback(
            light: Color(red: 0.97, green: 0.97, blue: 0.96),
            dark:  Color(red: 0.06, green: 0.07, blue: 0.08)
        )

        /// Elevated surface (cards, sheets).
        static let surface = Color.fallback(
            light: Color.white,
            dark:  Color(red: 0.11, green: 0.13, blue: 0.14)
        )

        /// Recessed surface (inputs, chips).
        static let surfaceMuted = Color.fallback(
            light: Color(red: 0.93, green: 0.94, blue: 0.93),
            dark:  Color(red: 0.16, green: 0.18, blue: 0.19)
        )

        /// Primary text.
        static let textPrimary = Color.fallback(
            light: Color(red: 0.08, green: 0.10, blue: 0.11),
            dark:  Color(red: 0.96, green: 0.97, blue: 0.97)
        )

        /// Secondary text — captions, supporting copy.
        static let textSecondary = Color.fallback(
            light: Color(red: 0.40, green: 0.43, blue: 0.44),
            dark:  Color(red: 0.67, green: 0.70, blue: 0.71)
        )

        /// Tertiary text — placeholders, dividers.
        static let textTertiary = Color.fallback(
            light: Color(red: 0.62, green: 0.64, blue: 0.65),
            dark:  Color(red: 0.44, green: 0.47, blue: 0.48)
        )

        /// Divider / hairline.
        static let divider = Color.fallback(
            light: Color(red: 0.89, green: 0.90, blue: 0.90),
            dark:  Color(red: 0.22, green: 0.24, blue: 0.25)
        )

        // Semantic
        static let success = Color.fallback(
            light: Color(red: 0.13, green: 0.53, blue: 0.34),
            dark:  Color(red: 0.31, green: 0.78, blue: 0.56)
        )
        static let warning = Color.fallback(
            light: Color(red: 0.84, green: 0.55, blue: 0.10),
            dark:  Color(red: 0.99, green: 0.74, blue: 0.32)
        )
        static let danger = Color.fallback(
            light: Color(red: 0.76, green: 0.22, blue: 0.22),
            dark:  Color(red: 0.96, green: 0.42, blue: 0.42)
        )

        /// Hero gradient for the landing surfaces.
        static var heroGradient: LinearGradient {
            LinearGradient(
                colors: [
                    Color.fallback(
                        light: Color(red: 0.07, green: 0.28, blue: 0.20),
                        dark:  Color(red: 0.06, green: 0.17, blue: 0.12)
                    ),
                    Color.fallback(
                        light: Color(red: 0.13, green: 0.42, blue: 0.30),
                        dark:  Color(red: 0.11, green: 0.28, blue: 0.20)
                    ),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: Radius

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
        static let pill: CGFloat = 999
    }

    // MARK: Typography

    enum Type {
        static let hero = Font.system(size: 44, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        static let bodyStrong = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
        static let micro = Font.system(size: 11, weight: .semibold, design: .rounded)
        static let metric = Font.system(size: 40, weight: .bold, design: .rounded).monospacedDigit()
        static let metricSmall = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    }

    // MARK: Shadows

    enum Shadow {
        static let card = ShadowSpec(color: .black.opacity(0.08), radius: 14, y: 6)
        static let hero = ShadowSpec(color: .black.opacity(0.22), radius: 24, y: 10)
    }

    struct ShadowSpec {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }
}

// MARK: - Color helpers
//
// SwiftUI doesn't have a built-in "different color per appearance" literal
// without an asset catalog. We provide a small shim so tokens above can
// specify both modes inline and resolve via `UITraitCollection`.

extension Color {
    /// Builds a color that resolves differently in light vs. dark mode.
    static func fallback(light: Color, dark: Color) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    /// Asset catalog lookup with inline fallback for dev builds where the
    /// asset hasn't been added yet.
    init(_ name: String, bundle: Bundle?, fallback: FallbackPair) {
        if UIImage(named: name, in: bundle, with: nil) != nil || UIColor(named: name, in: bundle, compatibleWith: nil) != nil {
            self = Color(name, bundle: bundle)
        } else {
            self = Color.fallback(light: fallback.light, dark: fallback.dark)
        }
    }

    struct FallbackPair {
        let light: Color
        let dark: Color
        init(light: Color, dark: Color) {
            self.light = light
            self.dark = dark
        }
    }
}

// MARK: - View helpers

extension View {
    /// Applies the design-system card shadow.
    func themeShadow(_ spec: Theme.ShadowSpec = Theme.Shadow.card) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: 0, y: spec.y)
    }
}

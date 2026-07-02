import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

/// Apple-style design tokens (Health / Fitness / Music): grouped grey
/// background, clean white rounded cards, SF Pro text, SF Rounded numerals,
/// vibrant system-color accents. No glows, no gradients behind content —
/// color comes from the data, not the chrome.
enum Theme {
    // Backgrounds / surfaces
    static let bg = Color(hex: 0xF2F2F7)          // systemGroupedBackground base
    static let bgRaised = Color(hex: 0xFFFFFF)
    static let card = Color(hex: 0xFFFFFF)
    static let surface = Color(hex: 0xEFEFF4)     // subtle fill (inputs, tracks)

    // Text (Apple label hierarchy)
    static let text = Color(hex: 0x1C1C1E)
    static let textSecondary = Color(hex: 0x6E6E73)
    static let textMuted = Color(hex: 0xA0A0A8)

    // Apple system colors (multicolor accents)
    static let red = Color(hex: 0xFF3B30)
    static let orange = Color(hex: 0xFF9500)
    static let amber = Color(hex: 0xFF9500)
    static let gold = Color(hex: 0xFFCC00)
    static let green = Color(hex: 0x34C759)
    static let emerald = Color(hex: 0x34C759)
    static let teal = Color(hex: 0x00C7BE)
    static let cyan = Color(hex: 0x32ADE6)
    static let blue = Color(hex: 0x007AFF)
    static let indigo = Color(hex: 0x5856D6)
    static let violet = Color(hex: 0x5856D6)
    static let purple = Color(hex: 0xAF52DE)
    static let pink = Color(hex: 0xFF2D55)
    static let rose = Color(hex: 0xFF2D55)

    static let hairline = Color.black.opacity(0.06)
    static let track = Color.black.opacity(0.07)

    // Corner radii
    static let radius: CGFloat = 22
    static let radiusSmall: CGFloat = 14

    // Fonts — SF Pro for text, SF Rounded for big numeric values (Fitness style).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// App-wide light grouped background.
    static var backgroundGradient: some View {
        Theme.bg.ignoresSafeArea()
    }

    // MARK: - Score semantics (Vitals)

    /// WHOOP-style banding: green when ready, amber in the middle, red when low.
    static func scoreColor(_ score: Double?) -> Color {
        guard let score else { return textMuted }
        switch score {
        case 67...: return green
        case 34..<67: return amber
        default: return red
        }
    }

    static func guidanceColor(_ band: String?) -> Color {
        switch band {
        case "push": return green
        case "maintain": return blue
        case "recover": return amber
        case "rest": return rose
        default: return textMuted
        }
    }

    static func stressColor(_ level: String?) -> Color {
        switch level {
        case "low": return green
        case "moderate": return amber
        case "high": return rose
        default: return textMuted
        }
    }
}

// MARK: - Card styling (white, soft Apple shadow)

struct GlassCardModifier: ViewModifier {
    var tint: Color = .clear
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func glassCard(tint: Color = .clear, padding: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(tint: tint, padding: padding))
    }
}

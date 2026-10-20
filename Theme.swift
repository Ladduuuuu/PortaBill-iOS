import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let primary = Color(hex: 0x512BD4)
    static let primaryTint = Color(hex: 0xEDE8FB)
    static let primaryLight = Color(hex: 0xD9CFF7)
    static let ink = Color(hex: 0x1F2230)
    static let muted = Color(hex: 0x8F92A1)
    static let background = Color(hex: 0xF4F5F9)
    static let border = Color(hex: 0xE3E5EC)
    static let field = Color(hex: 0xF1F2F6)
    static let success = Color(hex: 0x22A45D)
    static let successTint = Color(hex: 0xE7F8F1)
    static let danger = Color(hex: 0xD93B3B)
    static let dangerTint = Color(hex: 0xFDECEC)
    static let warning = Color(hex: 0xF59E0B)
    static let warningTint = Color(hex: 0xFEF3E2)
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

struct ProgressBar: View {
    var value: Double
    var tint: Color = Theme.primary
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.field)
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

struct StatusPill: View {
    var text: String
    var color: Color
    var tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint, in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? tint : Theme.muted.opacity(0.5), in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct Notice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

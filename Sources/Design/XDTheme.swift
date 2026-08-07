import SwiftUI

enum XDTheme {

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

    static let background = dynamic(light: 0xFFFFFF, dark: 0x111113)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let hairline = dynamic(light: 0xDEDEE3, dark: 0x2C2C31)
    static let text = dynamic(light: 0x1B1B1D, dark: 0xECECEE)
    static let secondaryText = dynamic(light: 0x76726A, dark: 0x9A9AA2)
    static let quote = dynamic(light: 0x789922, dark: 0x9BC24A)
    static let link = dynamic(light: 0x2F6FB0, dark: 0x6FB2F0)
    static let hiddenBackground = dynamic(light: 0x3A3A3C, dark: 0x54545A)
    static let admin = dynamic(light: 0xC0392B, dark: 0xFF6B5E)
    static let poBadge = dynamic(light: 0xB8860B, dark: 0xE3B341)
    static let selfHash = dynamic(light: 0x2E7D32, dark: 0x66BB6A)

    enum Accent: String, CaseIterable, Identifiable {
        case purple = "基佬紫"
        case green = "原谅绿"
        case sakura = "猛男粉"
        case red = "姨妈红"
        case blue = "胖次蓝"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .purple: return XDTheme.dynamic(light: 0x7B3FBF, dark: 0xB07AE8)
            case .green: return XDTheme.dynamic(light: 0x2E9E4F, dark: 0x5FD07E)
            case .sakura: return XDTheme.dynamic(light: 0xE85D8A, dark: 0xFF8FB4)
            case .red: return XDTheme.dynamic(light: 0xD23B3B, dark: 0xFF6B6B)
            case .blue: return XDTheme.dynamic(light: 0x2F6FE0, dark: 0x6FA5FF)
            }
        }
    }

    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 10
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

struct XDCard: ViewModifier {
    var padding: CGFloat = XDTheme.cardPadding
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: XDTheme.cardRadius, style: .continuous)
                    .fill(XDTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XDTheme.cardRadius, style: .continuous)
                    .stroke(XDTheme.hairline, lineWidth: 0.5)
            )
    }
}

extension View {
    func xdCard(padding: CGFloat = XDTheme.cardPadding) -> some View {
        modifier(XDCard(padding: padding))
    }
}

struct XDBadge: View {
    let text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

struct XDFloatingButton: View {
    let systemImage: String
    var action: () -> Void

    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(settings.accent.color))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }
}

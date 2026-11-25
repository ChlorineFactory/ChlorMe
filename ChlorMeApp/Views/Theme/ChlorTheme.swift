import SwiftUI

public enum ChlorThemeMode: String, CaseIterable {
    case darkGlass = "dark_glass"
    case warmJournal = "warm_journal"
    case system = "system"

    public var displayName: String {
        switch self {
        case .darkGlass: return "暗夜磨砂（极客）"
        case .warmJournal: return "暖雾手账（柔和）"
        case .system: return "跟随系统"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .darkGlass: return .dark
        case .warmJournal: return .light
        case .system: return nil
        }
    }
}

public struct ChlorPalette {
    public let background: Color
    public let surface: Color
    public let surfaceElevated: Color
    public let userBubble: LinearGradient
    public let assistantBubble: Color
    public let accent: Color
    public let secondaryText: Color
    public let border: Color

    public static func palette(for mode: ChlorThemeMode, scheme: ColorScheme) -> ChlorPalette {
        switch mode {
        case .warmJournal:
            return ChlorPalette(
                background: Color(hex: "#F6F1EA"),
                surface: Color(hex: "#FFFDF9"),
                surfaceElevated: Color(hex: "#F1E8DC"),
                userBubble: LinearGradient(
                    colors: [Color(hex: "#3E8E88"), Color(hex: "#2F7570")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                assistantBubble: Color(hex: "#FFFFFF"),
                accent: Color(hex: "#3E8E88"),
                secondaryText: Color(hex: "#7A6F64"),
                border: Color(hex: "#E6DACB")
            )
        case .darkGlass:
            return ChlorPalette(
                background: Color(hex: "#0B0F17"),
                surface: Color(hex: "#141B29"),
                surfaceElevated: Color(hex: "#1C2538"),
                userBubble: LinearGradient(
                    colors: [Color(hex: "#38B2AC"), Color(hex: "#2C7A9B")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                assistantBubble: Color(hex: "#182133"),
                accent: Color(hex: "#5EEAD4"),
                secondaryText: Color(hex: "#8E9BB5"),
                border: Color.white.opacity(0.09)
            )
        case .system:
            if scheme == .dark {
                return palette(for: .darkGlass, scheme: .dark)
            } else {
                return palette(for: .warmJournal, scheme: .light)
            }
        }
    }
}

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (94, 234, 212)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

public struct ChatWallpaperBackground: View {
    public let style: String
    public let accentHex: String
    public let palette: ChlorPalette

    public init(style: String, accentHex: String, palette: ChlorPalette) {
        self.style = style
        self.accentHex = accentHex
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            switch style {
            case "aurora":
                RadialGradient(
                    colors: [Color(hex: accentHex).opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 360
                ).ignoresSafeArea()
                RadialGradient(
                    colors: [Color.indigo.opacity(0.16), .clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 340
                ).ignoresSafeArea()
            case "sunset":
                LinearGradient(
                    colors: [Color.orange.opacity(0.14), Color.pink.opacity(0.10), palette.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()
            case "forest":
                LinearGradient(
                    colors: [Color.teal.opacity(0.16), Color.mint.opacity(0.08), palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
            default:
                EmptyView()
            }
        }
    }
}

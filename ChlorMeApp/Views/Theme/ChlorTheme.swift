import SwiftUI
import UIKit

// MARK: - Theme Modes

public enum ChlorThemeMode: String, CaseIterable {
    case cosmicLiquid = "cosmic_liquid"
    case auroraPrism = "aurora_prism"
    case warmJournal = "warm_journal"
    case midnightOLED = "midnight_oled"
    case system = "system"

    public var displayName: String {
        switch self {
        case .cosmicLiquid: return "神秘宇宙液态玻璃（主打）"
        case .auroraPrism: return "极昼冰晶玻璃（浅色）"
        case .warmJournal: return "暖雾琥珀手账（柔和）"
        case .midnightOLED: return "深空星夜 OLED（极省电）"
        case .system: return "跟随系统"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .cosmicLiquid, .midnightOLED: return .dark
        case .auroraPrism, .warmJournal: return .light
        case .system: return nil
        }
    }

    public static func resolved(from raw: String) -> ChlorThemeMode {
        if raw == "dark_glass" { return .cosmicLiquid }
        return ChlorThemeMode(rawValue: raw) ?? .cosmicLiquid
    }
}

// MARK: - Palette

public struct ChlorPalette {
    public let isDark: Bool
    public let background: Color
    public let surface: Color
    public let surfaceElevated: Color
    public let userBubble: LinearGradient
    public let assistantBubble: Color
    public let accent: Color
    public let secondaryAccent: Color
    public let tertiaryAccent: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let border: Color

    public static func palette(for mode: ChlorThemeMode, scheme: ColorScheme) -> ChlorPalette {
        switch mode {
        case .cosmicLiquid:
            return ChlorPalette(
                isDark: true,
                background: Color(hex: "#050816"),
                surface: Color(hex: "#0F172A").opacity(0.55),
                surfaceElevated: Color(hex: "#192440").opacity(0.72),
                userBubble: LinearGradient(
                    colors: [Color(hex: "#2FD4C5"), Color(hex: "#4A6BFF"), Color(hex: "#7F56FF")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                assistantBubble: Color.white.opacity(0.08),
                accent: Color(hex: "#5CF6E3"),
                secondaryAccent: Color(hex: "#9B7BFF"),
                tertiaryAccent: Color(hex: "#FF7AC6"),
                primaryText: .white,
                secondaryText: Color(hex: "#A8B8DA"),
                border: Color.white.opacity(0.18)
            )

        case .auroraPrism:
            return ChlorPalette(
                isDark: false,
                background: Color(hex: "#EBF4FA"),
                surface: Color.white.opacity(0.62),
                surfaceElevated: Color.white.opacity(0.82),
                userBubble: LinearGradient(
                    colors: [Color(hex: "#18B4A7"), Color(hex: "#3E7BFA")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                assistantBubble: Color.white.opacity(0.76),
                accent: Color(hex: "#0EA5A4"),
                secondaryAccent: Color(hex: "#6D5DF6"),
                tertiaryAccent: Color(hex: "#EC4899"),
                primaryText: Color(hex: "#0F172A"),
                secondaryText: Color(hex: "#52627A"),
                border: Color.white.opacity(0.78)
            )

        case .warmJournal:
            return ChlorPalette(
                isDark: false,
                background: Color(hex: "#F6EFE6"),
                surface: Color(hex: "#FFFDF9").opacity(0.70),
                surfaceElevated: Color(hex: "#FFF9F0").opacity(0.88),
                userBubble: LinearGradient(
                    colors: [Color(hex: "#3B8C84"), Color(hex: "#2C6B67")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                assistantBubble: Color.white.opacity(0.82),
                accent: Color(hex: "#3B8C84"),
                secondaryAccent: Color(hex: "#C97A5B"),
                tertiaryAccent: Color(hex: "#D99B52"),
                primaryText: Color(hex: "#2C241E"),
                secondaryText: Color(hex: "#786A5D"),
                border: Color(hex: "#E6D7C3").opacity(0.85)
            )

        case .midnightOLED:
            return ChlorPalette(
                isDark: true,
                background: Color(hex: "#000000"),
                surface: Color(hex: "#0D1017").opacity(0.78),
                surfaceElevated: Color(hex: "#161B26").opacity(0.90),
                userBubble: LinearGradient(
                    colors: [Color(hex: "#18B8A8"), Color(hex: "#3B5BDB")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                assistantBubble: Color.white.opacity(0.06),
                accent: Color(hex: "#4DF5DF"),
                secondaryAccent: Color(hex: "#8A63FF"),
                tertiaryAccent: Color(hex: "#FF7AC6"),
                primaryText: .white,
                secondaryText: Color(hex: "#8B95AA"),
                border: Color.white.opacity(0.14)
            )

        case .system:
            return palette(for: scheme == .dark ? .cosmicLiquid : .auroraPrism, scheme: scheme)
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
            (r, g, b) = (92, 246, 227)
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

// MARK: - Cosmic Nebula Backdrop

public struct CosmicNebulaBackdrop: View {
    public let palette: ChlorPalette
    public var accentHex: String?
    public var animated: Bool = true

    public init(palette: ChlorPalette, accentHex: String? = nil, animated: Bool = true) {
        self.palette = palette
        self.accentHex = accentHex
        self.animated = animated
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1.0 / 24.0 : 60.0)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate * 0.24 : 0.0
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))

                let primaryColor = accentHex.map { Color(hex: $0) } ?? palette.accent
                let alphaScale: Double = palette.isDark ? 1.0 : 0.55

                let p1 = CGPoint(
                    x: size.width * (0.20 + 0.16 * sin(t * 0.85)),
                    y: size.height * (0.16 + 0.09 * cos(t * 0.65))
                )
                drawOrb(ctx: &ctx, center: p1, radius: size.width * 0.82, color: primaryColor.opacity(0.36 * alphaScale))

                let p2 = CGPoint(
                    x: size.width * (0.82 + 0.14 * cos(t * 0.70)),
                    y: size.height * (0.68 + 0.11 * sin(t * 0.80))
                )
                drawOrb(ctx: &ctx, center: p2, radius: size.width * 0.88, color: palette.secondaryAccent.opacity(0.34 * alphaScale))

                let p3 = CGPoint(
                    x: size.width * (0.76 + 0.11 * sin(t * 1.15 + 1.2)),
                    y: size.height * (0.22 + 0.10 * cos(t * 0.90 + 0.7))
                )
                drawOrb(ctx: &ctx, center: p3, radius: size.width * 0.58, color: palette.tertiaryAccent.opacity(0.22 * alphaScale))

                if palette.isDark {
                    for i in 0..<32 {
                        let seed = Double(i) * 19.37
                        let sx = (sin(seed * 1.7) * 0.5 + 0.5) * size.width
                        let sy = (cos(seed * 2.3) * 0.5 + 0.5) * size.height
                        let twinkle = 0.22 + 0.60 * (0.5 + 0.5 * sin(t * 2.6 + seed))
                        let r = (i % 5 == 0) ? 1.9 : 1.1
                        let rect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle)))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func drawOrb(ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        let gradient = Gradient(stops: [
            .init(color: color, location: 0.0),
            .init(color: color.opacity(0.34), location: 0.45),
            .init(color: .clear, location: 1.0)
        ])
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
        )
    }
}

// MARK: - Authentic iOS 26+ Native Liquid Glass with Graceful iOS 17-18 Fallback

/// Wraps iOS 26+ `GlassEffectContainer` so adjacent Liquid Glass pills physically morph & refract together!
public struct LiquidGlassCluster<Content: View>: View {
    public let spacing: CGFloat
    @ViewBuilder public let content: () -> Content

    public init(spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

public struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let isDark: Bool
    let strokeWidth: CGFloat
    let interactive: Bool

    @ViewBuilder
    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let baseGlass = Glass.regular.tint(tint.opacity(isDark ? 0.14 : 0.10))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if interactive {
                content.glassEffect(baseGlass.interactive(), in: shape)
            } else {
                content.glassEffect(baseGlass, in: shape)
            }
        } else {
            fallbackGlass(content)
        }
        #else
        fallbackGlass(content)
        #endif
    }

    private func fallbackGlass(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background {
                ZStack {
                    shape.fill(isDark ? .ultraThinMaterial : .regularMaterial)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.14 : 0.45),
                                tint.opacity(isDark ? 0.08 : 0.05),
                                Color.white.opacity(isDark ? 0.03 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.52 : 0.90),
                                tint.opacity(isDark ? 0.40 : 0.25),
                                Color(hex: "#9B7BFF").opacity(isDark ? 0.34 : 0.20),
                                Color.white.opacity(isDark ? 0.12 : 0.40)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strokeWidth
                    )
                }
            }
            .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.10), radius: 16, x: 0, y: 8)
    }
}

public struct LiquidGlassCapsuleModifier: ViewModifier {
    let tint: Color
    let isDark: Bool
    let interactive: Bool

    @ViewBuilder
    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let baseGlass = Glass.regular.tint(tint.opacity(isDark ? 0.18 : 0.12))
            if interactive {
                content.glassEffect(baseGlass.interactive(), in: Capsule())
            } else {
                content.glassEffect(baseGlass, in: Capsule())
            }
        } else {
            fallbackCapsule(content)
        }
        #else
        fallbackCapsule(content)
        #endif
    }

    private func fallbackCapsule(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    Capsule().fill(isDark ? .ultraThinMaterial : .regularMaterial)
                    Capsule().fill(tint.opacity(isDark ? 0.10 : 0.08))
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.65), tint.opacity(0.45), Color(hex: "#9B7BFF").opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
                }
            }
            .shadow(color: Color.black.opacity(isDark ? 0.36 : 0.12), radius: 16, x: 0, y: 8)
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 22,
        tint: Color = Color(hex: "#5CF6E3"),
        isDark: Bool = true,
        strokeWidth: CGFloat = 1.0,
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, tint: tint, isDark: isDark, strokeWidth: strokeWidth, interactive: interactive))
    }

    func liquidGlassCapsule(
        tint: Color = Color(hex: "#5CF6E3"),
        isDark: Bool = true,
        interactive: Bool = true
    ) -> some View {
        modifier(LiquidGlassCapsuleModifier(tint: tint, isDark: isDark, interactive: interactive))
    }
}

// MARK: - Companion Avatar Component

public struct CompanionAvatarView: View {
    public let symbol: String
    public let imageFileName: String?
    public let accentHex: String
    public var size: CGFloat = 52

    public init(symbol: String, imageFileName: String? = nil, accentHex: String, size: CGFloat = 52) {
        self.symbol = symbol
        self.imageFileName = imageFileName
        self.accentHex = accentHex
        self.size = size
    }

    public var body: some View {
        let accent = Color(hex: accentHex)
        ZStack {
            if let uiImage = MediaStorage.loadImage(fileName: imageFileName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.48), Color(hex: "#7B61FF").opacity(0.34)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: accent.opacity(0.8), radius: 6)
            }
        }
        .overlay(
            Circle().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.75), accent.opacity(0.7), Color(hex: "#9B7BFF").opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.4
            )
        )
        .shadow(color: accent.opacity(0.28), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Chat Wallpaper Background

public struct ChatWallpaperBackground: View {
    public let style: String
    public let customImageFileName: String?
    public let accentHex: String
    public let palette: ChlorPalette

    public init(style: String, customImageFileName: String? = nil, accentHex: String, palette: ChlorPalette) {
        self.style = style
        self.customImageFileName = customImageFileName
        self.accentHex = accentHex
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            if let img = MediaStorage.loadImage(fileName: customImageFileName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                Color.black.opacity(palette.isDark ? 0.38 : 0.14)
                    .ignoresSafeArea()
            } else {
                switch style {
                case "cosmic", "aurora":
                    CosmicNebulaBackdrop(palette: palette, accentHex: accentHex, animated: true)
                case "sunset":
                    CosmicNebulaBackdrop(palette: palette, accentHex: "#FF8A65", animated: true)
                case "forest":
                    CosmicNebulaBackdrop(palette: palette, accentHex: "#34D399", animated: true)
                default:
                    palette.background.ignoresSafeArea()
                }
            }
        }
    }
}

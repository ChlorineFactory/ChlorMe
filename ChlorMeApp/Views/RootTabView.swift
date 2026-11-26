import SwiftUI
import ChlorCore

public struct RootTabView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedTab: Int = 0
    @State private var isInsideChatRoom: Bool = false
    @Namespace private var dockNamespace

    private var themeMode: ChlorThemeMode {
        ChlorThemeMode.resolved(from: store.settings.themeMode)
    }

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: themeMode, scheme: scheme)
    }

    private let tabs: [(index: Int, title: String, icon: String)] = [
        (0, "对话", "bubble.left.and.bubble.right.fill"),
        (1, "伴侣", "sparkles"),
        (2, "模型", "cpu.fill"),
        (3, "工坊", "slider.horizontal.3")
    ]

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0:
                    ChatListView(isInsideChatRoom: $isInsideChatRoom)
                case 1:
                    CompanionsHubView()
                case 2:
                    ModelsHubView()
                default:
                    StudioSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isInsideChatRoom {
                floatingLiquidGlassDock
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let toast = store.toastMessage {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .foregroundStyle(palette.accent)
                        Text(toast)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark)
                    .padding(.top, 56)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: store.toastMessage)
                .allowsHitTesting(false)
            }

            if store.isLocked {
                privacyLockOverlay
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: isInsideChatRoom)
        .tint(palette.accent)
        .alert("提示", isPresented: Binding(
            get: { store.alertError != nil },
            set: { if !$0 { store.alertError = nil } }
        )) {
            Button("好的", role: .cancel) { store.alertError = nil }
        } message: {
            Text(store.alertError ?? "")
        }
    }

    private var floatingLiquidGlassDock: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.index) { tab in
                let isSelected = selectedTab == tab.index
                Button {
                    if selectedTab != tab.index {
                        ChlorHaptics.light()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                            selectedTab = tab.index
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                            .symbolEffect(.bounce, value: isSelected)
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            palette.accent.opacity(palette.isDark ? 0.24 : 0.18),
                                            palette.secondaryAccent.opacity(palette.isDark ? 0.20 : 0.12)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Capsule().strokeBorder(palette.accent.opacity(0.45), lineWidth: 0.9)
                                )
                                .matchedGeometryEffect(id: "dockSelection", in: dockNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark)
    }

    private var privacyLockOverlay: some View {
        ZStack {
            CosmicNebulaBackdrop(palette: palette)
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.18))
                        .frame(width: 96, height: 96)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(colors: [palette.accent, palette.secondaryAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                .liquidGlass(cornerRadius: 48, tint: palette.accent, isDark: palette.isDark)

                Text("ChlorMe 已锁定")
                    .font(.title2.bold())
                    .foregroundStyle(palette.primaryText)
                Text("验证面容 ID 或密码以进入私密宇宙空间")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)

                Button {
                    store.authenticateUnlock()
                } label: {
                    Label("解锁进入", systemImage: "faceid")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(palette.userBubble, in: Capsule())
                        .shadow(color: palette.accent.opacity(0.35), radius: 14, y: 6)
                }
            }
            .padding(32)
            .liquidGlass(cornerRadius: 30, tint: palette.accent, isDark: palette.isDark)
            .padding(.horizontal, 28)
        }
        .onAppear {
            store.authenticateUnlock()
        }
    }
}

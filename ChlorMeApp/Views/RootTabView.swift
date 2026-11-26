import SwiftUI
import ChlorCore

/// Native iOS 26+ Liquid Glass TabView (automatically renders authentic refracting floating glass tab bar when built with Xcode 26 SDK!)
public struct RootTabView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedTab: Int = 0
    @State private var isInsideChatRoom: Bool = false

    private var themeMode: ChlorThemeMode {
        ChlorThemeMode.resolved(from: store.settings.themeMode)
    }

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: themeMode, scheme: scheme)
    }

    public init() {}

    public var body: some View {
        ZStack {
            nativeTabView
                .tint(palette.accent)

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
                    .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark, interactive: false)
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
        .alert("提示", isPresented: Binding(
            get: { store.alertError != nil },
            set: { if !$0 { store.alertError = nil } }
        )) {
            Button("好的", role: .cancel) { store.alertError = nil }
        } message: {
            Text(store.alertError ?? "")
        }
    }

    @ViewBuilder
    private var nativeTabView: some View {
        let base = TabView(selection: $selectedTab) {
            ChatListView(isInsideChatRoom: $isInsideChatRoom)
                .tabItem {
                    Label("对话", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(0)

            CompanionsHubView()
                .tabItem {
                    Label("伴侣", systemImage: "sparkles")
                }
                .tag(1)

            ModelsHubView()
                .tabItem {
                    Label("模型", systemImage: "cpu.fill")
                }
                .tag(2)

            StudioSettingsView()
                .tabItem {
                    Label("工坊", systemImage: "slider.horizontal.3")
                }
                .tag(3)
        }

        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            base.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            base
        }
        #else
        base
        #endif
    }

    private var privacyLockOverlay: some View {
        ZStack {
            CosmicNebulaBackdrop(palette: palette)
            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(colors: [palette.accent, palette.secondaryAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 88, height: 88)
                    .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark, interactive: false)

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

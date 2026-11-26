import SwiftUI
import ChlorCore

/// RikkaHub-inspired chat-first home shell: main screen IS the active chat room,
/// with a gesture-driven Liquid Glass left sidebar drawer for sessions, companions, local LLM hub & settings.
public struct RootTabView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    @State private var isDrawerOpen = false
    @State private var dragOffset: CGFloat = 0

    @State private var showModelsSheet = false
    @State private var showCompanionsSheet = false
    @State private var showSettingsSheet = false
    @State private var showTemplateGallery = false
    @State private var showNewCharacter = false

    private var themeMode: ChlorThemeMode {
        ChlorThemeMode.resolved(from: store.settings.themeMode)
    }

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: themeMode, scheme: scheme)
    }

    public init() {}

    private var activeConversation: Conversation? {
        if let id = store.activeConversationId,
           let conv = store.conversations.first(where: { $0.id == id }) {
            return conv
        }
        return store.conversations.first
    }

    public var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(geo.size.width * 0.84, 340)

            ZStack(alignment: .leading) {
                // 1. Main Chat Home
                mainChatHome
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(!isDrawerOpen)

                // 2. Dimming Backdrop when Drawer Open
                if isDrawerOpen || dragOffset > 0 {
                    let progress = isDrawerOpen
                        ? max(0, min(1, 1 + dragOffset / drawerWidth))
                        : max(0, min(1, dragOffset / drawerWidth))
                    Color.black.opacity(0.45 * progress)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeDrawer()
                        }
                }

                // 3. Left Liquid Glass Sidebar Drawer
                SidebarDrawerView(
                    drawerWidth: drawerWidth,
                    onSelectConversation: { conv in
                        store.activeConversationId = conv.id
                        closeDrawer()
                    },
                    onOpenModels: {
                        closeDrawer()
                        showModelsSheet = true
                    },
                    onOpenCompanions: {
                        closeDrawer()
                        showCompanionsSheet = true
                    },
                    onOpenSettings: {
                        closeDrawer()
                        showSettingsSheet = true
                    },
                    onOpenTemplates: {
                        closeDrawer()
                        showTemplateGallery = true
                    },
                    onCreateNewCharacter: {
                        closeDrawer()
                        showNewCharacter = true
                    }
                )
                .frame(width: drawerWidth)
                .offset(x: drawerXOffset(drawerWidth: drawerWidth))
                .shadow(color: .black.opacity(0.35), radius: 28, x: 8, y: 0)

                // 4. Floating Liquid Toast
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
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.36, dampingFraction: 0.82), value: store.toastMessage)
                    .allowsHitTesting(false)
                }

                // 5. Privacy Face ID Lock
                if store.isLocked {
                    privacyLockOverlay
                }
            }
            .gesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .local)
                    .onChanged { value in
                        let horizontal = value.translation.width
                        let vertical = abs(value.translation.height)
                        guard abs(horizontal) > vertical * 1.15 else { return }

                        if !isDrawerOpen {
                            // Open from left edge swipe
                            guard value.startLocation.x < 46, horizontal > 0 else { return }
                            dragOffset = min(drawerWidth, horizontal)
                        } else {
                            // Close by swiping left
                            guard horizontal < 0 else { return }
                            dragOffset = max(-drawerWidth, horizontal)
                        }
                    }
                    .onEnded { value in
                        let threshold = drawerWidth * 0.28
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            if !isDrawerOpen {
                                if dragOffset > threshold || value.predictedEndTranslation.width > drawerWidth * 0.5 {
                                    isDrawerOpen = true
                                    ChlorHaptics.light()
                                }
                            } else {
                                if -dragOffset > threshold || value.predictedEndTranslation.width < -drawerWidth * 0.45 {
                                    isDrawerOpen = false
                                    ChlorHaptics.light()
                                }
                            }
                            dragOffset = 0
                        }
                    }
            )
        }
        .tint(palette.accent)
        .sheet(isPresented: $showModelsSheet) {
            ModelsHubView(showCloseButton: true)
        }
        .sheet(isPresented: $showCompanionsSheet) {
            CompanionsHubView(showCloseButton: true)
        }
        .sheet(isPresented: $showSettingsSheet) {
            StudioSettingsView(
                onOpenModels: {
                    showSettingsSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showModelsSheet = true }
                },
                onOpenCompanions: {
                    showSettingsSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCompanionsSheet = true }
                }
            )
        }
        .sheet(isPresented: $showTemplateGallery) {
            CompanionTemplateGallerySheet()
        }
        .sheet(isPresented: $showNewCharacter) {
            NavigationStack { CharacterEditorView(character: nil) }
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
    private var mainChatHome: some View {
        if let conv = activeConversation,
           let char = store.characters.first(where: { $0.id == conv.characterId }) {
            ChatRoomView(
                conversationId: conv.id,
                characterId: char.id,
                onOpenDrawer: { openDrawer() },
                onOpenModels: { showModelsSheet = true }
            )
            .id(conv.id)
        } else {
            ZStack {
                CosmicNebulaBackdrop(palette: palette)
                VStack(spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(palette.accent)
                    Text("欢迎来到 ChlorMe")
                        .font(.title2.bold())
                        .foregroundStyle(palette.primaryText)
                    Text("本地离线大模型 × 伴侣长期记忆")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                    HStack(spacing: 12) {
                        Button("开启新对话") {
                            Task { await store.selectOrCreateDefaultConversation() }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(palette.userBubble, in: Capsule())

                        Button("打开侧边栏") {
                            openDrawer()
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark)
                    }
                }
                .padding(28)
                .liquidGlass(cornerRadius: 28, tint: palette.accent, isDark: palette.isDark)
                .padding(.horizontal, 24)
            }
        }
    }

    private func drawerXOffset(drawerWidth: CGFloat) -> CGFloat {
        if isDrawerOpen {
            return min(0, dragOffset)
        } else {
            return -drawerWidth + max(0, dragOffset)
        }
    }

    private func openDrawer() {
        ChlorHaptics.light()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isDrawerOpen = true
        }
    }

    private func closeDrawer() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            isDrawerOpen = false
        }
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

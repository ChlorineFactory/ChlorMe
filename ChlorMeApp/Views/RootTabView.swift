import SwiftUI
import ChlorCore

public struct RootTabView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedTab: Int = 0

    private var themeMode: ChlorThemeMode {
        ChlorThemeMode(rawValue: store.settings.themeMode) ?? .darkGlass
    }

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: themeMode, scheme: scheme)
    }

    public init() {}

    public var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ChatListView()
                    .tabItem {
                        Label("对话", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .tag(0)

                CompanionsHubView()
                    .tabItem {
                        Label("伴侣", systemImage: "heart.text.square.fill")
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
            .tint(palette.accent)

            if let toast = store.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(palette.accent.opacity(0.4), lineWidth: 1))
                        .shadow(radius: 10)
                        .padding(.bottom, 76)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: store.toastMessage)
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

    private var privacyLockOverlay: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(palette.accent)
                Text("ChlorMe 已锁定")
                    .font(.title2.bold())
                Text("验证面容 ID 或密码以进入私密伴侣空间")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                Button {
                    store.authenticateUnlock()
                } label: {
                    Label("解锁进入", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
            }
            .padding()
        }
        .onAppear {
            store.authenticateUnlock()
        }
    }
}

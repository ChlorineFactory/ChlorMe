import SwiftUI
import UniformTypeIdentifiers
import ChlorCore

public struct ChatListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Binding public var isInsideChatRoom: Bool

    @State private var searchText = ""
    @State private var showNewCharacter = false
    @State private var showTemplateGallery = false
    @State private var showCardImporter = false
    @State private var deletingConversation: Conversation?

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    public init(isInsideChatRoom: Binding<Bool> = .constant(false)) {
        _isInsideChatRoom = isInsideChatRoom
    }

    private var filteredConversations: [Conversation] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.conversations }
        return store.conversations.filter { conv in
            let char = store.characters.first(where: { $0.id == conv.characterId })
            let charMatch = char?.name.lowercased().contains(q) == true || conv.title.lowercased().contains(q)
            let msgMatch = store.visibleMessages(for: conv.id).contains { $0.content.lowercased().contains(q) }
            return charMatch || msgMatch
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicNebulaBackdrop(palette: palette)

                ScrollView {
                    VStack(spacing: 16) {
                        headerHeroRow
                        runtimeStatusGlassCard
                        searchGlassBar
                        conversationListSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 108)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNewCharacter) {
                NavigationStack { CharacterEditorView(character: nil) }
            }
            .sheet(isPresented: $showTemplateGallery) {
                CompanionTemplateGallerySheet()
            }
            .fileImporter(
                isPresented: $showCardImporter,
                allowedContentTypes: [.json, .png],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await store.importCharacterCard(from: url) }
                }
            }
            .confirmationDialog(
                "确认删除此会话？",
                isPresented: Binding(get: { deletingConversation != nil }, set: { if !$0 { deletingConversation = nil } }),
                titleVisibility: .visible
            ) {
                Button("删除会话", role: .destructive) {
                    if let conv = deletingConversation {
                        Task { await store.deleteConversation(conv) }
                    }
                    deletingConversation = nil
                }
                Button("取消", role: .cancel) { deletingConversation = nil }
            }
        }
    }

    private var headerHeroRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ChlorMe")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [palette.primaryText, palette.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("\(store.characters.count) 位伴侣 · \(store.totalMemoryCount) 段星光回忆")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            Menu {
                Button {
                    showTemplateGallery = true
                } label: {
                    Label("从精选模板迎接伴侣", systemImage: "sparkles")
                }
                Button {
                    showNewCharacter = true
                } label: {
                    Label("从零自定义新伴侣", systemImage: "person.badge.plus")
                }
                Button {
                    showCardImporter = true
                } label: {
                    Label("导入 V2 角色卡 (JSON / PNG)", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44)
                    .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark)
            }
        }
        .padding(.top, 6)
    }

    private var runtimeStatusGlassCard: some View {
        let loadedModel = store.models.first(where: { $0.id == store.loadedModelId })
        let availText = MemoryBudgetAdvisor.formatBytes(store.availableMemoryBytes)

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((loadedModel != nil ? Color.green : palette.accent).opacity(0.24))
                    .frame(width: 34, height: 34)
                Circle()
                    .fill(loadedModel != nil ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                    .shadow(color: (loadedModel != nil ? Color.green : Color.orange).opacity(0.85), radius: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                if store.isLoadingModel {
                    Text("正在唤醒本地神经网络…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                } else if let m = loadedModel {
                    Text("驻留引擎 · \(m.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                } else if let remote = store.models.first(where: { $0.backendKind == .openAICompatible }) {
                    Text("星际远程 · \(remote.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                } else {
                    Text("尚未加载模型 · 前往「模型」唤醒")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                }

                Text("剩余安全显存 \(availText)\(store.currentTokensPerSecond > 0 ? String(format: " · %.1f tok/s", store.currentTokensPerSecond) : "")")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            if loadedModel != nil {
                Button {
                    ChlorHaptics.light()
                    Task { await store.unloadLocalModel() }
                } label: {
                    Text("释放")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.8))
                }
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 22, tint: loadedModel != nil ? .green : palette.accent, isDark: palette.isDark)
    }

    private var searchGlassBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondaryText)
            TextField("搜索伴侣或历史聊天关键词…", text: $searchText)
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassCapsule(tint: palette.secondaryAccent, isDark: palette.isDark)
    }

    private var conversationListSection: some View {
        LazyVStack(spacing: 14) {
            if filteredConversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(palette.accent)
                    Text(searchText.isEmpty ? "还没有对话" : "没有找到匹配的聊天记录")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    if searchText.isEmpty {
                        Button("挑选一位伴侣开始聊天") {
                            showTemplateGallery = true
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(palette.userBubble, in: Capsule())
                        .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .liquidGlass(cornerRadius: 24, tint: palette.accent, isDark: palette.isDark)
            } else {
                ForEach(filteredConversations) { conv in
                    if let character = store.characters.first(where: { $0.id == conv.characterId }) {
                        NavigationLink {
                            ChatRoomView(
                                conversationId: conv.id,
                                characterId: character.id,
                                isInsideChatRoom: $isInsideChatRoom
                            )
                        } label: {
                            conversationCard(conv: conv, character: character)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task { _ = await store.createNewConversation(for: character) }
                            } label: {
                                Label("为 \(character.name) 新开一条平行会话", systemImage: "plus.bubble")
                            }
                            if store.conversations.count > 1 {
                                Button(role: .destructive) {
                                    deletingConversation = conv
                                } label: {
                                    Label("删除此会话", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func conversationCard(conv: Conversation, character: CharacterCard) -> some View {
        let lastMsg = store.visibleMessages(for: conv.id).last
        let memCount = (store.episodicMemoriesByCharacter[character.id] ?? []).count
        let accent = Color(hex: character.accentHex)

        return HStack(spacing: 14) {
            CompanionAvatarView(
                symbol: character.avatarSymbol,
                imageFileName: character.avatarImageFileName,
                accentHex: character.accentHex,
                size: 56
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(conv.title.isEmpty ? character.name : conv.title)
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    if !character.moodLabel.isEmpty {
                        Text(character.moodLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(accent.opacity(0.20), in: Capsule())
                            .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 0.7))
                            .foregroundStyle(accent)
                    }
                    Spacer()
                    Text(relativeTime(conv.lastMessageAt))
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }

                Text(lastMsg?.content.replacingOccurrences(of: "\n", with: " ") ?? character.tagline)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label(character.relationshipLabel, systemImage: "heart.fill")
                    Label("\(memCount) 条回忆", systemImage: "sparkles")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.secondaryText.opacity(0.85))
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 24, tint: accent, isDark: palette.isDark)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

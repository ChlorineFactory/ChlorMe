import SwiftUI
import ChlorCore

/// RikkaHub-style left sidebar drawer with search, quick new-session creation, time-grouped chat history,
/// Local LLM Hub shortcut, Companion Workshop shortcut, and bottom Settings entry.
public struct SidebarDrawerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    public let drawerWidth: CGFloat
    public let onSelectConversation: (Conversation) -> Void
    public let onOpenModels: () -> Void
    public let onOpenCompanions: () -> Void
    public let onOpenSettings: () -> Void
    public let onOpenTemplates: () -> Void
    public let onCreateNewCharacter: () -> Void

    @State private var searchText = ""
    @State private var renamingConversation: Conversation?
    @State private var renameDraft = ""

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    public init(
        drawerWidth: CGFloat,
        onSelectConversation: @escaping (Conversation) -> Void,
        onOpenModels: @escaping () -> Void,
        onOpenCompanions: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenTemplates: @escaping () -> Void,
        onCreateNewCharacter: @escaping () -> Void
    ) {
        self.drawerWidth = drawerWidth
        self.onSelectConversation = onSelectConversation
        self.onOpenModels = onOpenModels
        self.onOpenCompanions = onOpenCompanions
        self.onOpenSettings = onOpenSettings
        self.onOpenTemplates = onOpenTemplates
        self.onCreateNewCharacter = onCreateNewCharacter
    }

    private var filteredConversations: [Conversation] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.conversations }
        return store.conversations.filter { conv in
            let char = store.characters.first(where: { $0.id == conv.characterId })
            let titleHit = conv.title.lowercased().contains(q) || (char?.name.lowercased().contains(q) == true)
            let msgHit = store.visibleMessages(for: conv.id).contains { $0.content.lowercased().contains(q) }
            return titleHit || msgHit
        }
    }

    private var groupedConversations: [(title: String, items: [Conversation])] {
        let cal = Calendar.current
        let now = Date()
        var today: [Conversation] = []
        var week: [Conversation] = []
        var earlier: [Conversation] = []

        for conv in filteredConversations {
            if cal.isDateInToday(conv.lastMessageAt) {
                today.append(conv)
            } else if let diff = cal.dateComponents([.day], from: conv.lastMessageAt, to: now).day, diff <= 7 {
                week.append(conv)
            } else {
                earlier.append(conv)
            }
        }
        var groups: [(String, [Conversation])] = []
        if !today.isEmpty { groups.append(("今天", today)) }
        if !week.isEmpty { groups.append(("最近 7 天", week)) }
        if !earlier.isEmpty { groups.append(("更早之前", earlier)) }
        return groups
    }

    public var body: some View {
        ZStack {
            // Drawer glass backdrop
            CosmicNebulaBackdrop(palette: palette, animated: false)
                .opacity(0.92)
            Rectangle()
                .fill(palette.isDark ? Color.black.opacity(0.32) : Color.white.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Top Brand + New Chat Button
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ChlorMe")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [palette.primaryText, palette.accent], startPoint: .leading, endPoint: .trailing)
                            )
                        Text("本地模型 · 星光伴侣")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()

                    // New chat picker menu
                    Menu {
                        Section("选择伴侣开启新会话") {
                            ForEach(store.characters) { char in
                                Button {
                                    Task {
                                        let conv = await store.createNewConversation(for: char)
                                        onSelectConversation(conv)
                                    }
                                } label: {
                                    Label(char.name, systemImage: char.avatarSymbol)
                                }
                            }
                        }
                        Divider()
                        Button { onOpenTemplates() } label: {
                            Label("从模板广场迎接新伴侣", systemImage: "sparkles")
                        }
                        Button { onCreateNewCharacter() } label: {
                            Label("自定义新伴侣", systemImage: "person.badge.plus")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.pencil")
                            Text("新对话")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(palette.userBubble, in: Capsule())
                        .shadow(color: palette.accent.opacity(0.3), radius: 8, y: 3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    TextField("搜索会话或聊天内容…", text: $searchText)
                        .font(.subheadline)
                        .foregroundStyle(palette.primaryText)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark, interactive: false)
                .padding(.horizontal, 14)

                // Quick Hub Cards (Local LLM Engine & Companion Workshop)
                LiquidGlassCluster(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            ChlorHaptics.light()
                            onOpenModels()
                        } label: {
                            let loaded = store.models.first(where: { $0.id == store.loadedModelId })
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "cpu.fill")
                                        .foregroundStyle(loaded != nil ? .green : palette.accent)
                                    Spacer()
                                    Circle()
                                        .fill(loaded != nil ? Color.green : Color.orange)
                                        .frame(width: 7, height: 7)
                                }
                                Text("本地模型舱")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(palette.primaryText)
                                Text(loaded?.name ?? "管理 GGUF / API")
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(cornerRadius: 18, tint: loaded != nil ? .green : palette.accent, isDark: palette.isDark, interactive: true)
                        }
                        .buttonStyle(.plain)

                        Button {
                            ChlorHaptics.light()
                            onOpenCompanions()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(palette.secondaryAccent)
                                    Spacer()
                                    Text("\(store.characters.count)")
                                        .font(.caption2.monospacedDigit().bold())
                                        .foregroundStyle(palette.secondaryText)
                                }
                                Text("角色与世界书")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(palette.primaryText)
                                Text("人设 · Lorebook")
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(cornerRadius: 18, tint: palette.secondaryAccent, isDark: palette.isDark, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)

                // Grouped Conversation History
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if groupedConversations.isEmpty {
                            Text(searchText.isEmpty ? "暂无会话，点右上角开始聊吧" : "未找到匹配会话")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 30)
                        } else {
                            ForEach(groupedConversations, id: \.title) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.title)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(palette.secondaryText)
                                        .padding(.horizontal, 6)

                                    ForEach(group.items) { conv in
                                        conversationRow(conv)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }

                // Bottom User & Settings Dock
                HStack(spacing: 10) {
                    let persona = store.personas.first(where: \.isDefault) ?? store.personas.first
                    VStack(alignment: .leading, spacing: 2) {
                        Text(persona?.name ?? "我")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                        Text("显存可用 \(MemoryBudgetAdvisor.formatBytes(store.availableMemoryBytes)) · \(store.totalMemoryCount) 回忆")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        ChlorHaptics.light()
                        onOpenSettings()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape.fill")
                            Text("设置")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .liquidGlass(cornerRadius: 22, tint: palette.accent, isDark: palette.isDark)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .overlay(
            Rectangle()
                .fill(palette.border.opacity(0.6))
                .frame(width: 0.7),
            alignment: .trailing
        )
        .alert("重命名会话", isPresented: Binding(get: { renamingConversation != nil }, set: { if !$0 { renamingConversation = nil } })) {
            TextField("新标题", text: $renameDraft)
            Button("取消", role: .cancel) { renamingConversation = nil }
            Button("保存") {
                if var conv = renamingConversation {
                    let t = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        conv.title = t
                        Task { await store.updateConversation(conv) }
                    }
                }
                renamingConversation = nil
            }
        }
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        let character = store.characters.first(where: { $0.id == conv.characterId })
        let isActive = (store.activeConversationId ?? store.conversations.first?.id) == conv.id
        let lastMsg = store.visibleMessages(for: conv.id).last?.content.replacingOccurrences(of: "\n", with: " ") ?? ""
        let accent = Color(hex: character?.accentHex ?? "#5CF6E3")

        return Button {
            ChlorHaptics.light()
            onSelectConversation(conv)
        } label: {
            HStack(spacing: 10) {
                if let character {
                    CompanionAvatarView(
                        symbol: character.avatarSymbol,
                        imageFileName: character.avatarImageFileName,
                        accentHex: character.accentHex,
                        size: 36
                    )
                }
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(conv.title.isEmpty ? (character?.name ?? "会话") : conv.title)
                        .font(.subheadline.weight(isActive ? .bold : .medium))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    if !lastMsg.isEmpty {
                        Text(lastMsg)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(palette.isDark ? 0.22 : 0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(accent.opacity(0.55), lineWidth: 1)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renamingConversation = conv
                renameDraft = conv.title
            } label: {
                Label("重命名会话", systemImage: "pencil")
            }
            if let character {
                Button {
                    Task {
                        let newConv = await store.createNewConversation(for: character)
                        onSelectConversation(newConv)
                    }
                } label: {
                    Label("以 \(character.name) 再开新会话", systemImage: "plus.bubble")
                }
            }
            if store.conversations.count > 1 {
                Button(role: .destructive) {
                    Task { await store.deleteConversation(conv) }
                } label: {
                    Label("删除此会话", systemImage: "trash")
                }
            }
        }
    }
}

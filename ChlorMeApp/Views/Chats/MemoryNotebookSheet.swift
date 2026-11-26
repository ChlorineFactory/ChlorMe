import SwiftUI
import ChlorCore

public struct MemoryNotebookSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    public let conversation: Conversation
    public let character: CharacterCard

    @State private var tab = 0
    @State private var searchQuery = ""
    @State private var selectedCategory: MemoryCategory? = nil
    @State private var pinnedOnly = false

    @State private var moodDraft = ""
    @State private var relationDraft = ""

    @State private var showAddCore = false
    @State private var coreKey = ""
    @State private var coreValue = ""

    @State private var showAddEpisodic = false
    @State private var editingEpisodic: EpisodicMemory?
    @State private var epContent = ""
    @State private var epCategory: MemoryCategory = .event
    @State private var epImportance = 3
    @State private var epMood = "温暖"
    @State private var epPinned = false

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    public init(conversation: Conversation, character: CharacterCard) {
        self.conversation = conversation
        self.character = character
    }

    private var filteredEpisodic: [EpisodicMemory] {
        let raw = store.episodicMemoriesByCharacter[character.id] ?? []
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return raw.filter { mem in
            if pinnedOnly && !mem.isPinned { return false }
            if let cat = selectedCategory, mem.category != cat { return false }
            if !q.isEmpty && !mem.content.lowercased().contains(q) && !mem.mood.lowercased().contains(q) { return false }
            return true
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicNebulaBackdrop(palette: palette, accentHex: character.accentHex, animated: false)

                VStack(spacing: 12) {
                    Picker("记忆类型", selection: $tab) {
                        Text("关于我（核心档案）").tag(0)
                        Text("共同回忆录 (\((store.episodicMemoriesByCharacter[character.id] ?? []).count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if tab == 0 {
                        coreMemoryPanel
                    } else {
                        episodicMemoryPanel
                    }

                    Button {
                        ChlorHaptics.medium()
                        Task { await store.reflectMemories(for: conversation, character: character, silent: false) }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isReflectingMemory {
                                ProgressView().tint(.white)
                                Text("正在让 \(character.name) 珍藏最近的回忆…")
                            } else {
                                Image(systemName: "sparkles")
                                Text("立即整理刚才的对话入库")
                            }
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(palette.userBubble, in: Capsule())
                        .shadow(color: palette.accent.opacity(0.35), radius: 12, y: 5)
                    }
                    .disabled(store.isReflectingMemory || store.isGenerating)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("\(character.name) 的星光手账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if tab == 0 {
                            coreKey = ""
                            coreValue = ""
                            showAddCore = true
                        } else {
                            editingEpisodic = nil
                            epContent = ""
                            epCategory = .event
                            epImportance = 3
                            epMood = "温暖"
                            epPinned = false
                            showAddEpisodic = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .onAppear {
                moodDraft = character.moodLabel
                relationDraft = character.relationshipLabel
            }
            .sheet(isPresented: $showAddCore) {
                NavigationStack {
                    Form {
                        TextField("条目名（如：称呼 / 喜好 / 雷区 / 近况）", text: $coreKey)
                        TextField("内容", text: $coreValue, axis: .vertical).lineLimit(2...5)
                    }
                    .navigationTitle("核心档案条目")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showAddCore = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                Task {
                                    await store.upsertCoreMemory(characterId: character.id, key: coreKey, value: coreValue)
                                    showAddCore = false
                                }
                            }
                            .disabled(coreKey.isEmpty || coreValue.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showAddEpisodic) {
                NavigationStack {
                    Form {
                        Section("回忆内容") {
                            TextField("写下一段值得 TA 记住的事…", text: $epContent, axis: .vertical).lineLimit(3...6)
                        }
                        Section("属性") {
                            Picker("分类", selection: $epCategory) {
                                ForEach(MemoryCategory.allCases, id: \.self) { cat in
                                    Text(cat.displayName).tag(cat)
                                }
                            }
                            Stepper("重要度：\(epImportance) / 5", value: $epImportance, in: 1...5)
                            TextField("情绪标签", text: $epMood)
                            Toggle("置顶（永不遗忘）", isOn: $epPinned)
                        }
                    }
                    .navigationTitle(editingEpisodic == nil ? "新增共同回忆" : "编辑回忆")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showAddEpisodic = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                Task {
                                    await store.addOrUpdateEpisodicMemory(
                                        existing: editingEpisodic,
                                        characterId: character.id,
                                        content: epContent,
                                        category: epCategory,
                                        importance: epImportance,
                                        mood: epMood,
                                        isPinned: epPinned
                                    )
                                    showAddEpisodic = false
                                }
                            }
                            .disabled(epContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var coreMemoryPanel: some View {
        let items = store.coreMemoriesByCharacter[character.id] ?? []
        return ScrollView {
            VStack(spacing: 12) {
                // Live mood & relationship editor card
                VStack(alignment: .leading, spacing: 10) {
                    Text("此刻关系与心境")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.accent)
                    HStack(spacing: 10) {
                        TextField("关系阶段", text: $relationDraft)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                        TextField("当前心情", text: $moodDraft)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                        Button("更新") {
                            var updated = character
                            updated.relationshipLabel = relationDraft
                            updated.moodLabel = moodDraft
                            Task {
                                await store.saveCharacter(updated, createConversationIfMissing: false)
                                store.showToast("已更新关系与心境")
                            }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                    }
                }
                .padding(14)
                .liquidGlass(cornerRadius: 20, tint: Color(hex: character.accentHex), isDark: palette.isDark)

                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.key)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.accent)
                            Text(item.value)
                                .font(.subheadline)
                                .foregroundStyle(palette.primaryText)
                        }
                        Spacer()
                        Button {
                            coreKey = item.key
                            coreValue = item.value
                            showAddCore = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(palette.secondaryText)
                        }
                        Button(role: .destructive) {
                            Task { await store.deleteCoreMemory(item) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.8))
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 18, tint: palette.secondaryAccent, isDark: palette.isDark)
                }

                Text("核心档案会在每次聊天时常驻发给模型，保持精简（300 字以内）最能稳住“懂你”的体感。")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
        }
    }

    private var episodicMemoryPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondaryText)
                TextField("搜索回忆关键词或情绪…", text: $searchQuery)
                    .font(.subheadline)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark)
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "全部", active: selectedCategory == nil && !pinnedOnly) {
                        selectedCategory = nil
                        pinnedOnly = false
                    }
                    filterChip(title: "置顶", active: pinnedOnly) {
                        pinnedOnly.toggle()
                    }
                    ForEach(MemoryCategory.allCases, id: \.self) { cat in
                        filterChip(title: cat.displayName, active: selectedCategory == cat) {
                            selectedCategory = (selectedCategory == cat) ? nil : cat
                        }
                    }
                }
                .padding(.horizontal)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if filteredEpisodic.isEmpty {
                        ContentUnavailableView(
                            "暂无符合条件的回忆",
                            systemImage: "sparkles",
                            description: Text("聊满几轮会自动提炼，或者点击下方按钮立刻整理。")
                        )
                        .padding(.top, 24)
                    } else {
                        ForEach(filteredEpisodic) { mem in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    if mem.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                    Label(mem.category.displayName, systemImage: mem.category.iconName)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(palette.accent.opacity(0.18), in: Capsule())
                                        .foregroundStyle(palette.accent)
                                    Text(mem.mood)
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText)
                                    Spacer()
                                    Text(String(repeating: "★", count: mem.importance))
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                }

                                Text(mem.content)
                                    .font(.subheadline)
                                    .foregroundStyle(palette.primaryText)

                                HStack {
                                    Text(mem.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    Text("· 已想起 \(mem.recallCount) 次")
                                    Spacer()
                                    Button {
                                        Task { await store.togglePinMemory(mem) }
                                    } label: {
                                        Image(systemName: mem.isPinned ? "pin.slash" : "pin")
                                            .foregroundStyle(.orange)
                                    }
                                    Button {
                                        editingEpisodic = mem
                                        epContent = mem.content
                                        epCategory = mem.category
                                        epImportance = mem.importance
                                        epMood = mem.mood
                                        epPinned = mem.isPinned
                                        showAddEpisodic = true
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(palette.secondaryText)
                                    }
                                    Button(role: .destructive) {
                                        Task { await store.deleteEpisodicMemory(mem) }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryText)
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 18, tint: mem.isPinned ? .orange : palette.accent, isDark: palette.isDark)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
    }

    private func filterChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            ChlorHaptics.light()
            action()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? .white : palette.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if active {
                        Capsule().fill(palette.userBubble)
                    } else {
                        Capsule().fill(palette.surface)
                            .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.8))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI
import ChlorCore

public struct MemoryNotebookSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public let conversation: Conversation
    public let character: CharacterCard

    @State private var tab = 0
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

    public init(conversation: Conversation, character: CharacterCard) {
        self.conversation = conversation
        self.character = character
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("记忆类型", selection: $tab) {
                    Text("关于我（核心档案）").tag(0)
                    Text("共同回忆录").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if tab == 0 {
                    coreMemoryList
                } else {
                    episodicMemoryList
                }

                // Bottom reflect trigger
                Button {
                    Task { await store.reflectMemories(for: conversation, character: character, silent: false) }
                } label: {
                    HStack {
                        if store.isReflectingMemory {
                            ProgressView().tint(.white)
                            Text("正在让 \(character.name) 整理最近的回忆…")
                        } else {
                            Image(systemName: "sparkles")
                            Text("立即整理刚才的对话入库")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isReflectingMemory || store.isGenerating)
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .navigationTitle("\(character.name) 的回忆手账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
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
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddCore) {
                NavigationStack {
                    Form {
                        TextField("条目名（如：称呼 / 喜好 / 雷区 / 近况）", text: $coreKey)
                        TextField("内容", text: $coreValue, axis: .vertical)
                            .lineLimit(2...5)
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
                            TextField("写下一段值得 TA 记住的事…", text: $epContent, axis: .vertical)
                                .lineLimit(3...6)
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

    private var coreMemoryList: some View {
        let items = store.coreMemoriesByCharacter[character.id] ?? []
        return List {
            Section {
                ForEach(items) { item in
                    Button {
                        coreKey = item.key
                        coreValue = item.value
                        showAddCore = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.key)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(item.value)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await store.deleteCoreMemory(item) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("核心档案会在每次聊天时常驻发给模型，保持精简（300 字以内）效果最好。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var episodicMemoryList: some View {
        let items = store.episodicMemoriesByCharacter[character.id] ?? []
        return List {
            if items.isEmpty {
                ContentUnavailableView(
                    "还没有共同回忆",
                    systemImage: "book.closed",
                    description: Text("聊满几轮后会自动提炼，或者点击下方按钮立刻整理。")
                )
            } else {
                ForEach(items) { mem in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if mem.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Label(mem.category.displayName, systemImage: mem.category.iconName)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                            Text(mem.mood)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(repeating: "★", count: mem.importance))
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }

                        Text(mem.content)
                            .font(.subheadline)

                        HStack {
                            Text(mem.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text("已想起 \(mem.recallCount) 次")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingEpisodic = mem
                        epContent = mem.content
                        epCategory = mem.category
                        epImportance = mem.importance
                        epMood = mem.mood
                        epPinned = mem.isPinned
                        showAddEpisodic = true
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await store.togglePinMemory(mem) }
                        } label: {
                            Label(mem.isPinned ? "取消置顶" : "置顶", systemImage: mem.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await store.deleteEpisodicMemory(mem) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

import SwiftUI
import UniformTypeIdentifiers
import ChlorCore

public struct CompanionsHubView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    @State private var section = 0
    @State private var showNewCharacter = false
    @State private var editingCharacter: CharacterCard?
    @State private var showCardImporter = false

    @State private var showNewLorebook = false
    @State private var editingLorebook: LorebookEntry?

    @State private var showNewPersona = false
    @State private var editingPersona: Persona?

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode(rawValue: store.settings.themeMode) ?? .darkGlass, scheme: scheme)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("模块", selection: $section) {
                    Text("角色卡库").tag(0)
                    Text("世界书").tag(1)
                    Text("我的身份").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if section == 0 {
                    charactersList
                } else if section == 1 {
                    lorebookList
                } else {
                    personasList
                }
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("伴侣工坊")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if section == 0 {
                        Menu {
                            Button {
                                showNewCharacter = true
                            } label: {
                                Label("新建角色", systemImage: "person.badge.plus")
                            }
                            Button {
                                showCardImporter = true
                            } label: {
                                Label("导入 V2 角色卡 (JSON/PNG)", systemImage: "square.and.arrow.down")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(palette.accent)
                        }
                    } else if section == 1 {
                        Button {
                            showNewLorebook = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(palette.accent)
                        }
                    } else {
                        Button {
                            showNewPersona = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewCharacter) {
                NavigationStack { CharacterEditorView(character: nil) }
            }
            .sheet(item: $editingCharacter) { char in
                NavigationStack { CharacterEditorView(character: char) }
            }
            .sheet(isPresented: $showNewLorebook) {
                NavigationStack { LorebookEditorView(entry: nil) }
            }
            .sheet(item: $editingLorebook) { entry in
                NavigationStack { LorebookEditorView(entry: entry) }
            }
            .sheet(isPresented: $showNewPersona) {
                NavigationStack { PersonaEditorView(persona: nil) }
            }
            .sheet(item: $editingPersona) { p in
                NavigationStack { PersonaEditorView(persona: p) }
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
        }
    }

    private var charactersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.characters) { char in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: char.accentHex).opacity(0.22))
                                    .frame(width: 48, height: 48)
                                Image(systemName: char.avatarSymbol)
                                    .font(.title3)
                                    .foregroundStyle(Color(hex: char.accentHex))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(char.name).font(.headline)
                                    Text(char.relationshipLabel)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: char.accentHex).opacity(0.16), in: Capsule())
                                        .foregroundStyle(Color(hex: char.accentHex))
                                }
                                Text(char.tagline.isEmpty ? char.personality : char.tagline)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("编辑") {
                                editingCharacter = char
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(palette.accent)
                        }
                    }
                    .padding(14)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.border, lineWidth: 1))
                }
            }
            .padding(16)
        }
    }

    private var lorebookList: some View {
        List {
            if store.lorebooks.isEmpty {
                ContentUnavailableView(
                    "暂无世界书设定",
                    systemImage: "books.vertical",
                    description: Text("添加关键词触发式背景设定（如宠物、老家、共同秘密），聊天提到对应词时才注入上下文，省 Token 又防忘设定。")
                )
            } else {
                ForEach(store.lorebooks) { entry in
                    Button {
                        editingLorebook = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.title).font(.headline).foregroundStyle(.primary)
                                Spacer()
                                if entry.alwaysActive {
                                    Text("常驻")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                                Text(entry.isEnabled ? "已启用" : "停用")
                                    .font(.caption2)
                                    .foregroundStyle(entry.isEnabled ? .green : .secondary)
                            }
                            if !entry.keywords.isEmpty {
                                Text("关键词：\(entry.keywords.joined(separator: " / "))")
                                    .font(.caption)
                                    .foregroundStyle(palette.accent)
                            }
                            Text(entry.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await store.deleteLorebook(entry) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var personasList: some View {
        List {
            ForEach(store.personas) { persona in
                Button {
                    editingPersona = persona
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(persona.name).font(.headline).foregroundStyle(.primary)
                            if persona.isDefault {
                                Text("默认")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.accent.opacity(0.2), in: Capsule())
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        if !persona.nicknameForAI.isEmpty {
                            Text("希望伴侣称呼：\(persona.nicknameForAI)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !persona.bio.isEmpty {
                            Text(persona.bio)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .swipeActions {
                    if store.personas.count > 1 {
                        Button(role: .destructive) {
                            Task { await store.deletePersona(persona) }
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

import SwiftUI
import UniformTypeIdentifiers
import ChlorCore

public struct CompanionsHubView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    @State private var section = 0
    @State private var showNewCharacter = false
    @State private var showTemplateGallery = false
    @State private var editingCharacter: CharacterCard?
    @State private var showCardImporter = false

    @State private var showNewLorebook = false
    @State private var editingLorebook: LorebookEntry?

    @State private var showNewPersona = false
    @State private var editingPersona: Persona?

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicNebulaBackdrop(palette: palette)

                VStack(spacing: 12) {
                    headerBar
                    liquidSegmentBar

                    ScrollView {
                        Group {
                            if section == 0 {
                                charactersGallery
                            } else if section == 1 {
                                lorebookGallery
                            } else {
                                personasGallery
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 110)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNewCharacter) {
                NavigationStack { CharacterEditorView(character: nil) }
            }
            .sheet(isPresented: $showTemplateGallery) {
                CompanionTemplateGallerySheet()
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

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("伴侣工坊")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Text("雕琢灵魂人设、世界书与你的平行身份")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()

            if section == 0 {
                Menu {
                    Button {
                        showTemplateGallery = true
                    } label: {
                        Label("伴侣模板广场", systemImage: "sparkles")
                    }
                    Button {
                        showNewCharacter = true
                    } label: {
                        Label("从零新建伴侣", systemImage: "person.badge.plus")
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
            } else {
                Button {
                    if section == 1 { showNewLorebook = true } else { showNewPersona = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 44, height: 44)
                        .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var liquidSegmentBar: some View {
        HStack(spacing: 6) {
            segmentPill("角色卡库", index: 0)
            segmentPill("世界书", index: 1)
            segmentPill("我的身份", index: 2)
        }
        .padding(5)
        .liquidGlassCapsule(tint: palette.secondaryAccent, isDark: palette.isDark)
        .padding(.horizontal, 16)
    }

    private func segmentPill(_ title: String, index: Int) -> some View {
        let active = section == index
        return Button {
            ChlorHaptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                section = index
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(active ? .bold : .medium))
                .foregroundStyle(active ? .white : palette.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if active {
                        Capsule().fill(palette.userBubble)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var charactersGallery: some View {
        LazyVStack(spacing: 14) {
            // Template Banner
            Button {
                ChlorHaptics.light()
                showTemplateGallery = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("探索精选伴侣模板")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryText)
                        Text("内置 4 位精调性格与示例对话的伴侣，一键迎接开聊")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(14)
                .liquidGlass(cornerRadius: 20, tint: palette.secondaryAccent, isDark: palette.isDark)
            }
            .buttonStyle(.plain)

            ForEach(store.characters) { char in
                let accent = Color(hex: char.accentHex)
                let memCount = (store.episodicMemoriesByCharacter[char.id] ?? []).count

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        CompanionAvatarView(
                            symbol: char.avatarSymbol,
                            imageFileName: char.avatarImageFileName,
                            accentHex: char.accentHex,
                            size: 56
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(char.name)
                                    .font(.headline)
                                    .foregroundStyle(palette.primaryText)
                                Text(char.relationshipLabel)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(accent.opacity(0.20), in: Capsule())
                                    .foregroundStyle(accent)
                            }
                            Text(char.tagline.isEmpty ? char.personality : char.tagline)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Label("\(memCount) 条回忆", systemImage: "sparkles")
                        if char.autoSpeakReplies {
                            Label("自动语音", systemImage: "speaker.wave.2.fill")
                        }
                        Spacer()
                        Button {
                            editingCharacter = char
                        } label: {
                            Text("定制人设")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(accent.opacity(0.16), in: Capsule())
                                .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 0.8))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 24, tint: accent, isDark: palette.isDark)
            }
        }
    }

    private var lorebookGallery: some View {
        LazyVStack(spacing: 12) {
            if store.lorebooks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.largeTitle)
                        .foregroundStyle(palette.accent)
                    Text("暂无世界书设定")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Text("添加关键词触发式背景设定（如宠物、老家、共同秘密），聊天提到对应词时才注入上下文，省 Token 又防忘设定。")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .liquidGlass(cornerRadius: 24, tint: palette.accent, isDark: palette.isDark)
            } else {
                ForEach(store.lorebooks) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.title)
                                .font(.headline)
                                .foregroundStyle(palette.primaryText)
                            Spacer()
                            if entry.alwaysActive {
                                Text("常驻")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.22), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            Text(entry.isEnabled ? "启用" : "停用")
                                .font(.caption2)
                                .foregroundStyle(entry.isEnabled ? .green : palette.secondaryText)
                        }
                        if !entry.keywords.isEmpty {
                            Text("触发词：\(entry.keywords.joined(separator: " / "))")
                                .font(.caption)
                                .foregroundStyle(palette.accent)
                        }
                        Text(entry.content)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(3)

                        HStack {
                            Spacer()
                            Button("编辑") { editingLorebook = entry }
                                .font(.caption.bold())
                                .foregroundStyle(palette.accent)
                            Button("删除", role: .destructive) {
                                Task { await store.deleteLorebook(entry) }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 20, tint: palette.secondaryAccent, isDark: palette.isDark)
                }
            }
        }
    }

    private var personasGallery: some View {
        LazyVStack(spacing: 12) {
            ForEach(store.personas) { persona in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(persona.name)
                            .font(.headline)
                            .foregroundStyle(palette.primaryText)
                        if persona.isDefault {
                            Text("默认身份")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(palette.accent.opacity(0.22), in: Capsule())
                                .foregroundStyle(palette.accent)
                        }
                        Spacer()
                        Button("编辑") { editingPersona = persona }
                            .font(.caption.bold())
                            .foregroundStyle(palette.accent)
                    }
                    if !persona.nicknameForAI.isEmpty {
                        Text("伴侣称呼：\(persona.nicknameForAI)")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    if !persona.bio.isEmpty {
                        Text(persona.bio)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .padding(14)
                .liquidGlass(cornerRadius: 20, tint: palette.accent, isDark: palette.isDark)
            }
        }
    }
}

public struct CompanionTemplateGallerySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicNebulaBackdrop(palette: palette)

                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(DefaultsFactory.companionTemplates()) { tpl in
                            let accent = Color(hex: tpl.accentHex)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    CompanionAvatarView(symbol: tpl.avatarSymbol, accentHex: tpl.accentHex, size: 52)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(tpl.name).font(.headline).foregroundStyle(palette.primaryText)
                                            Text(tpl.relationshipLabel)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(accent.opacity(0.22), in: Capsule())
                                                .foregroundStyle(accent)
                                        }
                                        Text(tpl.tagline)
                                            .font(.caption)
                                            .foregroundStyle(palette.secondaryText)
                                    }
                                    Spacer()
                                }

                                Text(tpl.personality)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(3)

                                Button {
                                    Task {
                                        await store.instantiateTemplate(tpl)
                                        dismiss()
                                    }
                                } label: {
                                    Text("迎接 \(tpl.name) 进入对话")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(palette.userBubble, in: Capsule())
                                }
                            }
                            .padding(16)
                            .liquidGlass(cornerRadius: 22, tint: accent, isDark: palette.isDark)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("伴侣模板广场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
        }
    }
}

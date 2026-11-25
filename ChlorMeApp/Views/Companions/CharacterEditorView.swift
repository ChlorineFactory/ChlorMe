import SwiftUI
import ChlorCore

public struct CharacterEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public let character: CharacterCard?

    @State private var name = ""
    @State private var tagline = ""
    @State private var relationshipLabel = "亲密伙伴"
    @State private var moodLabel = "温和"
    @State private var avatarSymbol = "moon.stars.fill"
    @State private var accentHex = "#64D2FF"
    @State private var wallpaperStyle = "aurora"
    @State private var personality = ""
    @State private var speakingStyle = ""
    @State private var scenario = ""
    @State private var firstMessage = ""
    @State private var exampleDialogue = ""
    @State private var systemOverride = ""
    @State private var postHistoryInstruction = ""
    @State private var defaultModelId = ""
    @State private var defaultPresetId = ""
    @State private var defaultPersonaId = ""
    @State private var bubbleSplitEnabled = true
    @State private var exportedCardURL: URL?

    private let symbolOptions = ["moon.stars.fill", "sparkles", "heart.fill", "cat.fill", "leaf.fill", "flame.fill", "cloud.moon.fill", "music.note"]
    private let colorOptions = ["#64D2FF", "#5EEAD4", "#FF7EB6", "#FFB86C", "#A78BFA", "#4ADE80"]
    private let wallpaperOptions = [("aurora", "极光渐变"), ("sunset", "晚霞微光"), ("forest", "静谧森林"), ("plain", "纯净极简")]

    public init(character: CharacterCard?) {
        self.character = character
    }

    public var body: some View {
        Form {
            Section("基础形象") {
                TextField("伴侣名字", text: $name)
                TextField("一句话简介", text: $tagline)
                TextField("关系标签（如：恋人 / 深夜挚友 / 青梅竹马）", text: $relationshipLabel)
                TextField("当前情绪", text: $moodLabel)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(symbolOptions, id: \.self) { sym in
                            Button {
                                avatarSymbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(avatarSymbol == sym ? Color(hex: accentHex).opacity(0.25) : Color.secondary.opacity(0.12), in: Circle())
                                    .foregroundStyle(avatarSymbol == sym ? Color(hex: accentHex) : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 12) {
                    Text("主题色").font(.subheadline)
                    Spacer()
                    ForEach(colorOptions, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.white, lineWidth: accentHex == hex ? 2.5 : 0))
                            .onTapGesture { accentHex = hex }
                    }
                }

                Picker("聊天壁纸", selection: $wallpaperStyle) {
                    ForEach(wallpaperOptions, id: \.0) { opt in
                        Text(opt.1).tag(opt.0)
                    }
                }
                Toggle("微信式多段气泡", isOn: $bubbleSplitEnabled)
            }

            Section("人设与说话风格") {
                LabeledTextEditor(title: "性格与背景", text: $personality, minHeight: 80)
                LabeledTextEditor(title: "说话风格 / 口癖", text: $speakingStyle, minHeight: 70)
                LabeledTextEditor(title: "相遇情境 (Scenario)", text: $scenario, minHeight: 55)
                LabeledTextEditor(title: "开场白 (First Message)", text: $firstMessage, minHeight: 75)
                LabeledTextEditor(title: "示例对话 (Few-shot，稳人设神器)", text: $exampleDialogue, minHeight: 90)
            }

            Section("默认模型与参数绑定") {
                Picker("默认模型", selection: $defaultModelId) {
                    Text("自动选择").tag("")
                    ForEach(store.models) { m in
                        Text(m.name).tag(m.id)
                    }
                }
                Picker("默认采样预设", selection: $defaultPresetId) {
                    Text("默认预设").tag("")
                    ForEach(store.presets) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                Picker("绑定我的身份", selection: $defaultPersonaId) {
                    Text("默认身份").tag("")
                    ForEach(store.personas) { p in
                        Text(p.name).tag(p.id)
                    }
                }
            }

            Section("高级指令覆盖（可选）") {
                LabeledTextEditor(title: "System Prompt 覆盖（留空则使用全局）", text: $systemOverride, minHeight: 60)
                LabeledTextEditor(title: "末尾防 OOC 提醒 (Post-History)", text: $postHistoryInstruction, minHeight: 55)
            }

            if let existing = character {
                Section("分享与管理") {
                    if let url = exportedCardURL {
                        ShareLink(item: url) {
                            Label("分享角色卡 JSON 文件", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("生成 V2 角色卡 JSON 导出") {
                            if let data = try? CharacterCardV2Codec.exportJSON(character: existing) {
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(existing.name)-card-v2.json")
                                try? data.write(to: url)
                                exportedCardURL = url
                            }
                        }
                    }

                    if store.characters.count > 1 {
                        Button(role: .destructive) {
                            Task {
                                await store.deleteCharacter(existing)
                                dismiss()
                            }
                        } label: {
                            Label("删除此伴侣及所有聊天记录", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(character == nil ? "创建新伴侣" : "编辑 \(character!.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let card = CharacterCard(
                        id: character?.id ?? UUID().uuidString,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        avatarSymbol: avatarSymbol,
                        accentHex: accentHex,
                        tagline: tagline,
                        personality: personality,
                        speakingStyle: speakingStyle,
                        scenario: scenario,
                        firstMessage: firstMessage,
                        exampleDialogue: exampleDialogue,
                        systemOverride: systemOverride,
                        postHistoryInstruction: postHistoryInstruction,
                        moodLabel: moodLabel,
                        relationshipLabel: relationshipLabel,
                        wallpaperStyle: wallpaperStyle,
                        defaultModelId: defaultModelId.isEmpty ? nil : defaultModelId,
                        defaultPresetId: defaultPresetId.isEmpty ? nil : defaultPresetId,
                        defaultPersonaId: defaultPersonaId.isEmpty ? nil : defaultPersonaId,
                        bubbleSplitEnabled: bubbleSplitEnabled,
                        createdAt: character?.createdAt ?? Date()
                    )
                    Task {
                        await store.saveCharacter(card, createConversationIfMissing: true)
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            guard let c = character else { return }
            name = c.name
            tagline = c.tagline
            relationshipLabel = c.relationshipLabel
            moodLabel = c.moodLabel
            avatarSymbol = c.avatarSymbol
            accentHex = c.accentHex
            wallpaperStyle = c.wallpaperStyle
            personality = c.personality
            speakingStyle = c.speakingStyle
            scenario = c.scenario
            firstMessage = c.firstMessage
            exampleDialogue = c.exampleDialogue
            systemOverride = c.systemOverride
            postHistoryInstruction = c.postHistoryInstruction
            defaultModelId = c.defaultModelId ?? ""
            defaultPresetId = c.defaultPresetId ?? ""
            defaultPersonaId = c.defaultPersonaId ?? ""
            bubbleSplitEnabled = c.bubbleSplitEnabled
        }
    }
}

struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

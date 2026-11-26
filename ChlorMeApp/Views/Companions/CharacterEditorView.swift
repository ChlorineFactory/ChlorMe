import SwiftUI
import PhotosUI
import AVFoundation
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
    @State private var avatarImageFileName: String?
    @State private var accentHex = "#5CF6E3"
    @State private var wallpaperStyle = "cosmic"
    @State private var wallpaperImageFileName: String?
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

    // Voice customization
    @State private var voiceIdentifier = ""
    @State private var voiceRate = 0.50
    @State private var voicePitch = 1.05
    @State private var autoSpeakReplies = false

    // Photo pickers
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var wallpaperPickerItem: PhotosPickerItem?
    @State private var exportedCardURL: URL?

    private let symbolOptions = ["moon.stars.fill", "sparkles", "heart.fill", "cat.fill", "atom", "flame.fill", "cloud.moon.fill", "music.note"]
    private let colorOptions = ["#5CF6E3", "#64D2FF", "#B794F6", "#FF7AC6", "#FFB86C", "#4ADE80"]
    private let wallpaperOptions = [("cosmic", "流动宇宙星云"), ("aurora", "极光流影"), ("sunset", "晚霞微光"), ("forest", "静谧森林"), ("plain", "纯净极简")]

    public init(character: CharacterCard?) {
        self.character = character
    }

    public var body: some View {
        Form {
            Section("专属头像与视觉形象") {
                HStack(spacing: 16) {
                    CompanionAvatarView(
                        symbol: avatarSymbol,
                        imageFileName: avatarImageFileName,
                        accentHex: accentHex,
                        size: 64
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                            Label("从相册选择照片头像", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.semibold))
                        }
                        if avatarImageFileName != nil {
                            Button("恢复为星光符号头像", role: .destructive) {
                                avatarImageFileName = nil
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)

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
                    Text("伴侣光晕色").font(.subheadline)
                    Spacer()
                    ForEach(colorOptions, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.white, lineWidth: accentHex == hex ? 2.5 : 0))
                            .onTapGesture { accentHex = hex }
                    }
                }

                Picker("内置动态壁纸", selection: $wallpaperStyle) {
                    ForEach(wallpaperOptions, id: \.0) { opt in
                        Text(opt.1).tag(opt.0)
                    }
                }

                HStack {
                    PhotosPicker(selection: $wallpaperPickerItem, matching: .images) {
                        Label(wallpaperImageFileName == nil ? "从相册设置专属聊天壁纸" : "更换相册聊天壁纸", systemImage: "photo.fill")
                    }
                    if wallpaperImageFileName != nil {
                        Spacer()
                        Button("清除", role: .destructive) {
                            wallpaperImageFileName = nil
                        }
                        .font(.caption)
                    }
                }

                Toggle("微信式多段气泡", isOn: $bubbleSplitEnabled)
            }

            Section("专属声音朗读 (TTS)") {
                Picker("中文音色", selection: $voiceIdentifier) {
                    Text("系统默认中文").tag("")
                    ForEach(VoiceService.availableChineseVoices(), id: \.identifier) { v in
                        Text("\(v.name) (\(v.language))").tag(v.identifier)
                    }
                }
                SliderRow(title: "语速", value: $voiceRate, range: 0.35...0.62, format: "%.2f")
                SliderRow(title: "音调", value: $voicePitch, range: 0.80...1.30, format: "%.2f")
                Toggle("收到回复自动朗读", isOn: $autoSpeakReplies)
                Button {
                    store.voiceService.speak(
                        text: firstMessage.isEmpty ? "你好呀，我是\(name.isEmpty ? "你的专属伴侣" : name)，很高兴见到你。" : firstMessage,
                        messageId: nil,
                        voiceIdentifier: voiceIdentifier.isEmpty ? nil : voiceIdentifier,
                        rate: voiceRate,
                        pitch: voicePitch
                    )
                } label: {
                    Label("试听当前声线", systemImage: "speaker.wave.2.fill")
                }
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
                        avatarImageFileName: avatarImageFileName,
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
                        wallpaperImageFileName: wallpaperImageFileName,
                        defaultModelId: defaultModelId.isEmpty ? nil : defaultModelId,
                        defaultPresetId: defaultPresetId.isEmpty ? nil : defaultPresetId,
                        defaultPersonaId: defaultPersonaId.isEmpty ? nil : defaultPersonaId,
                        bubbleSplitEnabled: bubbleSplitEnabled,
                        voiceIdentifier: voiceIdentifier.isEmpty ? nil : voiceIdentifier,
                        voiceRate: voiceRate,
                        voicePitch: voicePitch,
                        autoSpeakReplies: autoSpeakReplies,
                        createdAt: character?.createdAt ?? Date()
                    )
                    Task {
                        await store.saveCharacter(card, createConversationIfMissing: true)
                        ChlorHaptics.success()
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: avatarPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let saved = MediaStorage.saveImageData(data, maxDimension: 512, quality: 0.85) {
                    avatarImageFileName = saved
                }
            }
        }
        .onChange(of: wallpaperPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let saved = MediaStorage.saveImageData(data, maxDimension: 1440, quality: 0.82) {
                    wallpaperImageFileName = saved
                }
            }
        }
        .onAppear {
            guard let c = character else { return }
            name = c.name
            tagline = c.tagline
            relationshipLabel = c.relationshipLabel
            moodLabel = c.moodLabel
            avatarSymbol = c.avatarSymbol
            avatarImageFileName = c.avatarImageFileName
            accentHex = c.accentHex
            wallpaperStyle = c.wallpaperStyle
            wallpaperImageFileName = c.wallpaperImageFileName
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
            voiceIdentifier = c.voiceIdentifier ?? ""
            voiceRate = c.voiceRate
            voicePitch = c.voicePitch
            autoSpeakReplies = c.autoSpeakReplies
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

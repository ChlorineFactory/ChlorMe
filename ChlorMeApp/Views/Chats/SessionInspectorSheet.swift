import SwiftUI
import ChlorCore

public struct SessionInspectorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public let conversation: Conversation
    public let character: CharacterCard

    @State private var selectedModelId: String = ""
    @State private var selectedPresetId: String = ""
    @State private var selectedPersonaId: String = ""
    @State private var sessionTitle: String = ""
    @State private var bubbleSplit: Bool = true
    @State private var autoSpeak: Bool = false
    @State private var showPromptDebug = false
    @State private var showClearConfirm = false
    @State private var transcriptURL: URL?

    public init(conversation: Conversation, character: CharacterCard) {
        self.conversation = conversation
        self.character = character
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("会话名称与绑定") {
                    TextField("会话标题", text: $sessionTitle)

                    Picker("推理模型", selection: $selectedModelId) {
                        Text("跟随默认").tag("")
                        ForEach(store.models) { model in
                            Text("\(model.name) (\(model.backendKind == .localGGUF ? model.quantizationLabel : "API"))")
                                .tag(model.id)
                        }
                    }

                    Picker("采样参数预设", selection: $selectedPresetId) {
                        Text("跟随默认").tag("")
                        ForEach(store.presets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }

                    Picker("我的身份 (Persona)", selection: $selectedPersonaId) {
                        Text("跟随默认").tag("")
                        ForEach(store.personas) { persona in
                            Text(persona.name).tag(persona.id)
                        }
                    }

                    Toggle("微信式多段气泡拆分", isOn: $bubbleSplit)
                    Toggle("收到回复自动语音朗读", isOn: $autoSpeak)
                }

                if let activePreset = store.presets.first(where: { $0.id == (selectedPresetId.isEmpty ? (character.defaultPresetId ?? store.presets.first?.id) : selectedPresetId) }) {
                    Section("当前预设参数速览") {
                        LabeledContent("Temperature", value: String(format: "%.2f", activePreset.temperature))
                        LabeledContent("Min-P / Top-P", value: String(format: "%.2f / %.2f", activePreset.minP, activePreset.topP))
                        LabeledContent("Repeat Penalty", value: String(format: "%.2f (last %d)", activePreset.repeatPenalty, activePreset.repeatLastN))
                        LabeledContent("DRY 防复读", value: activePreset.dryMultiplier > 0 ? String(format: "%.2f", activePreset.dryMultiplier) : "已关闭")
                        LabeledContent("最大输出 Tokens", value: "\(activePreset.maxTokens)")
                    }
                }

                Section("实时 Prompt 透视（调试神器）") {
                    if let snap = store.lastAssembledPrompt {
                        LabeledContent("估算输入 Tokens", value: "\(snap.estimatedTotalTokens) / \(snap.tokenBudget)")
                        LabeledContent("触发世界书", value: snap.triggeredLorebooks.isEmpty ? "无" : snap.triggeredLorebooks.map(\.title).joined(separator: "、"))
                        LabeledContent("召回共同回忆", value: "\(snap.recalledMemories.count) 条")

                        DisclosureGroup("查看完整模块拆分", isExpanded: $showPromptDebug) {
                            ForEach(snap.sections) { sec in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(sec.title).font(.caption.bold())
                                        Spacer()
                                        Text("~\(sec.estimatedTokens) tok")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(sec.content)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else {
                        Text("发送一条消息后，可在此透视发给模型的完整上下文、召回记忆和世界书命中情况。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("会话导出与平行线") {
                    if let url = transcriptURL {
                        ShareLink(item: url) {
                            Label("分享 Markdown 聊天日记", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            transcriptURL = store.createTranscriptFileURL(conversation: conversation, character: character)
                        } label: {
                            Label("导出本段对话为 Markdown 日记", systemImage: "doc.text")
                        }
                    }

                    Button {
                        Task {
                            _ = await store.createNewConversation(for: character)
                            store.showToast("已为 \(character.name) 新开平行会话")
                            dismiss()
                        }
                    } label: {
                        Label("新开一条平行宇宙会话", systemImage: "plus.bubble")
                    }

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清空本段对话记录（保留共同回忆）", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("会话调校与透视")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        var updatedConv = conversation
                        updatedConv.title = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? character.name : sessionTitle
                        updatedConv.modelIdOverride = selectedModelId.isEmpty ? nil : selectedModelId
                        updatedConv.presetIdOverride = selectedPresetId.isEmpty ? nil : selectedPresetId
                        updatedConv.personaId = selectedPersonaId.isEmpty ? nil : selectedPersonaId

                        var updatedChar = character
                        updatedChar.bubbleSplitEnabled = bubbleSplit
                        updatedChar.autoSpeakReplies = autoSpeak

                        Task {
                            await store.updateConversation(updatedConv)
                            await store.saveCharacter(updatedChar, createConversationIfMissing: false)
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog("确定清空本段对话？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空对话（保留回忆）", role: .destructive) {
                    Task {
                        await store.clearMessages(in: conversation, character: character)
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear {
                sessionTitle = conversation.title
                selectedModelId = conversation.modelIdOverride ?? ""
                selectedPresetId = conversation.presetIdOverride ?? ""
                selectedPersonaId = conversation.personaId ?? ""
                bubbleSplit = character.bubbleSplitEnabled
                autoSpeak = character.autoSpeakReplies
            }
        }
    }
}

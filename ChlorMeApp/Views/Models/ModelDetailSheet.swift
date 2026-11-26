import SwiftUI
import ChlorCore

public struct ModelDetailSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ModelConfig

    public init(model: ModelConfig) {
        _draft = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("显示名称", text: $draft.name)
                    LabeledContent("后端类型", value: draft.backendKind.displayName)
                }

                if draft.backendKind == .localGGUF {
                    Section("本地推理硬件参数") {
                        Picker("上下文长度 (Context)", selection: $draft.contextLength) {
                            Text("2048").tag(2048)
                            Text("4096").tag(4096)
                            Text("8192（17 Pro 推荐）").tag(8192)
                            Text("12288").tag(12288)
                            Text("16384").tag(16384)
                        }

                        Picker("KV Cache 量化", selection: $draft.kvQuantType) {
                            ForEach(KVCacheQuantType.allCases, id: \.self) { q in
                                Text(q.displayName).tag(q)
                            }
                        }

                        Stepper("Metal GPU 层数：\(draft.gpuLayers)", value: $draft.gpuLayers, in: 0...120, step: 1)

                        Picker("对话模板 (Chat Template)", selection: $draft.chatTemplate) {
                            ForEach(ChatTemplateStyle.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }

                        LabeledContent("预计总内存占用", value: MemoryBudgetAdvisor.formatBytes(draft.estimatedMemoryBytes))
                    }
                } else {
                    Section("远程接口配置 (\(draft.backendKind.displayName))") {
                        Picker("协议类型", selection: $draft.backendKind) {
                            Text("OpenAI 兼容").tag(ModelBackendKind.openAICompatible)
                            Text("Anthropic Claude").tag(ModelBackendKind.anthropic)
                            Text("Google Gemini").tag(ModelBackendKind.gemini)
                        }

                        TextField("Base URL", text: Binding(
                            get: { draft.apiBaseURL ?? "" },
                            set: { draft.apiBaseURL = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        TextField("Remote Model ID", text: Binding(
                            get: { draft.remoteModelName ?? "" },
                            set: { draft.remoteModelName = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        SecureField("API Key", text: Binding(
                            get: { draft.apiKey ?? "" },
                            set: { draft.apiKey = $0 }
                        ))

                        TextField("自定义 Headers JSON（可选）", text: Binding(
                            get: { draft.customHeadersJSON ?? "" },
                            set: { draft.customHeadersJSON = $0.isEmpty ? nil : $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption.monospaced())

                        Picker("上下文预算", selection: $draft.contextLength) {
                            Text("8192").tag(8192)
                            Text("16384").tag(16384)
                            Text("32768").tag(32768)
                            Text("65536").tag(65536)
                        }
                    }
                }
            }
            .navigationTitle("模型配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await store.saveModel(draft)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

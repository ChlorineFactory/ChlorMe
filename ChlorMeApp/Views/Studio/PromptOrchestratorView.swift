import SwiftUI
import ChlorCore

public struct PromptOrchestratorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var blocks: [PromptBlock] = []
    @State private var editingBlock: PromptBlock?

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach($blocks) { $block in
                    HStack(spacing: 12) {
                        Toggle("", isOn: $block.isEnabled)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.kind.title)
                                .font(.subheadline.weight(.semibold))
                            if !block.customTemplate.isEmpty {
                                Text(block.customTemplate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if block.kind == .systemCore || block.kind == .postHistory {
                            Button("模板") {
                                editingBlock = block
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .onMove { source, destination in
                    blocks.move(fromOffsets: source, toOffset: destination)
                    persist()
                }
            } header: {
                Text("拖拽右侧手柄即可自由调整发给模型的 Prompt 顺序")
            } footer: {
                Text("提示：把「示例对话」与「末尾防出戏」留在靠后位置，能显著提升 3B~8B 小模型的人设稳定度。")
            }

            Section {
                Button("恢复默认编排顺序", role: .destructive) {
                    blocks = DefaultsFactory.defaultPromptBlocks()
                    persist()
                }
            }
        }
        .navigationTitle("Prompt 编排器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onAppear {
            blocks = store.settings.promptBlocks
        }
        .onChange(of: blocks) { _, _ in
            persist()
        }
        .sheet(item: $editingBlock) { block in
            BlockTemplateSheet(block: block) { newTemplate in
                if let idx = blocks.firstIndex(where: { $0.id == block.id }) {
                    blocks[idx].customTemplate = newTemplate
                    persist()
                }
            }
        }
    }

    private func persist() {
        var s = store.settings
        s.promptBlocks = blocks
        Task { await store.saveSettings(s) }
    }
}

private struct BlockTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let block: PromptBlock
    let onSave: (String) -> Void
    @State private var text: String

    init(block: PromptBlock, onSave: @escaping (String) -> Void) {
        self.block = block
        self.onSave = onSave
        _text = State(initialValue: block.customTemplate)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(block.kind.title).font(.headline)
                TextEditor(text: $text)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
            }
            .padding()
            .navigationTitle("编辑模块提示词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

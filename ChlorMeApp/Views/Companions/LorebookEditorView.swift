import SwiftUI
import ChlorCore

public struct LorebookEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public let entry: LorebookEntry?

    @State private var title = ""
    @State private var keywordsText = ""
    @State private var content = ""
    @State private var characterId = ""
    @State private var priority = 50
    @State private var alwaysActive = false
    @State private var isEnabled = true

    public init(entry: LorebookEntry?) {
        self.entry = entry
    }

    public var body: some View {
        Form {
            Section("触发条件") {
                TextField("条目名称（如：橘猫汤圆 / 老家小镇）", text: $title)
                TextField("触发关键词（用逗号分隔，如：汤圆,橘猫,猫）", text: $keywordsText)
                Picker("适用范围", selection: $characterId) {
                    Text("全局（所有伴侣共享）").tag("")
                    ForEach(store.characters) { c in
                        Text("仅 \(c.name)").tag(c.id)
                    }
                }
                Toggle("常驻注入（无需触发词）", isOn: $alwaysActive)
                Toggle("启用此条目", isOn: $isEnabled)
                Stepper("优先级：\(priority)", value: $priority, in: 1...100, step: 5)
            }

            Section("设定正文") {
                TextEditor(text: $content)
                    .frame(minHeight: 120)
            }
        }
        .navigationTitle(entry == nil ? "新增世界书" : "编辑世界书")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let kws = keywordsText
                        .replacingOccurrences(of: "，", with: ",")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let model = LorebookEntry(
                        id: entry?.id ?? UUID().uuidString,
                        characterId: characterId.isEmpty ? nil : characterId,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        keywords: kws,
                        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                        priority: priority,
                        alwaysActive: alwaysActive,
                        isEnabled: isEnabled,
                        createdAt: entry?.createdAt ?? Date()
                    )
                    Task {
                        await store.saveLorebook(model)
                        dismiss()
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            guard let entry else { return }
            title = entry.title
            keywordsText = entry.keywords.joined(separator: ", ")
            content = entry.content
            characterId = entry.characterId ?? ""
            priority = entry.priority
            alwaysActive = entry.alwaysActive
            isEnabled = entry.isEnabled
        }
    }
}

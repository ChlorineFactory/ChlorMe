import SwiftUI
import ChlorCore

public struct PersonaEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public let persona: Persona?

    @State private var name = ""
    @State private var nicknameForAI = ""
    @State private var bio = ""
    @State private var isDefault = false

    public init(persona: Persona?) {
        self.persona = persona
    }

    public var body: some View {
        Form {
            Section("我的身份设定") {
                TextField("身份名称（如：日常的我 / 赛博旅人）", text: $name)
                TextField("希望伴侣怎么称呼你", text: $nicknameForAI)
                Toggle("设为全局默认身份", isOn: $isDefault)
            }

            Section("个人简介（会告知伴侣）") {
                TextEditor(text: $bio)
                    .frame(minHeight: 110)
            }
        }
        .navigationTitle(persona == nil ? "新增身份" : "编辑身份")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let model = Persona(
                        id: persona?.id ?? UUID().uuidString,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        nicknameForAI: nicknameForAI.trimmingCharacters(in: .whitespacesAndNewlines),
                        bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                        isDefault: isDefault,
                        createdAt: persona?.createdAt ?? Date()
                    )
                    Task {
                        await store.savePersona(model)
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            guard let persona else { return }
            name = persona.name
            nicknameForAI = persona.nicknameForAI
            bio = persona.bio
            isDefault = persona.isDefault
        }
    }
}

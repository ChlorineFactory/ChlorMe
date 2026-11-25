import SwiftUI
import ChlorCore

public struct SamplerPresetEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SamplerPreset
    @State private var stopText: String

    public init(preset: SamplerPreset?) {
        let initial = preset ?? SamplerPreset(name: "我的自定义预设", summary: "自由调校的采样方案")
        _draft = State(initialValue: initial)
        _stopText = State(initialValue: initial.stopSequences.joined(separator: ", "))
    }

    public var body: some View {
        Form {
            Section("名称与说明") {
                TextField("预设名", text: $draft.name)
                TextField("简短说明", text: $draft.summary)
            }

            Section("核心采样 (Temperature / Min-P / Top-P / Top-K)") {
                SliderRow(title: "Temperature", value: $draft.temperature, range: 0.0...1.8, format: "%.2f")
                SliderRow(title: "Min-P（小模型陪聊核心）", value: $draft.minP, range: 0.0...0.4, format: "%.2f")
                SliderRow(title: "Top-P", value: $draft.topP, range: 0.1...1.0, format: "%.2f")
                Stepper("Top-K：\(draft.topK)（0 为关闭）", value: $draft.topK, in: 0...150, step: 5)
                Stepper("最大生成 Tokens：\(draft.maxTokens)", value: $draft.maxTokens, in: 64...2048, step: 64)
            }

            Section("防复读惩罚 (Penalties)") {
                SliderRow(title: "Repeat Penalty", value: $draft.repeatPenalty, range: 1.0...1.5, format: "%.2f")
                Stepper("Repeat 回看窗口：\(draft.repeatLastN)", value: $draft.repeatLastN, in: 0...512, step: 32)
                SliderRow(title: "Frequency Penalty", value: $draft.frequencyPenalty, range: 0.0...1.0, format: "%.2f")
                SliderRow(title: "Presence Penalty", value: $draft.presencePenalty, range: 0.0...1.0, format: "%.2f")
            }

            Section("DRY 序列防复读（长对话伴侣神器）") {
                SliderRow(title: "DRY Multiplier（0 关闭，推荐 0.6~1.0）", value: $draft.dryMultiplier, range: 0.0...2.0, format: "%.2f")
                SliderRow(title: "DRY Base", value: $draft.dryBase, range: 1.0...3.0, format: "%.2f")
                Stepper("允许重复长度：\(draft.dryAllowedLength)", value: $draft.dryAllowedLength, in: 1...6)
                Stepper("DRY 回看窗口：\(draft.dryPenaltyLastN)", value: $draft.dryPenaltyLastN, in: 64...2048, step: 64)
            }

            Section("停止词 (Stop Sequences，逗号分隔)") {
                TextField("<|im_end|>, <|eot_id|>, </s>", text: $stopText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("编辑采样预设")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    draft.stopSequences = stopText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    Task {
                        await store.saveSamplerPreset(draft)
                        dismiss()
                    }
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: format, value))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
        .padding(.vertical, 2)
    }
}

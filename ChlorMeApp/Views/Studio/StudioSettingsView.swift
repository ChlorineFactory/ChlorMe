import SwiftUI
import UniformTypeIdentifiers
import ChlorCore

public struct StudioSettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var showNewPreset = false
    @State private var editingPreset: SamplerPreset?
    @State private var backupURL: URL?
    @State private var showRestoreImporter = false
    @State private var kvBytes: Int64 = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("视觉外观") {
                    Picker("主题风格", selection: Binding(
                        get: { store.settings.themeMode },
                        set: { newVal in
                            var s = store.settings
                            s.themeMode = newVal
                            Task { await store.saveSettings(s) }
                        }
                    )) {
                        ForEach(ChlorThemeMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                }

                Section("采样参数预设库（含 Min-P / DRY 防复读）") {
                    ForEach(store.presets) { preset in
                        Button {
                            editingPreset = preset
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(preset.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Spacer()
                                    Text("T \(String(format: "%.2f", preset.temperature)) · MinP \(String(format: "%.2f", preset.minP))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                if !preset.summary.isEmpty {
                                    Text(preset.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .swipeActions {
                            if !preset.isBuiltIn {
                                Button(role: .destructive) {
                                    Task { await store.deleteSamplerPreset(preset) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        showNewPreset = true
                    } label: {
                        Label("新建采样预设", systemImage: "plus.circle")
                    }
                }

                Section("Prompt 编排与记忆策略") {
                    NavigationLink {
                        PromptOrchestratorView()
                    } label: {
                        Label("Prompt 模块编排器（拖拽顺序与模板）", systemImage: "list.bullet.indent")
                    }

                    Stepper("自动整理回忆阈值：每 \(store.settings.autoReflectMessageThreshold) 条新消息", value: Binding(
                        get: { store.settings.autoReflectMessageThreshold },
                        set: { val in
                            var s = store.settings
                            s.autoReflectMessageThreshold = val
                            Task { await store.saveSettings(s) }
                        }
                    ), in: 0...40, step: 2)

                    Stepper("单次召回共同回忆：Top \(store.settings.memoryRecallTopK)", value: Binding(
                        get: { store.settings.memoryRecallTopK },
                        set: { val in
                            var s = store.settings
                            s.memoryRecallTopK = val
                            Task { await store.saveSettings(s) }
                        }
                    ), in: 0...10)

                    Stepper("单次触发世界书上限：\(store.settings.lorebookMaxEntries) 条", value: Binding(
                        get: { store.settings.lorebookMaxEntries },
                        set: { val in
                            var s = store.settings
                            s.lorebookMaxEntries = val
                            Task { await store.saveSettings(s) }
                        }
                    ), in: 0...8)

                    Stepper("近期原文窗口上限：\(store.settings.maxHistoryMessages) 条", value: Binding(
                        get: { store.settings.maxHistoryMessages },
                        set: { val in
                            var s = store.settings
                            s.maxHistoryMessages = val
                            Task { await store.saveSettings(s) }
                        }
                    ), in: 6...60, step: 2)

                    Toggle("真实时间与间隔感知", isOn: Binding(
                        get: { store.settings.enableTimeAwareness },
                        set: { val in
                            var s = store.settings
                            s.enableTimeAwareness = val
                            Task { await store.saveSettings(s) }
                        }
                    ))
                }

                Section("离线定时问候通知") {
                    Toggle("每日定时本地问候", isOn: Binding(
                        get: { store.settings.enableDailyGreetingNotification },
                        set: { val in
                            var s = store.settings
                            s.enableDailyGreetingNotification = val
                            Task { await store.saveSettings(s) }
                        }
                    ))

                    if store.settings.enableDailyGreetingNotification {
                        DatePicker("问候时间", selection: Binding(
                            get: {
                                var comps = DateComponents()
                                comps.hour = store.settings.greetingHour
                                comps.minute = store.settings.greetingMinute
                                return Calendar.current.date(from: comps) ?? Date()
                            },
                            set: { date in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                                var s = store.settings
                                s.greetingHour = comps.hour ?? 22
                                s.greetingMinute = comps.minute ?? 30
                                Task { await store.saveSettings(s) }
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                }

                Section("性能与防闪退") {
                    Picker("切后台自动释放模型", selection: Binding(
                        get: { store.settings.backgroundUnloadSeconds },
                        set: { val in
                            var s = store.settings
                            s.backgroundUnloadSeconds = val
                            Task { await store.saveSettings(s) }
                        }
                    )) {
                        Text("从不自动释放").tag(0)
                        Text("30 秒后释放").tag(30)
                        Text("2 分钟后释放（推荐）").tag(120)
                        Text("5 分钟后释放").tag(300)
                    }

                    HStack {
                        Text("KV Cache 快照缓存")
                        Spacer()
                        Text(MemoryBudgetAdvisor.formatBytes(kvBytes))
                            .foregroundStyle(.secondary)
                    }

                    Button("清理 KV 快照缓存") {
                        let freed = store.localBackend.clearKVSnapshots()
                        kvBytes = store.localBackend.kvSnapshotsTotalBytes()
                        store.showToast("已释放 \(MemoryBudgetAdvisor.formatBytes(freed)) 缓存")
                    }
                }

                Section("隐私安全与整库备份") {
                    Toggle("开启 Face ID / 密码应用锁", isOn: Binding(
                        get: { store.settings.enableFaceIDLock },
                        set: { val in
                            var s = store.settings
                            s.enableFaceIDLock = val
                            Task { await store.saveSettings(s) }
                        }
                    ))

                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("分享/保存 SQLite 完整备份", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task {
                                do {
                                    backupURL = try await store.createBackupFileURL()
                                } catch {
                                    store.alertError = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("生成整库备份（含所有伴侣、聊天与记忆）", systemImage: "externaldrive.badge.plus")
                        }
                    }

                    Button {
                        showRestoreImporter = true
                    } label: {
                        Label("从备份文件 (.sqlite) 恢复", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("自定义工坊")
            .sheet(isPresented: $showNewPreset) {
                NavigationStack { SamplerPresetEditorView(preset: nil) }
            }
            .sheet(item: $editingPreset) { p in
                NavigationStack { SamplerPresetEditorView(preset: p) }
            }
            .fileImporter(
                isPresented: $showRestoreImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await store.restoreBackup(from: url) }
                }
            }
            .onAppear {
                kvBytes = store.localBackend.kvSnapshotsTotalBytes()
            }
        }
    }
}

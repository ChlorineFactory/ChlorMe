import SwiftUI
import UniformTypeIdentifiers
import ChlorCore

public struct StudioSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    @State private var showNewPreset = false
    @State private var editingPreset: SamplerPreset?
    @State private var backupURL: URL?
    @State private var showRestoreImporter = false
    @State private var kvBytes: Int64 = 0
    @State private var isWebDAVBusy = false
    @State private var webDAVStatus: String?
    @State private var remoteBackups: [WebDAVRemoteBackup] = []
    @State private var showWebDAVList = false

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicNebulaBackdrop(palette: palette)

                List {
                    Section {
                        HStack(spacing: 12) {
                            statPill(value: "\(store.characters.count)", label: "星海伴侣", icon: "heart.fill", tint: palette.tertiaryAccent)
                            statPill(value: "\(store.totalMessageCount)", label: "累计对话", icon: "bubble.left.fill", tint: palette.accent)
                            statPill(value: "\(store.totalMemoryCount)", label: "珍藏回忆", icon: "sparkles", tint: palette.secondaryAccent)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                    }

                    Section("视觉宇宙主题") {
                        Picker("外观风格", selection: Binding(
                            get: { ChlorThemeMode.resolved(from: store.settings.themeMode).rawValue },
                            set: { newVal in
                                ChlorHaptics.light()
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
                    .listRowBackground(palette.surface)

                    Section("采样参数预设库（含 Min-P / DRY 防复读）") {
                        ForEach(store.presets) { preset in
                            Button {
                                editingPreset = preset
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(preset.name).font(.subheadline.weight(.semibold)).foregroundStyle(palette.primaryText)
                                        Spacer()
                                        Text("T \(String(format: "%.2f", preset.temperature)) · MinP \(String(format: "%.2f", preset.minP))")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(palette.accent)
                                    }
                                    if !preset.summary.isEmpty {
                                        Text(preset.summary)
                                            .font(.caption)
                                            .foregroundStyle(palette.secondaryText)
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
                    .listRowBackground(palette.surface)

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
                    .listRowBackground(palette.surface)

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
                    .listRowBackground(palette.surface)

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
                    .listRowBackground(palette.surface)

                    Section("联网搜索增强（聊天室 🌐 开关）") {
                        Picker("搜索引擎", selection: Binding(
                            get: { store.settings.webSearchProvider },
                            set: { val in
                                var s = store.settings
                                s.webSearchProvider = val
                                Task { await store.saveSettings(s) }
                            }
                        )) {
                            ForEach(WebSearchProviderKind.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }

                        if store.settings.webSearchProvider.requiresAPIKey {
                            SecureField("输入 \(store.settings.webSearchProvider.displayName) API Key", text: Binding(
                                get: { store.settings.webSearchAPIKey },
                                set: { val in
                                    var s = store.settings
                                    s.webSearchAPIKey = val
                                    Task { await store.saveSettings(s) }
                                }
                            ))
                        }

                        Stepper("单次参考网页条数：\(store.settings.webSearchMaxResults)", value: Binding(
                            get: { store.settings.webSearchMaxResults },
                            set: { val in
                                var s = store.settings
                                s.webSearchMaxResults = val
                                Task { await store.saveSettings(s) }
                            }
                        ), in: 1...8)
                    }
                    .listRowBackground(palette.surface)

                    Section("WebDAV 云端备份同步（坚果云 / Nextcloud）") {
                        TextField("服务器地址（如 https://dav.jianguoyun.com/dav/）", text: Binding(
                            get: { store.settings.webDAV.serverURL },
                            set: { val in
                                var s = store.settings
                                s.webDAV.serverURL = val
                                Task { await store.saveSettings(s) }
                            }
                        ))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        TextField("用户名 / 邮箱", text: Binding(
                            get: { store.settings.webDAV.username },
                            set: { val in
                                var s = store.settings
                                s.webDAV.username = val
                                Task { await store.saveSettings(s) }
                            }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        SecureField("应用密码（坚果云需生成第三方应用密码）", text: Binding(
                            get: { store.settings.webDAV.password },
                            set: { val in
                                var s = store.settings
                                s.webDAV.password = val
                                Task { await store.saveSettings(s) }
                            }
                        ))

                        TextField("远程子目录（默认 ChlorMe）", text: Binding(
                            get: { store.settings.webDAV.remoteFolder },
                            set: { val in
                                var s = store.settings
                                s.webDAV.remoteFolder = val
                                Task { await store.saveSettings(s) }
                            }
                        ))
                        .textInputAutocapitalization(.never)

                        HStack(spacing: 12) {
                            Button("测试连接") {
                                isWebDAVBusy = true
                                webDAVStatus = nil
                                Task {
                                    do {
                                        try await store.testWebDAVConnection()
                                        webDAVStatus = "✅ WebDAV 连接正常"
                                    } catch {
                                        webDAVStatus = "❌ \(error.localizedDescription)"
                                    }
                                    isWebDAVBusy = false
                                }
                            }
                            .disabled(isWebDAVBusy)

                            Spacer()

                            Button("立即云端备份") {
                                isWebDAVBusy = true
                                webDAVStatus = nil
                                Task {
                                    do {
                                        let name = try await store.uploadBackupToWebDAV()
                                        webDAVStatus = "✅ 已上传：\(name)"
                                        ChlorHaptics.success()
                                    } catch {
                                        webDAVStatus = "❌ \(error.localizedDescription)"
                                    }
                                    isWebDAVBusy = false
                                }
                            }
                            .disabled(isWebDAVBusy)

                            Spacer()

                            Button("拉取恢复") {
                                isWebDAVBusy = true
                                webDAVStatus = nil
                                Task {
                                    do {
                                        remoteBackups = try await store.fetchWebDAVBackups()
                                        showWebDAVList = true
                                    } catch {
                                        webDAVStatus = "❌ \(error.localizedDescription)"
                                    }
                                    isWebDAVBusy = false
                                }
                            }
                            .disabled(isWebDAVBusy)
                        }
                        .font(.subheadline.weight(.semibold))

                        if let webDAVStatus {
                            Text(webDAVStatus)
                                .font(.caption)
                                .foregroundStyle(webDAVStatus.hasPrefix("✅") ? .green : .red)
                        }
                    }
                    .listRowBackground(palette.surface)

                    Section("隐私安全与本地整库备份") {
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
                    .listRowBackground(palette.surface)

                    Section("关于 ChlorMe") {
                        LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0")
                        LabeledContent("构建号", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2")
                    }
                    .listRowBackground(palette.surface)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("自定义工坊")
            .sheet(isPresented: $showWebDAVList) {
                NavigationStack {
                    List {
                        if remoteBackups.isEmpty {
                            ContentUnavailableView("云端暂无备份文件", systemImage: "icloud.slash", description: Text("点击「立即云端备份」上传一份后再来恢复。"))
                        } else {
                            ForEach(remoteBackups) { item in
                                Button {
                                    showWebDAVList = false
                                    Task {
                                        do {
                                            try await store.restoreFromWebDAV(fileName: item.fileName)
                                            ChlorHaptics.success()
                                        } catch {
                                            store.alertError = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    Label(item.fileName, systemImage: "arrow.down.doc.fill")
                                }
                            }
                        }
                    }
                    .navigationTitle("选择云端备份恢复")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("关闭") { showWebDAVList = false } }
                    }
                }
                .presentationDetents([.medium])
            }
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

    private func statPill(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(palette.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .liquidGlass(cornerRadius: 20, tint: tint, isDark: palette.isDark)
    }
}

import SwiftUI
import UniformTypeIdentifiers
import ChlorCore

/// RikkaHub-inspired layered Settings Center with Liquid Glass hero card and dedicated clean subpages.
public struct StudioSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    public let onOpenModels: (() -> Void)?
    public let onOpenCompanions: (() -> Void)?

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    public init(onOpenModels: (() -> Void)? = nil, onOpenCompanions: (() -> Void)? = nil) {
        self.onOpenModels = onOpenModels
        self.onOpenCompanions = onOpenCompanions
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicNebulaBackdrop(palette: palette)

                ScrollView {
                    VStack(spacing: 16) {
                        heroOverviewCard
                        primaryResourcesSection
                        intelligenceSection
                        personalizationSection
                        systemAndSyncSection
                        versionFooter
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Hero Card

    private var heroOverviewCard: some View {
        let loaded = store.models.first(where: { $0.id == store.loadedModelId })
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"

        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(palette.userBubble)
                        .frame(width: 54, height: 54)
                    Image(systemName: "moon.stars.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .shadow(color: palette.accent.opacity(0.45), radius: 10)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("ChlorMe")
                            .font(.title3.bold())
                            .foregroundStyle(palette.primaryText)
                        Text("v\(version)")
                            .font(.caption2.monospaced().bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(palette.accent.opacity(0.20), in: Capsule())
                            .foregroundStyle(palette.accent)
                    }
                    Text(loaded != nil ? "本地引擎驻留中 · \(loaded!.name)" : "本地离线部署 + 多协议全能伴侣")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                miniStat(value: "\(store.models.count)", label: "模型/节点", tint: palette.accent)
                miniStat(value: "\(store.characters.count)", label: "伴侣", tint: palette.tertiaryAccent)
                miniStat(value: "\(store.totalMessageCount)", label: "对话", tint: Color.blue)
                miniStat(value: "\(store.totalMemoryCount)", label: "回忆", tint: palette.secondaryAccent)
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 24, tint: palette.accent, isDark: palette.isDark)
    }

    private func miniStat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit().bold())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(palette.isDark ? 0.05 : 0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Section 1: Core Hubs (Models & Companions)

    private var primaryResourcesSection: some View {
        settingsGroup(title: "核心引擎与伴侣") {
            if let onOpenModels {
                Button {
                    ChlorHaptics.light()
                    onOpenModels()
                } label: {
                    settingsRowLabel(
                        icon: "cpu.fill",
                        iconColor: .cyan,
                        title: "模型与服务商",
                        subtitle: "本地 GGUF 部署 · OpenAI / Claude / Gemini",
                        trailing: "\(store.models.count) 个"
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    ModelsHubView()
                } label: {
                    settingsRowLabel(
                        icon: "cpu.fill",
                        iconColor: .cyan,
                        title: "模型与服务商",
                        subtitle: "本地 GGUF 部署 · OpenAI / Claude / Gemini",
                        trailing: "\(store.models.count) 个"
                    )
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.22).padding(.leading, 52)

            if let onOpenCompanions {
                Button {
                    ChlorHaptics.light()
                    onOpenCompanions()
                } label: {
                    settingsRowLabel(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "角色卡、世界书与身份",
                        subtitle: "V2 角色卡 · Lorebook · 多套 Persona",
                        trailing: "\(store.characters.count) 位"
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    CompanionsHubView()
                } label: {
                    settingsRowLabel(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "角色卡、世界书与身份",
                        subtitle: "V2 角色卡 · Lorebook · 多套 Persona",
                        trailing: "\(store.characters.count) 位"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Section 2: Intelligence (Sampling, Prompt, Memory, Search)

    private var intelligenceSection: some View {
        settingsGroup(title: "智能、记忆与搜索") {
            NavigationLink {
                InferenceSettingsSubpage()
            } label: {
                settingsRowLabel(
                    icon: "waveform.path.ecg",
                    iconColor: .mint,
                    title: "采样参数与 Prompt 编排",
                    subtitle: "Min-P / DRY 防复读预设 · 模块顺序拖拽",
                    trailing: "\(store.presets.count) 套预设"
                )
            }
            .buttonStyle(.plain)

            Divider().opacity(0.22).padding(.leading, 52)

            NavigationLink {
                MemoryAndSearchSettingsSubpage()
            } label: {
                settingsRowLabel(
                    icon: "globe.asia.australia.fill",
                    iconColor: .blue,
                    title: "记忆引擎与联网搜索",
                    subtitle: "自动反思 · 回忆召回 · \(store.settings.webSearchProvider.displayName)",
                    trailing: "Top \(store.settings.memoryRecallTopK)"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Section 3: Personalization (Themes & Notifications)

    private var personalizationSection: some View {
        settingsGroup(title: "外观与陪伴体验") {
            NavigationLink {
                AppearanceSettingsSubpage()
            } label: {
                settingsRowLabel(
                    icon: "paintpalette.fill",
                    iconColor: .pink,
                    title: "外观主题与视觉风格",
                    subtitle: ChlorThemeMode.resolved(from: store.settings.themeMode).displayName,
                    trailing: nil
                )
            }
            .buttonStyle(.plain)

            Divider().opacity(0.22).padding(.leading, 52)

            NavigationLink {
                GreetingSettingsSubpage()
            } label: {
                settingsRowLabel(
                    icon: "bell.badge.fill",
                    iconColor: .orange,
                    title: "时间感知与离线问候",
                    subtitle: store.settings.enableDailyGreetingNotification ? "每日 \(String(format: "%02d:%02d", store.settings.greetingHour, store.settings.greetingMinute)) 本地推送" : "未开启定时问候",
                    trailing: store.settings.enableTimeAwareness ? "时间感知开" : nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Section 4: Performance, Privacy, WebDAV Sync & Backup

    private var systemAndSyncSection: some View {
        settingsGroup(title: "性能、隐私与云端同步") {
            NavigationLink {
                PrivacySyncSettingsSubpage()
            } label: {
                settingsRowLabel(
                    icon: "icloud.and.arrow.up.fill",
                    iconColor: .indigo,
                    title: "WebDAV 云同步与本地备份",
                    subtitle: store.settings.webDAV.username.isEmpty ? "支持坚果云 / Nextcloud / 整库导入导出" : "已配置：\(store.settings.webDAV.username)",
                    trailing: nil
                )
            }
            .buttonStyle(.plain)

            Divider().opacity(0.22).padding(.leading, 52)

            NavigationLink {
                PerformancePrivacySubpage()
            } label: {
                settingsRowLabel(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "内存防闪退与隐私锁",
                    subtitle: "后台自动释放 · KV 缓存 · Face ID 应用锁",
                    trailing: store.settings.enableFaceIDLock ? "已锁定" : nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var versionFooter: some View {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
        return Text("ChlorMe v\(ver) (Build \(build)) · iOS Native Liquid Glass & Local LLM")
            .font(.caption2)
            .foregroundStyle(palette.secondaryText.opacity(0.75))
            .padding(.top, 4)
    }

    // MARK: - Helpers

    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.secondaryText)
                .padding(.leading, 8)

            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .liquidGlass(cornerRadius: 22, tint: palette.accent, isDark: palette.isDark)
        }
    }

    private func settingsRowLabel(icon: String, iconColor: Color, title: String, subtitle: String, trailing: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(iconColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let trailing {
                Text(trailing)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.secondaryText)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(palette.secondaryText.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Subpage 1: Inference & Prompt

private struct InferenceSettingsSubpage: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNewPreset = false
    @State private var editingPreset: SamplerPreset?

    var body: some View {
        Form {
            Section("Prompt 结构编排") {
                NavigationLink {
                    PromptOrchestratorView()
                } label: {
                    Label("Prompt 模块编排器（拖拽顺序与提示词模板）", systemImage: "list.bullet.indent")
                }
            }

            Section("采样参数预设库（Min-P / Repeat / DRY 防复读）") {
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
                                Text(preset.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .swipeActions {
                        if !preset.isBuiltIn {
                            Button(role: .destructive) {
                                Task { await store.deleteSamplerPreset(preset) }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }

                Button {
                    showNewPreset = true
                } label: {
                    Label("新建自定义采样预设", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("采样与 Prompt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNewPreset) {
            NavigationStack { SamplerPresetEditorView(preset: nil) }
        }
        .sheet(item: $editingPreset) { p in
            NavigationStack { SamplerPresetEditorView(preset: p) }
        }
    }
}

// MARK: - Subpage 2: Memory & Web Search

private struct MemoryAndSearchSettingsSubpage: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
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

            Section("伴侣记忆召回与反思策略") {
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
            }
        }
        .navigationTitle("记忆与联网搜索")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Subpage 3: Visual Themes

private struct AppearanceSettingsSubpage: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let current = ChlorThemeMode.resolved(from: store.settings.themeMode)
        Form {
            Section("选择视觉主题（iOS 26+ 自动启用原生 Liquid Glass 折射）") {
                ForEach(ChlorThemeMode.allCases, id: \.rawValue) { mode in
                    let p = ChlorPalette.palette(for: mode, scheme: scheme)
                    Button {
                        ChlorHaptics.light()
                        var s = store.settings
                        s.themeMode = mode.rawValue
                        Task { await store.saveSettings(s) }
                    } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: -6) {
                                Circle().fill(p.background).frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                                Circle().fill(p.accent).frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                                Circle().fill(p.secondaryAccent).frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                            }
                            Text(mode.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if current == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(p.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("外观与主题")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Subpage 4: Time Awareness & Daily Greeting

private struct GreetingSettingsSubpage: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("真实时间感知") {
                Toggle("向模型注入当前时间与聊天间隔", isOn: Binding(
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
        }
        .navigationTitle("时间与定时问候")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Subpage 5: WebDAV Cloud Sync & Local Backup

private struct PrivacySyncSettingsSubpage: View {
    @EnvironmentObject private var store: AppStore
    @State private var isWebDAVBusy = false
    @State private var webDAVStatus: String?
    @State private var remoteBackups: [WebDAVRemoteBackup] = []
    @State private var showWebDAVList = false
    @State private var backupURL: URL?
    @State private var showRestoreImporter = false

    var body: some View {
        Form {
            Section("WebDAV 云端同步（坚果云 / Nextcloud / Alist）") {
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

                HStack {
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

                    Button("上传备份") {
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

                    Button("云端恢复") {
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

            Section("本地单文件整库备份 (.sqlite)") {
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
                        Label("生成本地整库备份（含所有伴侣、聊天与回忆）", systemImage: "externaldrive.badge.plus")
                    }
                }

                Button {
                    showRestoreImporter = true
                } label: {
                    Label("从本地 .sqlite 备份恢复", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("云同步与备份")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWebDAVList) {
            NavigationStack {
                List {
                    if remoteBackups.isEmpty {
                        ContentUnavailableView("云端暂无备份", systemImage: "icloud.slash")
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
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await store.restoreBackup(from: url) }
            }
        }
    }
}

// MARK: - Subpage 6: Performance & Face ID Lock

private struct PerformancePrivacySubpage: View {
    @EnvironmentObject private var store: AppStore
    @State private var kvBytes: Int64 = 0

    var body: some View {
        Form {
            Section("本地模型显存防闪退") {
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

                LabeledContent("KV Cache 快照缓存", value: MemoryBudgetAdvisor.formatBytes(kvBytes))

                Button("清理 KV 快照缓存") {
                    let freed = store.localBackend.clearKVSnapshots()
                    kvBytes = store.localBackend.kvSnapshotsTotalBytes()
                    store.showToast("已释放 \(MemoryBudgetAdvisor.formatBytes(freed)) 缓存")
                }
            }

            Section("隐私安全") {
                Toggle("开启 Face ID / 密码应用锁", isOn: Binding(
                    get: { store.settings.enableFaceIDLock },
                    set: { val in
                        var s = store.settings
                        s.enableFaceIDLock = val
                        Task { await store.saveSettings(s) }
                    }
                ))
            }
        }
        .navigationTitle("性能与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            kvBytes = store.localBackend.kvSnapshotsTotalBytes()
        }
    }
}

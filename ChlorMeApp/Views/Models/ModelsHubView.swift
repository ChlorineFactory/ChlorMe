import SwiftUI
import UniformTypeIdentifiers
import ChlorCore

public struct ModelsHubView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    @State private var showFileImporter = false
    @State private var showCustomURLDownload = false
    @State private var showAddRemoteAPI = false
    @State private var showWiFiSheet = false
    @State private var selectedModelForDetail: ModelConfig?

    @State private var customModelName = ""
    @State private var customURL = ""

    @State private var apiName = ""
    @State private var apiBaseURL = "http://192.168.1.100:11434/v1"
    @State private var apiKey = ""
    @State private var apiRemoteModel = "qwen2.5:14b"
    @State private var fetchedRemoteModels: [String] = []
    @State private var isTestingAPI = false
    @State private var apiTestStatus: String?

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicNebulaBackdrop(palette: palette)

                ScrollView {
                    VStack(spacing: 16) {
                        headerRow
                        liquidMemoryGaugeCard

                        if !store.downloadManager.activeDownloads.isEmpty {
                            activeDownloadsCard
                        }

                        installedModelsSection
                        recommendedDownloadsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    do {
                        let model = try store.downloadManager.importLocalGGUF(from: url)
                        Task {
                            await store.saveModel(model)
                            ChlorHaptics.success()
                            store.showToast("已导入模型：\(model.name)")
                        }
                    } catch {
                        store.alertError = "导入模型失败：\(error.localizedDescription)"
                    }
                }
            }
            .sheet(item: $selectedModelForDetail) { model in
                ModelDetailSheet(model: model)
            }
            .sheet(isPresented: $showWiFiSheet) {
                WiFiTransferSheet()
            }
            .sheet(isPresented: $showCustomURLDownload) {
                NavigationStack {
                    Form {
                        Section("GGUF 直链下载") {
                            TextField("显示名称（如：My-RP-7B）", text: $customModelName)
                            TextField("https://huggingface.co/.../model.gguf", text: $customURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .navigationTitle("链接下载模型")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showCustomURLDownload = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("开始下载") {
                                let name = customModelName.isEmpty ? "自定义 GGUF" : customModelName
                                let fileName = URL(string: customURL)?.lastPathComponent ?? "\(UUID().uuidString).gguf"
                                store.downloadManager.startDownload(name: name, urlString: customURL, fileName: fileName) { res in
                                    Task { @MainActor in
                                        switch res {
                                        case .success(let model):
                                            await store.saveModel(model)
                                            ChlorHaptics.success()
                                            store.showToast("下载完成：\(model.name)")
                                        case .failure(let err):
                                            store.alertError = err.localizedDescription
                                        }
                                    }
                                }
                                showCustomURLDownload = false
                            }
                            .disabled(customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showAddRemoteAPI) {
                NavigationStack {
                    Form {
                        Section("OpenAI 兼容接口（可连家中 Mac 或云端）") {
                            TextField("节点名称（如：家里 Mac Qwen 14B）", text: $apiName)
                            TextField("Base URL (含 /v1)", text: $apiBaseURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Model ID（如：qwen2.5:14b / gpt-4o-mini）", text: $apiRemoteModel)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("API Key（本地 Ollama 可留空）", text: $apiKey)
                        }

                        Section("连通性测试 & 模型发现") {
                            Button {
                                isTestingAPI = true
                                apiTestStatus = nil
                                Task {
                                    do {
                                        let list = try await store.testRemoteAPI(baseURL: apiBaseURL, apiKey: apiKey.isEmpty ? nil : apiKey)
                                        fetchedRemoteModels = list
                                        if let first = list.first, apiRemoteModel.isEmpty {
                                            apiRemoteModel = first
                                        }
                                        apiTestStatus = list.isEmpty ? "✅ 连接成功（未返回模型列表，请手填 Model ID）" : "✅ 连接成功！发现 \(list.count) 个模型"
                                    } catch {
                                        apiTestStatus = "❌ \(error.localizedDescription)"
                                    }
                                    isTestingAPI = false
                                }
                            } label: {
                                HStack {
                                    if isTestingAPI { ProgressView() }
                                    Text(isTestingAPI ? "正在测试连通性…" : "测试连接并自动拉取模型列表")
                                }
                            }
                            .disabled(isTestingAPI || apiBaseURL.isEmpty)

                            if let apiTestStatus {
                                Text(apiTestStatus)
                                    .font(.caption)
                                    .foregroundStyle(apiTestStatus.hasPrefix("✅") ? .green : .red)
                            }

                            if !fetchedRemoteModels.isEmpty {
                                Picker("点选已发现的模型", selection: $apiRemoteModel) {
                                    ForEach(fetchedRemoteModels, id: \.self) { mid in
                                        Text(mid).tag(mid)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("添加远程 API 节点")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showAddRemoteAPI = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                let model = ModelConfig(
                                    name: apiName.isEmpty ? apiRemoteModel : apiName,
                                    backendKind: .openAICompatible,
                                    quantizationLabel: "API",
                                    contextLength: 16384,
                                    apiBaseURL: apiBaseURL,
                                    apiKey: apiKey.isEmpty ? nil : apiKey,
                                    remoteModelName: apiRemoteModel
                                )
                                Task {
                                    await store.saveModel(model)
                                    ChlorHaptics.success()
                                    store.showToast("已添加远程节点：\(model.name)")
                                    showAddRemoteAPI = false
                                }
                            }
                            .disabled(apiBaseURL.isEmpty || apiRemoteModel.isEmpty)
                        }
                    }
                }
            }
            .onAppear {
                store.refreshMemoryStats()
            }
        }
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("模型部署舱")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Text("本地 llama.cpp Metal 加速 · OpenAI 远程接力")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Menu {
                Button { showFileImporter = true } label: { Label("从「文件」导入 .gguf", systemImage: "folder.badge.plus") }
                Button { showWiFiSheet = true } label: { Label("局域网 Wi-Fi 电脑拖传", systemImage: "wifi") }
                Button {
                    customModelName = ""
                    customURL = ""
                    showCustomURLDownload = true
                } label: { Label("自定义直链 / HuggingFace 下载", systemImage: "link.badge.plus") }
                Divider()
                Button {
                    fetchedRemoteModels = []
                    apiTestStatus = nil
                    showAddRemoteAPI = true
                } label: { Label("添加 OpenAI 兼容远程 API", systemImage: "network") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44)
                    .liquidGlassCapsule(tint: palette.accent, isDark: palette.isDark)
            }
        }
        .padding(.top, 6)
    }

    private var liquidMemoryGaugeCard: some View {
        let loaded = store.models.first(where: { $0.id == store.loadedModelId })
        let totalPhys = Double(ProcessInfo.processInfo.physicalMemory)
        let avail = Double(max(store.availableMemoryBytes, 0))
        let ratio = totalPhys > 0 ? max(0.08, min(1.0, avail / (totalPhys * 0.72))) : 0.5

        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(
                        AngularGradient(
                            colors: [palette.accent, palette.secondaryAccent, palette.tertiaryAccent, palette.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(MemoryBudgetAdvisor.formatBytes(store.availableMemoryBytes))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(palette.primaryText)
                    Text("可用显存")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .frame(width: 82, height: 82)

            VStack(alignment: .leading, spacing: 6) {
                if let loaded {
                    Label("驻留中：\(loaded.name)", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    Text("上下文 \(loaded.contextLength) · KV \(loaded.kvQuantType.rawValue.uppercased())")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    HStack(spacing: 10) {
                        Button("卸载释放内存") {
                            ChlorHaptics.light()
                            Task { await store.unloadLocalModel() }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.18), in: Capsule())

                        if store.currentTokensPerSecond > 0 {
                            Text(String(format: "%.1f tok/s", store.currentTokensPerSecond))
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(palette.accent)
                        }
                    }
                } else {
                    Text("等待唤醒本地引擎")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                    Text("支持金属 GPU 全层卸载与 Q8/Q4 KV 量化，iPhone 17 Pro 可稳跑 7B~8B Q4。")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .liquidGlass(cornerRadius: 24, tint: palette.accent, isDark: palette.isDark)
    }

    private var activeDownloadsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("正在下载")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.accent)
            ForEach(Array(store.downloadManager.activeDownloads.values)) { dl in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dl.name).font(.subheadline.weight(.semibold)).foregroundStyle(palette.primaryText)
                        Spacer()
                        Text("\(Int(dl.progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(palette.accent)
                        Button("取消", role: .destructive) {
                            store.downloadManager.cancelDownload(id: dl.id)
                        }
                        .font(.caption)
                    }
                    ProgressView(value: dl.progress).tint(palette.accent)
                    Text("\(MemoryBudgetAdvisor.formatBytes(dl.bytesWritten)) / \(MemoryBudgetAdvisor.formatBytes(dl.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 20, tint: palette.accent, isDark: palette.isDark)
    }

    private var installedModelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("我的模型与节点（\(store.models.count)）")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.secondaryText)
                .padding(.leading, 4)

            if store.models.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无模型")
                        .font(.subheadline.bold())
                        .foregroundStyle(palette.primaryText)
                    Text("可在下方一键下载精选模型，或点右上角 + Wi-Fi 无线拖传 / 导入 GGUF / 接入远程 API。")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .liquidGlass(cornerRadius: 20, tint: palette.secondaryAccent, isDark: palette.isDark)
            } else {
                ForEach(store.models) { model in
                    let isLoaded = store.loadedModelId == model.id
                    let safety = MemoryBudgetAdvisor.evaluate(
                        estimatedModelBytes: model.estimatedMemoryBytes,
                        availableMemoryBytes: store.availableMemoryBytes + (isLoaded ? model.estimatedMemoryBytes : 0)
                    )
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(model.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)
                                Text(model.quantizationLabel)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                                    .foregroundStyle(palette.secondaryText)
                                if model.backendKind == .localGGUF {
                                    Text(safety.label)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(safetyColor(safety).opacity(0.22), in: Capsule())
                                        .foregroundStyle(safetyColor(safety))
                                }
                            }
                            if model.backendKind == .localGGUF {
                                Text("文件 \(MemoryBudgetAdvisor.formatBytes(model.fileSizeBytes)) · 预计 \(MemoryBudgetAdvisor.formatBytes(model.estimatedMemoryBytes)) · \(model.contextLength) ctx")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                            } else {
                                Text("远程 API · \(model.remoteModelName ?? "") · \(model.apiBaseURL ?? "")")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if model.backendKind == .localGGUF {
                            Button {
                                ChlorHaptics.medium()
                                Task { await store.loadLocalModel(model, allowDanger: safety == .danger) }
                            } label: {
                                Text(isLoaded ? "已加载" : "加载")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(isLoaded ? AnyShapeStyle(Color.green) : AnyShapeStyle(palette.userBubble), in: Capsule())
                            }
                            .disabled(store.isLoadingModel)
                        }

                        Menu {
                            Button { selectedModelForDetail = model } label: { Label("参数配置", systemImage: "slider.horizontal.3") }
                            Button(role: .destructive) { Task { await store.deleteModel(model) } } label: { Label("删除模型", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 20, tint: isLoaded ? .green : palette.accent, isDark: palette.isDark)
                    .onTapGesture { selectedModelForDetail = model }
                }
            }
        }
    }

    private var recommendedDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("精选开源伴侣模型（适配 iPhone 17 Pro）")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.secondaryText)
                .padding(.leading, 4)

            ForEach(DefaultsFactory.recommendedModels()) { item in
                let alreadyDownloaded = store.models.contains(where: { $0.localFileName == item.fileName })
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.primaryText)
                            Text(item.badge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(palette.accent.opacity(0.20), in: Capsule())
                                .foregroundStyle(palette.accent)
                        }
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                        Text("\(item.quantization) · \(item.sizeDescription) · 推荐 \(item.recommendedContext) ctx")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText.opacity(0.8))
                    }
                    Spacer()
                    Button {
                        ChlorHaptics.light()
                        store.downloadManager.startDownload(
                            name: item.name,
                            urlString: item.downloadURL,
                            fileName: item.fileName,
                            quantization: item.quantization,
                            recommendedContext: item.recommendedContext,
                            chatTemplate: item.chatTemplate
                        ) { res in
                            Task { @MainActor in
                                switch res {
                                case .success(let model):
                                    await store.saveModel(model)
                                    ChlorHaptics.success()
                                    store.showToast("下载完成：\(model.name)")
                                case .failure(let err):
                                    store.alertError = err.localizedDescription
                                }
                            }
                        }
                    } label: {
                        Text(alreadyDownloaded ? "已有" : "下载")
                            .font(.caption.bold())
                            .foregroundStyle(alreadyDownloaded ? palette.secondaryText : palette.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(palette.accent.opacity(alreadyDownloaded ? 0.08 : 0.18), in: Capsule())
                    }
                    .disabled(alreadyDownloaded)
                }
                .padding(14)
                .liquidGlass(cornerRadius: 20, tint: palette.secondaryAccent, isDark: palette.isDark)
            }
        }
    }

    private func safetyColor(_ level: MemorySafetyLevel) -> Color {
        switch level {
        case .safe: return .green
        case .caution: return .orange
        case .danger: return .red
        }
    }
}

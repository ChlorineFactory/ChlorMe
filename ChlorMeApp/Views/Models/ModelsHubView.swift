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

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode(rawValue: store.settings.themeMode) ?? .darkGlass, scheme: scheme)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                hardwareDashboardSection

                if !store.downloadManager.activeDownloads.isEmpty {
                    activeDownloadsSection
                }

                installedModelsSection
                recommendedDownloadsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("模型部署舱")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("从「文件」导入 .gguf", systemImage: "folder.badge.plus")
                        }
                        Button {
                            showWiFiSheet = true
                        } label: {
                            Label("局域网 Wi-Fi 电脑拖传", systemImage: "wifi")
                        }
                        Button {
                            customModelName = ""
                            customURL = ""
                            showCustomURLDownload = true
                        } label: {
                            Label("自定义直链 / HuggingFace 下载", systemImage: "link.badge.plus")
                        }
                        Divider()
                        Button {
                            showAddRemoteAPI = true
                        } label: {
                            Label("添加 OpenAI 兼容远程 API", systemImage: "network")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(palette.accent)
                    }
                }
            }
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
                                    store.showToast("已添加远程节点：\(model.name)")
                                    showAddRemoteAPI = false
                                }
                            }
                            .disabled(apiBaseURL.isEmpty || apiRemoteModel.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                store.refreshMemoryStats()
            }
        }
    }

    private var hardwareDashboardSection: some View {
        Section("iPhone 硬件与显存仪表盘") {
            let loaded = store.models.first(where: { $0.id == store.loadedModelId })
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("进程剩余安全内存", systemImage: "memorychip")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(MemoryBudgetAdvisor.formatBytes(store.availableMemoryBytes))
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(palette.accent)
                }

                if let loaded {
                    HStack {
                        Label("已驻留：\(loaded.name)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .lineLimit(1)
                        Spacer()
                        Button("卸载释放") {
                            Task { await store.unloadLocalModel() }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                } else {
                    Text("当前无常驻本地模型，随时可加载或通过下方按钮导入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.currentTokensPerSecond > 0 {
                    Text(String(format: "上次本地生成速度：%.1f tokens/s", store.currentTokensPerSecond))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var activeDownloadsSection: some View {
        Section("正在下载") {
            ForEach(Array(store.downloadManager.activeDownloads.values)) { dl in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dl.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(dl.progress * 100))%")
                            .font(.caption.monospacedDigit())
                        Button("取消", role: .destructive) {
                            store.downloadManager.cancelDownload(id: dl.id)
                        }
                        .font(.caption)
                    }
                    ProgressView(value: dl.progress)
                    Text("\(MemoryBudgetAdvisor.formatBytes(dl.bytesWritten)) / \(MemoryBudgetAdvisor.formatBytes(dl.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var installedModelsSection: some View {
        Section("我的模型与节点（\(store.models.count)）") {
            if store.models.isEmpty {
                Text("暂无模型。可从下方一键下载精选模型，或点右上角 + 无线拖传 / 导入 GGUF / 添加远程 API。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.models) { model in
                    let isLoaded = store.loadedModelId == model.id
                    let safety = MemoryBudgetAdvisor.evaluate(
                        estimatedModelBytes: model.estimatedMemoryBytes,
                        availableMemoryBytes: store.availableMemoryBytes + (isLoaded ? model.estimatedMemoryBytes : 0)
                    )
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(model.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(model.quantizationLabel)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.16), in: Capsule())
                                if model.backendKind == .localGGUF {
                                    Text(safety.label)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(safetyColor(safety).opacity(0.2), in: Capsule())
                                        .foregroundStyle(safetyColor(safety))
                                }
                            }
                            if model.backendKind == .localGGUF {
                                Text("文件 \(MemoryBudgetAdvisor.formatBytes(model.fileSizeBytes)) · 预计占内存 \(MemoryBudgetAdvisor.formatBytes(model.estimatedMemoryBytes)) · \(model.contextLength) ctx · KV \(model.kvQuantType.rawValue.uppercased())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("远程 API · \(model.apiBaseURL ?? "") · \(model.remoteModelName ?? "")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if model.backendKind == .localGGUF {
                            Button(isLoaded ? "已加载" : "加载") {
                                Task { await store.loadLocalModel(model, allowDanger: safety == .danger) }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(isLoaded ? .green : palette.accent)
                            .disabled(store.isLoadingModel)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedModelForDetail = model
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await store.deleteModel(model) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var recommendedDownloadsSection: some View {
        Section("精选开源伴侣模型（适合 iPhone 17 Pro）") {
            ForEach(DefaultsFactory.recommendedModels()) { item in
                let alreadyDownloaded = store.models.contains(where: { $0.localFileName == item.fileName })
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Text(item.badge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.accent.opacity(0.18), in: Capsule())
                                .foregroundStyle(palette.accent)
                        }
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(item.quantization) · \(item.sizeDescription) · 推荐 \(item.recommendedContext) ctx")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(alreadyDownloaded ? "已有" : "下载") {
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
                                    store.showToast("下载完成：\(model.name)")
                                case .failure(let err):
                                    store.alertError = err.localizedDescription
                                }
                            }
                        }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .disabled(alreadyDownloaded)
                }
                .padding(.vertical, 3)
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

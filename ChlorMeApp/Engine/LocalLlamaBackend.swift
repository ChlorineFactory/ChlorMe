import Foundation
import ChlorCore

public enum LocalLlamaError: LocalizedError {
    case missingModelFile
    case memoryTooLow(required: String, available: String)
    case engineFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingModelFile:
            return "未找到该模型的本地 GGUF 文件，请先在「模型」页下载或导入"
        case .memoryTooLow(let req, let avail):
            return "当前可用内存不足（预计需要 \(req)，系统剩余 \(avail)），建议减小上下文长度或开启 Q8/Q4 KV 量化"
        case .engineFailure(let msg):
            return msg
        }
    }
}

/// Manages the single resident llama.cpp model instance, memory safety, KV snapshots, and streaming tokens.
public final class LocalLlamaBackend: @unchecked Sendable, LLMBackend {
    public static let shared = LocalLlamaBackend()

    private let engine = ChlorLlamaEngine()
    private let queue = DispatchQueue(label: "com.chlorme.llama.runtime", qos: .userInitiated)
    private let stateLock = NSLock()

    private var _loadedModelId: String?
    private var _loadedContextLength: Int = 0
    private var _loadedKVQuant: KVCacheQuantType = .q8_0
    private var _lastTokensPerSecond: Double = 0
    private var _cancelFlag: Bool = false

    public var loadedModelId: String? {
        stateLock.withLock { _loadedModelId }
    }

    public var lastTokensPerSecond: Double {
        stateLock.withLock { _lastTokensPerSecond }
    }

    public static var modelsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var kvCacheDirectoryURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("KVSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func availableMemoryBytes() -> Int64 {
        ChlorLlamaEngine.availableMemoryBytes()
    }

    public static func modelFileURL(for model: ModelConfig) -> URL? {
        guard let fileName = model.localFileName, !fileName.isEmpty else { return nil }
        return modelsDirectoryURL.appendingPathComponent(fileName)
    }

    public func requestCancel() {
        stateLock.withLock { _cancelFlag = true }
    }

    public func ensureLoaded(model: ModelConfig, allowDangerOverride: Bool = false) async throws {
        guard let fileURL = Self.modelFileURL(for: model),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LocalLlamaError.missingModelFile
        }

        let alreadyLoaded: Bool = stateLock.withLock {
            _loadedModelId == model.id &&
            _loadedContextLength == model.contextLength &&
            _loadedKVQuant == model.kvQuantType &&
            engine.isLoaded
        }
        if alreadyLoaded { return }

        // Unload existing weights before checking memory headroom
        await unload()

        let available = Self.availableMemoryBytes()
        let safety = MemoryBudgetAdvisor.evaluate(
            estimatedModelBytes: model.estimatedMemoryBytes,
            availableMemoryBytes: available
        )
        if safety == .danger && !allowDangerOverride {
            throw LocalLlamaError.memoryTooLow(
                required: MemoryBudgetAdvisor.formatBytes(model.estimatedMemoryBytes),
                available: MemoryBudgetAdvisor.formatBytes(available)
            )
        }

        let kvMode: Int32
        switch model.kvQuantType {
        case .f16: kvMode = 0
        case .q8_0: kvMode = 1
        case .q4_0: kvMode = 2
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: LocalLlamaError.engineFailure("引擎已释放"))
                    return
                }
                do {
                    try self.engine.loadModel(
                        atPath: fileURL.path,
                        contextLength: Int32(model.contextLength),
                        gpuLayers: Int32(model.gpuLayers),
                        kvQuantMode: kvMode
                    )
                    self.stateLock.withLock {
                        self._loadedModelId = model.id
                        self._loadedContextLength = model.contextLength
                        self._loadedKVQuant = model.kvQuantType
                    }
                    cont.resume()
                } catch {
                    cont.resume(throwing: LocalLlamaError.engineFailure(error.localizedDescription))
                }
            }
        }
    }

    public func unload() async {
        requestCancel()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                guard let self else {
                    cont.resume()
                    return
                }
                self.engine.unloadModel()
                self.stateLock.withLock {
                    self._loadedModelId = nil
                }
                cont.resume()
            }
        }
    }

    public func saveKVSnapshot(named fileName: String) async -> Bool {
        let path = Self.kvCacheDirectoryURL.appendingPathComponent(fileName).path
        return await withCheckedContinuation { cont in
            queue.async { [weak self] in
                cont.resume(returning: self?.engine.saveState(toPath: path) ?? false)
            }
        }
    }

    public func clearKVSnapshots() -> Int64 {
        let dir = Self.kvCacheDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var freed: Int64 = 0
        for file in files {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            freed += Int64(size)
            try? FileManager.default.removeItem(at: file)
        }
        return freed
    }

    public func kvSnapshotsTotalBytes() -> Int64 {
        let dir = Self.kvCacheDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { sum, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    public func streamCompletion(
        messages: [PromptMessage],
        model: ModelConfig,
        preset: SamplerPreset
    ) -> AsyncThrowingStream<GenerationChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ensureLoaded(model: model, allowDangerOverride: true)
                    stateLock.withLock { _cancelFlag = false }

                    let style = ChatTemplateFormatter.detectStyle(for: model)
                    let formattedPrompt = ChatTemplateFormatter.format(messages: messages, style: style)

                    let bridgeParams = ChlorLlamaSamplingParams()
                    bridgeParams.temperature = Float(preset.temperature)
                    bridgeParams.minP = Float(preset.minP)
                    bridgeParams.topP = Float(preset.topP)
                    bridgeParams.topK = Int32(preset.topK)
                    bridgeParams.repeatPenalty = Float(preset.repeatPenalty)
                    bridgeParams.repeatLastN = Int32(preset.repeatLastN)
                    bridgeParams.frequencyPenalty = Float(preset.frequencyPenalty)
                    bridgeParams.presencePenalty = Float(preset.presencePenalty)
                    bridgeParams.dryMultiplier = Float(preset.dryMultiplier)
                    bridgeParams.dryBase = Float(preset.dryBase)
                    bridgeParams.dryAllowedLength = Int32(preset.dryAllowedLength)
                    bridgeParams.dryPenaltyLastN = Int32(preset.dryPenaltyLastN)
                    bridgeParams.maxTokens = Int32(preset.maxTokens)
                    bridgeParams.stopSequences = preset.stopSequences

                    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                        queue.async { [weak self] in
                            guard let self else {
                                done.resume(throwing: LocalLlamaError.engineFailure("引擎不可用"))
                                return
                            }
                            do {
                                try self.engine.generate(
                                    withPrompt: formattedPrompt,
                                    params: bridgeParams,
                                    onToken: { tokenText, tps in
                                        self.stateLock.withLock { self._lastTokensPerSecond = tps }
                                        continuation.yield(GenerationChunk(text: tokenText, tokensPerSecond: tps, isDone: false))
                                    },
                                    shouldStop: { [weak self] in
                                        guard let self else { return true }
                                        return self.stateLock.withLock { self._cancelFlag }
                                    }
                                )
                                done.resume()
                            } catch {
                                done.resume(throwing: LocalLlamaError.engineFailure(error.localizedDescription))
                            }
                        }
                    }

                    continuation.yield(GenerationChunk(text: "", tokensPerSecond: lastTokensPerSecond, isDone: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.requestCancel()
                task.cancel()
            }
        }
    }
}

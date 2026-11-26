import Foundation
import SwiftUI
import Combine
import LocalAuthentication
import ChlorCore

@MainActor
public final class AppStore: ObservableObject {
    public let database: ChlorDatabase
    public let memoryEngine: MemoryEngine
    public let localBackend = LocalLlamaBackend.shared
    public let openAIClient = OpenAICompatibleClient()
    public let downloadManager = ModelDownloadManager()
    public let wifiServer = WiFiModelTransferServer()
    public let voiceService = VoiceService()

    @Published public var settings: AppSettings = AppSettings()
    @Published public var models: [ModelConfig] = []
    @Published public var presets: [SamplerPreset] = []
    @Published public var characters: [CharacterCard] = []
    @Published public var personas: [Persona] = []
    @Published public var lorebooks: [LorebookEntry] = []
    @Published public var conversations: [Conversation] = []

    /// Active conversation cache
    @Published public var messagesByConversation: [String: [ChatMessage]] = [:]
    @Published public var coreMemoriesByCharacter: [String: [CoreMemoryItem]] = [:]
    @Published public var episodicMemoriesByCharacter: [String: [EpisodicMemory]] = [:]

    /// Runtime & Generation state
    @Published public var loadedModelId: String?
    @Published public var isLoadingModel: Bool = false
    @Published public var isGenerating: Bool = false
    @Published public var streamingText: String = ""
    @Published public var streamingConversationId: String?
    @Published public var currentTokensPerSecond: Double = 0
    @Published public var availableMemoryBytes: Int64 = LocalLlamaBackend.availableMemoryBytes()
    @Published public var isReflectingMemory: Bool = false
    @Published public var lastAssembledPrompt: AssembledPrompt?

    /// Global UI feedback & Privacy Lock
    @Published public var toastMessage: String?
    @Published public var alertError: String?
    @Published public var isLocked: Bool = false

    private var generationTask: Task<Void, Never>?
    private var backgroundUnloadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = docs.appendingPathComponent("chlorme.sqlite")
        do {
            let db = try ChlorDatabase(databaseURL: dbURL)
            self.database = db
            self.memoryEngine = MemoryEngine(database: db)
        } catch {
            fatalError("Failed to initialize ChlorDatabase: \(error)")
        }

        downloadManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        wifiServer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        voiceService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        wifiServer.onModelReceived = { [weak self] model in
            Task { @MainActor in
                await self?.saveModel(model)
                self?.showToast("已接收模型：\(model.name)")
            }
        }
    }

    public func bootstrap() async {
        do {
            try await database.seedDefaultsIfNeeded()
            await reloadAll()
            refreshMemoryStats()
            if settings.enableFaceIDLock {
                isLocked = true
            }
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func reloadAll() async {
        do {
            settings = try await database.loadSettings()
            models = try await database.fetchModels()
            presets = try await database.fetchSamplerPresets()
            characters = try await database.fetchCharacters()
            personas = try await database.fetchPersonas()
            lorebooks = try await database.fetchLorebookEntries()
            conversations = try await database.fetchConversations()
            loadedModelId = localBackend.loadedModelId
            for conv in conversations {
                messagesByConversation[conv.id] = try await database.fetchMessages(conversationId: conv.id)
            }
            for char in characters {
                coreMemoriesByCharacter[char.id] = try await database.fetchCoreMemories(characterId: char.id)
                episodicMemoriesByCharacter[char.id] = try await database.fetchEpisodicMemories(characterId: char.id)
            }
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func refreshMemoryStats() {
        availableMemoryBytes = LocalLlamaBackend.availableMemoryBytes()
        loadedModelId = localBackend.loadedModelId
        currentTokensPerSecond = localBackend.lastTokensPerSecond
    }

    public func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toastMessage == text {
                toastMessage = nil
            }
        }
    }

    // MARK: - Privacy Lock & Scene Lifecycle

    public func authenticateUnlock() {
        let context = LAContext()
        var err: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁 ChlorMe 私密伴侣空间") { success, _ in
                Task { @MainActor in
                    if success {
                        self.isLocked = false
                    }
                }
            }
        } else {
            isLocked = false
        }
    }

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if settings.enableFaceIDLock {
                isLocked = true
            }
            let delay = settings.backgroundUnloadSeconds
            if delay > 0 && localBackend.loadedModelId != nil {
                backgroundUnloadTask?.cancel()
                backgroundUnloadTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                    if !Task.isCancelled {
                        await self.unloadLocalModel()
                    }
                }
            }
        case .active:
            backgroundUnloadTask?.cancel()
            backgroundUnloadTask = nil
            refreshMemoryStats()
        default:
            break
        }
    }

    // MARK: - Settings

    public func saveSettings(_ updated: AppSettings) async {
        settings = updated
        do {
            try await database.saveSettings(updated)
            let primaryName = characters.first?.name ?? "ChlorMe"
            await NotificationManager.configureDailyGreeting(
                enabled: updated.enableDailyGreetingNotification,
                characterName: primaryName,
                hour: updated.greetingHour,
                minute: updated.greetingMinute
            )
        } catch {
            alertError = error.localizedDescription
        }
    }

    // MARK: - Models & Runtime

    public func saveModel(_ model: ModelConfig) async {
        do {
            try await database.saveModel(model)
            models = try await database.fetchModels()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func deleteModel(_ model: ModelConfig) async {
        if loadedModelId == model.id {
            await unloadLocalModel()
        }
        if let url = LocalLlamaBackend.modelFileURL(for: model) {
            try? FileManager.default.removeItem(at: url)
        }
        do {
            try await database.deleteModel(id: model.id)
            models = try await database.fetchModels()
            refreshMemoryStats()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func loadLocalModel(_ model: ModelConfig, allowDanger: Bool = false) async {
        guard model.backendKind == .localGGUF else { return }
        isLoadingModel = true
        defer {
            isLoadingModel = false
            refreshMemoryStats()
        }
        do {
            try await localBackend.ensureLoaded(model: model, allowDangerOverride: allowDanger)
            loadedModelId = model.id
            showToast("已加载：\(model.name)")
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func unloadLocalModel() async {
        await localBackend.unload()
        loadedModelId = nil
        refreshMemoryStats()
        showToast("已释放本地模型内存")
    }

    public func resolvedModel(for conversation: Conversation, character: CharacterCard) -> ModelConfig? {
        if let overrideId = conversation.modelIdOverride, let m = models.first(where: { $0.id == overrideId }) {
            return m
        }
        if let charDefault = character.defaultModelId, let m = models.first(where: { $0.id == charDefault }) {
            return m
        }
        if let loadedId = loadedModelId, let m = models.first(where: { $0.id == loadedId }) {
            return m
        }
        return models.first
    }

    public func resolvedPreset(for conversation: Conversation, character: CharacterCard) -> SamplerPreset {
        if let overrideId = conversation.presetIdOverride, let p = presets.first(where: { $0.id == overrideId }) {
            return p
        }
        if let charDefault = character.defaultPresetId, let p = presets.first(where: { $0.id == charDefault }) {
            return p
        }
        return presets.first ?? DefaultsFactory.defaultSamplerPresets()[0]
    }

    public func resolvedPersona(for conversation: Conversation, character: CharacterCard) -> Persona? {
        if let id = conversation.personaId, let p = personas.first(where: { $0.id == id }) {
            return p
        }
        if let id = character.defaultPersonaId, let p = personas.first(where: { $0.id == id }) {
            return p
        }
        return personas.first(where: \.isDefault) ?? personas.first
    }

    // MARK: - Characters, Personas, Lorebooks, Presets

    public func saveCharacter(_ character: CharacterCard, createConversationIfMissing: Bool = true) async {
        do {
            try await database.saveCharacter(character)
            characters = try await database.fetchCharacters()
            if createConversationIfMissing && !conversations.contains(where: { $0.characterId == character.id }) {
                let conv = Conversation(
                    characterId: character.id,
                    personaId: character.defaultPersonaId ?? personas.first(where: \.isDefault)?.id,
                    title: character.name
                )
                try await database.saveConversation(conv)
                if !character.firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let greeting = ChatMessage(conversationId: conv.id, role: .assistant, content: character.firstMessage)
                    try await database.saveMessage(greeting)
                }
                conversations = try await database.fetchConversations()
                messagesByConversation[conv.id] = try await database.fetchMessages(conversationId: conv.id)
            }
            if (coreMemoriesByCharacter[character.id] ?? []).isEmpty {
                for item in DefaultsFactory.defaultCoreMemories(characterId: character.id) {
                    try await database.upsertCoreMemory(item)
                }
                coreMemoriesByCharacter[character.id] = try await database.fetchCoreMemories(characterId: character.id)
            }
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func deleteCharacter(_ character: CharacterCard) async {
        do {
            try await database.deleteCharacter(id: character.id)
            await reloadAll()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func importCharacterCard(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let card = try CharacterCardV2Codec.importData(data)
            await saveCharacter(card, createConversationIfMissing: true)
            showToast("已导入角色：\(card.name)")
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func savePersona(_ persona: Persona) async {
        do {
            try await database.savePersona(persona)
            personas = try await database.fetchPersonas()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func deletePersona(_ persona: Persona) async {
        do {
            try await database.deletePersona(id: persona.id)
            personas = try await database.fetchPersonas()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func saveLorebook(_ entry: LorebookEntry) async {
        do {
            try await database.saveLorebookEntry(entry)
            lorebooks = try await database.fetchLorebookEntries()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func deleteLorebook(_ entry: LorebookEntry) async {
        do {
            try await database.deleteLorebookEntry(id: entry.id)
            lorebooks = try await database.fetchLorebookEntries()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func saveSamplerPreset(_ preset: SamplerPreset) async {
        do {
            try await database.saveSamplerPreset(preset)
            presets = try await database.fetchSamplerPresets()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func deleteSamplerPreset(_ preset: SamplerPreset) async {
        do {
            try await database.deleteSamplerPreset(id: preset.id)
            presets = try await database.fetchSamplerPresets()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func updateConversation(_ conv: Conversation) async {
        do {
            try await database.saveConversation(conv)
            conversations = try await database.fetchConversations()
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func ensureConversation(for character: CharacterCard) async -> Conversation {
        if let existing = conversations.first(where: { $0.characterId == character.id }) {
            return existing
        }
        return await createNewConversation(for: character, title: character.name)
    }

    @discardableResult
    public func createNewConversation(for character: CharacterCard, title: String? = nil) async -> Conversation {
        let count = conversations.filter { $0.characterId == character.id }.count
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (count == 0 ? character.name : "\(character.name) · 平行线 \(count + 1)")
        let conv = Conversation(
            characterId: character.id,
            personaId: character.defaultPersonaId ?? personas.first(where: \.isDefault)?.id,
            title: resolvedTitle
        )
        await updateConversation(conv)
        if !character.firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let msg = ChatMessage(conversationId: conv.id, role: .assistant, content: character.firstMessage)
            try? await database.saveMessage(msg)
            messagesByConversation[conv.id] = (try? await database.fetchMessages(conversationId: conv.id)) ?? [msg]
        } else {
            messagesByConversation[conv.id] = []
        }
        return conv
    }

    public func deleteConversation(_ conv: Conversation) async {
        do {
            try await database.deleteConversation(id: conv.id)
            messagesByConversation.removeValue(forKey: conv.id)
            conversations = try await database.fetchConversations()
            showToast("已删除会话")
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func clearMessages(in conversation: Conversation, character: CharacterCard) async {
        let msgs = messagesByConversation[conversation.id] ?? []
        do {
            for m in msgs {
                try await database.deleteMessage(id: m.id)
            }
            var resetConv = conversation
            resetConv.rollingSummary = ""
            resetConv.summarizedUntilMessageId = nil
            try await database.saveConversation(resetConv)
            if !character.firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let first = ChatMessage(conversationId: conversation.id, role: .assistant, content: character.firstMessage)
                try await database.saveMessage(first)
            }
            messagesByConversation[conversation.id] = try await database.fetchMessages(conversationId: conversation.id)
            conversations = try await database.fetchConversations()
            showToast("已重置本段对话")
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func instantiateTemplate(_ template: CharacterCard) async {
        var copy = template
        copy.id = UUID().uuidString
        copy.createdAt = Date()
        copy.updatedAt = Date()
        await saveCharacter(copy, createConversationIfMissing: true)
        ChlorHaptics.success()
        showToast("已迎接新伴侣：\(copy.name)")
    }

    public func testRemoteAPI(baseURL: String, apiKey: String?) async throws -> [String] {
        try await openAIClient.fetchAvailableModels(baseURL: baseURL, apiKey: apiKey)
    }

    public func createTranscriptFileURL(conversation: Conversation, character: CharacterCard) -> URL? {
        let msgs = visibleMessages(for: conversation.id)
        let md = OpenAICompatibleClient.exportMarkdownTranscript(character: character, conversation: conversation, messages: msgs)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ChlorMe-\(character.name)-\(df.string(from: Date())).md")
        do {
            try Data(md.utf8).write(to: url)
            return url
        } catch {
            return nil
        }
    }

    public var totalMessageCount: Int {
        messagesByConversation.values.reduce(0) { $0 + $1.filter(\.isSelected).count }
    }

    public var totalMemoryCount: Int {
        episodicMemoriesByCharacter.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Messaging, Swipe, Edit & Generation

    public func visibleMessages(for conversationId: String) -> [ChatMessage] {
        (messagesByConversation[conversationId] ?? []).filter(\.isSelected)
    }

    public func variants(for groupId: String, in conversationId: String) -> [ChatMessage] {
        (messagesByConversation[conversationId] ?? [])
            .filter { $0.groupId == groupId }
            .sorted { $0.variantIndex < $1.variantIndex }
    }

    public func selectVariant(groupId: String, messageId: String, conversationId: String) async {
        do {
            try await database.selectVariant(groupId: groupId, messageId: messageId)
            messagesByConversation[conversationId] = try await database.fetchMessages(conversationId: conversationId)
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func editMessage(_ message: ChatMessage, newContent: String) async {
        var updated = message
        updated.content = newContent
        do {
            try await database.saveMessage(updated)
            messagesByConversation[message.conversationId] = try await database.fetchMessages(conversationId: message.conversationId)
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func deleteMessage(_ message: ChatMessage) async {
        do {
            try await database.deleteMessage(id: message.id)
            messagesByConversation[message.conversationId] = try await database.fetchMessages(conversationId: message.conversationId)
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func branchFromMessage(_ message: ChatMessage) async {
        do {
            try await database.deleteMessagesAfter(conversationId: message.conversationId, timestamp: message.createdAt)
            messagesByConversation[message.conversationId] = try await database.fetchMessages(conversationId: message.conversationId)
            showToast("已截断此条之后的消息")
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        localBackend.requestCancel()
        isGenerating = false
    }

    public func sendUserMessage(text: String, conversation: Conversation, character: CharacterCard) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        let userMsg = ChatMessage(conversationId: conversation.id, role: .user, content: trimmed)
        do {
            try await database.saveMessage(userMsg)
            messagesByConversation[conversation.id] = try await database.fetchMessages(conversationId: conversation.id)
            conversations = try await database.fetchConversations()
        } catch {
            alertError = error.localizedDescription
            return
        }

        await generateAssistantReply(conversation: conversation, character: character, swipeGroupId: nil)
    }

    public func regenerateSwipe(for assistantMessage: ChatMessage, conversation: Conversation, character: CharacterCard) async {
        guard !isGenerating else { return }
        await generateAssistantReply(conversation: conversation, character: character, swipeGroupId: assistantMessage.groupId)
    }

    public func generateAssistantReply(
        conversation: Conversation,
        character: CharacterCard,
        swipeGroupId: String?
    ) async {
        guard let model = resolvedModel(for: conversation, character: character) else {
            alertError = "还没有可用模型。请前往「模型」页下载/导入 GGUF，或添加一个 OpenAI 兼容远程接口。"
            return
        }
        let preset = resolvedPreset(for: conversation, character: character)
        let persona = resolvedPersona(for: conversation, character: character)

        isGenerating = true
        streamingText = ""
        streamingConversationId = conversation.id

        // Build history excluding the swipe group being regenerated
        var activeHistory = visibleMessages(for: conversation.id)
        if let swipeGroupId {
            activeHistory.removeAll { $0.groupId == swipeGroupId }
        }
        let queryText = activeHistory.last?.content ?? ""

        // Recall memories & assemble prompt
        let recalled = (try? await memoryEngine.recallMemories(
            characterId: character.id,
            query: queryText,
            topK: settings.memoryRecallTopK
        )) ?? []
        let coreMems = coreMemoriesByCharacter[character.id] ?? []
        let charLore = lorebooks.filter { $0.characterId == nil || $0.characterId == character.id }

        let assembled = PromptAssembler.assemble(
            character: character,
            persona: persona,
            conversation: conversation,
            historyMessages: activeHistory,
            coreMemories: coreMems,
            recalledMemories: recalled,
            allLorebooks: charLore,
            settings: settings,
            contextLength: model.contextLength,
            maxGenerationTokens: preset.maxTokens
        )
        lastAssembledPrompt = assembled

        let backend: LLMBackend = (model.backendKind == .localGGUF) ? localBackend : openAIClient

        generationTask = Task {
            var accumulated = ""
            var finalTps: Double?
            do {
                let stream = backend.streamCompletion(messages: assembled.messages, model: model, preset: preset)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if !chunk.text.isEmpty {
                        accumulated += chunk.text
                        streamingText = accumulated
                    }
                    if let tps = chunk.tokensPerSecond {
                        finalTps = tps
                        currentTokensPerSecond = tps
                    }
                }
            } catch {
                if !Task.isCancelled {
                    alertError = error.localizedDescription
                }
            }

            let cleaned = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                let groupId = swipeGroupId ?? UUID().uuidString
                let nextVariantIndex: Int
                if let swipeGroupId {
                    nextVariantIndex = variants(for: swipeGroupId, in: conversation.id).count
                } else {
                    nextVariantIndex = 0
                }
                let assistantMsg = ChatMessage(
                    conversationId: conversation.id,
                    role: .assistant,
                    content: cleaned,
                    groupId: groupId,
                    variantIndex: nextVariantIndex,
                    isSelected: true,
                    tokensPerSecond: finalTps
                )
                try? await database.saveMessage(assistantMsg)
                messagesByConversation[conversation.id] = (try? await database.fetchMessages(conversationId: conversation.id)) ?? []
                conversations = (try? await database.fetchConversations()) ?? conversations
                if character.autoSpeakReplies {
                    voiceService.speak(
                        text: cleaned,
                        messageId: assistantMsg.id,
                        voiceIdentifier: character.voiceIdentifier,
                        rate: character.voiceRate,
                        pitch: character.voicePitch
                    )
                }
            }

            streamingText = ""
            streamingConversationId = nil
            isGenerating = false
            refreshMemoryStats()

            // Auto-reflect when unmemorized message count reaches threshold
            let unmemorized = visibleMessages(for: conversation.id).filter { !$0.isMemorized }
            if settings.autoReflectMessageThreshold > 0 && unmemorized.count >= settings.autoReflectMessageThreshold {
                await reflectMemories(for: conversation, character: character, silent: true)
            }
        }
    }

    // MARK: - Companion Memory Operations

    public func upsertCoreMemory(characterId: String, key: String, value: String) async {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedVal.isEmpty else { return }
        do {
            try await database.upsertCoreMemory(CoreMemoryItem(characterId: characterId, key: trimmedKey, value: trimmedVal))
            coreMemoriesByCharacter[characterId] = try await database.fetchCoreMemories(characterId: characterId)
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func deleteCoreMemory(_ item: CoreMemoryItem) async {
        do {
            try await database.deleteCoreMemory(id: item.id)
            coreMemoriesByCharacter[item.characterId] = try await database.fetchCoreMemories(characterId: item.characterId)
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func addOrUpdateEpisodicMemory(
        existing: EpisodicMemory? = nil,
        characterId: String,
        content: String,
        category: MemoryCategory,
        importance: Int,
        mood: String,
        isPinned: Bool
    ) async {
        do {
            if var item = existing {
                item.content = content
                item.category = category
                item.importance = importance
                item.mood = mood
                item.isPinned = isPinned
                item.embedding = EmbeddingEngine.embed(content)
                try await database.saveEpisodicMemory(item)
            } else {
                _ = try await memoryEngine.saveOrMergeEpisodicMemory(
                    characterId: characterId,
                    content: content,
                    category: category,
                    importance: importance,
                    mood: mood,
                    isPinned: isPinned
                )
            }
            episodicMemoriesByCharacter[characterId] = try await database.fetchEpisodicMemories(characterId: characterId)
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func togglePinMemory(_ memory: EpisodicMemory) async {
        var copy = memory
        copy.isPinned.toggle()
        do {
            try await database.saveEpisodicMemory(copy)
            episodicMemoriesByCharacter[memory.characterId] = try await database.fetchEpisodicMemories(characterId: memory.characterId)
        } catch {
            alertError = error.localizedDescription
        }
    }

    public func deleteEpisodicMemory(_ memory: EpisodicMemory) async {
        do {
            try await database.deleteEpisodicMemory(id: memory.id)
            episodicMemoriesByCharacter[memory.characterId] = try await database.fetchEpisodicMemories(characterId: memory.characterId)
        } catch {
            alertError = error.localizedDescription
        }
    }

    /// Runs a quiet reflection pass using the active model to extract core updates + diary memories + rolling summary.
    public func reflectMemories(for conversation: Conversation, character: CharacterCard, silent: Bool = false) async {
        guard !isReflectingMemory, !isGenerating else { return }
        guard let model = resolvedModel(for: conversation, character: character) else {
            if !silent { alertError = "需要先配置或加载一个模型才能自动整理回忆" }
            return
        }

        let unmemorized = visibleMessages(for: conversation.id).filter { !$0.isMemorized }
        guard !unmemorized.isEmpty else {
            if !silent { showToast("最近的对话都已整理过啦") }
            return
        }

        isReflectingMemory = true
        defer { isReflectingMemory = false }

        let core = coreMemoriesByCharacter[character.id] ?? []
        let reflectPrompt = MemoryEngine.buildReflectionPrompt(
            characterName: character.name,
            existingCore: core,
            recentMessages: Array(unmemorized.suffix(16))
        )
        let reflectPreset = SamplerPreset(
            name: "Reflection",
            temperature: 0.25,
            minP: 0.05,
            topP: 0.9,
            topK: 40,
            repeatPenalty: 1.05,
            dryMultiplier: 0.0,
            maxTokens: 384
        )
        let backend: LLMBackend = (model.backendKind == .localGGUF) ? localBackend : openAIClient

        var output = ""
        do {
            for try await chunk in backend.streamCompletion(messages: reflectPrompt, model: model, preset: reflectPreset) {
                output += chunk.text
            }
            if let parsed = MemoryEngine.parseReflectionJSON(output) {
                let added = try await memoryEngine.applyReflection(
                    parsed,
                    characterId: character.id,
                    processedMessageIds: unmemorized.map(\.id)
                )
                if let mood = parsed.moodUpdate?.trimmingCharacters(in: .whitespacesAndNewlines), !mood.isEmpty {
                    var updatedChar = character
                    updatedChar.moodLabel = mood
                    try await database.saveCharacter(updatedChar)
                    characters = try await database.fetchCharacters()
                }
                coreMemoriesByCharacter[character.id] = try await database.fetchCoreMemories(characterId: character.id)
                episodicMemoriesByCharacter[character.id] = try await database.fetchEpisodicMemories(characterId: character.id)
                messagesByConversation[conversation.id] = try await database.fetchMessages(conversationId: conversation.id)
                if !silent {
                    showToast(added > 0 ? "已记下 \(added) 条新回忆" : "已同步核心状态，暂无新增碎片")
                }
            } else if !silent {
                showToast("模型输出未能解析为 JSON，可在手账中手动记下")
            }

            // Compress older turns into rolling summary when history exceeds window
            let allActive = visibleMessages(for: conversation.id)
            if allActive.count > settings.maxHistoryMessages + 8 {
                let overflowCount = allActive.count - settings.maxHistoryMessages
                let toSummarize = Array(allActive.prefix(overflowCount))
                let sumPrompt = MemoryEngine.buildRollingSummaryPrompt(
                    characterName: character.name,
                    previousSummary: conversation.rollingSummary,
                    olderMessages: toSummarize
                )
                var summaryOut = ""
                for try await chunk in backend.streamCompletion(messages: sumPrompt, model: model, preset: reflectPreset) {
                    summaryOut += chunk.text
                }
                let cleanSummary = summaryOut.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanSummary.isEmpty {
                    var updatedConv = conversation
                    updatedConv.rollingSummary = cleanSummary
                    updatedConv.summarizedUntilMessageId = toSummarize.last?.id
                    try await database.saveConversation(updatedConv)
                    conversations = try await database.fetchConversations()
                }
            }
        } catch {
            if !silent {
                alertError = "整理回忆失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Backup & Restore

    public func createBackupFileURL() async throws -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("ChlorMe-Backup-\(df.string(from: Date())).sqlite")
        try await database.exportBackupCopy(to: dest)
        return dest
    }

    public func restoreBackup(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try await database.restoreFromBackup(at: url)
            await reloadAll()
            showToast("已恢复伴侣与全部回忆备份")
        } catch {
            alertError = "恢复备份失败：\(error.localizedDescription)"
        }
    }
}

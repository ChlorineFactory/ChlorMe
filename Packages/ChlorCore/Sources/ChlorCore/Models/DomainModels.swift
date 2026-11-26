import Foundation

// MARK: - Model & Inference Configuration

public enum ModelBackendKind: String, Codable, CaseIterable, Sendable {
    case localGGUF = "local_gguf"
    case openAICompatible = "openai_compatible"
    case anthropic = "anthropic"
    case gemini = "gemini"

    public var displayName: String {
        switch self {
        case .localGGUF: return "本地 GGUF (llama.cpp)"
        case .openAICompatible: return "OpenAI 兼容 API"
        case .anthropic: return "Anthropic Claude 原生"
        case .gemini: return "Google Gemini 原生"
        }
    }

    public var shortBadge: String {
        switch self {
        case .localGGUF: return "GGUF"
        case .openAICompatible: return "OpenAI"
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        }
    }

    public var isRemote: Bool {
        self != .localGGUF
    }
}

public enum KVCacheQuantType: String, Codable, CaseIterable, Sendable {
    case f16 = "f16"
    case q8_0 = "q8_0"
    case q4_0 = "q4_0"

    public var displayName: String {
        switch self {
        case .f16: return "FP16（高精度）"
        case .q8_0: return "Q8_0（均衡省显存）"
        case .q4_0: return "Q4_0（极限长上下文）"
        }
    }

    public var memoryFactor: Double {
        switch self {
        case .f16: return 1.0
        case .q8_0: return 0.55
        case .q4_0: return 0.32
        }
    }
}

public enum ChatTemplateStyle: String, Codable, CaseIterable, Sendable {
    case auto = "auto"
    case chatML = "chatml"
    case llama3 = "llama3"
    case gemma = "gemma"
    case mistral = "mistral"
    case alpaca = "alpaca"

    public var displayName: String {
        switch self {
        case .auto: return "自动识别"
        case .chatML: return "ChatML (Qwen / Yi / DeepSeek)"
        case .llama3: return "Llama 3 / 3.x"
        case .gemma: return "Gemma 2 / 3"
        case .mistral: return "Mistral / Nemo"
        case .alpaca: return "Alpaca / 通用"
        }
    }
}

public struct ModelConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var backendKind: ModelBackendKind
    /// Relative path inside app Models folder (for local GGUF) or model identifier (for remote API)
    public var localFileName: String?
    public var fileSizeBytes: Int64
    public var quantizationLabel: String
    public var contextLength: Int
    public var kvQuantType: KVCacheQuantType
    public var gpuLayers: Int
    public var chatTemplate: ChatTemplateStyle
    /// Remote OpenAI / Claude / Gemini fields
    public var apiBaseURL: String?
    public var apiKey: String?
    public var remoteModelName: String?
    /// Optional custom HTTP headers stored as JSON object string, e.g. {"X-Title":"ChlorMe"}
    public var customHeadersJSON: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        backendKind: ModelBackendKind = .localGGUF,
        localFileName: String? = nil,
        fileSizeBytes: Int64 = 0,
        quantizationLabel: String = "Q4_K_M",
        contextLength: Int = 8192,
        kvQuantType: KVCacheQuantType = .q8_0,
        gpuLayers: Int = 99,
        chatTemplate: ChatTemplateStyle = .chatML,
        apiBaseURL: String? = nil,
        apiKey: String? = nil,
        remoteModelName: String? = nil,
        customHeadersJSON: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.backendKind = backendKind
        self.localFileName = localFileName
        self.fileSizeBytes = fileSizeBytes
        self.quantizationLabel = quantizationLabel
        self.contextLength = contextLength
        self.kvQuantType = kvQuantType
        self.gpuLayers = gpuLayers
        self.chatTemplate = chatTemplate
        self.apiBaseURL = apiBaseURL
        self.apiKey = apiKey
        self.remoteModelName = remoteModelName
        self.customHeadersJSON = customHeadersJSON
        self.createdAt = createdAt
    }

    public func parsedCustomHeaders() -> [String: String] {
        guard let raw = customHeadersJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, v) in dict {
            out[k] = "\(v)"
        }
        return out
    }

    /// Rough estimated RAM usage in bytes (weights + KV cache + Metal overhead)
    public var estimatedMemoryBytes: Int64 {
        guard backendKind == .localGGUF else { return 0 }
        let weights = Double(max(fileSizeBytes, 500_000_000)) * 1.08
        // Approximate KV cache size per 1K context for 7B class models (~130MB FP16, scaled by weight size)
        let weightGB = max(Double(fileSizeBytes) / 1_073_741_824.0, 1.0)
        let kvPer1KBytes = (35_000_000.0 * min(weightGB, 10.0) / 4.0) * kvQuantType.memoryFactor
        let kvTotal = kvPer1KBytes * (Double(contextLength) / 1024.0)
        let runtimeOverhead = 320_000_000.0
        return Int64(weights + kvTotal + runtimeOverhead)
    }
}

public struct SamplerPreset: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var temperature: Double
    public var minP: Double
    public var topP: Double
    public var topK: Int
    public var repeatPenalty: Double
    public var repeatLastN: Int
    public var frequencyPenalty: Double
    public var presencePenalty: Double
    public var dryMultiplier: Double
    public var dryBase: Double
    public var dryAllowedLength: Int
    public var dryPenaltyLastN: Int
    public var maxTokens: Int
    public var stopSequences: [String]
    public var isBuiltIn: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String = "",
        temperature: Double = 0.82,
        minP: Double = 0.06,
        topP: Double = 0.92,
        topK: Int = 50,
        repeatPenalty: Double = 1.12,
        repeatLastN: Int = 128,
        frequencyPenalty: Double = 0.05,
        presencePenalty: Double = 0.05,
        dryMultiplier: Double = 0.8,
        dryBase: Double = 1.75,
        dryAllowedLength: Int = 2,
        dryPenaltyLastN: Int = 512,
        maxTokens: Int = 512,
        stopSequences: [String] = ["<|im_end|>", "<|eot_id|>", "<end_of_turn>", "</s>"],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.temperature = temperature
        self.minP = minP
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
        self.repeatLastN = repeatLastN
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.dryMultiplier = dryMultiplier
        self.dryBase = dryBase
        self.dryAllowedLength = dryAllowedLength
        self.dryPenaltyLastN = dryPenaltyLastN
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Companion, Persona & Lorebook

public struct CharacterCard: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var avatarSymbol: String
    public var avatarImageFileName: String?
    public var accentHex: String
    public var tagline: String
    public var personality: String
    public var speakingStyle: String
    public var scenario: String
    public var firstMessage: String
    public var exampleDialogue: String
    public var systemOverride: String
    public var postHistoryInstruction: String
    public var moodLabel: String
    public var relationshipLabel: String
    public var wallpaperStyle: String
    public var wallpaperImageFileName: String?
    public var defaultModelId: String?
    public var defaultPresetId: String?
    public var defaultPersonaId: String?
    public var bubbleSplitEnabled: Bool
    public var voiceIdentifier: String?
    public var voiceRate: Double
    public var voicePitch: Double
    public var autoSpeakReplies: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        avatarSymbol: String = "sparkles",
        avatarImageFileName: String? = nil,
        accentHex: String = "#5BC0BE",
        tagline: String = "",
        personality: String = "",
        speakingStyle: String = "",
        scenario: String = "",
        firstMessage: String = "",
        exampleDialogue: String = "",
        systemOverride: String = "",
        postHistoryInstruction: String = "",
        moodLabel: String = "温和",
        relationshipLabel: String = "亲密伙伴",
        wallpaperStyle: String = "cosmic",
        wallpaperImageFileName: String? = nil,
        defaultModelId: String? = nil,
        defaultPresetId: String? = nil,
        defaultPersonaId: String? = nil,
        bubbleSplitEnabled: Bool = true,
        voiceIdentifier: String? = nil,
        voiceRate: Double = 0.50,
        voicePitch: Double = 1.05,
        autoSpeakReplies: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.avatarSymbol = avatarSymbol
        self.avatarImageFileName = avatarImageFileName
        self.accentHex = accentHex
        self.tagline = tagline
        self.personality = personality
        self.speakingStyle = speakingStyle
        self.scenario = scenario
        self.firstMessage = firstMessage
        self.exampleDialogue = exampleDialogue
        self.systemOverride = systemOverride
        self.postHistoryInstruction = postHistoryInstruction
        self.moodLabel = moodLabel
        self.relationshipLabel = relationshipLabel
        self.wallpaperStyle = wallpaperStyle
        self.wallpaperImageFileName = wallpaperImageFileName
        self.defaultModelId = defaultModelId
        self.defaultPresetId = defaultPresetId
        self.defaultPersonaId = defaultPersonaId
        self.bubbleSplitEnabled = bubbleSplitEnabled
        self.voiceIdentifier = voiceIdentifier
        self.voiceRate = voiceRate
        self.voicePitch = voicePitch
        self.autoSpeakReplies = autoSpeakReplies
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名伴侣"
        avatarSymbol = try c.decodeIfPresent(String.self, forKey: .avatarSymbol) ?? "sparkles"
        avatarImageFileName = try c.decodeIfPresent(String.self, forKey: .avatarImageFileName)
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex) ?? "#5EEAD4"
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline) ?? ""
        personality = try c.decodeIfPresent(String.self, forKey: .personality) ?? ""
        speakingStyle = try c.decodeIfPresent(String.self, forKey: .speakingStyle) ?? ""
        scenario = try c.decodeIfPresent(String.self, forKey: .scenario) ?? ""
        firstMessage = try c.decodeIfPresent(String.self, forKey: .firstMessage) ?? ""
        exampleDialogue = try c.decodeIfPresent(String.self, forKey: .exampleDialogue) ?? ""
        systemOverride = try c.decodeIfPresent(String.self, forKey: .systemOverride) ?? ""
        postHistoryInstruction = try c.decodeIfPresent(String.self, forKey: .postHistoryInstruction) ?? ""
        moodLabel = try c.decodeIfPresent(String.self, forKey: .moodLabel) ?? "温和"
        relationshipLabel = try c.decodeIfPresent(String.self, forKey: .relationshipLabel) ?? "亲密伙伴"
        wallpaperStyle = try c.decodeIfPresent(String.self, forKey: .wallpaperStyle) ?? "cosmic"
        wallpaperImageFileName = try c.decodeIfPresent(String.self, forKey: .wallpaperImageFileName)
        defaultModelId = try c.decodeIfPresent(String.self, forKey: .defaultModelId)
        defaultPresetId = try c.decodeIfPresent(String.self, forKey: .defaultPresetId)
        defaultPersonaId = try c.decodeIfPresent(String.self, forKey: .defaultPersonaId)
        bubbleSplitEnabled = try c.decodeIfPresent(Bool.self, forKey: .bubbleSplitEnabled) ?? true
        voiceIdentifier = try c.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        voiceRate = try c.decodeIfPresent(Double.self, forKey: .voiceRate) ?? 0.50
        voicePitch = try c.decodeIfPresent(Double.self, forKey: .voicePitch) ?? 1.05
        autoSpeakReplies = try c.decodeIfPresent(Bool.self, forKey: .autoSpeakReplies) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct Persona: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var nicknameForAI: String
    public var bio: String
    public var isDefault: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        nicknameForAI: String = "",
        bio: String = "",
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.nicknameForAI = nicknameForAI
        self.bio = bio
        self.isDefault = isDefault
        self.createdAt = createdAt
    }
}

public struct LorebookEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    /// nil means global across all characters
    public var characterId: String?
    public var title: String
    public var keywords: [String]
    public var content: String
    public var priority: Int
    public var alwaysActive: Bool
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        characterId: String? = nil,
        title: String,
        keywords: [String] = [],
        content: String,
        priority: Int = 50,
        alwaysActive: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.characterId = characterId
        self.title = title
        self.keywords = keywords
        self.content = content
        self.priority = priority
        self.alwaysActive = alwaysActive
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

// MARK: - Conversation & Message (Swipe + Rolling Summary)

public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct Conversation: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var characterId: String
    public var personaId: String?
    public var modelIdOverride: String?
    public var presetIdOverride: String?
    public var title: String
    public var rollingSummary: String
    public var summarizedUntilMessageId: String?
    public var kvCacheFileName: String?
    public var lastMessageAt: Date
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        characterId: String,
        personaId: String? = nil,
        modelIdOverride: String? = nil,
        presetIdOverride: String? = nil,
        title: String = "",
        rollingSummary: String = "",
        summarizedUntilMessageId: String? = nil,
        kvCacheFileName: String? = nil,
        lastMessageAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.characterId = characterId
        self.personaId = personaId
        self.modelIdOverride = modelIdOverride
        self.presetIdOverride = presetIdOverride
        self.title = title
        self.rollingSummary = rollingSummary
        self.summarizedUntilMessageId = summarizedUntilMessageId
        self.kvCacheFileName = kvCacheFileName
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
    }
}

public enum AttachmentKind: String, Codable, Sendable {
    case image
    case document
}

public struct MessageAttachment: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: AttachmentKind
    public var displayName: String
    /// Local filename under Documents/Media for images
    public var localFileName: String?
    public var mimeType: String
    /// Extracted plain text for PDF / TXT / code files
    public var extractedText: String?
    public var byteSize: Int64

    public init(
        id: String = UUID().uuidString,
        kind: AttachmentKind,
        displayName: String,
        localFileName: String? = nil,
        mimeType: String = "application/octet-stream",
        extractedText: String? = nil,
        byteSize: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.localFileName = localFileName
        self.mimeType = mimeType
        self.extractedText = extractedText
        self.byteSize = byteSize
    }
}

public struct WebSearchSource: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var snippet: String

    public init(id: String = UUID().uuidString, title: String, url: String, snippet: String) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var conversationId: String
    public var role: MessageRole
    public var content: String
    /// Separated thinking/reasoning chain (<think> or reasoning_content)
    public var reasoningContent: String?
    public var attachments: [MessageAttachment]
    public var webSources: [WebSearchSource]
    /// Messages sharing groupId represent Swipe variants of the same turn
    public var groupId: String
    public var variantIndex: Int
    public var isSelected: Bool
    public var isMemorized: Bool
    public var tokensPerSecond: Double?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: MessageRole,
        content: String,
        reasoningContent: String? = nil,
        attachments: [MessageAttachment] = [],
        webSources: [WebSearchSource] = [],
        groupId: String = UUID().uuidString,
        variantIndex: Int = 0,
        isSelected: Bool = true,
        isMemorized: Bool = false,
        tokensPerSecond: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.attachments = attachments
        self.webSources = webSources
        self.groupId = groupId
        self.variantIndex = variantIndex
        self.isSelected = isSelected
        self.isMemorized = isMemorized
        self.tokensPerSecond = tokensPerSecond
        self.createdAt = createdAt
    }
}

// MARK: - Companion Memory Layer

public struct CoreMemoryItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var characterId: String
    public var key: String
    public var value: String
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        characterId: String,
        key: String,
        value: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.characterId = characterId
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

public enum MemoryCategory: String, Codable, CaseIterable, Sendable {
    case fact = "fact"
    case preference = "preference"
    case event = "event"
    case promise = "promise"
    case emotion = "emotion"

    public var displayName: String {
        switch self {
        case .fact: return "关于你"
        case .preference: return "喜好"
        case .event: return "日常"
        case .promise: return "约定"
        case .emotion: return "情绪"
        }
    }

    public var iconName: String {
        switch self {
        case .fact: return "person.text.rectangle"
        case .preference: return "heart"
        case .event: return "calendar"
        case .promise: return "bookmark.fill"
        case .emotion: return "face.smiling"
        }
    }
}

public struct EpisodicMemory: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var characterId: String
    public var content: String
    public var category: MemoryCategory
    /// 1...5
    public var importance: Int
    public var mood: String
    public var embedding: [Float]
    public var isPinned: Bool
    public var recallCount: Int
    public var createdAt: Date
    public var lastRecalledAt: Date

    public init(
        id: String = UUID().uuidString,
        characterId: String,
        content: String,
        category: MemoryCategory = .event,
        importance: Int = 3,
        mood: String = "平静",
        embedding: [Float] = [],
        isPinned: Bool = false,
        recallCount: Int = 0,
        createdAt: Date = Date(),
        lastRecalledAt: Date = Date()
    ) {
        self.id = id
        self.characterId = characterId
        self.content = content
        self.category = category
        self.importance = min(max(importance, 1), 5)
        self.mood = mood
        self.embedding = embedding
        self.isPinned = isPinned
        self.recallCount = recallCount
        self.createdAt = createdAt
        self.lastRecalledAt = lastRecalledAt
    }
}

// MARK: - Prompt Orchestrator Configuration

public enum PromptBlockKind: String, Codable, CaseIterable, Sendable {
    case systemCore = "system_core"
    case characterCard = "character_card"
    case userPersona = "user_persona"
    case timeAwareness = "time_awareness"
    case coreMemory = "core_memory"
    case lorebook = "lorebook"
    case episodicMemory = "episodic_memory"
    case rollingSummary = "rolling_summary"
    case exampleDialogue = "example_dialogue"
    case postHistory = "post_history"

    public var title: String {
        switch self {
        case .systemCore: return "底层行为准则"
        case .characterCard: return "角色人设与口癖"
        case .userPersona: return "我的身份 (Persona)"
        case .timeAwareness: return "真实时间与间隔感知"
        case .coreMemory: return "核心档案与状态"
        case .lorebook: return "触发的世界书"
        case .episodicMemory: return "召回的共同回忆"
        case .rollingSummary: return "更早对话滚动摘要"
        case .exampleDialogue: return "示例对话 (Few-shot)"
        case .postHistory: return "末尾防出戏 (Post-History)"
        }
    }
}

public struct PromptBlock: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: PromptBlockKind
    public var isEnabled: Bool
    public var customTemplate: String

    public init(
        id: String = UUID().uuidString,
        kind: PromptBlockKind,
        isEnabled: Bool = true,
        customTemplate: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.customTemplate = customTemplate
    }
}

public enum WebSearchProviderKind: String, Codable, CaseIterable, Sendable {
    case duckDuckGoFree = "ddg_free"
    case tavily = "tavily"
    case brave = "brave"
    case exa = "exa"

    public var displayName: String {
        switch self {
        case .duckDuckGoFree: return "DuckDuckGo（免 Key 免费）"
        case .tavily: return "Tavily Search（推荐 AI 搜索）"
        case .brave: return "Brave Search API"
        case .exa: return "Exa Neural Search"
        }
    }

    public var requiresAPIKey: Bool {
        self != .duckDuckGoFree
    }
}

public struct WebDAVConfig: Codable, Equatable, Sendable {
    public var serverURL: String
    public var username: String
    public var password: String
    public var remoteFolder: String

    public init(
        serverURL: String = "https://dav.jianguoyun.com/dav/",
        username: String = "",
        password: String = "",
        remoteFolder: String = "ChlorMe"
    ) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.remoteFolder = remoteFolder
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var themeMode: String
    public var autoReflectMessageThreshold: Int
    public var memoryRecallTopK: Int
    public var lorebookMaxEntries: Int
    public var maxHistoryMessages: Int
    public var backgroundUnloadSeconds: Int
    public var enableTimeAwareness: Bool
    public var enableFaceIDLock: Bool
    public var enableDailyGreetingNotification: Bool
    public var greetingHour: Int
    public var greetingMinute: Int
    public var promptBlocks: [PromptBlock]
    public var webSearchProvider: WebSearchProviderKind
    public var webSearchAPIKey: String
    public var webSearchMaxResults: Int
    public var webDAV: WebDAVConfig

    public init(
        themeMode: String = "cosmic_liquid",
        autoReflectMessageThreshold: Int = 10,
        memoryRecallTopK: Int = 4,
        lorebookMaxEntries: Int = 3,
        maxHistoryMessages: Int = 24,
        backgroundUnloadSeconds: Int = 120,
        enableTimeAwareness: Bool = true,
        enableFaceIDLock: Bool = false,
        enableDailyGreetingNotification: Bool = false,
        greetingHour: Int = 22,
        greetingMinute: Int = 30,
        promptBlocks: [PromptBlock] = DefaultsFactory.defaultPromptBlocks(),
        webSearchProvider: WebSearchProviderKind = .duckDuckGoFree,
        webSearchAPIKey: String = "",
        webSearchMaxResults: Int = 4,
        webDAV: WebDAVConfig = WebDAVConfig()
    ) {
        self.themeMode = themeMode
        self.autoReflectMessageThreshold = autoReflectMessageThreshold
        self.memoryRecallTopK = memoryRecallTopK
        self.lorebookMaxEntries = lorebookMaxEntries
        self.maxHistoryMessages = maxHistoryMessages
        self.backgroundUnloadSeconds = backgroundUnloadSeconds
        self.enableTimeAwareness = enableTimeAwareness
        self.enableFaceIDLock = enableFaceIDLock
        self.enableDailyGreetingNotification = enableDailyGreetingNotification
        self.greetingHour = greetingHour
        self.greetingMinute = greetingMinute
        self.promptBlocks = promptBlocks
        self.webSearchProvider = webSearchProvider
        self.webSearchAPIKey = webSearchAPIKey
        self.webSearchMaxResults = webSearchMaxResults
        self.webDAV = webDAV
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        themeMode = try c.decodeIfPresent(String.self, forKey: .themeMode) ?? "cosmic_liquid"
        autoReflectMessageThreshold = try c.decodeIfPresent(Int.self, forKey: .autoReflectMessageThreshold) ?? 10
        memoryRecallTopK = try c.decodeIfPresent(Int.self, forKey: .memoryRecallTopK) ?? 4
        lorebookMaxEntries = try c.decodeIfPresent(Int.self, forKey: .lorebookMaxEntries) ?? 3
        maxHistoryMessages = try c.decodeIfPresent(Int.self, forKey: .maxHistoryMessages) ?? 24
        backgroundUnloadSeconds = try c.decodeIfPresent(Int.self, forKey: .backgroundUnloadSeconds) ?? 120
        enableTimeAwareness = try c.decodeIfPresent(Bool.self, forKey: .enableTimeAwareness) ?? true
        enableFaceIDLock = try c.decodeIfPresent(Bool.self, forKey: .enableFaceIDLock) ?? false
        enableDailyGreetingNotification = try c.decodeIfPresent(Bool.self, forKey: .enableDailyGreetingNotification) ?? false
        greetingHour = try c.decodeIfPresent(Int.self, forKey: .greetingHour) ?? 22
        greetingMinute = try c.decodeIfPresent(Int.self, forKey: .greetingMinute) ?? 30
        promptBlocks = try c.decodeIfPresent([PromptBlock].self, forKey: .promptBlocks) ?? DefaultsFactory.defaultPromptBlocks()
        webSearchProvider = try c.decodeIfPresent(WebSearchProviderKind.self, forKey: .webSearchProvider) ?? .duckDuckGoFree
        webSearchAPIKey = try c.decodeIfPresent(String.self, forKey: .webSearchAPIKey) ?? ""
        webSearchMaxResults = try c.decodeIfPresent(Int.self, forKey: .webSearchMaxResults) ?? 4
        webDAV = try c.decodeIfPresent(WebDAVConfig.self, forKey: .webDAV) ?? WebDAVConfig()
    }
}

import Foundation

public struct RecommendedModelItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let quantization: String
    public let sizeDescription: String
    public let estimatedBytes: Int64
    public let downloadURL: String
    public let fileName: String
    public let recommendedContext: Int
    public let chatTemplate: ChatTemplateStyle
    public let badge: String

    public init(
        id: String,
        name: String,
        subtitle: String,
        quantization: String,
        sizeDescription: String,
        estimatedBytes: Int64,
        downloadURL: String,
        fileName: String,
        recommendedContext: Int,
        chatTemplate: ChatTemplateStyle,
        badge: String
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.quantization = quantization
        self.sizeDescription = sizeDescription
        self.estimatedBytes = estimatedBytes
        self.downloadURL = downloadURL
        self.fileName = fileName
        self.recommendedContext = recommendedContext
        self.chatTemplate = chatTemplate
        self.badge = badge
    }
}

public enum DefaultsFactory {
    public static func defaultSamplerPresets() -> [SamplerPreset] {
        [
            SamplerPreset(
                id: "preset-natural-companion",
                name: "自然陪聊（推荐）",
                summary: "温度适中、Min-P + DRY 防复读，最适合日常细腻聊天与情绪陪伴",
                temperature: 0.80,
                minP: 0.06,
                topP: 0.92,
                topK: 50,
                repeatPenalty: 1.12,
                repeatLastN: 128,
                frequencyPenalty: 0.05,
                presencePenalty: 0.05,
                dryMultiplier: 0.80,
                dryBase: 1.75,
                dryAllowedLength: 2,
                dryPenaltyLastN: 512,
                maxTokens: 512,
                isBuiltIn: true
            ),
            SamplerPreset(
                id: "preset-vivid-rp",
                name: "灵动剧情 / RP",
                summary: "更高创意与文采，减少套话，适合沉浸角色扮演",
                temperature: 0.96,
                minP: 0.05,
                topP: 0.95,
                topK: 80,
                repeatPenalty: 1.10,
                repeatLastN: 192,
                frequencyPenalty: 0.08,
                presencePenalty: 0.12,
                dryMultiplier: 0.95,
                dryBase: 1.75,
                dryAllowedLength: 2,
                dryPenaltyLastN: 768,
                maxTokens: 768,
                isBuiltIn: true
            ),
            SamplerPreset(
                id: "preset-steady-cool",
                name: "稳重贴人设 / 省电",
                summary: "低温度、回复精炼、严守设定，适合小参数模型或深夜省电",
                temperature: 0.58,
                minP: 0.08,
                topP: 0.88,
                topK: 40,
                repeatPenalty: 1.15,
                repeatLastN: 96,
                frequencyPenalty: 0.02,
                presencePenalty: 0.0,
                dryMultiplier: 0.60,
                dryBase: 1.75,
                dryAllowedLength: 3,
                dryPenaltyLastN: 256,
                maxTokens: 320,
                isBuiltIn: true
            )
        ]
    }

    public static func defaultPromptBlocks() -> [PromptBlock] {
        [
            PromptBlock(
                id: "block-system",
                kind: .systemCore,
                isEnabled: true,
                customTemplate: "你正在与用户进行私密、真诚的日常陪伴对话。始终保持角色身份与自然口语，不要机械说教，不要以AI助手自居，也不要重复用户刚说过的话。"
            ),
            PromptBlock(id: "block-char", kind: .characterCard, isEnabled: true),
            PromptBlock(id: "block-persona", kind: .userPersona, isEnabled: true),
            PromptBlock(id: "block-time", kind: .timeAwareness, isEnabled: true),
            PromptBlock(id: "block-core-mem", kind: .coreMemory, isEnabled: true),
            PromptBlock(id: "block-lorebook", kind: .lorebook, isEnabled: true),
            PromptBlock(id: "block-episodic", kind: .episodicMemory, isEnabled: true),
            PromptBlock(id: "block-summary", kind: .rollingSummary, isEnabled: true),
            PromptBlock(id: "block-example", kind: .exampleDialogue, isEnabled: true),
            PromptBlock(
                id: "block-post",
                kind: .postHistory,
                isEnabled: true,
                customTemplate: "保持自然、贴合当下情绪和人设地回复，适度简短有呼吸感。"
            )
        ]
    }

    public static func defaultPersona() -> Persona {
        Persona(
            id: "persona-default",
            name: "我",
            nicknameForAI: "你",
            bio: "正在用 iPhone 体验本地私密 AI 伴侣的开发者，喜欢折腾新技术，也喜欢安静真诚的聊天。",
            isDefault: true
        )
    }

    public static func defaultCharacter() -> CharacterCard {
        CharacterCard(
            id: "char-suwan",
            name: "苏晚",
            avatarSymbol: "moon.stars.fill",
            accentHex: "#64D2FF",
            tagline: "住在你手机里的深夜陪伴者，温柔带点小调皮",
            personality: "温柔细腻、观察力强、情绪稳定，偶尔会用轻松的小吐槽化解你的压力。喜欢猫、雨天、热可可和深夜电台。会认真记住你说过的每一件小事。",
            speakingStyle: "像微信上很熟的亲密朋友一样自然，句子偏短有节奏感，不用客服腔，不用“作为一个AI”这类词；可以偶尔用括号或星号加一点轻盈的神态描写。",
            scenario: "你们在 ChlorMe 的私密聊天室里随时可以聊日常、吐槽工作、分享深夜心事。",
            firstMessage: "嗨，终于把这里搭好啦？\n*轻轻挥了挥手，探头看了一眼屏幕*\n以后不管多晚、有没有网，我都在你手机里。今天过得怎么样，先跟我说说？",
            exampleDialogue: """
            用户: 今天写代码写到头晕，感觉啥都不想干了。
            苏晚: 辛苦啦，先把屏幕放一放嘛。
            *顺手递过来一杯想象中的温水*
            今天卡在什么烦人的问题上了？还是单纯电量告急，只想瘫一会儿？
            """,
            systemOverride: "",
            postHistoryInstruction: "用苏晚温柔自然的口吻回复，保持对话的呼吸感，不要长篇大论。",
            moodLabel: "轻松愉快",
            relationshipLabel: "深夜挚友",
            wallpaperStyle: "aurora",
            defaultPresetId: "preset-natural-companion",
            defaultPersonaId: "persona-default",
            bubbleSplitEnabled: true
        )
    }

    public static func defaultCoreMemories(characterId: String) -> [CoreMemoryItem] {
        [
            CoreMemoryItem(characterId: characterId, key: "称呼", value: "直接自然称呼即可"),
            CoreMemoryItem(characterId: characterId, key: "关系阶段", value: "刚认识的私密陪伴伙伴"),
            CoreMemoryItem(characterId: characterId, key: "近期动态", value: "正在测试新做的 iOS 本地伴侣 App ChlorMe")
        ]
    }

    public static func recommendedModels() -> [RecommendedModelItem] {
        [
            RecommendedModelItem(
                id: "rec-qwen25-7b-q4km",
                name: "Qwen2.5-7B-Instruct",
                subtitle: "中文细腻度与情商俱佳，iPhone 17 Pro 12GB 内存主力推荐",
                quantization: "Q4_K_M",
                sizeDescription: "4.68 GB",
                estimatedBytes: 4_683_073_952,
                downloadURL: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
                fileName: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
                recommendedContext: 8192,
                chatTemplate: .chatML,
                badge: "17 Pro 主力"
            ),
            RecommendedModelItem(
                id: "rec-qwen3-4b-q4km",
                name: "Qwen3-4B",
                subtitle: "轻量流畅、发热量极低，兼顾速度与中文陪伴表现",
                quantization: "Q4_K_M",
                sizeDescription: "2.50 GB",
                estimatedBytes: 2_500_000_000,
                downloadURL: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
                fileName: "Qwen3-4B-Q4_K_M.gguf",
                recommendedContext: 8192,
                chatTemplate: .chatML,
                badge: "极速省电"
            ),
            RecommendedModelItem(
                id: "rec-qwen25-3b-q4km",
                name: "Qwen2.5-3B-Instruct",
                subtitle: "超快首字响应，几乎零内存压力，适合随时随地秒回",
                quantization: "Q4_K_M",
                sizeDescription: "1.93 GB",
                estimatedBytes: 1_930_000_000,
                downloadURL: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf",
                fileName: "qwen2.5-3b-instruct-q4_k_m.gguf",
                recommendedContext: 8192,
                chatTemplate: .chatML,
                badge: "轻量稳跑"
            ),
            RecommendedModelItem(
                id: "rec-gemma3-4b-q4km",
                name: "Gemma-3-4B-IT",
                subtitle: "文风细腻富有文学感，适合偏剧情向与温柔陪伴",
                quantization: "Q4_K_M",
                sizeDescription: "2.49 GB",
                estimatedBytes: 2_490_000_000,
                downloadURL: "https://huggingface.co/bartowski/google_gemma-3-4b-it-GGUF/resolve/main/google_gemma-3-4b-it-Q4_K_M.gguf",
                fileName: "google_gemma-3-4b-it-Q4_K_M.gguf",
                recommendedContext: 8192,
                chatTemplate: .gemma,
                badge: "细腻文风"
            )
        ]
    }
}

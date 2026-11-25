import Foundation

public struct ScoredMemory: Identifiable, Sendable {
    public let memory: EpisodicMemory
    public let totalScore: Double
    public let semanticScore: Double
    public let keywordScore: Double
    public let importanceScore: Double
    public let recencyScore: Double

    public var id: String { memory.id }
}

public struct MemoryReflectionResult: Codable, Sendable {
    public struct NewMemoryDraft: Codable, Sendable {
        public var content: String
        public var category: String?
        public var importance: Int?
        public var mood: String?
    }

    public var coreUpdates: [String: String]?
    public var newMemories: [NewMemoryDraft]?
    public var moodUpdate: String?

    enum CodingKeys: String, CodingKey {
        case coreUpdates = "core_updates"
        case newMemories = "new_memories"
        case moodUpdate = "mood_update"
    }
}

public struct MemoryEngine: Sendable {
    public let database: ChlorDatabase

    public init(database: ChlorDatabase) {
        self.database = database
    }

    /// Hybrid companion memory retrieval: semantic (0.55) + FTS5 keyword (0.20) + importance (0.15) + recency (0.10) + pinned boost.
    public func recallMemories(
        characterId: String,
        query: String,
        topK: Int = 4,
        now: Date = Date()
    ) async throws -> [ScoredMemory] {
        guard topK > 0 else { return [] }
        let allMemories = try await database.fetchEpisodicMemories(characterId: characterId)
        guard !allMemories.isEmpty else { return [] }

        let queryVec = EmbeddingEngine.embed(query)
        let ftsScores = try await database.searchEpisodicFTS(characterId: characterId, query: query, limit: 25)

        var scored: [ScoredMemory] = []
        scored.reserveCapacity(allMemories.count)

        for mem in allMemories {
            let vec = mem.embedding.isEmpty ? EmbeddingEngine.embed(mem.content) : mem.embedding
            let semantic = max(0.0, EmbeddingEngine.cosineSimilarity(queryVec, vec))
            let keyword = ftsScores[mem.id] ?? 0.0
            let importance = Double(mem.importance) / 5.0

            let daysSinceRecalled = max(0.0, now.timeIntervalSince(mem.lastRecalledAt) / 86400.0)
            // Half-life scales with importance (importance 1 fades fast; importance 5 stays fresh much longer)
            let halfLifeDays = 7.0 * Double(mem.importance)
            let recency = mem.isPinned ? 1.0 : exp(-daysSinceRecalled / max(halfLifeDays, 1.0))

            // Soft forgetting filter: low-importance (<=2) unpinned memories older than 30 days need strong direct match to resurface
            if !mem.isPinned && mem.importance <= 2 && daysSinceRecalled > 30.0 && semantic < 0.45 && keyword < 0.25 {
                continue
            }

            let pinnedBonus = mem.isPinned ? 0.12 : 0.0
            let total = (semantic * 0.55) + (keyword * 0.20) + (importance * 0.15) + (recency * 0.10) + pinnedBonus

            // Keep memories that have at least minimal relevance or are pinned
            if total >= 0.22 || mem.isPinned {
                scored.append(ScoredMemory(
                    memory: mem,
                    totalScore: total,
                    semanticScore: semantic,
                    keywordScore: keyword,
                    importanceScore: importance,
                    recencyScore: recency
                ))
            }
        }

        scored.sort { $0.totalScore > $1.totalScore }
        let selected = Array(scored.prefix(topK))
        if !selected.isEmpty {
            try await database.recordMemoryRecalls(ids: selected.map(\.id), at: now)
        }
        return selected
    }

    /// Inserts a new memory or merges with an existing highly-similar memory (> 0.88 cosine) to avoid duplicates.
    @discardableResult
    public func saveOrMergeEpisodicMemory(
        characterId: String,
        content: String,
        category: MemoryCategory = .event,
        importance: Int = 3,
        mood: String = "平静",
        isPinned: Bool = false
    ) async throws -> EpisodicMemory {
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let newVec = EmbeddingEngine.embed(cleaned)
        let existing = try await database.fetchEpisodicMemories(characterId: characterId)

        if let duplicate = existing.first(where: { item in
            let v = item.embedding.isEmpty ? EmbeddingEngine.embed(item.content) : item.embedding
            return EmbeddingEngine.cosineSimilarity(newVec, v) >= 0.88
        }) {
            var updated = duplicate
            updated.content = cleaned
            updated.category = category
            updated.importance = max(duplicate.importance, min(max(importance, 1), 5))
            updated.mood = mood
            updated.embedding = newVec
            updated.isPinned = duplicate.isPinned || isPinned
            updated.lastRecalledAt = Date()
            try await database.saveEpisodicMemory(updated)
            return updated
        }

        let fresh = EpisodicMemory(
            characterId: characterId,
            content: cleaned,
            category: category,
            importance: importance,
            mood: mood,
            embedding: newVec,
            isPinned: isPinned
        )
        try await database.saveEpisodicMemory(fresh)
        return fresh
    }

    /// Builds a strict JSON prompt for the local model to reflect on recent unmemorized messages.
    public static func buildReflectionPrompt(
        characterName: String,
        existingCore: [CoreMemoryItem],
        recentMessages: [ChatMessage]
    ) -> [PromptMessage] {
        let coreText = existingCore.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
        let transcript = recentMessages.map { msg in
            let speaker = msg.role == .user ? "用户" : characterName
            return "\(speaker): \(msg.content)"
        }.joined(separator: "\n")

        let system = """
        你是一个精准的伴侣记忆整理模块。阅读下面的对话，提炼值得长期记住的信息。
        只输出合法 JSON，不要输出任何额外解释或前后缀文字。JSON 格式如下：
        {
          "core_updates": {"字段名": "更新后的值"},
          "mood_update": "角色当前情绪（2~4字）",
          "new_memories": [
            {"content": "一句话回忆", "category": "fact|preference|event|promise|emotion", "importance": 1到5, "mood": "情绪词"}
          ]
        }
        规则：
        1. 没有值得记住的新信息时，new_memories 返回空数组 []。
        2. 最多提炼 3 条高质量记忆，不要记寒暄废话。
        3. core_updates 只在用户称呼、关系、重大偏好或近期状态发生变化时填写，否则返回 {}。
        """

        let user = """
        【当前核心档案】
        \(coreText.isEmpty ? "（暂无）" : coreText)

        【最近对话片段】
        \(transcript)
        """

        return [
            PromptMessage(role: .system, content: system),
            PromptMessage(role: .user, content: user)
        ]
    }

    /// Builds a prompt to compress older chat turns into a compact rolling summary.
    public static func buildRollingSummaryPrompt(
        characterName: String,
        previousSummary: String,
        olderMessages: [ChatMessage]
    ) -> [PromptMessage] {
        let transcript = olderMessages.map { msg in
            let speaker = msg.role == .user ? "用户" : characterName
            return "\(speaker): \(msg.content)"
        }.joined(separator: "\n")

        let system = "你是对话摘要助手。请把已有摘要和新的早期对话合并成一段不超过 220 字的第三人称中文自然摘要，保留情感线索、关键事件和未完成约定，不要编造信息。"
        let user = """
        【已有摘要】
        \(previousSummary.isEmpty ? "（无）" : previousSummary)

        【需要并入摘要的对话】
        \(transcript)
        """
        return [
            PromptMessage(role: .system, content: system),
            PromptMessage(role: .user, content: user)
        ]
    }

    /// Resilient JSON parser that tolerates Markdown code fences or leading/trailing text from small local models.
    public static func parseReflectionJSON(_ rawOutput: String) -> MemoryReflectionResult? {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIdx = trimmed.firstIndex(of: "{"),
              let endIdx = trimmed.lastIndex(of: "}") ,
              startIdx <= endIdx else {
            return nil
        }
        let jsonSubstring = String(trimmed[startIdx...endIdx])
        guard let data = jsonSubstring.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MemoryReflectionResult.self, from: data)
    }

    /// Applies parsed reflection updates into SQLite (core memories + deduplicated episodic memories + mood).
    @discardableResult
    public func applyReflection(
        _ result: MemoryReflectionResult,
        characterId: String,
        processedMessageIds: [String]
    ) async throws -> Int {
        var addedCount = 0
        if let updates = result.coreUpdates {
            for (k, v) in updates {
                let key = k.trimmingCharacters(in: .whitespacesAndNewlines)
                let val = v.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !val.isEmpty else { continue }
                try await database.upsertCoreMemory(CoreMemoryItem(characterId: characterId, key: key, value: val))
            }
        }
        if let drafts = result.newMemories {
            for draft in drafts.prefix(4) {
                let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard content.count >= 4 else { continue }
                let category = MemoryCategory(rawValue: (draft.category ?? "event").lowercased()) ?? .event
                let importance = min(max(draft.importance ?? 3, 1), 5)
                let mood = (draft.mood?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "平静"
                _ = try await saveOrMergeEpisodicMemory(
                    characterId: characterId,
                    content: content,
                    category: category,
                    importance: importance,
                    mood: mood
                )
                addedCount += 1
            }
        }
        if !processedMessageIds.isEmpty {
            try await database.markMessagesMemorized(ids: processedMessageIds)
        }
        return addedCount
    }
}

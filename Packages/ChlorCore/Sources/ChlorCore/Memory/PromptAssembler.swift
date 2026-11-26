import Foundation

public struct PromptSectionSnapshot: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let content: String
    public let estimatedTokens: Int

    public init(id: String = UUID().uuidString, title: String, content: String, estimatedTokens: Int) {
        self.id = id
        self.title = title
        self.content = content
        self.estimatedTokens = estimatedTokens
    }
}

public struct AssembledPrompt: Sendable {
    public let messages: [PromptMessage]
    public let sections: [PromptSectionSnapshot]
    public let triggeredLorebooks: [LorebookEntry]
    public let recalledMemories: [ScoredMemory]
    public let estimatedTotalTokens: Int
    public let tokenBudget: Int

    public init(
        messages: [PromptMessage],
        sections: [PromptSectionSnapshot],
        triggeredLorebooks: [LorebookEntry],
        recalledMemories: [ScoredMemory],
        estimatedTotalTokens: Int,
        tokenBudget: Int
    ) {
        self.messages = messages
        self.sections = sections
        self.triggeredLorebooks = triggeredLorebooks
        self.recalledMemories = recalledMemories
        self.estimatedTotalTokens = estimatedTotalTokens
        self.tokenBudget = tokenBudget
    }
}

public enum PromptAssembler {
    /// Rough multilingual token estimator (CJK chars ~1.4 tokens, Latin words ~1.3 tokens)
    public static func estimateTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var cjkCount = 0
        var otherCount = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x3000...0x30FF).contains(v) {
                cjkCount += 1
            } else {
                otherCount += 1
            }
        }
        return max(1, Int(Double(cjkCount) * 1.35 + Double(otherCount) / 3.8))
    }

    public static func matchLorebooks(
        entries: [LorebookEntry],
        recentMessages: [ChatMessage],
        maxEntries: Int
    ) -> [LorebookEntry] {
        let enabled = entries.filter(\.isEnabled)
        guard !enabled.isEmpty, maxEntries > 0 else { return [] }
        let scanText = recentMessages.suffix(4).map(\.content).joined(separator: "\n").lowercased()

        let matched = enabled.filter { entry in
            if entry.alwaysActive { return true }
            return entry.keywords.contains { kw in
                let trimmed = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !trimmed.isEmpty && scanText.contains(trimmed)
            }
        }
        return Array(matched.sorted { $0.priority > $1.priority }.prefix(maxEntries))
    }

    public static func formatTimeAwareness(now: Date, lastMessageAt: Date?) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let period: String
        switch hour {
        case 0..<5: period = "深夜"
        case 5..<8: period = "清晨"
        case 8..<11: period = "上午"
        case 11..<14: period = "中午"
        case 14..<18: period = "下午"
        case 18..<22: period = "晚上"
        default: period = "夜深"
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        var desc = "当前真实时间：\(df.string(from: now))（\(period)）。"

        if let last = lastMessageAt {
            let diff = max(0, now.timeIntervalSince(last))
            if diff < 120 {
                desc += "你们正在连续聊天中。"
            } else if diff < 3600 {
                desc += "距离上一条消息过去了约 \(Int(diff / 60)) 分钟。"
            } else if diff < 86400 {
                desc += "距离上次聊天过去了约 \(Int(diff / 3600)) 小时。"
            } else {
                desc += "距离上次聊天已经过去了 \(Int(diff / 86400)) 天。"
            }
        }
        return desc
    }

    /// Assembles the full prompt according to the user's custom `PromptBlock` ordering and context budget.
    public static func assemble(
        character: CharacterCard,
        persona: Persona?,
        conversation: Conversation,
        historyMessages: [ChatMessage],
        coreMemories: [CoreMemoryItem],
        recalledMemories: [ScoredMemory],
        allLorebooks: [LorebookEntry],
        settings: AppSettings,
        contextLength: Int,
        maxGenerationTokens: Int,
        webSearchContext: String? = nil,
        imageLoader: ((MessageAttachment) -> PromptImageData?)? = nil,
        now: Date = Date()
    ) -> AssembledPrompt {
        let matchedLorebooks = matchLorebooks(
            entries: allLorebooks,
            recentMessages: historyMessages,
            maxEntries: settings.lorebookMaxEntries
        )

        var systemParts: [String] = []
        var sections: [PromptSectionSnapshot] = []
        var postHistoryText: String?

        let lastTurnDate = historyMessages.dropLast().last?.createdAt

        for block in settings.promptBlocks where block.isEnabled {
            let rendered: String
            switch block.kind {
            case .systemCore:
                if !character.systemOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rendered = character.systemOverride
                } else {
                    rendered = block.customTemplate
                }

            case .characterCard:
                var lines: [String] = ["【角色设定】", "姓名：\(character.name)"]
                if !character.relationshipLabel.isEmpty { lines.append("与用户的关系：\(character.relationshipLabel)") }
                if !character.moodLabel.isEmpty { lines.append("当前情绪：\(character.moodLabel)") }
                if !character.personality.isEmpty { lines.append("性格与背景：\(character.personality)") }
                if !character.speakingStyle.isEmpty { lines.append("说话风格：\(character.speakingStyle)") }
                if !character.scenario.isEmpty { lines.append("当前情境：\(character.scenario)") }
                rendered = lines.joined(separator: "\n")

            case .userPersona:
                if let persona {
                    var lines = ["【用户身份】", "名字：\(persona.name)"]
                    if !persona.nicknameForAI.isEmpty { lines.append("希望你称呼TA：\(persona.nicknameForAI)") }
                    if !persona.bio.isEmpty { lines.append("简介：\(persona.bio)") }
                    rendered = lines.joined(separator: "\n")
                } else {
                    rendered = ""
                }

            case .timeAwareness:
                if settings.enableTimeAwareness {
                    rendered = "【时间感知】\n" + formatTimeAwareness(now: now, lastMessageAt: lastTurnDate)
                } else {
                    rendered = ""
                }

            case .coreMemory:
                if !coreMemories.isEmpty {
                    let body = coreMemories.map { "- \($0.key)：\($0.value)" }.joined(separator: "\n")
                    rendered = "【你对用户的核心印象与近况】\n\(body)"
                } else {
                    rendered = ""
                }

            case .lorebook:
                if !matchedLorebooks.isEmpty {
                    let body = matchedLorebooks.map { "- [\($0.title)] \($0.content)" }.joined(separator: "\n")
                    rendered = "【触发的共同设定 / 世界书】\n\(body)"
                } else {
                    rendered = ""
                }

            case .episodicMemory:
                if !recalledMemories.isEmpty {
                    let df = DateFormatter()
                    df.dateFormat = "MM-dd"
                    let body = recalledMemories.map { item in
                        let dateStr = df.string(from: item.memory.createdAt)
                        return "- [\(dateStr) | \(item.memory.mood)] \(item.memory.content)"
                    }.joined(separator: "\n")
                    rendered = "【你回想起的过往回忆（自然融入，不要生硬背诵）】\n\(body)"
                } else {
                    rendered = ""
                }

            case .rollingSummary:
                if !conversation.rollingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rendered = "【更早之前的聊天摘要】\n\(conversation.rollingSummary)"
                } else {
                    rendered = ""
                }

            case .exampleDialogue:
                if !character.exampleDialogue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rendered = "【语气参考示例（模仿口吻，不要照抄内容）】\n\(character.exampleDialogue)"
                } else {
                    rendered = ""
                }

            case .postHistory:
                let note = !character.postHistoryInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? character.postHistoryInstruction
                    : block.customTemplate
                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    postHistoryText = note
                    sections.append(PromptSectionSnapshot(
                        title: block.kind.title,
                        content: note,
                        estimatedTokens: estimateTokens(note)
                    ))
                }
                rendered = ""
            }

            let cleaned = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                systemParts.append(cleaned)
                sections.append(PromptSectionSnapshot(
                    title: block.kind.title,
                    content: cleaned,
                    estimatedTokens: estimateTokens(cleaned)
                ))
            }
        }

        if let webCtx = webSearchContext?.trimmingCharacters(in: .whitespacesAndNewlines), !webCtx.isEmpty {
            systemParts.append(webCtx)
            sections.append(PromptSectionSnapshot(
                title: "实时联网搜索结果",
                content: webCtx,
                estimatedTokens: estimateTokens(webCtx)
            ))
        }

        let systemContent = systemParts.joined(separator: "\n\n")
        let systemTokens = estimateTokens(systemContent)
        let postTokens = postHistoryText.map(estimateTokens) ?? 0
        let inputBudget = max(512, contextLength - maxGenerationTokens - 128)
        let historyBudget = max(256, inputBudget - systemTokens - postTokens)

        // Pack recent messages from newest to oldest within token & count limits
        var keptHistory: [PromptMessage] = []
        var usedHistoryTokens = 0
        let candidateHistory = Array(historyMessages.suffix(settings.maxHistoryMessages))

        for msg in candidateHistory.reversed() {
            var enrichedText = msg.content
            var attachedImages: [PromptImageData] = []
            for att in msg.attachments {
                switch att.kind {
                case .document:
                    if let docText = att.extractedText, !docText.isEmpty {
                        let clipped = String(docText.prefix(6000))
                        enrichedText += "\n\n[附件文档：\(att.displayName)]\n\(clipped)"
                    }
                case .image:
                    if let imgData = imageLoader?(att) {
                        attachedImages.append(imgData)
                    } else {
                        enrichedText += "\n[用户发送了一张图片：\(att.displayName)]"
                    }
                }
            }

            let cost = estimateTokens(enrichedText) + 6 + (attachedImages.count * 256)
            if usedHistoryTokens + cost > historyBudget && !keptHistory.isEmpty {
                break
            }
            keptHistory.append(PromptMessage(role: msg.role, content: enrichedText, images: attachedImages))
            usedHistoryTokens += cost
        }
        keptHistory.reverse()

        sections.append(PromptSectionSnapshot(
            title: "近期对话原文（\(keptHistory.count) 条）",
            content: keptHistory.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n"),
            estimatedTokens: usedHistoryTokens
        ))

        var finalMessages: [PromptMessage] = []
        if !systemContent.isEmpty {
            finalMessages.append(PromptMessage(role: .system, content: systemContent))
        }
        finalMessages.append(contentsOf: keptHistory)
        if let postHistoryText, !postHistoryText.isEmpty {
            finalMessages.append(PromptMessage(role: .system, content: "[提示] " + postHistoryText))
        }

        let totalTokens = systemTokens + usedHistoryTokens + postTokens
        return AssembledPrompt(
            messages: finalMessages,
            sections: sections,
            triggeredLorebooks: matchedLorebooks,
            recalledMemories: recalledMemories,
            estimatedTotalTokens: totalTokens,
            tokenBudget: inputBudget
        )
    }
}

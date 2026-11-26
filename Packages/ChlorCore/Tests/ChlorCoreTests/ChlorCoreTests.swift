import Foundation
import Testing
@testable import ChlorCore

private func makeTempDB() throws -> (ChlorDatabase, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chlorme-test-\(UUID().uuidString)")
    let dbURL = dir.appendingPathComponent("chlorme.sqlite")
    let db = try ChlorDatabase(databaseURL: dbURL)
    return (db, dir)
}

@Test func seedDefaultsAndSwipeVariants() async throws {
    let (db, dir) = try makeTempDB()
    defer { try? FileManager.default.removeItem(at: dir) }

    try await db.seedDefaultsIfNeeded()
    let chars = try await db.fetchCharacters()
    let presets = try await db.fetchSamplerPresets()
    let convs = try await db.fetchConversations()

    #expect(chars.count == 1)
    #expect(chars.first?.name == "苏晚")
    #expect(presets.count == 3)
    #expect(convs.count == 1)

    let convId = convs[0].id
    let group = UUID().uuidString
    let v0 = ChatMessage(conversationId: convId, role: .assistant, content: "候选回复 A", groupId: group, variantIndex: 0, isSelected: true)
    let v1 = ChatMessage(conversationId: convId, role: .assistant, content: "候选回复 B", groupId: group, variantIndex: 1, isSelected: true)
    try await db.saveMessage(v0)
    try await db.saveMessage(v1)

    let selected = try await db.fetchMessages(conversationId: convId, includeUnselectedVariants: false)
    #expect(selected.last?.content == "候选回复 B")

    try await db.selectVariant(groupId: group, messageId: v0.id)
    let afterSwitch = try await db.fetchMessages(conversationId: convId, includeUnselectedVariants: false)
    #expect(afterSwitch.last?.content == "候选回复 A")
}

@Test func hybridMemoryRecallAndDeduplication() async throws {
    let (db, dir) = try makeTempDB()
    defer { try? FileManager.default.removeItem(at: dir) }

    let engine = MemoryEngine(database: db)
    let charId = "char-test"

    let m1 = try await engine.saveOrMergeEpisodicMemory(
        characterId: charId,
        content: "用户家里养了一只叫汤圆的橘猫，最喜欢摸它的下巴",
        category: .fact,
        importance: 5,
        mood: "开心"
    )
    _ = try await engine.saveOrMergeEpisodicMemory(
        characterId: charId,
        content: "今天中午在公司楼下吃了番茄牛肉面",
        category: .event,
        importance: 2,
        mood: "平静"
    )
    let m1Dup = try await engine.saveOrMergeEpisodicMemory(
        characterId: charId,
        content: "用户家里养了一只叫汤圆的橘猫，最喜欢摸它的下巴",
        category: .fact,
        importance: 5,
        mood: "温暖"
    )
    #expect(m1.id == m1Dup.id)

    let all = try await db.fetchEpisodicMemories(characterId: charId)
    #expect(all.count == 2)

    let recalled = try await engine.recallMemories(characterId: charId, query: "汤圆今天又来蹭我了", topK: 2)
    #expect(!recalled.isEmpty)
    #expect(recalled.first?.memory.id == m1.id)
}

@Test func reflectionJSONParsing() {
    let noisyModelOutput = """
    好的，这是提炼结果：
    ```json
    {
      "core_updates": {"称呼": "阿哲", "近期动态": "正在做 ChlorMe"},
      "mood_update": "期待",
      "new_memories": [
        {"content": "用户喜欢喝不加糖的冰美式", "category": "preference", "importance": 4, "mood": "轻松"}
      ]
    }
    ```
    """
    let parsed = MemoryEngine.parseReflectionJSON(noisyModelOutput)
    #expect(parsed != nil)
    #expect(parsed?.coreUpdates?["称呼"] == "阿哲")
    #expect(parsed?.moodUpdate == "期待")
    #expect(parsed?.newMemories?.count == 1)
}

@Test func promptAssemblerLorebookAndBudget() async throws {
    let (db, dir) = try makeTempDB()
    defer { try? FileManager.default.removeItem(at: dir) }

    let char = DefaultsFactory.defaultCharacter()
    let persona = DefaultsFactory.defaultPersona()
    let conv = Conversation(characterId: char.id, personaId: persona.id, title: char.name, rollingSummary: "昨天聊了关于雨天听歌的事。")
    let lore = LorebookEntry(
        characterId: char.id,
        title: "橘猫汤圆",
        keywords: ["汤圆", "橘猫"],
        content: "汤圆是一只 3 岁的肥橘猫，每次开罐头都会冲过来。",
        priority: 90
    )
    let msgs = [
        ChatMessage(conversationId: conv.id, role: .user, content: "刚刚给汤圆开了个鱼罐头")
    ]
    let core = DefaultsFactory.defaultCoreMemories(characterId: char.id)

    let assembled = PromptAssembler.assemble(
        character: char,
        persona: persona,
        conversation: conv,
        historyMessages: msgs,
        coreMemories: core,
        recalledMemories: [],
        allLorebooks: [lore],
        settings: AppSettings(),
        contextLength: 4096,
        maxGenerationTokens: 512
    )

    #expect(assembled.triggeredLorebooks.count == 1)
    #expect(assembled.triggeredLorebooks.first?.title == "橘猫汤圆")
    #expect(assembled.estimatedTotalTokens > 50)
    #expect(assembled.messages.first?.content.contains("汤圆是一只 3 岁的肥橘猫") == true)
    _ = db
}

@Test func characterCardV2JSONAndPNGRoundTrip() throws {
    let card = DefaultsFactory.defaultCharacter()
    let jsonData = try CharacterCardV2Codec.exportJSON(character: card)
    let decodedFromJSON = try CharacterCardV2Codec.decodeJSON(jsonData)
    #expect(decodedFromJSON.name == card.name)
    #expect(decodedFromJSON.firstMessage == card.firstMessage)

    var minimalPNG = Data([137, 80, 78, 71, 13, 10, 26, 10])
    minimalPNG.append(Data([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]))

    let cardPNG = try CharacterCardV2Codec.embedInPNG(pngData: minimalPNG, character: card)
    let decodedFromPNG = try CharacterCardV2Codec.importData(cardPNG)
    #expect(decodedFromPNG.name == card.name)
}

@Test func chatTemplateAndBubbleSplitter() {
    let msgs = [
        PromptMessage(role: .system, content: "你是苏晚"),
        PromptMessage(role: .user, content: "晚安")
    ]
    let chatML = ChatTemplateFormatter.format(messages: msgs, style: .chatML)
    #expect(chatML.contains("<|im_start|>assistant\n"))

    let bubbles = BubbleSplitter.split("今天辛苦啦。\n*递过一杯热牛奶*\n早点休息呀！", enabled: true)
    #expect(bubbles.count == 3)
}

@Test func companionTemplatesLegacyDecodeAndMarkdownExport() throws {
    let templates = DefaultsFactory.companionTemplates()
    #expect(templates.count == 4)

    // Simulate legacy JSON missing new voice/avatar/wallpaper fields
    let legacyJSON = #"{"id":"old-1","name":"旧角色","personality":"温柔"}"#
    let decoded = try JSONDecoder().decode(CharacterCard.self, from: Data(legacyJSON.utf8))
    #expect(decoded.name == "旧角色")
    #expect(decoded.voiceRate == 0.50)
    #expect(decoded.autoSpeakReplies == false)

    let conv = Conversation(characterId: decoded.id, title: "深夜漫谈", rollingSummary: "聊了关于宇宙星云的话题")
    let msgs = [
        ChatMessage(conversationId: conv.id, role: .user, content: "今晚的星星很好看"),
        ChatMessage(conversationId: conv.id, role: .assistant, content: "那我们一起再看一会儿吧")
    ]
    let md = OpenAICompatibleClient.exportMarkdownTranscript(character: decoded, conversation: conv, messages: msgs)
    #expect(md.contains("# 与 旧角色 的私密回忆记录"))
    #expect(md.contains("今晚的星星很好看"))
}

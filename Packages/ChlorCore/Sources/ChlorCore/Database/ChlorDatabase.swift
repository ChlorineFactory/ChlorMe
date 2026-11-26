import Foundation
import SQLite3

public enum ChlorDatabaseError: LocalizedError {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "无法打开数据库：\(msg)"
        case .executeFailed(let msg): return "SQL 执行失败：\(msg)"
        case .prepareFailed(let msg): return "SQL 预处理失败：\(msg)"
        case .stepFailed(let msg): return "SQL 写入失败：\(msg)"
        }
    }
}

/// Thread-safe single-file SQLite database using system libsqlite3 with WAL mode, FTS5, and Float32 vector BLOBs.
public actor ChlorDatabase {
    private var db: OpaquePointer?
    public let databaseURL: URL
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let parentDir = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &handle, flags, nil) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(handle)
            throw ChlorDatabaseError.openFailed(msg)
        }
        self.db = handle
        try Self.bootstrapSchema(db: handle!)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Schema

    private static func bootstrapSchema(db: OpaquePointer) throws {
        let sql = """
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS model_configs (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            backend_kind TEXT NOT NULL,
            local_file_name TEXT,
            file_size_bytes INTEGER NOT NULL DEFAULT 0,
            quantization_label TEXT NOT NULL DEFAULT 'Q4_K_M',
            context_length INTEGER NOT NULL DEFAULT 8192,
            kv_quant_type TEXT NOT NULL DEFAULT 'q8_0',
            gpu_layers INTEGER NOT NULL DEFAULT 99,
            chat_template TEXT NOT NULL DEFAULT 'chatml',
            api_base_url TEXT,
            api_key TEXT,
            remote_model_name TEXT,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sampler_presets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            summary TEXT NOT NULL,
            payload_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS personas (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            nickname_for_ai TEXT NOT NULL,
            bio TEXT NOT NULL,
            is_default INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS characters (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS lorebook_entries (
            id TEXT PRIMARY KEY,
            character_id TEXT,
            title TEXT NOT NULL,
            keywords_json TEXT NOT NULL,
            content TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 50,
            always_active INTEGER NOT NULL DEFAULT 0,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            character_id TEXT NOT NULL,
            persona_id TEXT,
            model_id_override TEXT,
            preset_id_override TEXT,
            title TEXT NOT NULL,
            rolling_summary TEXT NOT NULL DEFAULT '',
            summarized_until_msg_id TEXT,
            kv_cache_file_name TEXT,
            last_message_at REAL NOT NULL,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            group_id TEXT NOT NULL,
            variant_index INTEGER NOT NULL DEFAULT 0,
            is_selected INTEGER NOT NULL DEFAULT 1,
            is_memorized INTEGER NOT NULL DEFAULT 0,
            tokens_per_second REAL,
            created_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_messages_conv_created ON messages(conversation_id, created_at);
        CREATE INDEX IF NOT EXISTS idx_messages_group ON messages(group_id);

        CREATE TABLE IF NOT EXISTS core_memories (
            id TEXT PRIMARY KEY,
            character_id TEXT NOT NULL,
            mem_key TEXT NOT NULL,
            mem_value TEXT NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(character_id, mem_key)
        );

        CREATE TABLE IF NOT EXISTS episodic_memories (
            id TEXT PRIMARY KEY,
            character_id TEXT NOT NULL,
            content TEXT NOT NULL,
            category TEXT NOT NULL,
            importance INTEGER NOT NULL DEFAULT 3,
            mood TEXT NOT NULL DEFAULT '平静',
            embedding BLOB,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            recall_count INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            last_recalled_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_episodic_char ON episodic_memories(character_id, is_pinned, importance);

        CREATE VIRTUAL TABLE IF NOT EXISTS episodic_memories_fts USING fts5(
            memory_id UNINDEXED,
            character_id UNINDEXED,
            content,
            tokenize = 'unicode61'
        );

        CREATE TABLE IF NOT EXISTS app_kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        try execRaw(db: db, sql: sql)

        // Safe additive migrations for existing v1.0.0 user databases (ignore errors if columns already exist)
        let migrations = [
            "ALTER TABLE model_configs ADD COLUMN custom_headers_json TEXT;",
            "ALTER TABLE messages ADD COLUMN reasoning_content TEXT;",
            "ALTER TABLE messages ADD COLUMN attachments_json TEXT;",
            "ALTER TABLE messages ADD COLUMN web_sources_json TEXT;"
        ]
        for alter in migrations {
            _ = try? execRaw(db: db, sql: alter)
        }
    }

    private static func execRaw(db: OpaquePointer, sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errMsg)
            throw ChlorDatabaseError.executeFailed(msg)
        }
    }

    public func seedDefaultsIfNeeded() throws {
        let existingChars = try fetchCharacters()
        let existingPresets = try fetchSamplerPresets()
        let existingPersonas = try fetchPersonas()

        if existingPresets.isEmpty {
            for preset in DefaultsFactory.defaultSamplerPresets() {
                try saveSamplerPreset(preset)
            }
        }
        if existingPersonas.isEmpty {
            try savePersona(DefaultsFactory.defaultPersona())
        }
        if existingChars.isEmpty {
            let suwan = DefaultsFactory.defaultCharacter()
            try saveCharacter(suwan)
            for item in DefaultsFactory.defaultCoreMemories(characterId: suwan.id) {
                try upsertCoreMemory(item)
            }
            let conv = Conversation(
                id: "conv-suwan-default",
                characterId: suwan.id,
                personaId: DefaultsFactory.defaultPersona().id,
                title: suwan.name
            )
            try saveConversation(conv)
            if !suwan.firstMessage.isEmpty {
                let firstMsg = ChatMessage(
                    conversationId: conv.id,
                    role: .assistant,
                    content: suwan.firstMessage
                )
                try saveMessage(firstMsg)
            }
        }
    }

    // MARK: - Backup & Restore

    public func exportBackupCopy(to destinationURL: URL) throws {
        guard let db else { throw ChlorDatabaseError.openFailed("Database closed") }
        // Flush WAL into main db file before copying
        _ = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: databaseURL, to: destinationURL)
    }

    public func restoreFromBackup(at sourceURL: URL) throws {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
        try fm.copyItem(at: sourceURL, to: databaseURL)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &handle, flags, nil) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(handle)
            throw ChlorDatabaseError.openFailed(msg)
        }
        self.db = handle
        try Self.bootstrapSchema(db: handle!)
    }

    // MARK: - AppSettings

    public func loadSettings() throws -> AppSettings {
        let sql = "SELECT value FROM app_kv WHERE key = 'app_settings' LIMIT 1;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW, let text = readText(stmt, 0), let data = text.data(using: .utf8) {
            if let decoded = try? jsonDecoder.decode(AppSettings.self, from: data) {
                return decoded
            }
        }
        return AppSettings()
    }

    public func saveSettings(_ settings: AppSettings) throws {
        let data = try jsonEncoder.encode(settings)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let sql = "INSERT OR REPLACE INTO app_kv (key, value) VALUES ('app_settings', ?);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, json)
        try stepDone(stmt)
    }

    // MARK: - ModelConfig CRUD

    public func fetchModels() throws -> [ModelConfig] {
        let sql = """
        SELECT id, name, backend_kind, local_file_name, file_size_bytes, quantization_label,
               context_length, kv_quant_type, gpu_layers, chat_template, api_base_url, api_key,
               remote_model_name, created_at, custom_headers_json
        FROM model_configs ORDER BY created_at DESC;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var list: [ModelConfig] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let item = ModelConfig(
                id: readText(stmt, 0) ?? UUID().uuidString,
                name: readText(stmt, 1) ?? "",
                backendKind: ModelBackendKind(rawValue: readText(stmt, 2) ?? "") ?? .localGGUF,
                localFileName: readText(stmt, 3),
                fileSizeBytes: sqlite3_column_int64(stmt, 4),
                quantizationLabel: readText(stmt, 5) ?? "Q4_K_M",
                contextLength: Int(sqlite3_column_int(stmt, 6)),
                kvQuantType: KVCacheQuantType(rawValue: readText(stmt, 7) ?? "") ?? .q8_0,
                gpuLayers: Int(sqlite3_column_int(stmt, 8)),
                chatTemplate: ChatTemplateStyle(rawValue: readText(stmt, 9) ?? "") ?? .chatML,
                apiBaseURL: readText(stmt, 10),
                apiKey: readText(stmt, 11),
                remoteModelName: readText(stmt, 12),
                customHeadersJSON: readText(stmt, 14),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13))
            )
            list.append(item)
        }
        return list
    }

    public func saveModel(_ model: ModelConfig) throws {
        let sql = """
        INSERT OR REPLACE INTO model_configs (
            id, name, backend_kind, local_file_name, file_size_bytes, quantization_label,
            context_length, kv_quant_type, gpu_layers, chat_template, api_base_url, api_key,
            remote_model_name, created_at, custom_headers_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, model.id)
        bindText(stmt, 2, model.name)
        bindText(stmt, 3, model.backendKind.rawValue)
        bindOptionalText(stmt, 4, model.localFileName)
        sqlite3_bind_int64(stmt, 5, model.fileSizeBytes)
        bindText(stmt, 6, model.quantizationLabel)
        sqlite3_bind_int(stmt, 7, Int32(model.contextLength))
        bindText(stmt, 8, model.kvQuantType.rawValue)
        sqlite3_bind_int(stmt, 9, Int32(model.gpuLayers))
        bindText(stmt, 10, model.chatTemplate.rawValue)
        bindOptionalText(stmt, 11, model.apiBaseURL)
        bindOptionalText(stmt, 12, model.apiKey)
        bindOptionalText(stmt, 13, model.remoteModelName)
        sqlite3_bind_double(stmt, 14, model.createdAt.timeIntervalSince1970)
        bindOptionalText(stmt, 15, model.customHeadersJSON)
        try stepDone(stmt)
    }

    public func deleteModel(id: String) throws {
        let stmt = try prepare("DELETE FROM model_configs WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        try stepDone(stmt)
    }

    // MARK: - SamplerPreset CRUD

    public func fetchSamplerPresets() throws -> [SamplerPreset] {
        let stmt = try prepare("SELECT payload_json FROM sampler_presets ORDER BY rowid ASC;")
        defer { sqlite3_finalize(stmt) }
        var list: [SamplerPreset] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = readText(stmt, 0), let data = text.data(using: .utf8),
               let preset = try? jsonDecoder.decode(SamplerPreset.self, from: data) {
                list.append(preset)
            }
        }
        return list
    }

    public func saveSamplerPreset(_ preset: SamplerPreset) throws {
        let data = try jsonEncoder.encode(preset)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let stmt = try prepare("INSERT OR REPLACE INTO sampler_presets (id, name, summary, payload_json) VALUES (?, ?, ?, ?);")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, preset.id)
        bindText(stmt, 2, preset.name)
        bindText(stmt, 3, preset.summary)
        bindText(stmt, 4, json)
        try stepDone(stmt)
    }

    public func deleteSamplerPreset(id: String) throws {
        let stmt = try prepare("DELETE FROM sampler_presets WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        try stepDone(stmt)
    }

    // MARK: - Persona CRUD

    public func fetchPersonas() throws -> [Persona] {
        let stmt = try prepare("SELECT id, name, nickname_for_ai, bio, is_default, created_at FROM personas ORDER BY is_default DESC, created_at ASC;")
        defer { sqlite3_finalize(stmt) }
        var list: [Persona] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            list.append(Persona(
                id: readText(stmt, 0) ?? UUID().uuidString,
                name: readText(stmt, 1) ?? "",
                nicknameForAI: readText(stmt, 2) ?? "",
                bio: readText(stmt, 3) ?? "",
                isDefault: sqlite3_column_int(stmt, 4) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            ))
        }
        return list
    }

    public func savePersona(_ persona: Persona) throws {
        if persona.isDefault, let db {
            try Self.execRaw(db: db, sql: "UPDATE personas SET is_default = 0;")
        }
        let stmt = try prepare("INSERT OR REPLACE INTO personas (id, name, nickname_for_ai, bio, is_default, created_at) VALUES (?, ?, ?, ?, ?, ?);")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, persona.id)
        bindText(stmt, 2, persona.name)
        bindText(stmt, 3, persona.nicknameForAI)
        bindText(stmt, 4, persona.bio)
        sqlite3_bind_int(stmt, 5, persona.isDefault ? 1 : 0)
        sqlite3_bind_double(stmt, 6, persona.createdAt.timeIntervalSince1970)
        try stepDone(stmt)
    }

    public func deletePersona(id: String) throws {
        let stmt = try prepare("DELETE FROM personas WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        try stepDone(stmt)
    }

    // MARK: - CharacterCard CRUD

    public func fetchCharacters() throws -> [CharacterCard] {
        let stmt = try prepare("SELECT payload_json FROM characters ORDER BY updated_at DESC;")
        defer { sqlite3_finalize(stmt) }
        var list: [CharacterCard] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = readText(stmt, 0), let data = text.data(using: .utf8),
               let character = try? jsonDecoder.decode(CharacterCard.self, from: data) {
                list.append(character)
            }
        }
        return list
    }

    public func saveCharacter(_ character: CharacterCard) throws {
        var copy = character
        copy.updatedAt = Date()
        let data = try jsonEncoder.encode(copy)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let stmt = try prepare("INSERT OR REPLACE INTO characters (id, name, payload_json, updated_at) VALUES (?, ?, ?, ?);")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, copy.id)
        bindText(stmt, 2, copy.name)
        bindText(stmt, 3, json)
        sqlite3_bind_double(stmt, 4, copy.updatedAt.timeIntervalSince1970)
        try stepDone(stmt)
    }

    public func deleteCharacter(id: String) throws {
        for sql in [
            "DELETE FROM characters WHERE id = ?;",
            "DELETE FROM core_memories WHERE character_id = ?;",
            "DELETE FROM episodic_memories WHERE character_id = ?;",
            "DELETE FROM episodic_memories_fts WHERE character_id = ?;",
            "DELETE FROM lorebook_entries WHERE character_id = ?;"
        ] {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            try stepDone(stmt)
        }
        let convs = try fetchConversations().filter { $0.characterId == id }
        for conv in convs {
            try deleteConversation(id: conv.id)
        }
    }

    // MARK: - Lorebook CRUD

    public func fetchLorebookEntries(characterId: String? = nil) throws -> [LorebookEntry] {
        let sql: String
        if characterId != nil {
            sql = "SELECT id, character_id, title, keywords_json, content, priority, always_active, is_enabled, created_at FROM lorebook_entries WHERE character_id IS NULL OR character_id = ? ORDER BY priority DESC, created_at DESC;"
        } else {
            sql = "SELECT id, character_id, title, keywords_json, content, priority, always_active, is_enabled, created_at FROM lorebook_entries ORDER BY priority DESC, created_at DESC;"
        }
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        if let characterId {
            bindText(stmt, 1, characterId)
        }
        var list: [LorebookEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let kwJson = readText(stmt, 3) ?? "[]"
            let keywords = (try? jsonDecoder.decode([String].self, from: Data(kwJson.utf8))) ?? []
            list.append(LorebookEntry(
                id: readText(stmt, 0) ?? UUID().uuidString,
                characterId: readText(stmt, 1),
                title: readText(stmt, 2) ?? "",
                keywords: keywords,
                content: readText(stmt, 4) ?? "",
                priority: Int(sqlite3_column_int(stmt, 5)),
                alwaysActive: sqlite3_column_int(stmt, 6) != 0,
                isEnabled: sqlite3_column_int(stmt, 7) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
            ))
        }
        return list
    }

    public func saveLorebookEntry(_ entry: LorebookEntry) throws {
        let kwData = try jsonEncoder.encode(entry.keywords)
        let kwJson = String(data: kwData, encoding: .utf8) ?? "[]"
        let sql = "INSERT OR REPLACE INTO lorebook_entries (id, character_id, title, keywords_json, content, priority, always_active, is_enabled, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, entry.id)
        bindOptionalText(stmt, 2, entry.characterId)
        bindText(stmt, 3, entry.title)
        bindText(stmt, 4, kwJson)
        bindText(stmt, 5, entry.content)
        sqlite3_bind_int(stmt, 6, Int32(entry.priority))
        sqlite3_bind_int(stmt, 7, entry.alwaysActive ? 1 : 0)
        sqlite3_bind_int(stmt, 8, entry.isEnabled ? 1 : 0)
        sqlite3_bind_double(stmt, 9, entry.createdAt.timeIntervalSince1970)
        try stepDone(stmt)
    }

    public func deleteLorebookEntry(id: String) throws {
        let stmt = try prepare("DELETE FROM lorebook_entries WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        try stepDone(stmt)
    }

    // MARK: - Conversations & Messages

    public func fetchConversations() throws -> [Conversation] {
        let sql = """
        SELECT id, character_id, persona_id, model_id_override, preset_id_override, title,
               rolling_summary, summarized_until_msg_id, kv_cache_file_name, last_message_at, created_at
        FROM conversations ORDER BY last_message_at DESC;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var list: [Conversation] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            list.append(Conversation(
                id: readText(stmt, 0) ?? UUID().uuidString,
                characterId: readText(stmt, 1) ?? "",
                personaId: readText(stmt, 2),
                modelIdOverride: readText(stmt, 3),
                presetIdOverride: readText(stmt, 4),
                title: readText(stmt, 5) ?? "",
                rollingSummary: readText(stmt, 6) ?? "",
                summarizedUntilMessageId: readText(stmt, 7),
                kvCacheFileName: readText(stmt, 8),
                lastMessageAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
            ))
        }
        return list
    }

    public func saveConversation(_ conv: Conversation) throws {
        let sql = """
        INSERT OR REPLACE INTO conversations (
            id, character_id, persona_id, model_id_override, preset_id_override, title,
            rolling_summary, summarized_until_msg_id, kv_cache_file_name, last_message_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, conv.id)
        bindText(stmt, 2, conv.characterId)
        bindOptionalText(stmt, 3, conv.personaId)
        bindOptionalText(stmt, 4, conv.modelIdOverride)
        bindOptionalText(stmt, 5, conv.presetIdOverride)
        bindText(stmt, 6, conv.title)
        bindText(stmt, 7, conv.rollingSummary)
        bindOptionalText(stmt, 8, conv.summarizedUntilMessageId)
        bindOptionalText(stmt, 9, conv.kvCacheFileName)
        sqlite3_bind_double(stmt, 10, conv.lastMessageAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 11, conv.createdAt.timeIntervalSince1970)
        try stepDone(stmt)
    }

    public func deleteConversation(id: String) throws {
        for sql in ["DELETE FROM messages WHERE conversation_id = ?;", "DELETE FROM conversations WHERE id = ?;"] {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            try stepDone(stmt)
        }
    }

    public func fetchMessages(conversationId: String, includeUnselectedVariants: Bool = true) throws -> [ChatMessage] {
        let sql: String
        if includeUnselectedVariants {
            sql = "SELECT id, conversation_id, role, content, group_id, variant_index, is_selected, is_memorized, tokens_per_second, created_at, reasoning_content, attachments_json, web_sources_json FROM messages WHERE conversation_id = ? ORDER BY created_at ASC, variant_index ASC;"
        } else {
            sql = "SELECT id, conversation_id, role, content, group_id, variant_index, is_selected, is_memorized, tokens_per_second, created_at, reasoning_content, attachments_json, web_sources_json FROM messages WHERE conversation_id = ? AND is_selected = 1 ORDER BY created_at ASC;"
        }
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, conversationId)
        var list: [ChatMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tps: Double? = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 8)
            let attJSON = readText(stmt, 11)
            let attachments = attJSON.flatMap { try? jsonDecoder.decode([MessageAttachment].self, from: Data($0.utf8)) } ?? []
            let srcJSON = readText(stmt, 12)
            let webSources = srcJSON.flatMap { try? jsonDecoder.decode([WebSearchSource].self, from: Data($0.utf8)) } ?? []
            list.append(ChatMessage(
                id: readText(stmt, 0) ?? UUID().uuidString,
                conversationId: readText(stmt, 1) ?? "",
                role: MessageRole(rawValue: readText(stmt, 2) ?? "user") ?? .user,
                content: readText(stmt, 3) ?? "",
                reasoningContent: readText(stmt, 10),
                attachments: attachments,
                webSources: webSources,
                groupId: readText(stmt, 4) ?? UUID().uuidString,
                variantIndex: Int(sqlite3_column_int(stmt, 5)),
                isSelected: sqlite3_column_int(stmt, 6) != 0,
                isMemorized: sqlite3_column_int(stmt, 7) != 0,
                tokensPerSecond: tps,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
            ))
        }
        return list
    }

    public func saveMessage(_ message: ChatMessage) throws {
        if message.isSelected {
            let unselectStmt = try prepare("UPDATE messages SET is_selected = 0 WHERE group_id = ? AND id != ?;")
            defer { sqlite3_finalize(unselectStmt) }
            bindText(unselectStmt, 1, message.groupId)
            bindText(unselectStmt, 2, message.id)
            try stepDone(unselectStmt)
        }
        let sql = """
        INSERT OR REPLACE INTO messages (
            id, conversation_id, role, content, group_id, variant_index, is_selected,
            is_memorized, tokens_per_second, created_at, reasoning_content, attachments_json, web_sources_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, message.id)
        bindText(stmt, 2, message.conversationId)
        bindText(stmt, 3, message.role.rawValue)
        bindText(stmt, 4, message.content)
        bindText(stmt, 5, message.groupId)
        sqlite3_bind_int(stmt, 6, Int32(message.variantIndex))
        sqlite3_bind_int(stmt, 7, message.isSelected ? 1 : 0)
        sqlite3_bind_int(stmt, 8, message.isMemorized ? 1 : 0)
        if let tps = message.tokensPerSecond {
            sqlite3_bind_double(stmt, 9, tps)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        sqlite3_bind_double(stmt, 10, message.createdAt.timeIntervalSince1970)
        bindOptionalText(stmt, 11, message.reasoningContent)
        let attStr = message.attachments.isEmpty ? nil : (try? String(data: jsonEncoder.encode(message.attachments), encoding: .utf8))
        let srcStr = message.webSources.isEmpty ? nil : (try? String(data: jsonEncoder.encode(message.webSources), encoding: .utf8))
        bindOptionalText(stmt, 12, attStr)
        bindOptionalText(stmt, 13, srcStr)
        try stepDone(stmt)

        let touchStmt = try prepare("UPDATE conversations SET last_message_at = ? WHERE id = ?;")
        defer { sqlite3_finalize(touchStmt) }
        sqlite3_bind_double(touchStmt, 1, message.createdAt.timeIntervalSince1970)
        bindText(touchStmt, 2, message.conversationId)
        try stepDone(touchStmt)
    }

    public func selectVariant(groupId: String, messageId: String) throws {
        let s1 = try prepare("UPDATE messages SET is_selected = 0 WHERE group_id = ?;")
        defer { sqlite3_finalize(s1) }
        bindText(s1, 1, groupId)
        try stepDone(s1)

        let s2 = try prepare("UPDATE messages SET is_selected = 1 WHERE id = ?;")
        defer { sqlite3_finalize(s2) }
        bindText(s2, 1, messageId)
        try stepDone(s2)
    }

    public func deleteMessage(id: String) throws {
        let stmt = try prepare("DELETE FROM messages WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        try stepDone(stmt)
    }

    public func deleteMessagesAfter(conversationId: String, timestamp: Date) throws {
        let stmt = try prepare("DELETE FROM messages WHERE conversation_id = ? AND created_at > ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, conversationId)
        sqlite3_bind_double(stmt, 2, timestamp.timeIntervalSince1970)
        try stepDone(stmt)
    }

    public func markMessagesMemorized(ids: [String]) throws {
        for id in ids {
            let stmt = try prepare("UPDATE messages SET is_memorized = 1 WHERE id = ?;")
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            try stepDone(stmt)
        }
    }

    // MARK: - Core & Episodic Memories

    public func fetchCoreMemories(characterId: String) throws -> [CoreMemoryItem] {
        let stmt = try prepare("SELECT id, character_id, mem_key, mem_value, updated_at FROM core_memories WHERE character_id = ? ORDER BY updated_at DESC;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, characterId)
        var list: [CoreMemoryItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            list.append(CoreMemoryItem(
                id: readText(stmt, 0) ?? UUID().uuidString,
                characterId: readText(stmt, 1) ?? characterId,
                key: readText(stmt, 2) ?? "",
                value: readText(stmt, 3) ?? "",
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            ))
        }
        return list
    }

    public func upsertCoreMemory(_ item: CoreMemoryItem) throws {
        let sql = """
        INSERT INTO core_memories (id, character_id, mem_key, mem_value, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(character_id, mem_key) DO UPDATE SET
            mem_value = excluded.mem_value,
            updated_at = excluded.updated_at;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, item.id)
        bindText(stmt, 2, item.characterId)
        bindText(stmt, 3, item.key)
        bindText(stmt, 4, item.value)
        sqlite3_bind_double(stmt, 5, item.updatedAt.timeIntervalSince1970)
        try stepDone(stmt)
    }

    public func deleteCoreMemory(id: String) throws {
        let stmt = try prepare("DELETE FROM core_memories WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        try stepDone(stmt)
    }

    public func fetchEpisodicMemories(characterId: String) throws -> [EpisodicMemory] {
        let sql = """
        SELECT id, character_id, content, category, importance, mood, embedding, is_pinned,
               recall_count, created_at, last_recalled_at
        FROM episodic_memories
        WHERE character_id = ?
        ORDER BY is_pinned DESC, created_at DESC;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, characterId)
        var list: [EpisodicMemory] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let vector = readFloatBlob(stmt, 6)
            list.append(EpisodicMemory(
                id: readText(stmt, 0) ?? UUID().uuidString,
                characterId: readText(stmt, 1) ?? characterId,
                content: readText(stmt, 2) ?? "",
                category: MemoryCategory(rawValue: readText(stmt, 3) ?? "event") ?? .event,
                importance: Int(sqlite3_column_int(stmt, 4)),
                mood: readText(stmt, 5) ?? "平静",
                embedding: vector,
                isPinned: sqlite3_column_int(stmt, 7) != 0,
                recallCount: Int(sqlite3_column_int(stmt, 8)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                lastRecalledAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
            ))
        }
        return list
    }

    public func saveEpisodicMemory(_ memory: EpisodicMemory) throws {
        let sql = """
        INSERT OR REPLACE INTO episodic_memories (
            id, character_id, content, category, importance, mood, embedding, is_pinned,
            recall_count, created_at, last_recalled_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, memory.id)
        bindText(stmt, 2, memory.characterId)
        bindText(stmt, 3, memory.content)
        bindText(stmt, 4, memory.category.rawValue)
        sqlite3_bind_int(stmt, 5, Int32(memory.importance))
        bindText(stmt, 6, memory.mood)
        bindFloatBlob(stmt, 7, memory.embedding)
        sqlite3_bind_int(stmt, 8, memory.isPinned ? 1 : 0)
        sqlite3_bind_int(stmt, 9, Int32(memory.recallCount))
        sqlite3_bind_double(stmt, 10, memory.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 11, memory.lastRecalledAt.timeIntervalSince1970)
        try stepDone(stmt)

        // Sync FTS5 row
        let delFts = try prepare("DELETE FROM episodic_memories_fts WHERE memory_id = ?;")
        defer { sqlite3_finalize(delFts) }
        bindText(delFts, 1, memory.id)
        try stepDone(delFts)

        let insFts = try prepare("INSERT INTO episodic_memories_fts (memory_id, character_id, content) VALUES (?, ?, ?);")
        defer { sqlite3_finalize(insFts) }
        bindText(insFts, 1, memory.id)
        bindText(insFts, 2, memory.characterId)
        bindText(insFts, 3, Self.spaceSegmentedForFTS(memory.content))
        try stepDone(insFts)
    }

    public func deleteEpisodicMemory(id: String) throws {
        for sql in ["DELETE FROM episodic_memories WHERE id = ?;", "DELETE FROM episodic_memories_fts WHERE memory_id = ?;"] {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            try stepDone(stmt)
        }
    }

    public func recordMemoryRecalls(ids: [String], at date: Date = Date()) throws {
        for id in ids {
            let stmt = try prepare("UPDATE episodic_memories SET recall_count = recall_count + 1, last_recalled_at = ? WHERE id = ?;")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
            bindText(stmt, 2, id)
            try stepDone(stmt)
        }
    }

    /// Performs FTS5 keyword search on segmented Chinese/English memory content, returning matched memory IDs -> normalized rank score (0...1).
    public func searchEpisodicFTS(characterId: String, query: String, limit: Int = 20) throws -> [String: Double] {
        let tokens = Self.extractFTSTerms(from: query)
        guard !tokens.isEmpty else { return [:] }
        let matchExpr = tokens.prefix(12).map { "\"\($0)\"" }.joined(separator: " OR ")
        let sql = """
        SELECT memory_id, bm25(episodic_memories_fts) AS rank_score
        FROM episodic_memories_fts
        WHERE character_id = ? AND episodic_memories_fts MATCH ?
        ORDER BY rank_score ASC
        LIMIT ?;
        """
        guard let stmt = try? prepare(sql) else { return [:] }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, characterId)
        bindText(stmt, 2, matchExpr)
        sqlite3_bind_int(stmt, 3, Int32(limit))

        var scores: [String: Double] = [:]
        var rankIndex = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let memId = readText(stmt, 0) {
                // Convert rank position into clean 0...1 relevance score
                let score = max(0.25, 1.0 - Double(rankIndex) * 0.08)
                scores[memId] = score
                rankIndex += 1
            }
        }
        return scores
    }

    // MARK: - Helpers

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw ChlorDatabaseError.openFailed("Database closed") }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw ChlorDatabaseError.prepareFailed("\(msg) | SQL: \(sql)")
        }
        return stmt!
    }

    private func stepDone(_ stmt: OpaquePointer) throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Step error \(rc)"
            throw ChlorDatabaseError.stepFailed(msg)
        }
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func bindOptionalText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            bindText(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func readText(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let cStr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: cStr)
    }

    private func bindFloatBlob(_ stmt: OpaquePointer, _ index: Int32, _ floats: [Float]) {
        if floats.isEmpty {
            sqlite3_bind_null(stmt, index)
            return
        }
        floats.withUnsafeBytes { rawBuf in
            if let base = rawBuf.baseAddress {
                _ = sqlite3_bind_blob(stmt, index, base, Int32(rawBuf.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                _ = sqlite3_bind_null(stmt, index)
            }
        }
    }

    private func readFloatBlob(_ stmt: OpaquePointer, _ col: Int32) -> [Float] {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(stmt, col) else { return [] }
        let byteCount = Int(sqlite3_column_bytes(stmt, col))
        let count = byteCount / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        let ptr = bytes.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    /// Inserts spaces around CJK bigrams so SQLite unicode61 FTS5 matches Chinese phrases accurately.
    public static func spaceSegmentedForFTS(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var tokens: [String] = []
        var cjkBuffer: [Character] = []

        func flushCJK() {
            if cjkBuffer.count == 1 {
                tokens.append(String(cjkBuffer[0]))
            } else if cjkBuffer.count > 1 {
                for i in 0..<(cjkBuffer.count - 1) {
                    tokens.append(String([cjkBuffer[i], cjkBuffer[i + 1]]))
                }
                for ch in cjkBuffer {
                    tokens.append(String(ch))
                }
            }
            cjkBuffer.removeAll(keepingCapacity: true)
        }

        var latinBuffer: [Character] = []
        func flushLatin() {
            if !latinBuffer.isEmpty {
                tokens.append(String(latinBuffer).lowercased())
                latinBuffer.removeAll(keepingCapacity: true)
            }
        }

        for ch in trimmed {
            if isCJK(ch) {
                flushLatin()
                cjkBuffer.append(ch)
            } else if ch.isLetter || ch.isNumber {
                flushCJK()
                latinBuffer.append(ch)
            } else {
                flushCJK()
                flushLatin()
            }
        }
        flushCJK()
        flushLatin()
        return tokens.joined(separator: " ")
    }

    private static func extractFTSTerms(from query: String) -> [String] {
        let segmented = spaceSegmentedForFTS(query)
        let stopWords: Set<String> = ["的", "了", "吗", "呢", "啊", "吧", "我", "你", "他", "她", "是", "在", "有", "和", "就", "都", "也", "很"]
        var seen: Set<String> = []
        var result: [String] = []
        for part in segmented.split(separator: " ") {
            let token = String(part).replacingOccurrences(of: "\"", with: "")
            guard !token.isEmpty, !stopWords.contains(token), !seen.contains(token) else { continue }
            seen.insert(token)
            result.append(token)
        }
        return result
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x3040...0x30FF).contains(v)
    }
}

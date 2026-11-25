import Foundation

/// Supports importing and exporting SillyTavern / TavernAI Character Card V2 JSON & PNG (tEXt "chara" base64 chunk)
public struct CharacterCardV2Envelope: Codable, Sendable {
    public var spec: String
    public var specVersion: String
    public var data: CharacterCardV2Data

    enum CodingKeys: String, CodingKey {
        case spec
        case specVersion = "spec_version"
        case data
    }

    public init(spec: String = "chara_card_v2", specVersion: String = "2.0", data: CharacterCardV2Data) {
        self.spec = spec
        self.specVersion = specVersion
        self.data = data
    }
}

public struct CharacterCardV2Data: Codable, Sendable {
    public var name: String
    public var description: String
    public var personality: String
    public var scenario: String
    public var firstMes: String
    public var mesExample: String
    public var systemPrompt: String?
    public var postHistoryInstructions: String?
    public var creatorNotes: String?
    public var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case personality
        case scenario
        case firstMes = "first_mes"
        case mesExample = "mes_example"
        case systemPrompt = "system_prompt"
        case postHistoryInstructions = "post_history_instructions"
        case creatorNotes = "creator_notes"
        case tags
    }

    public init(
        name: String,
        description: String = "",
        personality: String = "",
        scenario: String = "",
        firstMes: String = "",
        mesExample: String = "",
        systemPrompt: String? = nil,
        postHistoryInstructions: String? = nil,
        creatorNotes: String? = nil,
        tags: [String]? = nil
    ) {
        self.name = name
        self.description = description
        self.personality = personality
        self.scenario = scenario
        self.firstMes = firstMes
        self.mesExample = mesExample
        self.systemPrompt = systemPrompt
        self.postHistoryInstructions = postHistoryInstructions
        self.creatorNotes = creatorNotes
        self.tags = tags
    }
}

public enum CharacterCardCodecError: LocalizedError {
    case invalidFormat
    case missingCharaChunk
    case invalidBase64

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "无法识别的角色卡格式（仅支持 V2 JSON 或 PNG 角色卡）"
        case .missingCharaChunk: return "PNG 图片中未包含 chara 角色卡元数据"
        case .invalidBase64: return "角色卡 PNG 内的 Base64 数据损坏"
        }
    }
}

public enum CharacterCardV2Codec {
    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    public static func exportJSON(character: CharacterCard) throws -> Data {
        let data = CharacterCardV2Data(
            name: character.name,
            description: character.speakingStyle,
            personality: character.personality,
            scenario: character.scenario,
            firstMes: character.firstMessage,
            mesExample: character.exampleDialogue,
            systemPrompt: character.systemOverride.isEmpty ? nil : character.systemOverride,
            postHistoryInstructions: character.postHistoryInstruction.isEmpty ? nil : character.postHistoryInstruction,
            creatorNotes: character.tagline.isEmpty ? nil : character.tagline,
            tags: [character.relationshipLabel, character.moodLabel].filter { !$0.isEmpty }
        )
        let envelope = CharacterCardV2Envelope(data: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func importData(_ rawData: Data) throws -> CharacterCard {
        if rawData.count >= 8 && Array(rawData.prefix(8)) == pngSignature {
            let jsonData = try extractCharaJSONFromPNG(rawData)
            return try decodeJSON(jsonData)
        }
        return try decodeJSON(rawData)
    }

    public static func decodeJSON(_ data: Data) throws -> CharacterCard {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(CharacterCardV2Envelope.self, from: data) {
            return makeCharacter(from: envelope.data)
        }
        if let v1Data = try? decoder.decode(CharacterCardV2Data.self, from: data) {
            return makeCharacter(from: v1Data)
        }
        throw CharacterCardCodecError.invalidFormat
    }

    /// Embeds a tEXt "chara" chunk into an existing PNG image before IEND
    public static func embedInPNG(pngData: Data, character: CharacterCard) throws -> Data {
        guard pngData.count >= 8 && Array(pngData.prefix(8)) == pngSignature else {
            throw CharacterCardCodecError.invalidFormat
        }
        let jsonData = try exportJSON(character: character)
        let base64 = jsonData.base64EncodedString()
        var chunkPayload = Data("chara".utf8)
        chunkPayload.append(0)
        chunkPayload.append(Data(base64.utf8))

        let chunkType = Data("tEXt".utf8)
        var crcInput = Data()
        crcInput.append(chunkType)
        crcInput.append(chunkPayload)
        let crc = crc32(crcInput)

        var textChunk = Data()
        var lengthBE = UInt32(chunkPayload.count).bigEndian
        textChunk.append(Data(bytes: &lengthBE, count: 4))
        textChunk.append(chunkType)
        textChunk.append(chunkPayload)
        var crcBE = crc.bigEndian
        textChunk.append(Data(bytes: &crcBE, count: 4))

        // Insert right before IEND chunk (last 12 bytes in standard PNG, scan safely)
        var offset = 8
        var output = Data(pngData.prefix(8))
        var inserted = false
        while offset + 12 <= pngData.count {
            let length = readUInt32BE(pngData, at: offset)
            let typeData = pngData.subdata(in: (offset + 4)..<(offset + 8))
            let typeStr = String(data: typeData, encoding: .ascii) ?? ""
            let totalChunkSize = 12 + Int(length)
            guard offset + totalChunkSize <= pngData.count else { break }

            if typeStr == "IEND" && !inserted {
                output.append(textChunk)
                inserted = true
            }
            output.append(pngData.subdata(in: offset..<(offset + totalChunkSize)))
            offset += totalChunkSize
        }
        if !inserted {
            output.append(textChunk)
        }
        return output
    }

    private static func extractCharaJSONFromPNG(_ pngData: Data) throws -> Data {
        var offset = 8
        while offset + 12 <= pngData.count {
            let length = Int(readUInt32BE(pngData, at: offset))
            let typeData = pngData.subdata(in: (offset + 4)..<(offset + 8))
            let typeStr = String(data: typeData, encoding: .ascii) ?? ""
            let dataStart = offset + 8
            let dataEnd = dataStart + length
            guard dataEnd + 4 <= pngData.count else { break }

            if typeStr == "tEXt" {
                let chunkData = pngData.subdata(in: dataStart..<dataEnd)
                if let nullIdx = chunkData.firstIndex(of: 0) {
                    let key = String(data: chunkData[..<nullIdx], encoding: .utf8) ?? ""
                    if key.lowercased() == "chara" {
                        let b64Slice = chunkData[(nullIdx + 1)...]
                        let b64String = String(data: Data(b64Slice), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard let decoded = Data(base64Encoded: b64String, options: .ignoreUnknownCharacters) else {
                            throw CharacterCardCodecError.invalidBase64
                        }
                        return decoded
                    }
                }
            }
            offset = dataEnd + 4
        }
        throw CharacterCardCodecError.missingCharaChunk
    }

    private static func makeCharacter(from v2: CharacterCardV2Data) -> CharacterCard {
        let combinedPersonality = [v2.personality, v2.description]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return CharacterCard(
            name: v2.name.isEmpty ? "未命名角色" : v2.name,
            tagline: v2.creatorNotes ?? "",
            personality: combinedPersonality,
            speakingStyle: v2.description,
            scenario: v2.scenario,
            firstMessage: v2.firstMes,
            exampleDialogue: v2.mesExample,
            systemOverride: v2.systemPrompt ?? "",
            postHistoryInstruction: v2.postHistoryInstructions ?? ""
        )
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset]) << 24
        let b1 = UInt32(data[offset + 1]) << 16
        let b2 = UInt32(data[offset + 2]) << 8
        let b3 = UInt32(data[offset + 3])
        return b0 | b1 | b2 | b3
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return ~crc
    }
}

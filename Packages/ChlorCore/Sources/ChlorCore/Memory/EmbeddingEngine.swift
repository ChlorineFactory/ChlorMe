import Foundation
import Accelerate
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Zero-overhead local text embedding engine using character n-gram feature hashing + Apple Accelerate (vDSP) cosine similarity.
/// Uses < 1 MB RAM so it never competes with the main LLM weights on iOS.
public enum EmbeddingEngine {
    public static let dimensions: Int = 256

    /// Generates an L2-normalized 256-dim dense vector for Chinese & English companion memories.
    public static func embed(_ text: String) -> [Float] {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return Array(repeating: 0, count: dimensions)
        }

        var vector = Array(repeating: Float(0), count: dimensions)

        // 1. Word-level & CJK-bigram hashing with signed projection (Murmur-style FNV-1a mix)
        let segmented = ChlorDatabase.spaceSegmentedForFTS(normalized)
        for token in segmented.split(separator: " ") {
            let str = String(token)
            let weight: Float = str.count >= 2 ? 1.5 : 0.7
            addFeature(str, weight: weight, into: &vector)
        }

        // 2. Character trigrams for fuzzy morphology & typo resilience
        let chars = Array(normalized.filter { !$0.isWhitespace })
        if chars.count >= 3 {
            for i in 0...(chars.count - 3) {
                let trigram = String(chars[i..<(i + 3)])
                addFeature("tg:" + trigram, weight: 0.6, into: &vector)
            }
        }

        // 3. Optional semantic enrichment from Apple's built-in NLEmbedding (when available on device)
        #if canImport(NaturalLanguage)
        if let nlVec = naturalLanguageProjection(for: normalized) {
            for i in 0..<min(dimensions, nlVec.count) {
                vector[i] += nlVec[i] * 0.85
            }
        }
        #endif

        // L2 normalize via Accelerate vDSP
        var sumSq: Float = 0
        vDSP_svesq(vector, 1, &sumSq, vDSP_Length(dimensions))
        let norm = sqrt(sumSq)
        if norm > 1e-6 {
            var invNorm = 1.0 / norm
            vDSP_vsmul(vector, 1, &invNorm, &vector, 1, vDSP_Length(dimensions))
        }
        return vector
    }

    /// Ultra-fast cosine similarity using Apple Accelerate (vDSP).
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        // Vectors from `embed` are already L2-normalized; clamp for numerical safety
        return Double(max(-1.0, min(1.0, dot)))
    }

    private static func addFeature(_ key: String, weight: Float, into vector: inout [Float]) {
        let h1 = fnv1a64(key)
        let h2 = fnv1a64("sign:" + key)
        let idx = Int(h1 % UInt64(dimensions))
        let sign: Float = (h2 & 1) == 0 ? 1.0 : -1.0
        vector[idx] += sign * weight
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }

    #if canImport(NaturalLanguage)
    private static func naturalLanguageProjection(for text: String) -> [Float]? {
        let lang: NLLanguage = text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) ? .simplifiedChinese : .english
        guard let nlEmbedding = NLEmbedding.sentenceEmbedding(for: lang),
              let raw = nlEmbedding.vector(for: text), !raw.isEmpty else {
            return nil
        }
        var projected = Array(repeating: Float(0), count: dimensions)
        for (i, val) in raw.enumerated() {
            projected[i % dimensions] += Float(val)
        }
        var sumSq: Float = 0
        vDSP_svesq(projected, 1, &sumSq, vDSP_Length(dimensions))
        let norm = sqrt(sumSq)
        if norm > 1e-6 {
            var inv = 1.0 / norm
            vDSP_vsmul(projected, 1, &inv, &projected, 1, vDSP_Length(dimensions))
        }
        return projected
    }
    #endif
}

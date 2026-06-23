import Foundation

/// Cheap heuristic for "how many tokens will this string become" — without shipping a real
/// tokenizer (BPE / tiktoken). All major providers are around 4 chars per token for English
/// and 1–2 chars per token for CJK. We split the difference: use the larger of `chars / 4`
/// and a CJK character count.
public enum TokenEstimator {
    public static func estimateTokens(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        let total = text.unicodeScalars.count
        // Count CJK / Hangul / Hiragana / Katakana scalars as roughly 1 token each.
        var cjkCount = 0
        for scalar in text.unicodeScalars where isCJK(scalar) {
            cjkCount += 1
        }
        let asciiHeavyEstimate = max(1, total / 4)
        // For mixed text, the higher of the two is closer to the real tokenizer output.
        return max(asciiHeavyEstimate, cjkCount)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,    // CJK Unified Ideographs
             0x3040...0x309F,    // Hiragana
             0x30A0...0x30FF,    // Katakana
             0xAC00...0xD7AF,    // Hangul Syllables
             0x3400...0x4DBF,    // CJK Extension A
             0xF900...0xFAFF:    // CJK Compatibility Ideographs
            return true
        default:
            return false
        }
    }
}

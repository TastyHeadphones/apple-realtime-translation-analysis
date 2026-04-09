import Foundation

public struct TranscriptStabilizer {
    private var committedText: String = ""

    public init() {}

    public mutating func reset() {
        committedText = ""
    }

    public mutating func consume(_ update: TranscriptUpdate) -> StabilizedUpdate {
        let normalized = normalize(update.fullText)
        let tail = delta(fromCommitted: committedText, toCurrent: normalized)

        if update.isFinal {
            let finalized = tail.isEmpty ? nil : tail
            if !normalized.isEmpty {
                committedText = normalized
            }
            return StabilizedUpdate(partialTail: "", finalizedTail: finalized)
        }

        return StabilizedUpdate(partialTail: tail, finalizedTail: nil)
    }

    private func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func delta(fromCommitted committed: String, toCurrent current: String) -> String {
        guard !current.isEmpty else { return "" }
        guard !committed.isEmpty else { return current }

        if current.hasPrefix(committed) {
            let start = current.index(current.startIndex, offsetBy: committed.count)
            return current[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let prefix = longestCommonWordPrefix(committed, current)
        if current.hasPrefix(prefix) {
            let start = current.index(current.startIndex, offsetBy: prefix.count)
            return current[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return current
    }

    private func longestCommonWordPrefix(_ lhs: String, _ rhs: String) -> String {
        let leftWords = lhs.split(separator: " ")
        let rightWords = rhs.split(separator: " ")
        let sharedCount = zip(leftWords, rightWords).prefix { $0 == $1 }.count
        guard sharedCount > 0 else { return "" }
        return leftWords.prefix(sharedCount).joined(separator: " ") + " "
    }
}

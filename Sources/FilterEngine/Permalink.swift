import Foundation

/// A post identity taken from a public permalink.
/// Stored form is `p/<shortcode>` or `reel/<shortcode>` and nothing else.
public enum Permalink {
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else { return nil }

        let pattern = #"(?:^|/)(p|reel)/([A-Za-z0-9_-]{1,64})(?=/|$|\?|#)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let kindRange = Range(match.range(at: 1), in: trimmed),
              let idRange = Range(match.range(at: 2), in: trimmed) else {
            return nil
        }
        return "\(trimmed[kindRange])/\(trimmed[idRange])"
    }
}

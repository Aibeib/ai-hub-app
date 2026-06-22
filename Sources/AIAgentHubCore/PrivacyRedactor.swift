import Foundation

public struct PrivacyRedactor: Sendable {
    private let deviceNames: [String]
    private let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
    private let phonePattern = #"(?:\+?\d[\d -]{7,}\d)"#
    private let unixPathPattern = #"(?:(?:/Users|/private|/var|/tmp)/[^\s,。，;；]+)"#

    public init(deviceNames: [String] = []) {
        self.deviceNames = deviceNames
    }

    public func redact(_ text: String) -> String {
        var output = text
        output = replace(pattern: emailPattern, in: output, with: "[email]", options: [.caseInsensitive])
        output = replace(pattern: phonePattern, in: output, with: "[phone]")
        output = replace(pattern: unixPathPattern, in: output, with: "[local-path]")

        for deviceName in deviceNames where !deviceName.isEmpty {
            output = output.replacingOccurrences(of: deviceName, with: "[device-name]")
        }

        return output
    }

    private func replace(
        pattern: String,
        in text: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}


import Foundation

enum MessageTimestamp {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        fractional.date(from: value) ?? standard.date(from: value)
    }
}

assert(MessageTimestamp.date(from: "2026-07-18T02:18:05.123Z") != nil)
assert(MessageTimestamp.date(from: "2026-07-18T02:18:05Z") != nil)
assert(MessageTimestamp.date(from: "not-a-date") == nil)
print("MessageTimestamp checks passed")

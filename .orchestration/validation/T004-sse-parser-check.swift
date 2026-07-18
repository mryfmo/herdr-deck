import Foundation

struct GatewayEvent {
    let name: String
    let data: Data
}

// Copied from iOS/HerdDeck/Networking/GatewayClient.swift for standalone
// validation. Keep this struct verbatim with the production implementation.
struct SSEFrameParser {
    private let maxLineBytes: Int
    private let maxEventDataBytes: Int
    private var line: [UInt8] = []
    private var eventName = "message"
    private var dataLines: [String] = []
    private var dataBytes = 0
    private var lineOverflowed = false
    private var discardingEvent = false

    init(maxLineBytes: Int = 256 * 1024, maxEventDataBytes: Int = 1024 * 1024) {
        self.maxLineBytes = maxLineBytes
        self.maxEventDataBytes = maxEventDataBytes
    }

    mutating func feed(byte: UInt8) -> [GatewayEvent] {
        guard byte == 0x0A else {
            if !lineOverflowed {
                if line.count < maxLineBytes {
                    line.append(byte)
                } else {
                    line.removeAll(keepingCapacity: true)
                    lineOverflowed = true
                    discardEvent()
                }
            }
            return []
        }

        if lineOverflowed {
            lineOverflowed = false
            return []
        }
        if line.last == 0x0D { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        guard !line.isEmpty else { return finishEvent() }
        guard !discardingEvent, line.first != UInt8(ascii: ":") else { return [] }

        let separator = line.firstIndex(of: UInt8(ascii: ":"))
        let fieldBytes = separator.map { line[..<$0] } ?? line[...]
        var valueBytes = separator.map { line[line.index(after: $0)...] } ?? line[line.endIndex...]
        if valueBytes.first == UInt8(ascii: " ") { valueBytes = valueBytes.dropFirst() }
        let field = String(decoding: fieldBytes, as: UTF8.self)
        let value = String(decoding: valueBytes, as: UTF8.self)

        switch field {
        case "event":
            eventName = value
        case "data":
            let addedBytes = value.utf8.count + (dataLines.isEmpty ? 0 : 1)
            guard dataBytes + addedBytes <= maxEventDataBytes else {
                discardEvent()
                return []
            }
            dataLines.append(value)
            dataBytes += addedBytes
        default:
            break
        }
        return []
    }

    private mutating func finishEvent() -> [GatewayEvent] {
        defer { resetEvent() }
        guard !discardingEvent, !dataLines.isEmpty else { return [] }
        let payload = Data(dataLines.joined(separator: "\n").utf8)
        return [GatewayEvent(name: eventName.isEmpty ? "message" : eventName, data: payload)]
    }

    private mutating func discardEvent() {
        discardingEvent = true
        dataLines.removeAll(keepingCapacity: true)
        dataBytes = 0
    }

    private mutating func resetEvent() {
        eventName = "message"
        dataLines.removeAll(keepingCapacity: true)
        dataBytes = 0
        discardingEvent = false
    }
}

func parse(_ text: String, parser: SSEFrameParser = SSEFrameParser()) -> [GatewayEvent] {
    var parser = parser
    return text.utf8.flatMap { parser.feed(byte: $0) }
}

func payload(_ event: GatewayEvent) -> String {
    String(decoding: event.data, as: UTF8.self)
}

let snapshot = parse("event: snapshot\ndata: {\"a\":1}\n\n")
assert(snapshot.count == 1)
assert(snapshot[0].name == "snapshot")
assert(payload(snapshot[0]) == "{\"a\":1}")

let multiline = parse("data: first\ndata: second\n\n")
assert(multiline.count == 1)
assert(payload(multiline[0]) == "first\nsecond")

let crlf = parse("event: mission\r\ndata: ok\r\n\r\n")
assert(crlf.count == 1)
assert(crlf[0].name == "mission")
assert(payload(crlf[0]) == "ok")

let multiple = parse("event: first\ndata: 1\n\nevent: second\ndata: 2\n\n")
assert(multiple.map(\.name) == ["first", "second"])
assert(multiple.map(payload) == ["1", "2"])

let defaultName = parse("data: fallback\n\n")
assert(defaultName.count == 1)
assert(defaultName[0].name == "message")

var byteParser = SSEFrameParser()
var byteEvents: [GatewayEvent] = []
for byte in "event: snapshot\ndata: chunked\n\n".utf8 {
    byteEvents += byteParser.feed(byte: byte)
}
assert(byteEvents.count == 1)
assert(byteEvents[0].name == "snapshot")
assert(payload(byteEvents[0]) == "chunked")

let lineRecovery = parse(
    "data: too-long\n\ndata: ok\n\n",
    parser: SSEFrameParser(maxLineBytes: 8)
)
assert(lineRecovery.count == 1)
assert(payload(lineRecovery[0]) == "ok")

let dataRecovery = parse(
    "data: 1234\ndata: 56\n\ndata: ok\n\n",
    parser: SSEFrameParser(maxEventDataBytes: 5)
)
assert(dataRecovery.count == 1)
assert(payload(dataRecovery[0]) == "ok")

assert(parse("event: snapshot\ndata: unterminated").isEmpty)

print("SSEFrameParser checks passed")

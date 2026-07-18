import Foundation

struct TerminalMappedInput: Equatable, Sendable {
    var text: String = ""
    var keys: [String] = []
}

enum TerminalInputMapper {
    private static let sequences: [([UInt8], String)] = [
        ([0x1b, 0x5b, 0x41], "up"),
        ([0x1b, 0x5b, 0x42], "down"),
        ([0x1b, 0x5b, 0x43], "right"),
        ([0x1b, 0x5b, 0x44], "left"),
        ([0x1b, 0x5b, 0x5a], "shift+tab"),
    ]

    static func map(_ data: Data) -> TerminalMappedInput {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return TerminalMappedInput() }

        var output = TerminalMappedInput()
        var textBytes: [UInt8] = []
        var index = 0

        func flushText() {
            guard !textBytes.isEmpty else { return }
            if let value = String(bytes: textBytes, encoding: .utf8) {
                output.text.append(value)
            }
            textBytes.removeAll(keepingCapacity: true)
        }

        while index < bytes.count {
            if let sequence = sequences.first(where: { candidate, _ in
                guard index + candidate.count <= bytes.count else { return false }
                return Array(bytes[index..<(index + candidate.count)]) == candidate
            }) {
                flushText()
                output.keys.append(sequence.1)
                index += sequence.0.count
                continue
            }

            let byte = bytes[index]
            let key: String? = switch byte {
            case 0x03: "ctrl+c"
            case 0x04: "ctrl+d"
            case 0x08, 0x7f: "backspace"
            case 0x09: "tab"
            case 0x0a, 0x0d: "enter"
            case 0x1b: "esc"
            default: nil
            }
            if let key {
                flushText()
                output.keys.append(key)
            } else {
                textBytes.append(byte)
            }
            index += 1
        }
        flushText()
        return output
    }

    static func encode(keys: [String]) -> Data {
        var output = Data()
        for key in keys {
            switch key.lowercased() {
            case "esc": output.append(0x1b)
            case "tab": output.append(0x09)
            case "shift+tab": output.append(contentsOf: [0x1b, 0x5b, 0x5a])
            case "enter": output.append(0x0d)
            case "backspace": output.append(0x7f)
            case "ctrl+c", "control+c": output.append(0x03)
            case "ctrl+d", "control+d": output.append(0x04)
            case "ctrl+h", "control+h": output.append(0x08)
            case "left": output.append(contentsOf: [0x1b, 0x5b, 0x44])
            case "right": output.append(contentsOf: [0x1b, 0x5b, 0x43])
            case "up": output.append(contentsOf: [0x1b, 0x5b, 0x41])
            case "down": output.append(contentsOf: [0x1b, 0x5b, 0x42])
            default:
                if let chord = controlByte(for: key) {
                    output.append(chord)
                } else if let text = key.data(using: .utf8) {
                    output.append(text)
                }
            }
        }
        return output
    }

    private static func controlByte(for value: String) -> UInt8? {
        let lower = value.lowercased()
        let prefixes = ["ctrl+", "control+"]
        guard let prefix = prefixes.first(where: lower.hasPrefix) else { return nil }
        let suffix = lower.dropFirst(prefix.count)
        guard suffix.count == 1, let scalar = suffix.unicodeScalars.first else { return nil }
        let ascii = scalar.value
        guard (64...95).contains(ascii) || (97...122).contains(ascii) else { return nil }
        return UInt8(ascii & 0x1f)
    }

}
import Foundation

enum RichOutputBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, text: String)
    case quote(String)
    case listItem(marker: String, text: String)
    case table([[String]])
    case divider
}

enum RichOutputParser {
    static func parse(_ input: String) -> [RichOutputBlock] {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [RichOutputBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            let value = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result.append(.paragraph(value)) }
            paragraph.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[index])
                    index += 1
                }
                result.append(.code(language: language.isEmpty ? nil : language, text: codeLines.joined(separator: "\n")))
                if index < lines.count { index += 1 }
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                result.append(.divider)
                index += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                result.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                result.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            if let item = listItem(from: trimmed) {
                flushParagraph()
                result.append(.listItem(marker: item.marker, text: item.text))
                index += 1
                continue
            }

            if index + 1 < lines.count, isTableRow(trimmed), isTableSeparator(lines[index + 1]) {
                flushParagraph()
                var rows = [splitTableRow(trimmed)]
                index += 2
                while index < lines.count, isTableRow(lines[index]) {
                    rows.append(splitTableRow(lines[index]))
                    index += 1
                }
                result.append(.table(rows))
                continue
            }

            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return result
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func listItem(from line: String) -> (marker: String, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return ("•", String(line.dropFirst(marker.count)))
        }
        if let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            return (String(line[range]).trimmingCharacters(in: .whitespaces), String(line[range.upperBound...]))
        }
        return nil
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.filter { $0 == "|" }.count >= 1
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        return !cells.isEmpty && cells.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

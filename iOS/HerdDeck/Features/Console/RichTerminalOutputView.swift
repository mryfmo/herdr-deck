import SwiftUI
import UIKit

struct RichTerminalOutputView: View {
    let text: String
    let error: String?

    private var blocks: [RichOutputBlock] { RichOutputParser.parse(text) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if text.isEmpty && error == nil {
                    HStack(spacing: 10) {
                        ProgressView().tint(.herdCyan)
                        Text("Reading agent output…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }

                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    RichOutputBlockView(block: block)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.herdAmber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [Color.herdInk.opacity(0.96), Color.black.opacity(0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}


private struct RichOutputBlockView: View {
    let block: RichOutputBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            markdownText(text)
                .font(headingFont(level))
                .foregroundStyle(.primary)
                .padding(.top, level <= 2 ? 6 : 0)
        case let .paragraph(text):
            markdownText(text)
                .font(.body)
                .lineSpacing(4)
        case let .code(language, text):
            CodeOutputBlock(language: language, text: text)
        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.herdViolet)
                    .frame(width: 3)
                markdownText(text)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .padding(.vertical, 4)
        case let .listItem(marker, text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(marker)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.herdCyan)
                    .frame(minWidth: 18, alignment: .trailing)
                markdownText(text)
            }
        case let .table(rows):
            RichTable(rows: rows)
        case .divider:
            Divider().opacity(0.4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.bold()
        }
    }

    private func markdownText(_ value: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: value, options: options) {
            return Text(attributed)
        }
        return Text(value)
    }
}

private struct CodeOutputBlock: View {
    let language: String?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    Haptic.success()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.herdCyan)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.055))

            ScrollView(.horizontal, showsIndicators: true) {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color(red: 0.84, green: 0.90, blue: 0.94))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
        }
        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
    }
}

private struct RichTable: View {
    let rows: [[String]]

    private var columnCount: Int { rows.map(\.count).max() ?? 0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            Text(row.indices.contains(column) ? row[column] : "")
                                .font(rowIndex == 0 ? .caption.bold() : .caption)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(minWidth: 90, alignment: .leading)
                                .background(rowIndex == 0 ? Color.white.opacity(0.08) : Color.black.opacity(0.18))
                                .overlay(Rectangle().stroke(Color.white.opacity(0.07), lineWidth: 0.5))
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
    }
}
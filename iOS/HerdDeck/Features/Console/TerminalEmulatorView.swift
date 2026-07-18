import SwiftTerm
import SwiftUI
import UIKit

struct TerminalEmulatorView: UIViewRepresentable {
    let feed: TerminalFeed
    var fontSize: CGFloat = 13
    var onInput: @MainActor (Data) -> Void
    var onResize: @MainActor (_ columns: Int, _ rows: Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        context.coordinator.parent = self
        context.coordinator.terminalView = view
        view.terminalDelegate = context.coordinator
        view.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.nativeForegroundColor = UIColor(red: 0.84, green: 0.90, blue: 0.94, alpha: 1)
        view.nativeBackgroundColor = UIColor(red: 0.035, green: 0.047, blue: 0.07, alpha: 1)
        view.caretColor = UIColor.systemCyan
        view.selectedTextBackgroundColor = UIColor.systemCyan.withAlphaComponent(0.22)
        view.customBlockGlyphs = true
        view.antiAliasCustomBlockGlyphs = true
        view.useBrightColors = true
        view.allowMouseReporting = true
        view.linkReporting = .implicit
        view.optionAsMetaKey = true
        view.accessibilityLabel = "Herdr terminal"

        context.coordinator.subscription = feed.subscribe { [weak view] packet in
            guard let view else { return }
            if packet.reset {
                let reset = Array("\u{001B}c\u{001B}[2J\u{001B}[H".utf8)
                view.feed(byteArray: reset[...])
            }
            if !packet.data.isEmpty {
                let bytes = Array(packet.data)
                view.feed(byteArray: bytes[...])
            }
        }

        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.parent = self
        let desired = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if uiView.font.pointSize != desired.pointSize { uiView.font = desired }
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.parent.feed.unsubscribe(coordinator.subscription)
        coordinator.subscription = nil
        coordinator.terminalView = nil
    }

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        var parent: TerminalEmulatorView
        weak var terminalView: TerminalView?
        var subscription: UUID?

        init(parent: TerminalEmulatorView) {
            self.parent = parent
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            parent.onInput(Data(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            parent.onResize(newCols, newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            UIApplication.shared.open(url)
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            guard let text = String(data: content, encoding: .utf8) else { return }
            UIPasteboard.general.string = text
        }

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
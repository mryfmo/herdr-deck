import Foundation
import Combine

@MainActor
final class TerminalFeed: ObservableObject {
    struct Packet: Sendable {
        let data: Data
        let reset: Bool
    }

    typealias Sink = @MainActor (Packet) -> Void

    private var sinks: [UUID: Sink] = [:]

    @discardableResult
    func subscribe(_ sink: @escaping Sink) -> UUID {
        let id = UUID()
        sinks[id] = sink
        return id
    }

    func unsubscribe(_ id: UUID?) {
        guard let id else { return }
        sinks.removeValue(forKey: id)
    }

    func send(_ data: Data, reset: Bool = false) {
        guard !data.isEmpty || reset else { return }
        let packet = Packet(data: data, reset: reset)
        for sink in sinks.values { sink(packet) }
    }

    func send(_ text: String, reset: Bool = false) {
        send(text.data(using: .utf8) ?? Data(), reset: reset)
    }

    func clear() {
        send(Data(), reset: true)
    }
}
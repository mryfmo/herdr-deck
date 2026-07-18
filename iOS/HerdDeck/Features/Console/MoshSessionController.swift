import Foundation
import Combine

enum MoshConnectionPhase: Equatable, Sendable {
    case idle
    case bootstrapping
    case connecting
    case connected
    case unavailable(String)
    case failed(String)

    var label: String {
        switch self {
        case .idle: "Idle"
        case .bootstrapping: "Starting Mosh"
        case .connecting: "Connecting"
        case .connected: "Mosh connected"
        case .unavailable: "Mosh unavailable"
        case .failed: "Mosh failed"
        }
    }
}

@MainActor
protocol MoshEngine: AnyObject {
    var onOutput: ((Data) -> Void)? { get set }
    var onExit: ((Int32) -> Void)? { get set }
    func start(session: MoshSessionDescriptor, columns: Int, rows: Int) throws
    func send(_ data: Data)
    func resize(columns: Int, rows: Int)
    func stop()
}

@MainActor
final class MoshSessionController: ObservableObject {
    @Published private(set) var phase: MoshConnectionPhase = .idle
    @Published private(set) var activeSession: MoshSessionDescriptor?

    let feed = TerminalFeed()

    private var engine: MoshEngine?
    private var lastColumns = 100
    private var lastRows = 34
    private var generation = UUID()

    func connect(
        paneID: String,
        columns: Int,
        rows: Int,
        createSession: @escaping @MainActor () async throws -> MoshSessionDescriptor
    ) async {
        disconnect()
        let attempt = UUID()
        generation = attempt
        lastColumns = columns
        lastRows = rows

        guard MoshRuntimeSupport.embeddedAvailable else {
            phase = .unavailable("Build the optional GPL Mosh target to enable cellular roaming.")
            return
        }

        phase = .bootstrapping
        do {
            let descriptor = try await createSession()
            guard descriptor.paneId == paneID else {
                throw GatewayAPIError(statusCode: nil, code: "mosh_pane_mismatch", message: "Gateway returned a Mosh session for a different pane")
            }
            phase = .connecting
            let engine = try makeMoshEngine()
            engine.onOutput = { [weak self] data in
                guard let self, self.generation == attempt else { return }
                self.feed.send(data)
                if self.phase != .connected { self.phase = .connected }
            }
            engine.onExit = { [weak self] code in
                guard let self, self.generation == attempt else { return }
                self.engine = nil
                self.activeSession = nil
                if code == 0 {
                    self.phase = .idle
                } else {
                    self.phase = .failed("Mosh exited with code \(code)")
                }
            }
            self.engine = engine
            activeSession = descriptor
            feed.clear()
            try engine.start(session: descriptor, columns: columns, rows: rows)
        } catch {
            guard generation == attempt else { return }
            phase = .failed(error.localizedDescription)
            engine?.stop()
            engine = nil
            activeSession = nil
        }
    }

    func send(_ data: Data) {
        engine?.send(data)
    }

    func resize(columns: Int, rows: Int) {
        lastColumns = max(columns, 20)
        lastRows = max(rows, 6)
        engine?.resize(columns: lastColumns, rows: lastRows)
    }

    func disconnect() {
        generation = UUID()
        engine?.stop()
        engine = nil
        activeSession = nil
        if case .unavailable = phase { return }
        phase = .idle
    }

    private func makeMoshEngine() throws -> MoshEngine {
        #if HERDDECK_EMBEDDED_MOSH
        return EmbeddedMoshEngine()
        #else
        throw GatewayAPIError(
            statusCode: nil,
            code: "embedded_mosh_unavailable",
            message: "This build does not contain the optional embedded Mosh engine"
        )
        #endif
    }
}

#if HERDDECK_EMBEDDED_MOSH
@MainActor
private final class EmbeddedMoshEngine: MoshEngine {
    var onOutput: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?

    private var session: HerdMoshSession?

    func start(session descriptor: MoshSessionDescriptor, columns: Int, rows: Int) throws {
        guard session == nil else { return }
        let native = HerdMoshSession(
            host: descriptor.host,
            port: Int32(descriptor.port),
            key: descriptor.key,
            predictionMode: descriptor.predictionMode,
            columns: Int32(columns),
            rows: Int32(rows),
            outputHandler: { [weak self] data in self?.onOutput?(data) },
            exitHandler: { [weak self] code in self?.onExit?(code) }
        )
        session = native
        native.start()
    }

    func send(_ data: Data) {
        session?.write(data)
    }

    func resize(columns: Int, rows: Int) {
        session?.resize(withColumns: Int32(columns), rows: Int32(rows))
    }

    func stop() {
        session?.stop()
        session = nil
    }
}
#endif

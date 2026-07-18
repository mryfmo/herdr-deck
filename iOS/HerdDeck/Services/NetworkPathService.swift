import Foundation
import Combine
import Network

@MainActor
final class NetworkPathService: ObservableObject {
    @Published private(set) var interface: NetworkInterfaceKind = .unavailable
    @Published private(set) var isSatisfied = false
    @Published private(set) var isExpensive = false
    @Published private(set) var isConstrained = false

    var onChange: (@MainActor (NetworkInterfaceKind) -> Void)?
    var onMetricsChange: (@MainActor (_ isExpensive: Bool, _ isConstrained: Bool) -> Void)?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.herddeck.network-path", qos: .utility)
    private var started = false

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    deinit {
        monitor.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let interface = Self.interface(for: path)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let changed = self.interface != interface
                self.interface = interface
                self.isSatisfied = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                self.onMetricsChange?(path.isExpensive, path.isConstrained)
                if changed { self.onChange?(interface) }
            }
        }
        monitor.start(queue: queue)
    }

    private nonisolated static func interface(for path: NWPath) -> NetworkInterfaceKind {
        guard path.status == .satisfied else { return .unavailable }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        // Packet-tunnel VPNs may surface as `.other` even though their
        // underlying path is cellular. `isExpensive` gives us a conservative
        // fallback; users can still override the result with Prefer Mosh or
        // Gateway only in Settings.
        if path.isExpensive { return .cellular }
        return .other
    }
}

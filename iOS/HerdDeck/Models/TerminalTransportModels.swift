import Foundation

enum NetworkInterfaceKind: String, Codable, CaseIterable, Sendable {
    case unavailable
    case wifi
    case cellular
    case wiredEthernet
    case other

    var label: String {
        switch self {
        case .unavailable: "Offline"
        case .wifi: "Wi-Fi"
        case .cellular: "Cellular"
        case .wiredEthernet: "Ethernet"
        case .other: "Network"
        }
    }

    var symbolName: String {
        switch self {
        case .unavailable: "wifi.slash"
        case .wifi: "wifi"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .wiredEthernet: "cable.connector"
        case .other: "network"
        }
    }
}

enum TerminalTransportPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic
    case gatewayOnly
    case moshPreferred

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Mosh on cellular"
        case .gatewayOnly: "Gateway only"
        case .moshPreferred: "Prefer Mosh"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Use HTTPS on Wi-Fi and Mosh on cellular when the embedded engine is available."
        case .gatewayOnly: "Always use the Herdr HTTPS gateway for terminal I/O."
        case .moshPreferred: "Use Mosh whenever available, including Wi-Fi."
        }
    }
}

enum TerminalRenderMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case rich
    case terminal
    case raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rich: "Rich"
        case .terminal: "Terminal"
        case .raw: "Raw"
        }
    }

    var symbolName: String {
        switch self {
        case .rich: "text.justify.leading"
        case .terminal: "terminal"
        case .raw: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum TerminalRoute: String, Sendable {
    case gateway
    case mosh

    var label: String {
        switch self {
        case .gateway: "Gateway"
        case .mosh: "Mosh"
        }
    }

    var symbolName: String {
        switch self {
        case .gateway: "lock.icloud"
        case .mosh: "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
}

struct TerminalUserPreferences: Codable, Equatable, Sendable {
    var transportPolicy: TerminalTransportPolicy = .automatic
    var renderMode: TerminalRenderMode = .terminal
    var moshPredictionMode: String = "adaptive"
    var cellularHysteresisSeconds: Int = 45

    static let `default` = TerminalUserPreferences()
}

struct MoshCapabilities: Codable, Equatable, Sendable {
    let enabled: Bool
    let configured: Bool?
    let embeddedClientRequired: Bool?
    let advertiseHost: String?
    let portRange: String?
    let predictionMode: String?
    let serverAvailable: Bool?
    let herdrAvailable: Bool?
    let reason: String?
    let checks: [GatewayCheck]?
}

struct MoshCapabilitiesResponse: Codable, Sendable {
    let mosh: MoshCapabilities
}

struct MoshSessionRequest: Codable, Sendable {
    let paneId: String
    let columns: Int
    let rows: Int
    let predictionMode: String
}

struct MoshSessionDescriptor: Codable, Equatable, Sendable {
    let id: String
    let paneId: String
    let host: String
    let port: Int
    let key: String
    let predictionMode: String
    let createdAt: String
    let networkTimeoutSeconds: Int
    let serverPid: Int?
}

struct MoshSessionResponse: Codable, Sendable {
    let session: MoshSessionDescriptor
}

enum MoshRuntimeSupport {
    #if HERDDECK_EMBEDDED_MOSH
    static let embeddedAvailable = true
    #else
    static let embeddedAvailable = false
    #endif
}
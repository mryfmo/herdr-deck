import Foundation

struct GatewayConfiguration: Codable, Sendable, Equatable {
    var baseURL: URL
    var displayName: String
    var requiresBiometrics: Bool
    var terminalPollMilliseconds: Int

    static let defaultPollMilliseconds = 650
}

enum GatewayConnectionPhase: Equatable, Sendable {
    case unconfigured
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .unconfigured: "Set up"
        case .disconnected: "Offline"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .failed: "Unavailable"
        }
    }
}

struct GatewayDescriptor: Codable, Sendable {
    let name: String
    let version: String
    let configPath: String
    let tokenFingerprint: String
    let bind: String
}

struct AgmsgHealth: Codable, Sendable {
    let ok: Bool
    let checks: [GatewayCheck]
}

struct GatewayCheck: Codable, Identifiable, Sendable, Equatable {
    let name: String?
    let label: String?
    let path: String?
    let ok: Bool
    let error: String?

    var id: String { name ?? label ?? path ?? "unknown-check" }
    var displayName: String { name ?? label ?? "Check" }
}

struct HealthResponse: Codable, Sendable {
    let gateway: GatewayDescriptor
    let herdr: JSONValue
    let agmsg: AgmsgHealth
    let mosh: MoshCapabilities?
    let snapshotAt: String?
}

struct AgentProfile: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let runtime: String
    let role: String
    let agmsgName: String
    let modelLabel: String
    let effortLabel: String
    let accent: String
    let commandPreview: String
}

struct ProfilesResponse: Codable, Sendable {
    let profiles: [AgentProfile]
}

struct GatewayErrorEnvelope: Codable, Sendable {
    struct Body: Codable, Sendable {
        let code: String
        let message: String
    }
    let error: Body
}

struct GatewayEvent: Sendable {
    let name: String
    let data: Data
}

struct PairingPayload: Equatable, Sendable {
    let endpoint: String
    let token: String
    let displayName: String
}

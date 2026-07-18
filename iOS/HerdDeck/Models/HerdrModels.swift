import Foundation

enum HerdrAgentStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case idle
    case working
    case blocked
    case done
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = HerdrAgentStatus(rawValue: value) ?? .unknown
    }

    var priority: Int {
        switch self {
        case .blocked: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        case .unknown: 4
        }
    }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .blocked: "Needs input"
        case .done: "Done"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "pause.circle.fill"
        case .working: "waveform.path.ecg"
        case .blocked: "exclamationmark.bubble.fill"
        case .done: "checkmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

struct HerdrAgentSession: Codable, Sendable, Hashable {
    let source: String
    let agent: String
    let kind: String
    let value: String
}

struct HerdrAgent: Codable, Identifiable, Sendable, Hashable {
    let terminalId: String
    let name: String?
    let agent: String?
    let title: String?
    let displayAgent: String?
    let agentStatus: HerdrAgentStatus
    let screenDetectionSkipped: Bool?
    let customStatus: String?
    let stateLabels: [String: String]?
    let agentSession: HerdrAgentSession?
    let workspaceId: String
    let tabId: String
    let paneId: String
    let focused: Bool
    let cwd: String?
    let foregroundCwd: String?
    let revision: UInt64

    var id: String { terminalId }
    var displayName: String { name ?? displayAgent ?? agent ?? title ?? "Unnamed agent" }
    var runtimeLabel: String { displayAgent ?? agent ?? "terminal" }
    var locationLabel: String { foregroundCwd ?? cwd ?? "Unknown directory" }
}

struct HerdrPaneScroll: Codable, Sendable, Hashable {
    let offsetFromBottom: UInt64
    let maxOffsetFromBottom: UInt64
    let viewportRows: UInt64
}

struct HerdrPane: Codable, Identifiable, Sendable, Hashable {
    let paneId: String
    let terminalId: String
    let workspaceId: String
    let tabId: String
    let focused: Bool
    let cwd: String?
    let foregroundCwd: String?
    let label: String?
    let agent: String?
    let title: String?
    let displayAgent: String?
    let agentStatus: HerdrAgentStatus
    let customStatus: String?
    let stateLabels: [String: String]?
    let agentSession: HerdrAgentSession?
    let scroll: HerdrPaneScroll?
    let revision: UInt64

    var id: String { paneId }
}

struct HerdrWorkspace: Codable, Identifiable, Sendable, Hashable {
    let workspaceId: String
    let number: Int
    let label: String
    let focused: Bool
    let paneCount: Int
    let tabCount: Int
    let activeTabId: String
    let agentStatus: HerdrAgentStatus

    var id: String { workspaceId }
}

struct HerdrTab: Codable, Identifiable, Sendable, Hashable {
    let tabId: String
    let workspaceId: String
    let number: Int?
    let label: String?
    let focused: Bool?
    let paneCount: Int?
    let focusedPaneId: String?
    let agentStatus: HerdrAgentStatus?

    var id: String { tabId }
}

struct HerdrSnapshot: Codable, Sendable, Equatable {
    let version: String
    let `protocol`: UInt32
    let focusedWorkspaceId: String?
    let focusedTabId: String?
    let focusedPaneId: String?
    let workspaces: [HerdrWorkspace]
    let tabs: [HerdrTab]
    let panes: [HerdrPane]
    let layouts: [JSONValue]
    let agents: [HerdrAgent]
}

struct SnapshotResponse: Codable, Sendable {
    let snapshot: HerdrSnapshot
}

struct PaneReadResult: Codable, Sendable, Equatable {
    let paneId: String
    let workspaceId: String
    let tabId: String
    let source: String
    let format: String
    let text: String
    let revision: UInt64
    let truncated: Bool
}

struct PaneReadResponse: Codable, Sendable {
    let read: PaneReadResult
}

struct PaneInputRequest: Codable, Sendable {
    var text: String
    var keys: [String]
}

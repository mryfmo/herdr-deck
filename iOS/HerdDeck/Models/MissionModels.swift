import Foundation

struct MissionSpec: Codable, Sendable, Hashable {
    let title: String
    let goal: String
    let projectPath: String
    let team: String
    let maxRounds: Int
    let orchestratorProfileId: String
    let executorProfileIds: [String]
    let deliveryAssist: Bool
}

struct MissionAgent: Codable, Identifiable, Sendable, Hashable {
    let profileId: String
    let runtime: String
    let role: String
    let agmsgName: String
    let herdrName: String
    let paneId: String
    let terminalId: String

    var id: String { terminalId }
}

enum MissionStatus: String, Codable, Sendable, Hashable {
    case starting
    case running
    case completed
    case failed
    case stopped

    var label: String {
        switch self {
        case .starting: "Starting"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }
}

struct MissionRecord: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let createdAt: String
    let updatedAt: String
    let status: MissionStatus
    let spec: MissionSpec
    let agents: [MissionAgent]
    let workspaceId: String?
    let tabId: String?
    let controlAgmsgName: String?
    let error: String?
}

struct MissionsResponse: Codable, Sendable {
    let missions: [MissionRecord]
}

struct MissionResponse: Codable, Sendable {
    let mission: MissionRecord
}

struct StartMissionRequest: Codable, Sendable {
    let title: String
    let goal: String
    let projectPath: String
    let team: String
    let maxRounds: Int
    let orchestratorProfileId: String
    let executorProfileIds: [String]
    let deliveryAssist: Bool
}

struct StartProfileRequest: Codable, Sendable {
    let profileId: String
    let projectPath: String
    let name: String?
    let prompt: String?
    let split: String
    let focus: Bool
}

struct AgentStartedResponse: Codable, Sendable {
    let type: String
    let agent: HerdrAgent
    let argv: [String]
}

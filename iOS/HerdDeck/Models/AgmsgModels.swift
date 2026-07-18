import Foundation

struct TeamsResponse: Codable, Sendable {
    let teams: [String]
}

struct AgmsgMember: Codable, Identifiable, Sendable, Hashable {
    let name: String
    let types: [String]
    let project: String?
    let team: String?

    var id: String { "\(team ?? ""):\(name)" }
    var typeLabel: String { types.isEmpty ? "unknown" : types.joined(separator: ", ") }

    private enum CodingKeys: String, CodingKey {
        case name, types, type, project, team
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        if let values = try container.decodeIfPresent([String].self, forKey: .types) {
            types = values
        } else if let value = try container.decodeIfPresent(String.self, forKey: .type) {
            types = [value]
        } else {
            types = []
        }
        project = try container.decodeIfPresent(String.self, forKey: .project)
        team = try container.decodeIfPresent(String.self, forKey: .team)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(types, forKey: .types)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(team, forKey: .team)
    }
}

struct MembersResponse: Codable, Sendable {
    let members: [AgmsgMember]
}

struct AgmsgMessage: Codable, Identifiable, Sendable, Hashable {
    let type: String
    let id: String
    let team: String
    let fromAgent: String
    let toAgent: String
    let body: String
    let at: String

    enum CodingKeys: String, CodingKey {
        case type, id, team, body, at
        case fromAgent = "from"
        case toAgent = "to"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }
        team = try container.decode(String.self, forKey: .team)
        fromAgent = try container.decode(String.self, forKey: .fromAgent)
        toAgent = try container.decode(String.self, forKey: .toAgent)
        body = try container.decode(String.self, forKey: .body)
        at = try container.decode(String.self, forKey: .at)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(team, forKey: .team)
        try container.encode(fromAgent, forKey: .fromAgent)
        try container.encode(toAgent, forKey: .toAgent)
        try container.encode(body, forKey: .body)
        try container.encode(at, forKey: .at)
    }
}

struct MessagesResponse: Codable, Sendable {
    let messages: [AgmsgMessage]
}

struct SendAgmsgRequest: Codable, Sendable {
    let team: String
    let from: String
    let to: String
    let body: String
}

struct OKResponse: Codable, Sendable {
    let ok: Bool?
}

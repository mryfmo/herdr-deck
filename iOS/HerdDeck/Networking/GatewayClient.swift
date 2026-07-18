import Foundation

struct GatewayAPIError: LocalizedError, Sendable {
    let statusCode: Int?
    let code: String
    let message: String

    var errorDescription: String? { message }
}

struct SSEFrameParser {
    private let maxLineBytes: Int
    private let maxEventDataBytes: Int
    private var line: [UInt8] = []
    private var eventName = "message"
    private var dataLines: [String] = []
    private var dataBytes = 0
    private var lineOverflowed = false
    private var discardingEvent = false

    init(maxLineBytes: Int = 256 * 1024, maxEventDataBytes: Int = 1024 * 1024) {
        self.maxLineBytes = maxLineBytes
        self.maxEventDataBytes = maxEventDataBytes
    }

    mutating func feed(byte: UInt8) -> [GatewayEvent] {
        guard byte == 0x0A else {
            if !lineOverflowed {
                if line.count < maxLineBytes {
                    line.append(byte)
                } else {
                    line.removeAll(keepingCapacity: true)
                    lineOverflowed = true
                    discardEvent()
                }
            }
            return []
        }

        if lineOverflowed {
            lineOverflowed = false
            return []
        }
        if line.last == 0x0D { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        guard !line.isEmpty else { return finishEvent() }
        guard !discardingEvent, line.first != UInt8(ascii: ":") else { return [] }

        let separator = line.firstIndex(of: UInt8(ascii: ":"))
        let fieldBytes = separator.map { line[..<$0] } ?? line[...]
        var valueBytes = separator.map { line[line.index(after: $0)...] } ?? line[line.endIndex...]
        if valueBytes.first == UInt8(ascii: " ") { valueBytes = valueBytes.dropFirst() }
        let field = String(decoding: fieldBytes, as: UTF8.self)
        let value = String(decoding: valueBytes, as: UTF8.self)

        switch field {
        case "event":
            eventName = value
        case "data":
            let addedBytes = value.utf8.count + (dataLines.isEmpty ? 0 : 1)
            guard dataBytes + addedBytes <= maxEventDataBytes else {
                discardEvent()
                return []
            }
            dataLines.append(value)
            dataBytes += addedBytes
        default:
            break
        }
        return []
    }

    private mutating func finishEvent() -> [GatewayEvent] {
        defer { resetEvent() }
        guard !discardingEvent, !dataLines.isEmpty else { return [] }
        let payload = Data(dataLines.joined(separator: "\n").utf8)
        return [GatewayEvent(name: eventName.isEmpty ? "message" : eventName, data: payload)]
    }

    private mutating func discardEvent() {
        discardingEvent = true
        dataLines.removeAll(keepingCapacity: true)
        dataBytes = 0
    }

    private mutating func resetEvent() {
        eventName = "message"
        dataLines.removeAll(keepingCapacity: true)
        dataBytes = 0
        discardingEvent = false
    }
}

final class GatewayClient: @unchecked Sendable {
    private let configuration: GatewayConfiguration
    private let token: String
    private let session: URLSession

    init(configuration: GatewayConfiguration, token: String, session: URLSession = .shared) {
        self.configuration = configuration
        self.token = token
        self.session = session
    }

    private func makeDecoder() -> JSONDecoder {
        GatewayJSONCoding.makeDecoder()
    }

    private func makeEncoder() -> JSONEncoder {
        GatewayJSONCoding.makeEncoder()
    }

    private func encodedPathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func url(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw GatewayAPIError(statusCode: nil, code: "invalid_url", message: "Invalid gateway URL")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, requestedPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let value = components.url else {
            throw GatewayAPIError(statusCode: nil, code: "invalid_url", message: "Unable to construct gateway URL")
        }
        return value
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = method == "GET" ? 20 : 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GatewayAPIError(statusCode: nil, code: "invalid_response", message: "Gateway returned a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? makeDecoder().decode(GatewayErrorEnvelope.self, from: data) {
                throw GatewayAPIError(statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message)
            }
            throw GatewayAPIError(
                statusCode: http.statusCode,
                code: "http_\(http.statusCode)",
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
    }

    private func get<Response: Decodable & Sendable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let request = try makeRequest(path: path, queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        do {
            return try makeDecoder().decode(Response.self, from: data)
        } catch {
            throw GatewayAPIError(statusCode: nil, code: "decode_failed", message: "Unable to decode gateway response: \(error.localizedDescription)")
        }
    }

    private func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let bodyData = try makeEncoder().encode(body)
        let request = try makeRequest(path: path, method: "POST", body: bodyData)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        do {
            return try makeDecoder().decode(Response.self, from: data)
        } catch {
            throw GatewayAPIError(statusCode: nil, code: "decode_failed", message: "Unable to decode gateway response: \(error.localizedDescription)")
        }
    }

    func health() async throws -> HealthResponse {
        try await get("v1/health")
    }

    func snapshot() async throws -> HerdrSnapshot {
        let response: SnapshotResponse = try await get("v1/herdr/snapshot")
        return response.snapshot
    }

    func profiles() async throws -> [AgentProfile] {
        let response: ProfilesResponse = try await get("v1/profiles")
        return response.profiles
    }

    func missions() async throws -> [MissionRecord] {
        let response: MissionsResponse = try await get("v1/missions")
        return response.missions
    }

    func startMission(_ request: StartMissionRequest) async throws -> MissionRecord {
        let response: MissionResponse = try await post("v1/missions", body: request)
        return response.mission
    }

    func startProfile(_ request: StartProfileRequest) async throws -> AgentStartedResponse {
        try await post("v1/profiles/start", body: request)
    }

    func readPane(
        _ paneID: String,
        source: String = "visible",
        lines: Int = 400,
        format: String = "text"
    ) async throws -> PaneReadResult {
        let response: PaneReadResponse = try await get(
            "v1/herdr/panes/\(encodedPathSegment(paneID))/read",
            queryItems: [
                URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "lines", value: String(lines)),
                URLQueryItem(name: "format", value: format == "ansi" ? "ansi" : "text")
            ]
        )
        return response.read
    }

    func moshCapabilities() async throws -> MoshCapabilities {
        let response: MoshCapabilitiesResponse = try await get("v1/mosh/capabilities")
        return response.mosh
    }

    func createMoshSession(_ request: MoshSessionRequest) async throws -> MoshSessionDescriptor {
        let response: MoshSessionResponse = try await post("v1/mosh/sessions", body: request)
        return response.session
    }

    func sendInput(paneID: String, text: String = "", keys: [String] = []) async throws {
        let _: JSONValue = try await post(
            "v1/herdr/panes/\(encodedPathSegment(paneID))/input",
            body: PaneInputRequest(text: text, keys: keys)
        )
    }

    func teams() async throws -> [String] {
        let response: TeamsResponse = try await get("v1/agmsg/teams")
        return response.teams
    }

    func members(team: String) async throws -> [AgmsgMember] {
        let encoded = encodedPathSegment(team)
        let response: MembersResponse = try await get("v1/agmsg/teams/\(encoded)/members")
        return response.members
    }

    func messages(team: String, agent: String? = nil, limit: Int = 100) async throws -> [AgmsgMessage] {
        let encoded = encodedPathSegment(team)
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let agent, !agent.isEmpty { query.append(URLQueryItem(name: "agent", value: agent)) }
        let response: MessagesResponse = try await get("v1/agmsg/teams/\(encoded)/messages", queryItems: query)
        return response.messages
    }

    func sendMessage(_ request: SendAgmsgRequest) async throws {
        let _: OKResponse = try await post("v1/agmsg/messages", body: request)
    }

    func events() -> AsyncThrowingStream<GatewayEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(path: "v1/events")
                    request.timeoutInterval = 60 * 60
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw GatewayAPIError(statusCode: (response as? HTTPURLResponse)?.statusCode, code: "sse_failed", message: "Unable to subscribe to gateway events")
                    }

                    var parser = SSEFrameParser()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for event in parser.feed(byte: byte) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

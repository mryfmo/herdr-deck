import Combine
import Foundation

struct GatewayAPIError: LocalizedError, Sendable {
    let statusCode: Int?
    let code: String
    let message: String
    var errorDescription: String? { message }
}

struct MoshSessionDescriptor: Equatable, Sendable {
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

enum MoshRuntimeSupport {
    static let embeddedAvailable = true
}

@MainActor
final class TerminalFeed: ObservableObject {
    func send(_ data: Data) {}
    func clear() {}
}

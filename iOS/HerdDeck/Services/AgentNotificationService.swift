import Foundation
import UserNotifications

@MainActor
final class AgentNotificationService {
    private var previousStatuses: [String: HerdrAgentStatus] = [:]

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func process(_ agents: [HerdrAgent]) {
        defer {
            previousStatuses = Dictionary(
                agents.map { ($0.id, $0.agentStatus) },
                uniquingKeysWith: { _, latest in latest }
            )
        }
        for agent in agents {
            guard let previous = previousStatuses[agent.id], previous != agent.agentStatus else { continue }
            guard agent.agentStatus == .blocked || agent.agentStatus == .done else { continue }
            let content = UNMutableNotificationContent()
            content.title = agent.agentStatus == .blocked ? "Agent needs input" : "Agent finished"
            content.body = "\(agent.displayName) · \(agent.customStatus ?? agent.agentStatus.label)"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "herddeck-\(agent.id)-\(agent.agentStatus.rawValue)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}

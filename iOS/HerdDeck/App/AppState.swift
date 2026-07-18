import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var configuration: GatewayConfiguration?
    @Published private(set) var connectionPhase: GatewayConnectionPhase = .unconfigured
    @Published private(set) var health: HealthResponse?
    @Published private(set) var snapshot: HerdrSnapshot?
    @Published private(set) var profiles: [AgentProfile] = []
    @Published private(set) var missions: [MissionRecord] = []
    @Published private(set) var teams: [String] = []
    @Published private(set) var messages: [AgmsgMessage] = []
    @Published private(set) var teamMembers: [AgmsgMember] = []
    @Published private(set) var moshCapabilities: MoshCapabilities?
    @Published private(set) var networkInterface: NetworkInterfaceKind = .unavailable
    @Published private(set) var networkIsExpensive = false
    @Published private(set) var networkIsConstrained = false
    @Published private(set) var terminalRoute: TerminalRoute = .gateway
    @Published private(set) var terminalRouteNotice: String?
    @Published var terminalPreferences: TerminalUserPreferences = .default
    @Published var selectedPaneID: String?
    @Published var selectedTeam: String?
    @Published var presentedError: String?
    @Published var isUnlocked = true
    @Published var isRefreshing = false
    @Published var pairingPayload: PairingPayload?

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let biometricLock: BiometricLock
    private let notificationService = AgentNotificationService()
    private let networkPathService: NetworkPathService
    private var token: String?
    private var client: GatewayClient?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var transportSwitchTask: Task<Void, Never>?

    private let configurationKey = "HerdDeck.GatewayConfiguration.v1"
    private let terminalPreferencesKey = "HerdDeck.TerminalPreferences.v1"

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(),
        biometricLock: BiometricLock = BiometricLock(),
        networkPathService: NetworkPathService = NetworkPathService()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.biometricLock = biometricLock
        self.networkPathService = networkPathService
        if let data = defaults.data(forKey: terminalPreferencesKey),
           let saved = try? JSONDecoder().decode(TerminalUserPreferences.self, from: data) {
            terminalPreferences = saved
        }
        restoreConfiguration()
        networkPathService.onChange = { [weak self] interface in
            self?.handleNetworkChange(interface)
        }
        networkPathService.start()
    }

    deinit {
        eventTask?.cancel()
        reconnectTask?.cancel()
        transportSwitchTask?.cancel()
    }

    var agents: [HerdrAgent] {
        (snapshot?.agents ?? []).sorted {
            if $0.agentStatus.priority != $1.agentStatus.priority {
                return $0.agentStatus.priority < $1.agentStatus.priority
            }
            if $0.focused != $1.focused { return $0.focused }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var selectedAgent: HerdrAgent? {
        guard let selectedPaneID else { return agents.first }
        return agents.first { $0.paneId == selectedPaneID }
    }

    var isConfigured: Bool { configuration != nil && token != nil }

    var isMoshReady: Bool {
        moshCapabilities?.enabled == true && MoshRuntimeSupport.embeddedAvailable
    }

    private func account(for configuration: GatewayConfiguration) -> String {
        configuration.baseURL.absoluteString
    }

    private func restoreConfiguration() {
        guard
            let data = defaults.data(forKey: configurationKey),
            let saved = try? JSONDecoder().decode(GatewayConfiguration.self, from: data)
        else {
            connectionPhase = .unconfigured
            return
        }
        do {
            configuration = saved
            token = try keychain.token(account: account(for: saved))
            if let token {
                client = GatewayClient(configuration: saved, token: token)
                connectionPhase = .disconnected
                isUnlocked = !saved.requiresBiometrics
            } else {
                connectionPhase = .unconfigured
            }
        } catch {
            presentedError = error.localizedDescription
            connectionPhase = .unconfigured
        }
    }


    func acceptPairingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "herddeck", url.host?.lowercased() == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            // Keep the first occurrence so a duplicated query parameter cannot
            // override a value the user already inspected in the pairing code.
            if values[item.name] == nil {
                values[item.name] = item.value ?? ""
            }
        }
        guard let endpoint = values["endpoint"], let token = values["token"], !endpoint.isEmpty, !token.isEmpty else { return }
        pairingPayload = PairingPayload(
            endpoint: endpoint,
            token: token,
            displayName: values["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "MacBook"
        )
    }

    func clearPairingPayload() {
        pairingPayload = nil
    }

    func configure(
        endpoint: String,
        token newToken: String,
        displayName: String,
        requiresBiometrics: Bool,
        terminalPollMilliseconds: Int = GatewayConfiguration.defaultPollMilliseconds
    ) async throws {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)), url.host != nil else {
            throw GatewayAPIError(statusCode: nil, code: "invalid_url", message: "Enter a valid gateway URL")
        }
        let isLoopbackHTTP = url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
        guard url.scheme == "https" || isLoopbackHTTP else {
            throw GatewayAPIError(
                statusCode: nil,
                code: "https_required",
                message: "Use the HTTPS URL produced by Tailscale Serve. Plain HTTP is allowed only for loopback development."
            )
        }
        let trimmedToken = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken.count >= 32 else {
            throw GatewayAPIError(statusCode: nil, code: "token_too_short", message: "The gateway token appears incomplete")
        }
        let configuration = GatewayConfiguration(
            baseURL: url,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? "Mac") : displayName,
            requiresBiometrics: requiresBiometrics,
            terminalPollMilliseconds: min(max(terminalPollMilliseconds, 350), 3000)
        )
        let candidate = GatewayClient(configuration: configuration, token: trimmedToken)
        _ = try await candidate.health()

        if let old = self.configuration, old.baseURL != configuration.baseURL {
            try? keychain.deleteToken(account: account(for: old))
        }
        try keychain.saveToken(trimmedToken, account: account(for: configuration))
        defaults.set(try JSONEncoder().encode(configuration), forKey: configurationKey)
        self.configuration = configuration
        self.token = trimmedToken
        self.client = candidate
        self.isUnlocked = !requiresBiometrics
        connectionPhase = .disconnected
        try await connect()
    }

    func connect() async throws {
        guard let client, let configuration else {
            connectionPhase = .unconfigured
            return
        }
        if configuration.requiresBiometrics && !isUnlocked {
            guard try await biometricLock.unlock() else { return }
            isUnlocked = true
        }
        connectionPhase = .connecting
        do {
            async let health = client.health()
            async let snapshot = client.snapshot()
            async let profiles = client.profiles()
            async let missions = client.missions()
            async let teams = client.teams()

            let values = try await (health, snapshot, profiles, missions, teams)
            self.health = values.0
            if let healthMosh = values.0.mosh {
                self.moshCapabilities = healthMosh
            } else {
                self.moshCapabilities = try? await client.moshCapabilities()
            }
            applySnapshot(values.1)
            self.profiles = values.2
            self.missions = values.3
            self.teams = values.4
            if selectedTeam == nil { selectedTeam = values.4.first }
            connectionPhase = .connected
            recomputeTerminalRoute()
            startEventStream()
            await notificationService.requestAuthorization()
        } catch {
            connectionPhase = .failed(error.localizedDescription)
            throw error
        }
    }

    func reconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            do {
                try await connect()
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    func refresh() async {
        guard let client else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let health = client.health()
            async let snapshot = client.snapshot()
            async let missions = client.missions()
            async let teams = client.teams()
            let values = try await (health, snapshot, missions, teams)
            self.health = values.0
            self.moshCapabilities = values.0.mosh ?? self.moshCapabilities
            applySnapshot(values.1)
            self.missions = values.2
            self.teams = values.3
            connectionPhase = .connected
            recomputeTerminalRoute()
        } catch {
            presentedError = error.localizedDescription
            connectionPhase = .failed(error.localizedDescription)
        }
    }

    func lockIfNeeded() {
        guard configuration?.requiresBiometrics == true else { return }
        eventTask?.cancel()
        eventTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        transportSwitchTask?.cancel()
        transportSwitchTask = nil
        connectionPhase = .disconnected
        isUnlocked = false
    }

    func unlock() async {
        do {
            if try await biometricLock.unlock() {
                isUnlocked = true
                if connectionPhase != .connected { try await connect() }
            }
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func forgetGateway() {
        eventTask?.cancel()
        reconnectTask?.cancel()
        transportSwitchTask?.cancel()
        if let configuration { try? keychain.deleteToken(account: account(for: configuration)) }
        defaults.removeObject(forKey: configurationKey)
        configuration = nil
        token = nil
        client = nil
        health = nil
        snapshot = nil
        profiles = []
        missions = []
        teams = []
        messages = []
        teamMembers = []
        moshCapabilities = nil
        selectedPaneID = nil
        selectedTeam = nil
        connectionPhase = .unconfigured
        isUnlocked = true
        recomputeTerminalRoute()
    }

    func readPane(
        _ paneID: String,
        source: String = "visible",
        lines: Int = 400,
        format: String = "text"
    ) async throws -> PaneReadResult {
        guard let client else { throw GatewayAPIError(statusCode: nil, code: "not_configured", message: "Gateway is not configured") }
        return try await client.readPane(paneID, source: source, lines: lines, format: format)
    }

    func sendInput(paneID: String, text: String = "", keys: [String] = []) async throws {
        guard let client else { throw GatewayAPIError(statusCode: nil, code: "not_configured", message: "Gateway is not configured") }
        try await client.sendInput(paneID: paneID, text: text, keys: keys)
    }

    func createMoshSession(paneID: String, columns: Int, rows: Int) async throws -> MoshSessionDescriptor {
        guard let client else {
            throw GatewayAPIError(statusCode: nil, code: "not_configured", message: "Gateway is not configured")
        }
        guard moshCapabilities?.enabled == true else {
            throw GatewayAPIError(statusCode: nil, code: "mosh_unavailable", message: "Mosh is not enabled on the Mac Gateway")
        }
        return try await client.createMoshSession(
            MoshSessionRequest(
                paneId: paneID,
                columns: columns,
                rows: rows,
                predictionMode: terminalPreferences.moshPredictionMode
            )
        )
    }

    func updateTerminalPreferences(_ mutate: (inout TerminalUserPreferences) -> Void) {
        var updated = terminalPreferences
        mutate(&updated)
        let transportPolicyChanged = updated.transportPolicy != terminalPreferences.transportPolicy
        terminalPreferences = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: terminalPreferencesKey)
        }
        if transportPolicyChanged {
            transportSwitchTask?.cancel()
            recomputeTerminalRoute()
        }
    }

    func startMission(_ request: StartMissionRequest) async throws -> MissionRecord {
        guard let client else { throw GatewayAPIError(statusCode: nil, code: "not_configured", message: "Gateway is not configured") }
        let mission = try await client.startMission(request)
        missions.removeAll { $0.id == mission.id }
        missions.insert(mission, at: 0)
        try? await Task.sleep(for: .milliseconds(250))
        await refresh()
        return mission
    }

    func startProfile(_ request: StartProfileRequest) async throws -> AgentStartedResponse {
        guard let client else { throw GatewayAPIError(statusCode: nil, code: "not_configured", message: "Gateway is not configured") }
        let response = try await client.startProfile(request)
        selectedPaneID = response.agent.paneId
        await refresh()
        return response
    }

    func loadMessages(team: String, agent: String? = nil) async {
        guard let client else { return }
        do {
            async let messages = client.messages(team: team, agent: agent)
            async let members = client.members(team: team)
            let values = try await (messages, members)
            self.messages = values.0
            self.teamMembers = values.1
            selectedTeam = team
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func sendMessage(team: String, from: String, to: String, body: String) async throws {
        guard let client else { throw GatewayAPIError(statusCode: nil, code: "not_configured", message: "Gateway is not configured") }
        try await client.sendMessage(SendAgmsgRequest(team: team, from: from, to: to, body: body))
        messages = try await client.messages(team: team)
    }

    private func applySnapshot(_ snapshot: HerdrSnapshot) {
        self.snapshot = snapshot
        if selectedPaneID == nil || !snapshot.panes.contains(where: { $0.paneId == selectedPaneID }) {
            selectedPaneID = snapshot.focusedPaneId ?? snapshot.agents.first?.paneId
        }
        notificationService.process(snapshot.agents)
    }

    private func handleNetworkChange(_ interface: NetworkInterfaceKind) {
        networkInterface = interface
        networkIsExpensive = networkPathService.isExpensive
        networkIsConstrained = networkPathService.isConstrained
        transportSwitchTask?.cancel()

        if interface == .wifi,
           terminalRoute == .mosh,
           terminalPreferences.transportPolicy == .automatic {
            let delay = max(0, terminalPreferences.cellularHysteresisSeconds)
            transportSwitchTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.recomputeTerminalRoute()
            }
        } else {
            recomputeTerminalRoute()
        }

        if interface != .unavailable && connectionPhase != .connected {
            reconnect()
        }
    }

    private func recomputeTerminalRoute() {
        let wantsMosh: Bool
        switch terminalPreferences.transportPolicy {
        case .gatewayOnly:
            wantsMosh = false
        case .automatic:
            wantsMosh = networkInterface == .cellular
        case .moshPreferred:
            wantsMosh = networkInterface != .unavailable
        }

        if wantsMosh && isMoshReady {
            terminalRoute = .mosh
            terminalRouteNotice = nil
            return
        }

        terminalRoute = .gateway
        if wantsMosh {
            if moshCapabilities?.enabled != true {
                terminalRouteNotice = "Cellular detected, but Mosh is not enabled on the Mac Gateway."
            } else if !MoshRuntimeSupport.embeddedAvailable {
                terminalRouteNotice = "Cellular detected. This build lacks the optional embedded Mosh engine, so Terminal is using HTTPS."
            } else {
                terminalRouteNotice = "Mosh is temporarily unavailable; Terminal is using HTTPS."
            }
        } else {
            terminalRouteNotice = nil
        }
    }

    private func startEventStream() {
        eventTask?.cancel()
        guard let client else { return }
        eventTask = Task { [weak self] in
            var retryDelay = 1.0
            while !Task.isCancelled {
                do {
                    for try await event in client.events() {
                        try Task.checkCancellation()
                        retryDelay = 1.0
                        guard let self else { return }
                        await self.handle(event)
                    }
                    guard !Task.isCancelled else { return }
                    guard self != nil else { return }
                    await MainActor.run {
                        self?.connectionPhase = .disconnected
                    }
                    try? await Task.sleep(for: .seconds(retryDelay))
                    retryDelay = min(retryDelay * 1.8, 15)
                } catch is CancellationError {
                    return
                } catch {
                    guard self != nil else { return }
                    await MainActor.run {
                        self?.connectionPhase = .failed(error.localizedDescription)
                    }
                    try? await Task.sleep(for: .seconds(retryDelay))
                    retryDelay = min(retryDelay * 1.8, 15)
                }
            }
        }
    }

    private func handle(_ event: GatewayEvent) async {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        switch event.name {
        case "snapshot":
            if let value = try? decoder.decode(SnapshotResponse.self, from: event.data) {
                applySnapshot(value.snapshot)
                connectionPhase = .connected
            }
        case "mission":
            if let mission = try? decoder.decode(MissionRecord.self, from: event.data) {
                missions.removeAll { $0.id == mission.id }
                missions.insert(mission, at: 0)
            }
        case "agmsg":
            if let team = selectedTeam { await loadMessages(team: team) }
        case "gateway-error":
            if let envelope = try? decoder.decode(GatewayErrorEnvelope.Body.self, from: event.data) {
                connectionPhase = .failed(envelope.message)
            }
        default:
            break
        }
    }
}

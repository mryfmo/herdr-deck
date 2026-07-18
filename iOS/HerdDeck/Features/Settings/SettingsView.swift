import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showForgetConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    gatewayCard
                    networkCard
                    terminalCard
                    securityCard
                    runtimeCard
                    aboutCard
                }
                .padding(16)
            }
            .background(HerdDeckBackground())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionPill(phase: appState.connectionPhase)
                }
            }
            .confirmationDialog(
                "Forget this Gateway?",
                isPresented: $showForgetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Forget Gateway", role: .destructive) { appState.forgetGateway() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The URL and Keychain token will be removed from this iPhone. Nothing on the Mac will be changed.")
            }
        }
    }

    private var networkCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(text: "Network")
                SettingsRow(
                    symbol: appState.networkInterface.symbolName,
                    title: "Active interface",
                    value: appState.networkInterface.label
                )
                SettingsRow(
                    symbol: appState.terminalRoute.symbolName,
                    title: "Terminal route",
                    value: appState.terminalRoute.label
                )
                if appState.networkIsExpensive || appState.networkIsConstrained {
                    Label(
                        appState.networkIsConstrained ? "Low Data Mode or a constrained path is active." : "The current path is marked as metered.",
                        systemImage: "gauge.with.dots.needle.33percent"
                    )
                    .font(.caption)
                    .foregroundStyle(.herdAmber)
                }
                if let notice = appState.terminalRouteNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var terminalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionEyebrow(text: "Terminal")

                VStack(alignment: .leading, spacing: 7) {
                    Text("Transport policy")
                        .font(.subheadline.weight(.semibold))
                    Picker("Transport policy", selection: transportPolicyBinding) {
                        ForEach(TerminalTransportPolicy.allCases) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(appState.terminalPreferences.transportPolicy.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.25)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Default presentation")
                        .font(.subheadline.weight(.semibold))
                    Picker("Default presentation", selection: renderModeBinding) {
                        ForEach(TerminalRenderMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbolName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Rich renders Markdown-style output; Terminal uses VT100/Xterm; Raw preserves searchable plain text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.25)

                if appState.terminalPreferences.transportPolicy == .automatic {
                    Stepper(value: cellularHysteresisBinding, in: 0...120, step: 5) {
                        HStack {
                            Text("Wi-Fi return delay")
                            Spacer()
                            Text("\(appState.terminalPreferences.cellularHysteresisSeconds)s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                }

                HStack {
                    Text("Mosh prediction")
                        .font(.subheadline)
                    Spacer()
                    Picker("Mosh prediction", selection: moshPredictionBinding) {
                        Text("Adaptive").tag("adaptive")
                        Text("Always").tag("always")
                        Text("Never").tag("never")
                    }
                    .pickerStyle(.menu)
                }

                SettingsRow(
                    symbol: "server.rack",
                    title: "Mac Mosh server",
                    value: appState.moshCapabilities?.enabled == true ? "Ready" : "Disabled"
                )
                SettingsRow(
                    symbol: "iphone.gen3",
                    title: "Embedded Mosh client",
                    value: MoshRuntimeSupport.embeddedAvailable ? "Included" : "Not in this build"
                )
                SettingsRow(
                    symbol: "paintbrush.pointed.fill",
                    title: "Unicode renderer",
                    value: "SwiftTerm"
                )

                Text("Mosh is used only for the interactive Terminal surface. Agent state, missions, AGMSG, Rich, and Raw continue over the authenticated HTTPS control plane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gatewayCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionEyebrow(text: "Gateway")
                if let configuration = appState.configuration {
                    SettingsRow(symbol: "laptopcomputer", title: configuration.displayName, value: configuration.baseURL.host ?? configuration.baseURL.absoluteString)
                    SettingsRow(symbol: "server.rack", title: appState.health?.gateway.name ?? "HerdDeck Gateway", value: appState.health?.gateway.version ?? "—")
                    SettingsRow(symbol: "point.3.connected.trianglepath.dotted", title: "Herdr", value: appState.snapshot.map { "v\($0.version) · protocol \($0.protocol)" } ?? "Unavailable")
                    SettingsRow(symbol: "bubble.left.and.bubble.right", title: "AGMSG", value: appState.health?.agmsg.ok == true ? "Ready" : "Check Mac setup")
                }
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Label(appState.isRefreshing ? "Refreshing…" : "Run connection check", systemImage: "arrow.clockwise")
                }
                .buttonStyle(HerdDeckSecondaryButtonStyle())
                .disabled(appState.isRefreshing)
            }
        }
    }

    private var securityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(text: "Security")
                SettingsRow(
                    symbol: "faceid",
                    title: "Device authentication",
                    value: appState.configuration?.requiresBiometrics == true ? "Required" : "Off"
                )
                SettingsRow(symbol: "key.fill", title: "Gateway token", value: "Keychain · hidden")
                SettingsRow(symbol: "lock.fill", title: "Transport", value: appState.configuration?.baseURL.scheme?.uppercased() ?? "—")
                Text("The Gateway binds to loopback, Tailscale Serve provides tailnet HTTPS, and the mobile API blocks server-stop, plugin, integration, and lifecycle-report RPCs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runtimeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(text: "Runtime")
                SettingsRow(symbol: "person.3.fill", title: "Agent profiles", value: String(appState.profiles.count))
                SettingsRow(symbol: "scope", title: "Mission history", value: String(appState.missions.count))
                SettingsRow(symbol: "rectangle.3.group.fill", title: "Workspaces", value: String(appState.snapshot?.workspaces.count ?? 0))
            }
        }
    }

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(text: "HerdDeck")
                Text("Native Herdr operations with AGMSG-backed multi-agent coordination.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showForgetConfirmation = true
                } label: {
                    Label("Forget this Gateway", systemImage: "trash")
                }
                .buttonStyle(HerdDeckSecondaryButtonStyle())
            }
        }
    }

    private var transportPolicyBinding: Binding<TerminalTransportPolicy> {
        Binding(
            get: { appState.terminalPreferences.transportPolicy },
            set: { value in appState.updateTerminalPreferences { $0.transportPolicy = value } }
        )
    }

    private var renderModeBinding: Binding<TerminalRenderMode> {
        Binding(
            get: { appState.terminalPreferences.renderMode },
            set: { value in appState.updateTerminalPreferences { $0.renderMode = value } }
        )
    }

    private var cellularHysteresisBinding: Binding<Int> {
        Binding(
            get: { appState.terminalPreferences.cellularHysteresisSeconds },
            set: { value in appState.updateTerminalPreferences { $0.cellularHysteresisSeconds = value } }
        )
    }

    private var moshPredictionBinding: Binding<String> {
        Binding(
            get: { appState.terminalPreferences.moshPredictionMode },
            set: { value in appState.updateTerminalPreferences { $0.moshPredictionMode = value } }
        )
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.herdCyan)
                .frame(width: 28)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 12)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

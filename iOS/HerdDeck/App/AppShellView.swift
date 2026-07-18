import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: AppTab = .herd

    enum AppTab: Hashable {
        case herd, console, missions, messages, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            HerdOverviewView(openConsole: {
                selection = .console
            })
            .tag(AppTab.herd)
            .tabItem { Label("Herd", systemImage: "point.3.connected.trianglepath.dotted") }

            TerminalConsoleView()
                .tag(AppTab.console)
                .tabItem { Label("Console", systemImage: "terminal.fill") }

            MissionsView(openConsole: { paneID in
                appState.selectedPaneID = paneID
                selection = .console
            })
            .tag(AppTab.missions)
            .tabItem { Label("Missions", systemImage: "scope") }

            MessagesView()
                .tag(AppTab.messages)
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right.fill") }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.herdCyan)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .top) {
            if case .failed(let message) = appState.connectionPhase {
                ConnectionIssueBanner(message: message) {
                    appState.reconnect()
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: appState.connectionPhase)
    }
}

private struct ConnectionIssueBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.herdAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mac unavailable")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Retry", action: retry)
                .font(.caption.weight(.bold))
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.herdAmber.opacity(0.28)))
    }
}

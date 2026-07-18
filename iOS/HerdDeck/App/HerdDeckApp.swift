import SwiftUI
import UIKit
import UserNotifications

@main
struct HerdDeckApp: App {
    @UIApplicationDelegateAdaptor(HerdDeckApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .onOpenURL { url in appState.acceptPairingURL(url) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        if appState.isConfigured && appState.isUnlocked {
                            appState.reconnect()
                        }
                    } else if phase == .background {
                        appState.lockIfNeeded()
                    }
                }
        }
    }
}

final class HerdDeckApplicationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

private struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            HerdDeckBackground()
            if !appState.isConfigured {
                OnboardingView()
            } else if !appState.isUnlocked {
                LockedView()
            } else {
                AppShellView()
            }
        }
        .alert("HerdDeck", isPresented: Binding(
            get: { appState.presentedError != nil },
            set: { if !$0 { appState.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { appState.presentedError = nil }
        } message: {
            Text(appState.presentedError ?? "Unknown error")
        }
    }
}

private struct LockedView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            AppMark(size: 74)
            Text("HerdDeck is locked")
                .font(.title2.weight(.semibold))
            Text("Authenticate before sending commands to your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await appState.unlock() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(HerdDeckPrimaryButtonStyle())
        }
        .padding(32)
    }
}

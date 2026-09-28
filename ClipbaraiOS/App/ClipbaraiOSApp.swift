import SwiftData
import SwiftUI
import UIKit

@main
struct ClipbaraiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    private let snapshots: SnapshotPublisher

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(OnboardingView.doneKey, store: ClipStore.defaults) private var onboardingDone = false

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })
    }

    init() {
        #if DEBUG
        let demo = ProcessInfo.processInfo.arguments.contains("-ClipbaraDemoData")
        container = ClipStore.makeContainer(inMemory: demo)
        if demo {
            DemoData.seed(into: container.mainContext)
        }
        #else
        let demo = false
        container = ClipStore.makeContainer()
        #endif
        snapshots = SnapshotPublisher(container: container)
        snapshots.start()
        if !demo {
            ClipSync.shared.configure(container: container, defaults: ClipStore.defaults)
            Entitlements.shared.start()
        } else {
            // Demo data is for screenshots and UI tests: no trial gate.
            PaywallPresenter.shared.bypass = true
            KeyboardAccess.open.publish()
        }
    }

    private var paywallBinding: Binding<Bool> {
        Binding(get: { PaywallPresenter.shared.isPresented }, set: { PaywallPresenter.shared.isPresented = $0 })
    }

    /// The keyboard cannot check purchases, so the app tells it what is allowed.
    private func publishKeyboardAccess() {
        guard !PaywallPresenter.shared.bypass else { return }
        let entitlements = Entitlements.shared
        KeyboardAccess(state: entitlements.state, trialEnd: entitlements.trialEndDate).publish()
    }

    var body: some Scene {
        WindowGroup {
            ClipsScreen()
                .fullScreenCover(isPresented: onboardingBinding, onDismiss: {
                    guard !PaywallPresenter.shared.bypass else { return }
                    Task {
                        // Let the cover finish going away before the sheet comes up.
                        try? await Task.sleep(for: .milliseconds(500))
                        await PaywallPresenter.shared.showAfterOnboardingIfNeeded()
                    }
                }) {
                    OnboardingView()
                }
                .sheet(isPresented: paywallBinding) {
                    PaywallSheet()
                }
                .onChange(of: Entitlements.shared.state, initial: true) { publishKeyboardAccess() }
                .onChange(of: Entitlements.shared.trialEndDate) { publishKeyboardAccess() }
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Entitlements.shared.reevaluate()
                snapshots.refresh()
                ClipSync.shared.syncOnOpen()
                ClipSync.shared.startLivePolling()
            } else {
                ClipSync.shared.stopLivePolling()
            }
            if phase == .background { snapshots.publish() }
        }
    }
}

/// CloudKit tells the sync engine about changes from other devices with silent pushes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
}

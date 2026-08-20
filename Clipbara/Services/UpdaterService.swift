import Foundation

#if !APPSTORE
import Sparkle

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    private var observation: NSKeyValueObservation?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        observation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#else
// Mac App Store build: updates are delivered by the App Store, Sparkle is not linked.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    func checkForUpdates() {}
}
#endif

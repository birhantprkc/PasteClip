import SwiftData
import SwiftUI

@main
struct ClipbaraiOSApp: App {
    private let container: ModelContainer
    private let snapshots: SnapshotPublisher

    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        let demo = ProcessInfo.processInfo.arguments.contains("-ClipbaraDemoData")
        container = ClipStore.makeContainer(inMemory: demo)
        if demo {
            DemoData.seed(into: container.mainContext)
        }
        #else
        container = ClipStore.makeContainer()
        #endif
        snapshots = SnapshotPublisher(container: container)
        snapshots.start()
    }

    var body: some Scene {
        WindowGroup {
            ClipsScreen()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { snapshots.refresh() }
            if phase == .background { snapshots.publish() }
        }
    }
}

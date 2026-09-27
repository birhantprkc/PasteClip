import SwiftData
import SwiftUI

@main
struct ClipbaraiOSApp: App {
    private let container: ModelContainer

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
    }

    var body: some Scene {
        WindowGroup {
            ClipsScreen()
        }
        .modelContainer(container)
    }
}

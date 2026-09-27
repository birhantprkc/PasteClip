import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("autoSaveOnOpen", store: ClipStore.defaults) private var autoSaveOnOpen = false
    @AppStorage(ClipLibrary.historyLimitKey, store: ClipStore.defaults) private var historyLimit = ClipLibrary.defaultHistoryLimit

    @State private var confirmClear = false

    private let limits = [100, 250, 500, 1000, 0]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Save Clipboard When Opening", isOn: $autoSaveOnOpen)
                } footer: {
                    Text("iOS asks for permission each time unless you set Paste from Other Apps to Allow in Settings > Clipbara.")
                }

                Section {
                    Picker("History Limit", selection: $historyLimit) {
                        ForEach(limits, id: \.self) { limit in
                            if limit == 0 {
                                Text("Unlimited").tag(limit)
                            } else {
                                Text("\(limit) clips").tag(limit)
                            }
                        }
                    }
                    .onChange(of: historyLimit) {
                        ClipLibrary(context: context).trimHistory()
                    }
                } footer: {
                    Text("Clips on a pinboard are never removed by the limit.")
                }

                SyncSettingsSection()

                Section {
                    Button("Clear History", role: .destructive) {
                        confirmClear = true
                    }
                } footer: {
                    Text("Pinned clips are kept.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Link(destination: URL(string: "https://mobrava.github.io/Clipbara/privacy.html")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                }
            }
            .confirmationDialog("Clear History?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) {
                    ClipLibrary(context: context).clearHistory()
                }
            } message: {
                Text("This removes every clip that is not on a pinboard.")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

import SwiftUI
import KeyboardShortcuts

struct ShortcutSettingsTab: View {
    var body: some View {
        Form {
            HStack {
                Text("Toggle History Panel")
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleHistoryPanel)
            }
            HStack {
                Text("Clear All History")
                Spacer()
                KeyboardShortcuts.Recorder(for: .clearHistory)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Look Preview")
                    Text("Pressed inside the panel with a card selected.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LocalKeyRecorderView()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

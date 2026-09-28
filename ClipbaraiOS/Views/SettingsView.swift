import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("autoSaveOnOpen", store: ClipStore.defaults) private var autoSaveOnOpen = false
    @AppStorage(ClipLibrary.historyLimitKey, store: ClipStore.defaults) private var historyLimit = ClipLibrary.defaultHistoryLimit

    @State private var confirmClear = false
    @State private var showsSetupGuide = false
    @State private var showsPaywall = false
    @State private var restoreMessage: String?
    @State private var isRestoring = false

    private let limits = [100, 250, 500, 1000, 0]

    var body: some View {
        NavigationStack {
            Form {
                if !PaywallPresenter.shared.bypass {
                    purchaseSection
                }

                Section {
                    Toggle("Save Clipboard When Opening", isOn: $autoSaveOnOpen)
                } footer: {
                    Text("Saves what you copied in other apps each time you open Clipbara. iOS asks first every time unless you set Paste from Other Apps to Allow in Settings > Apps > Clipbara.")
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
                    Button {
                        showsSetupGuide = true
                    } label: {
                        Label("Setup Guide", systemImage: "list.bullet.clipboard")
                    }
                } footer: {
                    Text("iCloud sync and the Clipbara keyboard, step by step.")
                }

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
            .sheet(isPresented: $showsPaywall) {
                PaywallSheet()
            }
            .fullScreenCover(isPresented: $showsSetupGuide) {
                OnboardingView()
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

    // MARK: - Trial and unlock

    private var isUnlockedForGood: Bool {
        switch Entitlements.shared.state {
        case .unlocked(.lifetime), .unlocked(.grandfathered): true
        default: false
        }
    }

    private var accessStatus: String? {
        switch Entitlements.shared.state {
        case .unlocked(.lifetime), .unlocked(.grandfathered):
            return String(localized: "Unlocked")
        case .unlocked(.unverified):
            return nil
        case .trialActive(let daysLeft):
            return String(localized: "Free trial, \(daysLeft) days left")
        case .trialNotStarted:
            return String(localized: "Free trial not started")
        case .trialExpired:
            return String(localized: "Free trial ended")
        }
    }

    private var purchaseSection: some View {
        Section {
            if let accessStatus {
                LabeledContent("Clipbara", value: accessStatus)
            }
            if !isUnlockedForGood {
                Button("Unlock Clipbara…") { showsPaywall = true }
            }
            Button {
                Task {
                    isRestoring = true
                    defer { isRestoring = false }
                    switch await Entitlements.shared.restorePurchases() {
                    case .restored:
                        restoreMessage = String(localized: "Your purchases were restored.")
                    case .nothingFound:
                        restoreMessage = String(localized: "No unlock purchase was found for this Apple Account.")
                    case .failed:
                        restoreMessage = String(localized: "Couldn't restore purchases. Check your connection and try again.")
                    case .cancelled:
                        restoreMessage = nil
                    }
                }
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .disabled(isRestoring)
        } footer: {
            if let restoreMessage {
                Text(restoreMessage)
            } else {
                Text("One purchase unlocks Clipbara on your Mac and iPhone.")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

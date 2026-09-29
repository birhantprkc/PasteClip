import SwiftUI
import UIKit

/// First-launch setup in two steps: iCloud sync with the Mac, then the keyboard and
/// paste permissions that only the Settings app can turn on.
///
/// Every step can be skipped. It shows once on its own; Settings > Setup Guide opens
/// it again.
struct OnboardingView: View {
    static let doneKey = "onboardingDone"

    enum Step: Int {
        case sync = 1
        case keyboard = 2
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @AppStorage(OnboardingView.doneKey, store: ClipStore.defaults) private var done = false

    @State private var step: Step = .sync
    @State private var keyboard = KeyboardStatus.read()

    private let sync = ClipSync.shared

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .sync:
                    page(
                        symbol: "icloud",
                        title: "Sync with Your Mac",
                        message: "What you copy on one shows up on the other. Off until you turn it on.",
                        content: { syncCard }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
                case .keyboard:
                    page(
                        symbol: "keyboard",
                        title: "Add the Clipbara Keyboard",
                        message: "Type your clips into any app. iOS lets you add keyboards only in Settings.",
                        content: { keyboardCard }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(step.rawValue) of 2")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Later") { finish() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .onChange(of: scenePhase) { _, phase in
            // Back from the Settings app: pick up what the keyboard reported.
            if phase == .active { keyboard = KeyboardStatus.read() }
        }
    }

    // MARK: - Layout

    private func page<Content: View>(
        symbol: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.tint)
                        .frame(height: 48)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
    }

    private var bottomBar: some View {
        Button {
            switch step {
            case .sync:
                withAnimation(.snappy) { step = .keyboard }
            case .keyboard:
                finish()
            }
        } label: {
            Text(step == .sync ? "Continue" : "Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: .bottom))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Divider().padding(.leading, 56)
    }

    // MARK: - Step 1: sync

    private var syncCard: some View {
        VStack(spacing: 10) {
            card {
                row(symbol: "icloud", tint: .blue) {
                    Toggle("iCloud Sync", isOn: syncBinding)
                        .disabled(sync.phase == .starting)
                }
                if syncOn {
                    divider
                    row(symbol: "photo", tint: .orange) {
                        Toggle("Sync Images", isOn: imagesBinding)
                    }
                }
                if let status = syncStatus {
                    divider
                    row(symbol: status.symbol, tint: status.tint) {
                        Text(status.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.snappy, value: syncOn)
            footnote("Works with Clipbara for Mac from the Mac App Store, with iCloud Sync turned on there too. Clips are encrypted and stored in your private iCloud.")
        }
    }

    private var syncOn: Bool {
        sync.isEnabled || sync.phase == .starting
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { syncOn },
            set: { on in
                if on {
                    Task { await sync.enable() }
                } else {
                    sync.disable()
                }
            }
        )
    }

    private var imagesBinding: Binding<Bool> {
        Binding(
            get: {
                _ = sync.imageSettingVersion
                return sync.includesImages
            },
            set: { sync.setIncludesImages($0) }
        )
    }

    private var syncStatus: (symbol: String, tint: Color, text: String)? {
        switch sync.phase {
        case .starting:
            return ("arrow.triangle.2.circlepath", .secondary, String(localized: "Connecting to iCloud…"))
        case .needsAccount:
            return ("person.crop.circle.badge.exclamationmark", .orange, String(localized: "Sign in to iCloud to sync."))
        case .failed(let message):
            return ("exclamationmark.icloud", .red, message)
        case .off, .syncing, .upToDate:
            return nil
        }
    }

    // MARK: - Step 2: keyboard and paste

    private var keyboardCard: some View {
        VStack(spacing: 10) {
            card {
                checklistRow(
                    number: 1,
                    title: "Add the Keyboard",
                    detail: "Settings > General > Keyboard > Keyboards > Add New Keyboard > Clipbara",
                    isDone: keyboard.isAdded
                )
                divider
                checklistRow(
                    number: 2,
                    title: "Allow Full Access (Optional)",
                    detail: "In the same list, tap Clipbara and turn it on. New clips from your Mac then show up without opening Clipbara.",
                    isDone: keyboard.hasFullAccess
                )
            }
            // The system warning scares people off adding the keyboard at all,
            // though it works without Full Access and has no keys to type with.
            Text("iOS shows this same warning for every keyboard that asks for Full Access. Clipbara's keyboard has no letter keys and never sends what you type. Full Access only lets it read your own clips from your iCloud, and the keyboard works without it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 4)
        }
    }

    private func row<Content: View>(symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 52)
    }

    private func checklistRow(number: Int, title: LocalizedStringKey, detail: LocalizedStringKey, isDone: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : Color(.tertiarySystemFill))
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? Text("Done") : Text(""))
    }

    // MARK: -

    private func finish() {
        done = true
        dismiss()
    }
}

import StoreKit
import SwiftUI

/// Shows the trial and unlock sheet from anywhere in the app.
@MainActor
@Observable
final class PaywallPresenter {
    static let shared = PaywallPresenter()

    /// Set once the trial offer has followed the setup guide, so it never repeats there.
    static let shownAfterOnboardingKey = "paywall.shownAfterOnboarding"

    var isPresented = false
    /// Demo data (screenshots, UI tests) skips the gate.
    var bypass = false

    /// True when clips may be used. Otherwise shows the sheet and returns false.
    /// Uses what is already known and refreshes in the background, like the Mac app.
    func requireAccess() -> Bool {
        if bypass || Entitlements.shared.checkHistoryAccess() { return true }
        isPresented = true
        return false
    }

    /// Offers the trial once, right after the setup guide, to new customers only.
    func showAfterOnboardingIfNeeded() async {
        let defaults = ClipStore.defaults
        guard !defaults.bool(forKey: Self.shownAfterOnboardingKey) else { return }
        await Entitlements.shared.refresh()
        guard Entitlements.shared.state == .trialNotStarted else { return }
        defaults.set(true, forKey: Self.shownAfterOnboardingKey)
        isPresented = true
    }
}

/// The trial and unlock screen. Before the trial starts it states the trial length,
/// what stops working when it ends, and the one-time price (Guideline 3.1.1).
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var model = PaywallModel()

    private var entitlements: Entitlements { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let completion = shownCompletion {
                        completionContent(completion)
                    } else {
                        offerContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if shownCompletion == nil { bottomBar } else { doneBar }
            }
            .toolbar {
                if shownCompletion == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Not Now") { dismiss() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            model.reset()
            let purchase = purchase
            model.buy = { try await purchase($0) }
            Task {
                await entitlements.refresh()
                if entitlements.lifetimeProduct == nil { await entitlements.loadProducts() }
            }
        }
    }

    /// Also covers an unlock that arrives from elsewhere while the sheet is open,
    /// such as a purchase on the Mac.
    private var shownCompletion: PaywallModel.Completion? {
        if let completion = model.completion { return completion }
        switch entitlements.state {
        case .unlocked(.lifetime), .unlocked(.grandfathered): return .unlocked
        default: return nil
        }
    }

    private var isTrialOffer: Bool { entitlements.state == .trialNotStarted }
    private var price: String? { entitlements.lifetimeProduct?.displayPrice }

    // MARK: - Offer

    private var offerContent: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: isTrialOffer ? "gift" : "lock.open")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .frame(height: 48)
                    .accessibilityHidden(true)
                header
            }
            VStack(spacing: 0) {
                if isTrialOffer {
                    row(
                        symbol: "calendar",
                        tint: .blue,
                        title: "7 days of full access",
                        detail: Text("Copying clips, the Clipbara keyboard, pinboards and iCloud sync all work. The trial is free and never charges or renews on its own.")
                    )
                    Divider().padding(.leading, 56)
                }
                if entitlements.state == .trialExpired {
                    row(
                        symbol: "tray.full",
                        tint: .green,
                        title: "Your history is safe",
                        detail: Text("Clipbara kept saving and syncing your clips. Settings stay available.")
                    )
                } else {
                    row(
                        symbol: "lock",
                        tint: .orange,
                        title: "When the trial ends",
                        detail: Text("Copying clips from Clipbara and inserting them with the keyboard stop until you unlock. Saving and iCloud sync keep working, so nothing is lost.")
                    )
                }
                Divider().padding(.leading, 56)
                row(
                    symbol: "checkmark.seal",
                    tint: .indigo,
                    title: "One-time purchase, no subscription",
                    detail: price.map { Text("Unlock Clipbara for \($0) and keep full access on your Mac and iPhone.") }
                        ?? Text("Unlock Clipbara with a single purchase and keep full access on your Mac and iPhone.")
                )
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if price == nil, !entitlements.isLoadingProducts {
                HStack(spacing: 6) {
                    Text("Couldn't connect to the App Store.")
                        .foregroundStyle(.secondary)
                    Button("Try Again", action: model.retryLoadingProducts)
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        switch entitlements.state {
        case .trialNotStarted:
            title(Text("Try Clipbara free for 7 days"))
            subtitle(Text("Full access to everything. When the trial ends, keep using Clipbara with a one-time purchase."))
        case .trialActive:
            title(Text("Unlock Clipbara"))
            if let end = entitlements.trialEndDate {
                subtitle(Text("Your free trial ends on \(end, format: .dateTime.month(.wide).day().hour().minute())."))
            }
        case .trialExpired:
            title(Text("Your free trial has ended"))
            subtitle(Text("Unlock Clipbara to copy and insert your clips again. Everything you saved in the meantime has been kept."))
        case .unlocked:
            title(Text("Unlock Clipbara"))
        }
    }

    private func title(_ text: Text) -> some View {
        text.font(.title2.weight(.bold)).multilineTextAlignment(.center)
    }

    private func subtitle(_ text: Text) -> some View {
        text.font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(symbol: String, tint: Color, title: LocalizedStringKey, detail: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                detail.font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Buttons

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if isTrialOffer {
                primaryButton(Text("Start 7-Day Free Trial"), action: model.startTrial)
                    // The price must be on screen before anyone starts the trial.
                    .disabled(entitlements.trialProduct == nil || price == nil || entitlements.isBusy)
                if let price {
                    Button("Unlock for \(price)", action: model.unlock)
                        .font(.subheadline.weight(.semibold))
                        .disabled(entitlements.isBusy)
                }
            } else {
                primaryButton(price.map { Text("Unlock for \($0)") } ?? Text("Unlock Clipbara"), action: model.unlock)
                    .disabled(price == nil || entitlements.isBusy)
            }
            Button("Restore Purchases", action: model.restore)
                .font(.footnote.weight(.medium))
                .disabled(entitlements.isBusy)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: .bottom))
    }

    private var doneBar: some View {
        primaryButton(Text("Done")) { dismiss() }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: .bottom))
    }

    private func primaryButton(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                label.opacity(isWorking ? 0 : 1)
                ProgressView().tint(.white).opacity(isWorking ? 1 : 0)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private var isWorking: Bool {
        entitlements.isBusy || (price == nil && entitlements.isLoadingProducts)
    }

    // MARK: - Completion

    private func completionContent(_ completion: PaywallModel.Completion) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 24)
                .accessibilityHidden(true)
            switch completion {
            case .trialStarted:
                title(Text("Your free trial has started"))
                if let end = entitlements.trialEndDate {
                    subtitle(Text("It ends on \(end, format: .dateTime.month(.wide).day().hour().minute()). You can unlock Clipbara anytime in Settings."))
                }
            case .unlocked:
                title(Text("Clipbara is unlocked"))
                subtitle(Text("Thank you for supporting Clipbara."))
            }
        }
    }
}

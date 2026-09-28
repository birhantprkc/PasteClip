#if APPSTORE
import Foundation
import Observation
import StoreKit

/// Drives the purchase buttons and remembers what just happened, so the window
/// can confirm a started trial or an unlock instead of closing abruptly.
@MainActor
@Observable
final class PaywallModel {
    enum Completion {
        case trialStarted
        case unlocked
    }

    private(set) var completion: Completion?
    private(set) var message: String?
    /// Set by the iOS sheet to SwiftUI's purchase action; the Mac uses `Product.purchase()`.
    @ObservationIgnored var buy: ((Product) async throws -> Product.PurchaseResult)?

    func reset() {
        completion = nil
        message = nil
    }

    func startTrial() {
        guard let product = Entitlements.shared.trialProduct else { return }
        Task {
            message = nil
            let outcome = await Entitlements.shared.purchase(product, using: buy)
            handle(outcome) {
                switch Entitlements.shared.state {
                case .unlocked(.lifetime), .unlocked(.grandfathered): .unlocked
                default: .trialStarted
                }
            }
        }
    }

    func unlock() {
        guard let product = Entitlements.shared.lifetimeProduct else { return }
        Task {
            message = nil
            let outcome = await Entitlements.shared.purchase(product, using: buy)
            handle(outcome) { .unlocked }
        }
    }

    func restore() {
        Task {
            message = nil
            switch await Entitlements.shared.restorePurchases() {
            case .restored:
                switch Entitlements.shared.state {
                case .unlocked(.lifetime), .unlocked(.grandfathered):
                    completion = .unlocked
                default:
                    message = String(localized: "Your purchases were restored.")
                }
            case .nothingFound:
                message = String(localized: "No unlock purchase was found for this Apple Account.")
            case .failed:
                message = String(localized: "Couldn't restore purchases. Check your connection and try again.")
            case .cancelled:
                break
            }
        }
    }

    func retryLoadingProducts() {
        Task { await Entitlements.shared.loadProducts() }
    }

    private func handle(_ outcome: Entitlements.PurchaseOutcome, completed: () -> Completion) {
        switch outcome {
        case .completed:
            completion = completed()
        case .pending:
            message = String(localized: "Your purchase is waiting for approval. Clipbara unlocks as soon as it goes through.")
        case .failed:
            message = String(localized: "The purchase couldn't be completed. Please try again.")
        case .cancelled:
            break
        }
    }
}
#endif

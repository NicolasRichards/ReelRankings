import Foundation
import StoreKit

/// Loads and purchases the optional "buy us a coffee" tips.
///
/// The tips are consumable in-app purchases — nothing is unlocked, so there is
/// no entitlement to track. We just finish each transaction and show a thank-you.
@MainActor
@Observable
final class TipJar {
    static let productIDs = [
        "NickRichards.ReelRankings.tip.small",
        "NickRichards.ReelRankings.tip.medium",
        "NickRichards.ReelRankings.tip.large",
    ]

    /// Shared so the tip screen and the app-level transaction listener see the
    /// same state.
    static let shared = TipJar()

    /// Loaded products, sorted cheapest first.
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var purchasing: Product.ID?
    /// In memory only: the thank-you lasts for this session.
    private(set) var didTip = false
    /// Tips whose purchase came back `.pending` (Ask to Buy) and await approval.
    private(set) var pendingApprovals: Set<Product.ID> = []
    var awaitingApproval: Bool { !pendingApprovals.isEmpty }
    /// The last purchase attempt threw — for example Screen Time blocks
    /// in-app purchases, or the connection dropped mid-purchase.
    private(set) var purchaseFailed = false
    /// Products couldn't load, or fewer than requested came back.
    private(set) var loadFailed = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// Called each time the tip screen appears, and by its Retry button.
    func load() async {
        // A failure message belongs to the visit it happened in
        purchaseFailed = false
        guard products.count < Self.productIDs.count, !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
            loadFailed = products.count < Self.productIDs.count
        } catch {
            loadFailed = true
        }
    }

    /// Finishes any transaction that completes outside the purchase call
    /// (Ask to Buy approvals, retries after an interruption). Started once
    /// from the app's init and kept for the app's lifetime, so an approval
    /// that lands while the tip screen is closed is still finished.
    func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await update in Transaction.updates {
                // Finish unverified transactions too: a tip unlocks nothing, and an
                // unfinished transaction is redelivered on every launch.
                await update.unsafePayloadValue.finish()
                // Only thank someone waiting on an Ask to Buy approval. Anything else
                // here is a leftover StoreKit redelivered at launch, not a new tip.
                if case .verified(let transaction) = update,
                   pendingApprovals.remove(transaction.productID) != nil {
                    didTip = true
                }
            }
        }
    }

    func purchase(_ product: Product) async {
        guard purchasing == nil else { return }
        purchasing = product.id
        purchaseFailed = false
        defer { purchasing = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                // Finished even if unverified, for the same reason as the listener.
                await verification.unsafePayloadValue.finish()
                if case .verified = verification {
                    pendingApprovals.remove(product.id)
                    didTip = true
                } else {
                    purchaseFailed = true
                }
            case .pending:
                pendingApprovals.insert(product.id)
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch StoreKitError.userCancelled {
            // Cancelling the Apple Account sign-in arrives as a thrown error
            // rather than a .userCancelled result; it isn't a failure either way
        } catch {
            purchaseFailed = true
        }
    }
}

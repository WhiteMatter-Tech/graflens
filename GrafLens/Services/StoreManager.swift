import Foundation
import StoreKit

@MainActor
class StoreManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var purchaseError: String?
    @Published var isPurchasing = false
    @Published var showThankYou = false
    @Published var totalTips: Int

    static let tipProductIDs: Set<String> = [
        "tech.whitematter.graflens.tip.small",
        "tech.whitematter.graflens.tip.medium",
        "tech.whitematter.graflens.tip.large",
    ]

    private let totalTipsKey = "totalTipCount"
    private var transactionListener: Task<Void, Never>?

    init() {
        totalTips = UserDefaults.standard.integer(forKey: totalTipsKey)
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.tipProductIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Failed to load products"
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                recordTip()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase pending approval"
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isPurchasing = false
    }

    private func recordTip() {
        totalTips += 1
        UserDefaults.standard.set(totalTips, forKey: totalTipsKey)
        showThankYou = true
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await MainActor.run { self.recordTip() }
                }
            }
        }
    }
}

enum StoreError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "Transaction verification failed"
        }
    }
}

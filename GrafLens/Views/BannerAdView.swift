import SwiftUI
import StoreKit

struct TipJarView: View {
    @EnvironmentObject var storeManager: StoreManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "heart.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("Tip Jar")
                    .font(.title.bold())

                Text("GrafLens is free with no ads. If you find it useful, consider leaving a tip to support development.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if storeManager.totalTips > 0 {
                    Text("You've tipped \(storeManager.totalTips) time\(storeManager.totalTips == 1 ? "" : "s"). Thank you!")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                if let error = storeManager.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(spacing: 10) {
                    ForEach(storeManager.products, id: \.id) { product in
                        Button {
                            Task { await storeManager.purchase(product) }
                        } label: {
                            HStack {
                                Text(labelForProduct(product))
                                    .font(.body)
                                Spacer()
                                Text(product.displayPrice)
                                    .font(.body.bold())
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tintForProduct(product))
                        .disabled(storeManager.isPurchasing)
                    }

                    if storeManager.products.isEmpty {
                        Text("Loading tip options...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Thank You!", isPresented: $storeManager.showThankYou) {
                Button("OK") { }
            } message: {
                Text("Your support means a lot and helps keep GrafLens free for everyone.")
            }
        }
    }

    private func labelForProduct(_ product: Product) -> String {
        switch product.id {
        case "tech.whitematter.graflens.tip.small": return "Coffee"
        case "tech.whitematter.graflens.tip.medium": return "Lunch"
        case "tech.whitematter.graflens.tip.large": return "Dinner"
        default: return product.displayName
        }
    }

    private func tintForProduct(_ product: Product) -> Color {
        switch product.id {
        case "tech.whitematter.graflens.tip.small": return .orange
        case "tech.whitematter.graflens.tip.medium": return .orange.opacity(0.85)
        case "tech.whitematter.graflens.tip.large": return .orange.opacity(0.7)
        default: return .orange
        }
    }
}

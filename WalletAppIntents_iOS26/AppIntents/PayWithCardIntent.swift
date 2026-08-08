import AppIntents
import SwiftUI
import Foundation

@AssistantIntent(schema: .wallet.payWithCard)
struct PayWithCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Pay with Card"
    static var description: IntentDescription = "Pay using Apple Pay with a specific card"

    @Parameter(title: "Amount", description: "Amount to pay", requestValueDialog: "How much would you like to pay?")
    var amount: Double

    @Parameter(title: "Card", description: "Card to use for payment", requestValueDialog: "Which card would you like to use?")
    var card: CardEntity

    @Parameter(title: "Merchant", description: "Merchant name", default: "Current Merchant", requestValueDialog: "Who are you paying?")
    var merchant: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Pay \(.$amount) with my \(.$card)") {
            \.$merchant
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard amount > 0 else {
            throw WalletIntentError.invalidAmount
        }

        guard !card.isLocked else {
            throw WalletIntentError.cardLocked
        }

        // Simulate payment processing
        try await Task.sleep(for: .seconds(1))

        let transaction = TransactionEntity(
            id: UUID().uuidString,
            title: merchant ?? "Siri Payment",
            amount: amount,
            date: Date(),
            cardId: card.id,
            category: "Siri Payment",
            merchantName: merchant ?? "Unknown Merchant"
        )

        WalletDataProvider.shared.addTransaction(transaction)

        let dialog: LocalizedStringResource = "Paid \(amount, format: .currency(code: \"USD\")) using your \(card.name). Tap to see details."

        return .result(
            dialog: dialog,
            view: PaymentConfirmationView(card: card, amount: amount, merchant: merchant ?? "Merchant")
        )
    }
}

// MARK: - Custom Siri UI View
struct PaymentConfirmationView: View {
    let card: CardEntity
    let amount: Double
    let merchant: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title)

                VStack(alignment: .leading) {
                    Text("Payment Successful")
                        .font(.headline)
                    Text(merchant)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                CardImageView(card: card)
                    .frame(width: 60, height: 40)

                VStack(alignment: .leading) {
                    Text(card.name)
                        .font(.subheadline.bold())
                    Text("•••• \(card.lastFour)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(amount, format: .currency(code: "USD"))
                    .font(.title3.bold())
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct CardImageView: View {
    let card: CardEntity

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(hex: card.color) ?? .blue)
            .overlay(
                HStack {
                    Spacer()
                    Image(systemName: "creditcard.fill")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(8)
            )
    }
}

// MARK: - Hex Color Extension
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

import AppIntents
import SwiftUI

@AssistantIntent(schema: .wallet.transactionHistory)
struct GetTransactionHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Transaction History"
    static var description: IntentDescription = "Show recent transactions"

    @Parameter(title: "Count", description: "Number of transactions to show", default: 5, requestValueDialog: "How many transactions would you like to see?")
    var count: Int

    @Parameter(title: "Card", description: "Filter by card", requestValueDialog: "Which card?")
    var card: CardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show my last \(.$count) transactions") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let transactions = WalletDataProvider.shared.transactions
            .filter { card == nil || $0.cardId == card?.id }
            .prefix(max(1, min(count, 20)))

        guard !transactions.isEmpty else {
            return .result(dialog: "You don't have any recent transactions.")
        }

        let dialog: LocalizedStringResource = "Here are your last \(transactions.count) transactions."

        return .result(
            dialog: dialog,
            view: TransactionListView(transactions: Array(transactions), card: card)
        )
    }
}

struct TransactionListView: View {
    let transactions: [TransactionEntity]
    let card: CardEntity?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transactions")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(transactions) { tx in
                HStack {
                    VStack(alignment: .leading) {
                        Text(tx.merchantName)
                            .font(.subheadline.bold())
                        Text(tx.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(tx.amount, format: .currency(code: "USD"))
                        .font(.subheadline)
                }
                .padding(.vertical, 4)

                if tx.id != transactions.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

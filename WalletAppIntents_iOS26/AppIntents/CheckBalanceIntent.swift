import AppIntents
import SwiftUI

@AssistantIntent(schema: .wallet.checkBalance)
struct CheckBalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Balance"
    static var description: IntentDescription = "Check Apple Cash or card balance"

    @Parameter(title: "Account", description: "Card or account to check", requestValueDialog: "Which account would you like to check?")
    var account: CardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("What's my \(.$account) balance?")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let targetCard = account ?? WalletDataProvider.shared.cards.first { $0.type == .appleCash }

        guard let card = targetCard else {
            throw WalletIntentError.cardNotFound(name: "Apple Cash")
        }

        let balance = card.balance ?? 0.0

        let dialog: LocalizedStringResource = "Your \(card.name) balance is \(balance, format: .currency(code: \"USD\"))."

        return .result(
            dialog: dialog,
            view: BalanceView(card: card, balance: balance)
        )
    }
}

struct BalanceView: View {
    let card: CardEntity
    let balance: Double

    var body: some View {
        HStack {
            CardImageView(card: card)
                .frame(width: 80, height: 50)

            VStack(alignment: .leading) {
                Text(card.name)
                    .font(.headline)
                Text("Available Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(balance, format: .currency(code: "USD"))
                .font(.title2.bold())
                .foregroundStyle(.primary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

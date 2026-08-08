import AppIntents
import SwiftUI

@AssistantIntent(schema: .wallet.addCard)
struct AddCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Card"
    static var description: IntentDescription = "Add a new card to Apple Wallet"

    @Parameter(title: "Card Number", description: "Last four digits or full number", requestValueDialog: "What's the card number?")
    var cardNumber: String

    @Parameter(title: "Card Type", description: "Type of card", requestValueDialog: "What type of card is this?")
    var cardType: CardEntity.CardType

    @Parameter(title: "Issuer", description: "Bank or issuer", requestValueDialog: "Who issued this card?")
    var issuer: String

    @Parameter(title: "Nickname", description: "Optional nickname", default: "", requestValueDialog: "What would you like to call this card?")
    var nickname: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add my new \(.$cardType) card") {
            \.$cardNumber
            \.$issuer
            \.$nickname
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sanitized = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitized.count >= 4 else {
            throw WalletIntentError.invalidAmount
        }

        let lastFour = String(sanitized.suffix(4))
        let name = nickname?.isEmpty == false ? nickname! : "\(issuer) \(cardType.rawValue.capitalized)"

        let newCard = CardEntity(
            id: "card_\(UUID().uuidString)",
            name: name,
            lastFour: lastFour,
            type: cardType,
            issuer: issuer,
            balance: nil,
            isLocked: false,
            color: "#007AFF",
            imageName: "card_generic"
        )

        WalletDataProvider.shared.addCard(newCard)

        let dialog: LocalizedStringResource = "I've added your \(name) ending in \(lastFour) to Apple Wallet. You can start using it with Apple Pay right away."

        return .result(dialog: dialog)
    }
}

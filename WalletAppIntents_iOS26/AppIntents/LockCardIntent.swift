import AppIntents

@AssistantIntent(schema: .wallet.lockCard)
struct LockCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock Card"
    static var description: IntentDescription = "Temporarily lock a credit or debit card"

    @Parameter(title: "Card", description: "Card to lock", requestValueDialog: "Which card would you like to lock?")
    var card: CardEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Lock my \(.$card)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !card.isLocked else {
            return .result(dialog: "Your \(card.name) is already locked.")
        }

        WalletDataProvider.shared.lockCard(id: card.id)

        let dialog: LocalizedStringResource = "I've locked your \(card.name) ending in \(card.lastFour). No new transactions will be approved. You can unlock it anytime in the Wallet app."

        return .result(dialog: dialog)
    }
}

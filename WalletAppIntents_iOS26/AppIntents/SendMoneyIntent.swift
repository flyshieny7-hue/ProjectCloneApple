import AppIntents
import SwiftUI
import Foundation

@AssistantIntent(schema: .wallet.sendMoney)
struct SendMoneyIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Money"
    static var description: IntentDescription = "Send money to a contact using Apple Cash"

    @Parameter(title: "Amount", description: "Amount to send", requestValueDialog: "How much would you like to send?")
    var amount: Double

    @Parameter(title: "Recipient", description: "Contact to send money to", requestValueDialog: "Who would you like to send money to?")
    var recipient: ContactEntity

    @Parameter(title: "Note", description: "Optional note", default: "", requestValueDialog: "Would you like to add a note?")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(.$amount) to \(.$recipient)") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard amount > 0 else {
            throw WalletIntentError.invalidAmount
        }

        guard let appleCash = WalletDataProvider.shared.cards.first(where: { $0.type == .appleCash }),
              let balance = appleCash.balance, balance >= amount else {
            throw WalletIntentError.insufficientFunds
        }

        // Simulate sending
        try await Task.sleep(for: .seconds(1))

        let noteText = (note?.isEmpty == false) ? "Note: \(note!)" : ""
        let dialog: LocalizedStringResource = "Sent \(amount, format: .currency(code: \"USD\")) to \(recipient.name). \(noteText)"

        return .result(
            dialog: dialog,
            view: SendMoneyView(recipient: recipient, amount: amount, note: note)
        )
    }
}

struct SendMoneyView: View {
    let recipient: ContactEntity
    let amount: Double
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)

                Text("Money Sent")
                    .font(.headline)
            }

            Divider()

            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.gray)

                VStack(alignment: .leading) {
                    Text(recipient.name)
                        .font(.subheadline.bold())
                    Text(recipient.handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(amount, format: .currency(code: "USD"))
                    .font(.title3.bold())
            }

            if let note = note, !note.isEmpty {
                Text("Note: \(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

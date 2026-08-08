import AppIntents

struct WalletShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PayWithCardIntent(),
            phrases: [
                "Pay \(.$amount) with my \(.$card) using Apple Pay",
                "Pay with my \(.$card)",
                "Send \(.$amount) using Apple Pay"
            ],
            shortTitle: "Pay with Card",
            systemImageName: "creditcard.fill"
        )

        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "What's my \(.$account) balance",
                "Check my Apple Cash balance",
                "How much money do I have"
            ],
            shortTitle: "Check Balance",
            systemImageName: "dollarsign.circle.fill"
        )

        AppShortcut(
            intent: LockCardIntent(),
            phrases: [
                "Lock my \(.$card)",
                "Disable my \(.$card)",
                "Turn off my \(.$card)"
            ],
            shortTitle: "Lock Card",
            systemImageName: "lock.fill"
        )

        AppShortcut(
            intent: SendMoneyIntent(),
            phrases: [
                "Send \(.$amount) to \(.$recipient)",
                "Pay \(.$recipient) \(.$amount)",
                "Apple Cash \(.$recipient) \(.$amount)"
            ],
            shortTitle: "Send Money",
            systemImageName: "arrow.up.circle.fill"
        )

        AppShortcut(
            intent: GetTransactionHistoryIntent(),
            phrases: [
                "Show my last \(.$count) transactions",
                "Recent transactions",
                "What did I buy recently"
            ],
            shortTitle: "Transactions",
            systemImageName: "list.bullet.rectangle.fill"
        )

        AppShortcut(
            intent: AddCardIntent(),
            phrases: [
                "Add my new \(.$cardType) card",
                "Add a card to Wallet",
                "New card \(.$cardNumber)"
            ],
            shortTitle: "Add Card",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: BudgetStatusIntent(),
            phrases: [
                "How's my \(.$category) budget",
                "Budget status",
                "Am I over budget"
            ],
            shortTitle: "Budget Status",
            systemImageName: "chart.pie.fill"
        )
    }
}

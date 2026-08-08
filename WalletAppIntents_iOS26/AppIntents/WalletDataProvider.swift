import Foundation

@MainActor
final class WalletDataProvider: ObservableObject {
    static let shared = WalletDataProvider()

    @Published var cards: [CardEntity] = []
    @Published var contacts: [ContactEntity] = []
    @Published var transactions: [TransactionEntity] = []
    @Published var budgets: [BudgetCategoryEntity] = []

    private init() {
        loadMockData()
    }

    private func loadMockData() {
        cards = [
            CardEntity(
                id: "card_chase_sapphire",
                name: "Chase Sapphire Reserve",
                lastFour: "4242",
                type: .visa,
                issuer: "Chase",
                balance: nil,
                isLocked: false,
                color: "#1B4F72",
                imageName: "card_chase"
            ),
            CardEntity(
                id: "card_amex_platinum",
                name: "Amex Platinum",
                lastFour: "1001",
                type: .amex,
                issuer: "American Express",
                balance: nil,
                isLocked: false,
                color: "#2C3E50",
                imageName: "card_amex"
            ),
            CardEntity(
                id: "card_apple_cash",
                name: "Apple Cash",
                lastFour: "0000",
                type: .appleCash,
                issuer: "Apple",
                balance: 1250.75,
                isLocked: false,
                color: "#34C759",
                imageName: "card_apple_cash"
            ),
            CardEntity(
                id: "card_visa_debit",
                name: "Visa Debit",
                lastFour: "8888",
                type: .visa,
                issuer: "Bank of America",
                balance: 3420.50,
                isLocked: false,
                color: "#007AFF",
                imageName: "card_boa"
            )
        ]

        contacts = [
            ContactEntity(id: "contact_alice", name: "Alice Johnson", handle: "+1-555-0101", avatarName: "avatar_alice"),
            ContactEntity(id: "contact_bob", name: "Bob Smith", handle: "+1-555-0102", avatarName: "avatar_bob"),
            ContactEntity(id: "contact_charlie", name: "Charlie Brown", handle: "charlie@example.com", avatarName: "avatar_charlie")
        ]

        transactions = [
            TransactionEntity(id: "tx_1", title: "Whole Foods", amount: 87.43, date: Date().addingTimeInterval(-3600), cardId: "card_chase_sapphire", category: "Groceries", merchantName: "Whole Foods"),
            TransactionEntity(id: "tx_2", title: "Starbucks", amount: 5.67, date: Date().addingTimeInterval(-7200), cardId: "card_apple_cash", category: "Food & Drink", merchantName: "Starbucks"),
            TransactionEntity(id: "tx_3", title: "Uber", amount: 24.50, date: Date().addingTimeInterval(-18000), cardId: "card_amex_platinum", category: "Transport", merchantName: "Uber"),
            TransactionEntity(id: "tx_4", title: "Amazon", amount: 129.99, date: Date().addingTimeInterval(-86400), cardId: "card_chase_sapphire", category: "Shopping", merchantName: "Amazon"),
            TransactionEntity(id: "tx_5", title: "Netflix", amount: 15.49, date: Date().addingTimeInterval(-172800), cardId: "card_visa_debit", category: "Entertainment", merchantName: "Netflix")
        ]

        budgets = [
            BudgetCategoryEntity(id: "budget_food", name: "Food & Dining", spent: 450.00, limit: 600.00, iconName: "fork.knife.circle.fill"),
            BudgetCategoryEntity(id: "budget_transport", name: "Transport", spent: 180.00, limit: 300.00, iconName: "car.fill"),
            BudgetCategoryEntity(id: "budget_shopping", name: "Shopping", spent: 890.00, limit: 500.00, iconName: "bag.fill")
        ]
    }

    func card(named name: String) -> CardEntity? {
        let lowercased = name.lowercased()
        return cards.first {
            $0.name.lowercased().contains(lowercased) ||
            $0.issuer.lowercased().contains(lowercased) ||
            $0.lastFour == lowercased ||
            $0.type.rawValue.lowercased() == lowercased
        }
    }

    func contact(named name: String) -> ContactEntity? {
        let lowercased = name.lowercased()
        return contacts.first {
            $0.name.lowercased().contains(lowercased) ||
            $0.handle.lowercased().contains(lowercased)
        }
    }

    func addTransaction(_ transaction: TransactionEntity) {
        transactions.insert(transaction, at: 0)
    }

    func lockCard(id: String) {
        // In production: update persistent store
        // Mock implementation: print to console
        print("Card \(id) locked")
    }

    func addCard(_ card: CardEntity) {
        cards.append(card)
    }
}

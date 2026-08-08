import AppIntents
import SwiftUI

// MARK: - Card Entity
@AssistantEntity(schema: .wallet.card)
struct CardEntity: AppEntity, Identifiable {
    static var defaultQuery = CardQuery()

    let id: String
    let name: String
    let lastFour: String
    let type: CardType
    let issuer: String
    let balance: Double?
    let isLocked: Bool
    let color: String
    let imageName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: "•••• \(lastFour)"),
            image: .init(systemName: "creditcard.fill")
        )
    }

    enum CardType: String, AppEnum {
        case visa, mastercard, amex, discover, chase, appleCash

        static var typeDisplayRepresentation: TypeDisplayRepresentation {
            "Card Type"
        }

        static var caseDisplayRepresentations: [CardType: DisplayRepresentation] {
            [
                .visa: "Visa",
                .mastercard: "Mastercard",
                .amex: "American Express",
                .discover: "Discover",
                .chase: "Chase",
                .appleCash: "Apple Cash"
            ]
        }
    }
}

// MARK: - Card Query
struct CardQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CardEntity] {
        WalletDataProvider.shared.cards.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CardEntity] {
        WalletDataProvider.shared.cards
    }
}

// MARK: - Fuzzy Card Query (for Siri resolution)
struct FuzzyCardQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [CardEntity] {
        let lowercased = string.lowercased()
        return WalletDataProvider.shared.cards.filter { card in
            card.name.lowercased().contains(lowercased) ||
            card.issuer.lowercased().contains(lowercased) ||
            card.lastFour.contains(lowercased) ||
            card.type.rawValue.lowercased() == lowercased
        }
    }

    func entities(for identifiers: [String]) async throws -> [CardEntity] {
        WalletDataProvider.shared.cards.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CardEntity] {
        WalletDataProvider.shared.cards
    }
}

// MARK: - Contact Entity
@AssistantEntity(schema: .wallet.contact)
struct ContactEntity: AppEntity, Identifiable {
    static var defaultQuery = ContactQuery()

    let id: String
    let name: String
    let handle: String
    let avatarName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: handle),
            image: .init(systemName: "person.crop.circle.fill")
        )
    }
}

struct ContactQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ContactEntity] {
        WalletDataProvider.shared.contacts.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ContactEntity] {
        WalletDataProvider.shared.contacts
    }
}

struct FuzzyContactQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [ContactEntity] {
        let lowercased = string.lowercased()
        return WalletDataProvider.shared.contacts.filter { contact in
            contact.name.lowercased().contains(lowercased) ||
            contact.handle.lowercased().contains(lowercased)
        }
    }

    func entities(for identifiers: [String]) async throws -> [ContactEntity] {
        WalletDataProvider.shared.contacts.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ContactEntity] {
        WalletDataProvider.shared.contacts
    }
}

// MARK: - Transaction Entity
@AssistantEntity(schema: .wallet.transaction)
struct TransactionEntity: AppEntity, Identifiable {
    static var defaultQuery = TransactionQuery()

    let id: String
    let title: String
    let amount: Double
    let date: Date
    let cardId: String
    let category: String
    let merchantName: String

    var displayRepresentation: DisplayRepresentation {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let amountString = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"

        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: "\(amountString) at \(merchantName)"),
            subtitle: LocalizedStringResource(stringLiteral: category),
            image: .init(systemName: "dollarsign.circle.fill")
        )
    }
}

struct TransactionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TransactionEntity] {
        WalletDataProvider.shared.transactions.filter { identifiers.contains($0.id) }
    }
}

// MARK: - Budget Category Entity
@AssistantEntity(schema: .wallet.budgetCategory)
struct BudgetCategoryEntity: AppEntity, Identifiable {
    static var defaultQuery = BudgetCategoryQuery()

    let id: String
    let name: String
    let spent: Double
    let limit: Double
    let iconName: String

    var displayRepresentation: DisplayRepresentation {
        let percentage = Int((spent / limit) * 100)
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: "\(percentage)% used"),
            image: .init(systemName: iconName)
        )
    }
}

struct BudgetCategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BudgetCategoryEntity] {
        WalletDataProvider.shared.budgets.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BudgetCategoryEntity] {
        WalletDataProvider.shared.budgets
    }
}

struct FuzzyBudgetQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [BudgetCategoryEntity] {
        let lowercased = string.lowercased()
        return WalletDataProvider.shared.budgets.filter { budget in
            budget.name.lowercased().contains(lowercased)
        }
    }

    func entities(for identifiers: [String]) async throws -> [BudgetCategoryEntity] {
        WalletDataProvider.shared.budgets.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BudgetCategoryEntity] {
        WalletDataProvider.shared.budgets
    }
}

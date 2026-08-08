import AppIntents

enum WalletIntentError: Error, CustomLocalizedStringResourceConvertible {
    case cardNotFound(name: String)
    case contactNotFound(name: String)
    case invalidAmount
    case insufficientFunds
    case cardLocked
    case networkError
    case authenticationRequired
    case budgetNotFound(name: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .cardNotFound(let name):
            return "I couldn't find a card matching \(name). Please check the name and try again."
        case .contactNotFound(let name):
            return "I couldn't find a contact named \(name) in your address book."
        case .invalidAmount:
            return "Please provide a valid amount greater than zero."
        case .insufficientFunds:
            return "You don't have enough funds for this transaction."
        case .cardLocked:
            return "This card is currently locked. Unlock it in the Wallet app first."
        case .networkError:
            return "There was a network error. Please check your connection and try again."
        case .authenticationRequired:
            return "Authentication is required. Please unlock your device and try again."
        case .budgetNotFound(let name):
            return "I couldn't find a budget category named \(name)."
        }
    }
}

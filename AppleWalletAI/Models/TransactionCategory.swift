import Foundation

/// Категории транзакций с семантическими терминами для NLP
@available(iOS 26.0, *)
public enum TransactionCategory: String, Codable, CaseIterable, Hashable {
    case foodAndDrink = "food_and_drink"
    case groceries = "groceries"
    case transportation = "transportation"
    case shopping = "shopping"
    case entertainment = "entertainment"
    case travel = "travel"
    case health = "health"
    case utilities = "utilities"
    case gas = "gas"
    case education = "education"
    case income = "income"
    case other = "other"

    public var displayName: String {
        switch self {
        case .foodAndDrink: return "Food & Drink"
        case .groceries: return "Groceries"
        case .transportation: return "Transportation"
        case .shopping: return "Shopping"
        case .entertainment: return "Entertainment"
        case .travel: return "Travel"
        case .health: return "Health"
        case .utilities: return "Utilities"
        case .gas: return "Gas"
        case .education: return "Education"
        case .income: return "Income"
        case .other: return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .foodAndDrink: return "fork.knife"
        case .groceries: return "cart"
        case .transportation: return "car"
        case .shopping: return "bag"
        case .entertainment: return "film"
        case .travel: return "airplane"
        case .health: return "heart"
        case .utilities: return "bolt"
        case .gas: return "fuel.pump"
        case .education: return "book"
        case .income: return "arrow.down.circle"
        case .other: return "tag"
        }
    }

    public var color: String {
        switch self {
        case .foodAndDrink: return "#FF6B6B"
        case .groceries: return "#4ECDC4"
        case .transportation: return "#45B7D1"
        case .shopping: return "#96CEB4"
        case .entertainment: return "#FFEAA7"
        case .travel: return "#DDA0DD"
        case .health: return "#FF7675"
        case .utilities: return "#74B9FF"
        case .gas: return "#00B894"
        case .education: return "#E17055"
        case .income: return "#55EFC4"
        case .other: return "#B2BEC3"
        }
    }

    public var semanticTerms: [String] {
        switch self {
        case .foodAndDrink:
            return ["food", "restaurant", "dinner", "lunch", "breakfast", "cafe", "coffee", "eat", "drink", "meal"]
        case .groceries:
            return ["grocery", "supermarket", "food", "market", "store", "shopping", "produce"]
        case .transportation:
            return ["transport", "taxi", "ride", "bus", "train", "metro", "subway", "commute"]
        case .shopping:
            return ["shop", "buy", "purchase", "store", "mall", "retail", "clothes", "fashion"]
        case .entertainment:
            return ["fun", "movie", "game", "play", "show", "concert", "party", "event"]
        case .travel:
            return ["travel", "trip", "vacation", "hotel", "flight", "journey", "tour"]
        case .health:
            return ["health", "doctor", "medical", "gym", "fitness", "pharmacy", "wellness"]
        case .utilities:
            return ["utility", "bill", "electric", "water", "gas", "internet", "phone"]
        case .gas:
            return ["gas", "fuel", "petrol", "station", "pump", "oil"]
        case .education:
            return ["education", "school", "course", "learn", "study", "book", "class"]
        case .income:
            return ["income", "salary", "pay", "wage", "earn", "deposit"]
        case .other:
            return ["other", "misc", "general", "various"]
        }
    }
}

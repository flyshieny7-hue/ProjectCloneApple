import Foundation
import CoreLocation

/// Модель транзакции для Apple Wallet Clone
@available(iOS 26.0, *)
public struct Transaction: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var amount: Double
    public var merchantName: String
    public var date: Date
    public var category: TransactionCategory
    public var description: String?
    public var location: Location?
    public var cardLastFour: String?
    public var status: TransactionStatus
    public var isPending: Bool
    public var currency: String

    // AI-поля
    public var categorizationConfidence: Double?
    public var categorizationSource: CategorizationSource?
    public var riskAssessment: RiskAssessment?
    public var aiTags: [String]?

    public init(
        id: UUID = UUID(),
        amount: Double,
        merchantName: String,
        date: Date,
        category: TransactionCategory = .other,
        description: String? = nil,
        location: Location? = nil,
        cardLastFour: String? = nil,
        status: TransactionStatus = .completed,
        isPending: Bool = false,
        currency: String = "USD",
        categorizationConfidence: Double? = nil,
        categorizationSource: CategorizationSource? = nil,
        riskAssessment: RiskAssessment? = nil,
        aiTags: [String]? = nil
    ) {
        self.id = id
        self.amount = amount
        self.merchantName = merchantName
        self.date = date
        self.category = category
        self.description = description
        self.location = location
        self.cardLastFour = cardLastFour
        self.status = status
        self.isPending = isPending
        self.currency = currency
        self.categorizationConfidence = categorizationConfidence
        self.categorizationSource = categorizationSource
        self.riskAssessment = riskAssessment
        self.aiTags = aiTags
    }

    public static func == (lhs: Transaction, rhs: Transaction) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@available(iOS 26.0, *)
public enum TransactionStatus: String, Codable {
    case pending = "pending"
    case completed = "completed"
    case declined = "declined"
    case reversed = "reversed"
    case refunded = "refunded"
}

@available(iOS 26.0, *)
public struct Location: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let city: String?
    public let country: String?

    public init(latitude: Double, longitude: Double, city: String? = nil, country: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
        self.country = country
    }

    public func distance(from other: Location) -> Double {
        let loc1 = CLLocation(latitude: latitude, longitude: longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}

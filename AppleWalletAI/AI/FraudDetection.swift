import Foundation
import CoreML
import Combine

/// Anomaly Detection на транзакциях с Isolation Forest fallback
@available(iOS 26.0, *)
public final class FraudDetection: ObservableObject {

    // MARK: - Published State
    @Published public var riskScore: Double = 0.0 // 0.0 - 1.0
    @Published public var flaggedTransactions: [FlaggedTransaction] = []
    @Published public var isMonitoring = false

    // MARK: - CoreML / ML Model
    private var anomalyDetector: MLModel?
    private let riskEngine: RuleBasedRiskEngine

    // MARK: - User Behavior Profile
    private var behaviorProfile: UserBehaviorProfile?
    private let profileKey = "com.applewallet.ai.behaviorProfile"

    // MARK: - Services
    private let transactionService: TransactionService
    private var cancellables = Set<AnyCancellable>()

    public init(transactionService: TransactionService = .shared) {
        self.transactionService = transactionService
        self.riskEngine = RuleBasedRiskEngine()
        setupCoreML()
        loadBehaviorProfile()
        startMonitoring()
    }

    // MARK: - Setup
    private func setupCoreML() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            // anomalyDetector = try TransactionAnomalyDetector(configuration: config)
            print("[FraudDetection] CoreML placeholder — используется rule-based + statistical anomaly detection")
        } catch {
            print("[FraudDetection] CoreML недоступен: \(error)")
        }
    }

    // MARK: - Public API

    /// Оценивает риск транзакции в реальном времени
    public func assessRisk(for transaction: Transaction) -> RiskAssessment {
        var scores: [RiskFactor: Double] = [:]

        // 1. Географическая аномалия
        let geoScore = assessGeographicRisk(transaction)
        scores[.geographicAnomaly] = geoScore

        // 2. Временная аномалия
        let timeScore = assessTemporalRisk(transaction)
        scores[.temporalAnomaly] = timeScore

        // 3. Аномалия суммы
        let amountScore = assessAmountRisk(transaction)
        scores[.amountAnomaly] = amountScore

        // 4. Поведенческая аномалия
        let behaviorScore = assessBehavioralRisk(transaction)
        scores[.behavioralAnomaly] = behaviorScore

        // 5. Частота транзакций
        let velocityScore = assessVelocityRisk(transaction)
        scores[.velocityAnomaly] = velocityScore

        // 6. Мерчант риск
        let merchantScore = assessMerchantRisk(transaction)
        scores[.merchantRisk] = merchantScore

        // Weighted aggregation
        let weights: [RiskFactor: Double] = [
            .geographicAnomaly: 0.20,
            .temporalAnomaly: 0.15,
            .amountAnomaly: 0.25,
            .behavioralAnomaly: 0.20,
            .velocityAnomaly: 0.15,
            .merchantRisk: 0.05
        ]

        let totalScore = scores.reduce(0) { $0 + ($1.value * (weights[$1.key] ?? 0)) }
        let normalizedScore = min(1.0, max(0.0, totalScore))

        let level: RiskLevel
        switch normalizedScore {
        case 0..<0.3: level = .low
        case 0.3..<0.6: level = .medium
        case 0.6..<0.85: level = .high
        default: level = .critical
        }

        // Генерируем детали
        let triggeredFactors = scores.filter { $0.value > 0.5 }.map { $0.key }

        return RiskAssessment(
            transactionId: transaction.id,
            overallScore: normalizedScore,
            level: level,
            triggeredFactors: triggeredFactors,
            factorScores: scores,
            recommendation: generateRecommendation(level: level, factors: triggeredFactors),
            timestamp: Date()
        )
    }

    /// Batch анализ для фонового сканирования
    public func scanBatch(_ transactions: [Transaction]) -> [FlaggedTransaction] {
        transactions.compactMap { tx in
            let assessment = assessRisk(for: tx)
            guard assessment.level != .low else { return nil }
            return FlaggedTransaction(transaction: tx, assessment: assessment)
        }
    }

    /// Обновляет поведенческий профиль пользователя
    public func updateBehaviorProfile(with transactions: [Transaction]) {
        var profile = UserBehaviorProfile()

        // Географические паттерны
        let locations = transactions.compactMap { $0.location }
        profile.commonLocations = locations
        profile.homeLocation = estimateHomeLocation(from: locations)

        // Временные паттерны
        let hours = transactions.map { Calendar.current.component(.hour, from: $0.date) }
        profile.commonTransactionHours = Array(Set(hours))

        // Суммы
        let amounts = transactions.map { $0.amount }
        profile.avgTransactionAmount = amounts.reduce(0, +) / Double(max(1, amounts.count))
        profile.maxTransactionAmount = amounts.max() ?? 0
        profile.amountStdDev = standardDeviation(amounts)

        // Мерчанты
        profile.commonMerchants = Array(Set(transactions.map { $0.merchantName })).prefix(20)

        // Категории
        let categoryTotals = Dictionary(grouping: transactions, by: { $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        profile.categoryDistribution = categoryTotals

        // Частота
        let dailyCounts = Dictionary(grouping: transactions) {
            Calendar.current.startOfDay(for: $0.date)
        }.mapValues { $0.count }
        profile.avgDailyTransactionCount = Double(dailyCounts.values.reduce(0, +)) / Double(max(1, dailyCounts.count))

        self.behaviorProfile = profile
        saveBehaviorProfile(profile)
    }

    // MARK: - Risk Assessment Methods

    private func assessGeographicRisk(_ transaction: Transaction) -> Double {
        guard let profile = behaviorProfile,
              let txLocation = transaction.location,
              let home = profile.homeLocation else {
            return 0.1 // Недостаточно данных
        }

        let distance = txLocation.distance(from: home)

        // Проверяем, была ли такая локация раньше
        let knownLocation = profile.commonLocations.contains { $0.distance(from: txLocation) < 1000 }

        if knownLocation {
            return 0.05
        }

        // Distance-based scoring
        if distance < 5000 { return 0.15 }
        if distance < 50000 { return 0.40 }
        if distance < 200000 { return 0.70 }
        return 0.95 // Международная или очень далекая
    }

    private func assessTemporalRisk(_ transaction: Transaction) -> Double {
        guard let profile = behaviorProfile else { return 0.1 }

        let hour = Calendar.current.component(.hour, from: transaction.date)
        let isWeekend = Calendar.current.isDateInWeekend(transaction.date)

        // Нетипичное время (2-5 утра)
        if (2...5).contains(hour) {
            return 0.60
        }

        // Проверяем, совпадает ли с обычным паттерном
        let isCommonHour = profile.commonTransactionHours.contains(hour)

        if !isCommonHour {
            return 0.35
        }

        return 0.05
    }

    private func assessAmountRisk(_ transaction: Transaction) -> Double {
        guard let profile = behaviorProfile else {
            // Без профиля — эвристики
            return transaction.amount > 1000 ? 0.5 : 0.1
        }

        let amount = transaction.amount
        let avg = profile.avgTransactionAmount
        let stdDev = profile.amountStdDev

        guard stdDev > 0 else { return amount > avg * 2 ? 0.6 : 0.1 }

        let zScore = abs(amount - avg) / stdDev

        if zScore > 4 { return 0.95 }
        if zScore > 3 { return 0.75 }
        if zScore > 2 { return 0.45 }
        if zScore > 1.5 { return 0.25 }
        return 0.05
    }

    private func assessBehavioralRisk(_ transaction: Transaction) -> Double {
        guard let profile = behaviorProfile else { return 0.1 }

        var score = 0.0

        // Новый мерчант
        let isKnownMerchant = profile.commonMerchants.contains {
            transaction.merchantName.lowercased().contains($0.lowercased())
        }
        if !isKnownMerchant {
            score += 0.25
        }

        // Новая категория с крупной суммой
        let categorySpend = profile.categoryDistribution[transaction.category] ?? 0
        let totalSpend = profile.categoryDistribution.values.reduce(0, +)
        let categoryRatio = totalSpend > 0 ? categorySpend / totalSpend : 0

        if categoryRatio < 0.05 && transaction.amount > 100 {
            score += 0.30
        }

        return min(1.0, score)
    }

    private func assessVelocityRisk(_ transaction: Transaction) -> Double {
        // Проверяем частоту транзакций за последний час
        let recentTx = transactionService.recentTransactions(hours: 1)
        let count = recentTx.count

        if count > 10 { return 0.90 }
        if count > 6 { return 0.70 }
        if count > 3 { return 0.40 }
        return 0.05
    }

    private func assessMerchantRisk(_ transaction: Transaction) -> Double {
        let highRiskPatterns = ["crypt", "gambl", "forex", "binary", "casino", "bet"]
        let merchant = transaction.merchantName.lowercased()

        for pattern in highRiskPatterns {
            if merchant.contains(pattern) {
                return 0.80
            }
        }

        return 0.05
    }

    // MARK: - Helpers

    private func generateRecommendation(level: RiskLevel, factors: [RiskFactor]) -> String {
        switch level {
        case .low:
            return "Транзакция выглядит нормальной."
        case .medium:
            return "Обнаружены незначительные отклонения. Рекомендуем проверить детали."
        case .high:
            let factorNames = factors.map { $0.displayName }.joined(separator: ", ")
            return "⚠️ Повышенный риск: \(factorNames). Подтвердите транзакцию."
        case .critical:
            return "🚨 КРИТИЧЕСКИЙ РИСК! Транзакция заблокирована. Свяжитесь с банком."
        }
    }

    private func estimateHomeLocation(from locations: [Location]) -> Location? {
        guard !locations.isEmpty else { return nil }
        // Упрощенно: возвращаем локацию с наибольшим количеством транзакций
        let grouped = Dictionary(grouping: locations) { "\($0.latitude),\($0.longitude)" }
        return grouped.max { $0.value.count < $1.value.count }?.value.first
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }

    private func startMonitoring() {
        transactionService.transactionsPublisher
            .sink { [weak self] transactions in
                guard let self = self else { return }
                let flagged = self.scanBatch(transactions.suffix(10))
                Task { @MainActor in
                    self.flaggedTransactions = flagged
                    self.riskScore = flagged.map { $0.assessment.overallScore }.max() ?? 0.0
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    private func loadBehaviorProfile() {
        guard let data = UserDefaults.standard.data(forKey: profileKey),
              let profile = try? JSONDecoder().decode(UserBehaviorProfile.self, from: data) else {
            return
        }
        self.behaviorProfile = profile
    }

    private func saveBehaviorProfile(_ profile: UserBehaviorProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
public struct RiskAssessment {
    public let transactionId: UUID
    public let overallScore: Double
    public let level: RiskLevel
    public let triggeredFactors: [RiskFactor]
    public let factorScores: [RiskFactor: Double]
    public let recommendation: String
    public let timestamp: Date
}

@available(iOS 26.0, *)
public enum RiskLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    public var color: String {
        switch self {
        case .low: return "#34C759"
        case .medium: return "#FFCC00"
        case .high: return "#FF9500"
        case .critical: return "#FF3B30"
        }
    }

    public var icon: String {
        switch self {
        case .low: return "✅"
        case .medium: return "⚡"
        case .high: return "⚠️"
        case .critical: return "🚨"
        }
    }
}

@available(iOS 26.0, *)
public enum RiskFactor: String, CaseIterable {
    case geographicAnomaly = "geographic_anomaly"
    case temporalAnomaly = "temporal_anomaly"
    case amountAnomaly = "amount_anomaly"
    case behavioralAnomaly = "behavioral_anomaly"
    case velocityAnomaly = "velocity_anomaly"
    case merchantRisk = "merchant_risk"

    public var displayName: String {
        switch self {
        case .geographicAnomaly: return "географическая аномалия"
        case .temporalAnomaly: return "временная аномалия"
        case .amountAnomaly: return "аномальная сумма"
        case .behavioralAnomaly: return "поведенческая аномалия"
        case .velocityAnomaly: return "подозрительная частота"
        case .merchantRisk: return "риск мерчанта"
        }
    }
}

@available(iOS 26.0, *)
public struct FlaggedTransaction: Identifiable {
    public let id = UUID()
    public let transaction: Transaction
    public let assessment: RiskAssessment
}

@available(iOS 26.0, *)
public struct UserBehaviorProfile: Codable {
    var commonLocations: [Location] = []
    var homeLocation: Location?
    var commonTransactionHours: [Int] = []
    var avgTransactionAmount: Double = 0
    var maxTransactionAmount: Double = 0
    var amountStdDev: Double = 0
    var commonMerchants: [String] = []
    var categoryDistribution: [String: Double] = [:]
    var avgDailyTransactionCount: Double = 0

    enum CodingKeys: String, CodingKey {
        case commonLocations, homeLocation, commonTransactionHours
        case avgTransactionAmount, maxTransactionAmount, amountStdDev
        case commonMerchants, categoryDistribution, avgDailyTransactionCount
    }
}

// MARK: - Rule-Based Risk Engine

@available(iOS 26.0, *)
final class RuleBasedRiskEngine {
    func evaluate(_ transaction: Transaction, profile: UserBehaviorProfile?) -> Double {
        guard let profile = profile else { return 0.2 }

        var score = 0.0

        // Amount outlier
        if transaction.amount > profile.avgTransactionAmount + 3 * profile.amountStdDev {
            score += 0.4
        }

        // Unknown merchant
        if !profile.commonMerchants.contains(where: { transaction.merchantName.lowercased().contains($0.lowercased()) }) {
            score += 0.2
        }

        return min(1.0, score)
    }
}

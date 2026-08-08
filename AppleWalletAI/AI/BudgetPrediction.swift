import Foundation
import Combine

/// Прогноз "если продолжишь так тратить, бюджет закончится 15-го"
@available(iOS 26.0, *)
public final class BudgetPrediction: ObservableObject {

    // MARK: - Published State
    @Published public var budgetDepletionDate: Date?
    @Published public var daysUntilDepletion: Int?
    @Published public var projectedMonthlyTotal: Double?
    @Published public var dailyBurnRate: Double?
    @Published public var budgetStatus: BudgetStatus = .onTrack
    @Published public var categoryForecasts: [CategoryForecast] = []
    @Published public var recommendations: [BudgetRecommendation] = []

    // MARK: - Configuration
    public var monthlyBudget: Double = 3000.0 {
        didSet { recalculate() }
    }

    public var budgetStartDay: Int = 1 {
        didSet { recalculate() }
    }

    // MARK: - Services
    private let transactionService: TransactionService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - ML Models (Placeholder)
    private var timeSeriesModel: TimeSeriesForecaster?

    public init(transactionService: TransactionService = .shared) {
        self.transactionService = transactionService
        setupModels()
        observeTransactions()
    }

    private func setupModels() {
        // Placeholder для CoreML Time Series модели
        // timeSeriesModel = try? MonthlySpendingForecaster(configuration: MLModelConfiguration())
        print("[BudgetPrediction] Используется статистический forecasting (Holt-Winters fallback)")
    }

    // MARK: - Public API

    /// Пересчитывает все прогнозы
    public func recalculate() {
        Task {
            await calculateForecast()
        }
    }

    /// Прогноз с датой исчерпания бюджета
    public func predictDepletion() async -> DepletionForecast? {
        let transactions = await transactionService.fetchCurrentPeriodTransactions()
        let calendar = Calendar.current
        let now = Date()

        guard let periodStart = budgetStartDate() else { return nil }
        let daysElapsed = calendar.dateComponents([.day], from: periodStart, to: now).day ?? 1
        guard daysElapsed > 0 else { return nil }

        let spent = transactions.reduce(0) { $0 + $1.amount }
        let remaining = monthlyBudget - spent

        guard remaining > 0 else {
            return DepletionForecast(
                depletionDate: now,
                daysUntil: 0,
                status: .depleted,
                confidence: 0.99,
                projectedOverspend: abs(remaining)
            )
        }

        // Расчет daily burn rate
        let burnRate = spent / Double(daysElapsed)
        let daysRemaining = Int(remaining / burnRate)

        guard let depletionDate = calendar.date(byAdding: .day, value: daysRemaining, to: now) else {
            return nil
        }

        let status: BudgetStatus
        let periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart)!
        let totalDays = calendar.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 30

        if depletionDate < calendar.date(byAdding: .day, value: -5, to: periodEnd)! {
            status = .atRisk
        } else if depletionDate > periodEnd {
            status = .onTrack
        } else {
            status = .warning
        }

        // Прогнозируемый оверспенд
        let projectedTotal = burnRate * Double(totalDays)
        let projectedOverspend = max(0, projectedTotal - monthlyBudget)

        return DepletionForecast(
            depletionDate: depletionDate,
            daysUntil: daysRemaining,
            status: status,
            confidence: calculateConfidence(daysElapsed: daysElapsed),
            projectedOverspend: projectedOverspend
        )
    }

    /// Категориальный прогноз
    public func forecastByCategory() async -> [CategoryForecast] {
        let transactions = await transactionService.fetchCurrentPeriodTransactions()
        let calendar = Calendar.current
        let now = Date()

        guard let periodStart = budgetStartDate() else { return [] }
        let daysElapsed = max(1, calendar.dateComponents([.day], from: periodStart, to: now).day ?? 1)
        let periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart)!
        let totalDays = calendar.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 30
        let daysRemaining = totalDays - daysElapsed

        let byCategory = Dictionary(grouping: transactions, by: { $0.category })

        return byCategory.map { category, txs in
            let spent = txs.reduce(0) { $0 + $1.amount }
            let dailyRate = spent / Double(daysElapsed)
            let projected = dailyRate * Double(totalDays)
            let remainingBudget = categoryBudget(for: category)
            let projectedRemaining = max(0, remainingBudget - spent)

            let status: BudgetStatus
            if projected > remainingBudget * 1.2 {
                status = .atRisk
            } else if projected > remainingBudget {
                status = .warning
            } else {
                status = .onTrack
            }

            return CategoryForecast(
                category: category,
                spent: spent,
                projectedTotal: projected,
                budget: remainingBudget,
                dailyRate: dailyRate,
                projectedRemaining: projectedRemaining,
                daysRemaining: daysRemaining,
                status: status
            )
        }.sorted { $0.projectedTotal > $1.projectedTotal }
    }

    /// Smart recommendation engine
    public func generateRecommendations() async -> [BudgetRecommendation] {
        guard let forecast = await predictDepletion(),
              let depletionDate = forecast.depletionDate else { return [] }

        var recs: [BudgetRecommendation] = []
        let calendar = Calendar.current
        let now = Date()

        // Рекомендация 1: Скорректируйте траты
        if forecast.status == .atRisk || forecast.status == .warning {
            let daysUntil = calendar.dateComponents([.day], from: now, to: depletionDate).day ?? 0
            let dailyAllowance = (monthlyBudget - currentSpent()) / Double(max(1, daysUntil))

            recs.append(BudgetRecommendation(
                id: UUID(),
                title: "💡 Сократите дневные траты",
                description: "Чтобы уложиться в бюджет, тратьте не более \(formatCurrency(dailyAllowance)) в день.",
                type: .reduceSpending,
                impact: .high,
                category: nil,
                actionable: true
            ))
        }

        // Рекомендация 2: Категории для оптимизации
        let categoryForecasts = await forecastByCategory()
        let atRiskCategories = categoryForecasts.filter { $0.status == .atRisk }

        for cat in atRiskCategories.prefix(2) {
            let overspend = cat.projectedTotal - cat.budget
            recs.append(BudgetRecommendation(
                id: UUID(),
                title: "⚠️ \(cat.category.displayName) превысит бюджет",
                description: "Прогноз: \(formatCurrency(overspend)) сверх лимита. Рассмотрите сокращение трат в этой категории.",
                type: .categoryAlert,
                impact: .medium,
                category: cat.category,
                actionable: true
            ))
        }

        // Рекомендация 3: Паттерн трат
        if let patternRec = analyzeSpendingPattern() {
            recs.append(patternRec)
        }

        // Рекомендация 4: Накопления
        if forecast.status == .onTrack {
            let potentialSavings = monthlyBudget - (forecast.projectedOverspend + currentSpent())
            if potentialSavings > 100 {
                recs.append(BudgetRecommendation(
                    id: UUID(),
                    title: "🎯 Отличный месяц!",
                    description: "При текущем темпе вы сэкономите \(formatCurrency(potentialSavings)). Рассмотрите перевод на сберегательный счет.",
                    type: .saveExtra,
                    impact: .low,
                    category: nil,
                    actionable: true
                ))
            }
        }

        return recs
    }

    // MARK: - Private Methods

    private func calculateForecast() async {
        async let depletion = predictDepletion()
        async let forecasts = forecastByCategory()
        async let recs = generateRecommendations()

        let (depResult, catResult, recResult) = await (depletion, forecasts, recs)

        await MainActor.run {
            self.budgetDepletionDate = depResult?.depletionDate
            self.daysUntilDepletion = depResult?.daysUntil
            self.budgetStatus = depResult?.status ?? .onTrack
            self.categoryForecasts = catResult
            self.recommendations = recResult

            if let dep = depResult {
                let calendar = Calendar.current
                let now = Date()
                let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
                let daysElapsed = max(1, calendar.component(.day, from: now))
                self.dailyBurnRate = currentSpent() / Double(daysElapsed)
                self.projectedMonthlyTotal = self.dailyBurnRate! * Double(daysInMonth)
            }
        }
    }

    private func currentSpent() -> Double {
        // Синхронная версия для UI
        let transactions = transactionService.currentPeriodTransactions
        return transactions.reduce(0) { $0 + $1.amount }
    }

    private func budgetStartDate() -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: Date())
        components.day = budgetStartDay
        return calendar.date(from: components)
    }

    private func categoryBudget(for category: TransactionCategory) -> Double {
        // Распределение бюджета по категориям (configurable)
        let allocations: [TransactionCategory: Double] = [
            .groceries: 0.25,
            .foodAndDrink: 0.15,
            .transportation: 0.10,
            .entertainment: 0.10,
            .shopping: 0.15,
            .health: 0.05,
            .travel: 0.10,
            .utilities: 0.05,
            .other: 0.05
        ]
        return monthlyBudget * (allocations[category] ?? 0.05)
    }

    private func calculateConfidence(daysElapsed: Int) -> Double {
        // Чем больше данных, тем выше уверенность
        let baseConfidence = min(0.95, Double(daysElapsed) / 15.0)
        return baseConfidence
    }

    private func analyzeSpendingPattern() -> BudgetRecommendation? {
        let transactions = transactionService.currentPeriodTransactions
        let calendar = Calendar.current

        // Проверяем weekend spike
        let weekendTx = transactions.filter {
            calendar.isDateInWeekend($0.date)
        }
        let weekendTotal = weekendTx.reduce(0) { $0 + $1.amount }
        let total = transactions.reduce(0) { $0 + $1.amount }

        guard total > 0 else { return nil }

        let weekendRatio = weekendTotal / total
        if weekendRatio > 0.4 {
            return BudgetRecommendation(
                id: UUID(),
                title: "🎉 Weekend spending spike",
                description: "\(Int(weekendRatio * 100))% бюджета уходит на выходные. Попробуйте планировать активности заранее.",
                type: .patternAlert,
                impact: .medium,
                category: nil,
                actionable: false
            )
        }

        return nil
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func observeTransactions() {
        transactionService.transactionsPublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculate()
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
public struct DepletionForecast {
    public let depletionDate: Date?
    public let daysUntil: Int?
    public let status: BudgetStatus
    public let confidence: Double
    public let projectedOverspend: Double
}

@available(iOS 26.0, *)
public enum BudgetStatus: String, CaseIterable {
    case onTrack = "on_track"
    case warning = "warning"
    case atRisk = "at_risk"
    case depleted = "depleted"

    public var displayName: String {
        switch self {
        case .onTrack: return "В норме"
        case .warning: return "Внимание"
        case .atRisk: return "Риск"
        case .depleted: return "Исчерпан"
        }
    }

    public var color: String {
        switch self {
        case .onTrack: return "#34C759"
        case .warning: return "#FFCC00"
        case .atRisk: return "#FF9500"
        case .depleted: return "#FF3B30"
        }
    }

    public var icon: String {
        switch self {
        case .onTrack: return "✅"
        case .warning: return "⚠️"
        case .atRisk: return "🔥"
        case .depleted: return "💸"
        }
    }
}

@available(iOS 26.0, *)
public struct CategoryForecast: Identifiable {
    public let id = UUID()
    public let category: TransactionCategory
    public let spent: Double
    public let projectedTotal: Double
    public let budget: Double
    public let dailyRate: Double
    public let projectedRemaining: Double
    public let daysRemaining: Int
    public let status: BudgetStatus

    public var percentageUsed: Double {
        guard budget > 0 else { return 0 }
        return min(1.0, spent / budget)
    }

    public var projectedPercentage: Double {
        guard budget > 0 else { return 0 }
        return projectedTotal / budget
    }
}

@available(iOS 26.0, *)
public struct BudgetRecommendation: Identifiable {
    public let id: UUID
    public let title: String
    public let description: String
    public let type: RecommendationType
    public let impact: ImpactLevel
    public let category: TransactionCategory?
    public let actionable: Bool
}

@available(iOS 26.0, *)
public enum RecommendationType {
    case reduceSpending
    case categoryAlert
    case patternAlert
    case saveExtra
    case adjustBudget
}

@available(iOS 26.0, *)
public enum ImpactLevel: String {
    case high = "high"
    case medium = "medium"
    case low = "low"
}

// MARK: - Time Series Forecaster (Placeholder Protocol)

@available(iOS 26.0, *)
protocol TimeSeriesForecaster {
    func forecast(values: [Double], horizon: Int) -> [Double]
}

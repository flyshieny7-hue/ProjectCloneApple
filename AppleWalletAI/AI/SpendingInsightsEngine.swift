import Foundation
import CoreML
import NaturalLanguage
import Combine

/// ML анализ трат с предиктивными рекомендациями
@available(iOS 26.0, *)
public final class SpendingInsightsEngine: ObservableObject {

    // MARK: - Published State
    @Published public var insights: [SpendingInsight] = []
    @Published public var isAnalyzing = false
    @Published public var predictionConfidence: Double = 0.0

    // MARK: - CoreML (Placeholder с fallback)
    private var spendingPredictor: MLModel?
    private var sentimentAnalyzer: NLTagger?

    // MARK: - Services
    private let transactionService: TransactionService
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Analytics Cache
    private var analyticsCache: SpendingAnalytics?
    private let cacheTTL: TimeInterval = 300 // 5 минут

    public init(transactionService: TransactionService = .shared,
                userDefaults: UserDefaults = .standard) {
        self.transactionService = transactionService
        self.userDefaults = userDefaults
        setupCoreML()
        observeTransactions()
    }

    // MARK: - CoreML Setup
    private func setupCoreML() {
        do {
            // Попытка загрузить CoreML модель
            let config = MLModelConfiguration()
            config.computeUnits = .all
            // spendingPredictor = try SpendingPredictor(configuration: config)
            // Placeholder: fallback на rule-based
            print("[SpendingInsightsEngine] CoreML model not bundled, using rule-based fallback")
        } catch {
            print("[SpendingInsightsEngine] CoreML init failed: \(error). Using rule-based fallback.")
        }

        sentimentAnalyzer = NLTagger(tagSchemes: [.sentimentScore])
    }

    // MARK: - Public API

    /// Генерирует AI-инсайты на основе транзакций
    public func generateInsights(for transactions: [Transaction]) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        var newInsights: [SpendingInsight] = []

        // 1. Анализ трендов
        if let trendInsight = await analyzeSpendingTrends(transactions) {
            newInsights.append(trendInsight)
        }

        // 2. Аномалии
        if let anomalyInsight = detectAnomalies(transactions) {
            newInsights.append(anomalyInsight)
        }

        // 3. Предиктивные рекомендации
        let predictions = await generatePredictions(transactions)
        newInsights.append(contentsOf: predictions)

        // 4. Сравнение с прошлым месяцем
        if let comparison = compareWithPreviousMonth(transactions) {
            newInsights.append(comparison)
        }

        // 5. Категориальный анализ
        let categoryInsights = analyzeCategorySpending(transactions)
        newInsights.append(contentsOf: categoryInsights)

        // Сортируем по приоритету
        newInsights.sort { $0.priority > $1.priority }

        await MainActor.run {
            self.insights = newInsights
            self.predictionConfidence = calculateOverallConfidence(for: newInsights)
        }
    }

    /// Прогноз расходов на следующий месяц
    public func predictNextMonthSpending() async -> Double? {
        let transactions = await transactionService.fetchLast90Days()

        // Fallback: экспоненциальное сглаживание
        let dailyTotals = groupByDay(transactions)
        guard dailyTotals.count >= 7 else { return nil }

        let alpha = 0.3
        var smoothed = dailyTotals.first?.value ?? 0
        for i in 1..<dailyTotals.count {
            smoothed = alpha * dailyTotals[i].value + (1 - alpha) * smoothed
        }

        return smoothed * 30
    }

    // MARK: - Private Analysis Methods

    private func analyzeSpendingTrends(_ transactions: [Transaction]) async -> SpendingInsight? {
        let last30Days = transactions.filter { $0.date > Date().addingTimeInterval(-30*24*3600) }
        let previous30Days = transactions.filter {
            $0.date > Date().addingTimeInterval(-60*24*3600) &&
            $0.date <= Date().addingTimeInterval(-30*24*3600)
        }

        let currentTotal = last30Days.reduce(0) { $0 + $1.amount }
        let previousTotal = previous30Days.reduce(0) { $0 + $1.amount }

        guard previousTotal > 0 else { return nil }

        let change = (currentTotal - previousTotal) / previousTotal
        let absChange = abs(change)

        if absChange > 0.3 {
            let direction = change > 0 ? "увеличились" : "уменьшились"
            let emoji = change > 0 ? "📈" : "📉"
            let severity: InsightSeverity = change > 0.5 ? .critical : .warning

            return SpendingInsight(
                id: UUID(),
                title: "\(emoji) Траты \(direction) на \(Int(absChange * 100))%",
                description: "Ваши расходы за последние 30 дней \(direction) по сравнению с предыдущим периодом. Всего потрачено \(formatCurrency(currentTotal)) vs \(formatCurrency(previousTotal))",
                category: .trend,
                severity: severity,
                priority: 90,
                action: .viewTransactions,
                createdAt: Date()
            )
        }

        return nil
    }

    private func detectAnomalies(_ transactions: [Transaction]) -> SpendingInsight? {
        let amounts = transactions.map { $0.amount }
        guard amounts.count > 10 else { return nil }

        let mean = amounts.reduce(0, +) / Double(amounts.count)
        let variance = amounts.map { pow($0 - mean, 2) }.reduce(0, +) / Double(amounts.count)
        let stdDev = sqrt(variance)

        let threshold = mean + 3 * stdDev
        let anomalies = transactions.filter { $0.amount > threshold }

        guard let latestAnomaly = anomalies.sorted(by: { $0.date > $1.date }).first else { return nil }

        return SpendingInsight(
            id: UUID(),
            title: "⚠️ Необычно крупная трата",
            description: "Обнаружена аномалия: \(formatCurrency(latestAnomaly.amount)) в \(latestAnomaly.merchantName). Это в \(Int(latestAnomaly.amount / mean)) раз больше вашего среднего чека.",
            category: .anomaly,
            severity: .warning,
            priority: 95,
            action: .reviewTransaction(latestAnomaly.id),
            createdAt: Date()
        )
    }

    private func generatePredictions(_ transactions: [Transaction]) async -> [SpendingInsight] {
        var predictions: [SpendingInsight] = []

        // Предсказание по категориям
        let categories = Dictionary(grouping: transactions, by: { $0.category })

        for (category, txs) in categories {
            let monthlyAverage = txs.reduce(0) { $0 + $1.amount } / max(1, Double(txs.count / 30))
            let trend = calculateTrend(txs)

            if trend > 1.2 {
                predictions.append(SpendingInsight(
                    id: UUID(),
                    title: "🔮 Прогноз: рост трат на \(category.displayName)",
                    description: "Если текущий тренд продолжится, в следующем месяце вы потратите \(formatCurrency(monthlyAverage * trend * 30)) на \(category.displayName). Рекомендуем установить лимит.",
                    category: .prediction,
                    severity: .info,
                    priority: 70,
                    action: .setBudget(category),
                    createdAt: Date()
                ))
            }
        }

        return predictions
    }

    private func compareWithPreviousMonth(_ transactions: [Transaction]) -> SpendingInsight? {
        let calendar = Calendar.current
        let now = Date()

        guard let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
              let lastMonthEnd = calendar.date(byAdding: .day, value: -1, to: thisMonthStart) else {
            return nil
        }

        let thisMonth = transactions.filter { $0.date >= thisMonthStart }
        let lastMonth = transactions.filter { $0.date >= lastMonthStart && $0.date <= lastMonthEnd }

        let thisTotal = thisMonth.reduce(0) { $0 + $1.amount }
        let lastTotal = lastMonth.reduce(0) { $0 + $1.amount }

        guard lastTotal > 0 else { return nil }

        let diff = thisTotal - lastTotal
        let daysPassed = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let projectedThisMonth = thisTotal * Double(daysInMonth) / Double(daysPassed)

        if projectedThisMonth > lastTotal * 1.2 {
            return SpendingInsight(
                id: UUID(),
                title: "📊 Проекция месяца",
                description: "При текущем темпе трат к концу месяца вы потратите \(formatCurrency(projectedThisMonth)), что на \(formatCurrency(projectedThisMonth - lastTotal)) больше прошлого месяца.",
                category: .projection,
                severity: .warning,
                priority: 85,
                action: .viewBudget,
                createdAt: Date()
            )
        }

        return nil
    }

    private func analyzeCategorySpending(_ transactions: [Transaction]) -> [SpendingInsight] {
        var insights: [SpendingInsight] = []
        let calendar = Calendar.current

        // Топ категории
        let categoryTotals = Dictionary(grouping: transactions, by: { $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }

        let total = categoryTotals.values.reduce(0, +)
        guard total > 0 else { return [] }

        // Найти категорию с наибольшим ростом
        if let topCategory = categoryTotals.max(by: { $0.value < $1.value }) {
            let percentage = topCategory.value / total
            if percentage > 0.3 {
                insights.append(SpendingInsight(
                    id: UUID(),
                    title: "💡 \(topCategory.key.displayName) — \(Int(percentage * 100))% бюджета",
                    description: "Это ваша самая большая статья расходов. Рассмотрите возможность оптимизации или установки лимита.",
                    category: .categoryAnalysis,
                    severity: .info,
                    priority: 60,
                    action: .viewCategory(topCategory.key),
                    createdAt: Date()
                ))
            }
        }

        // Weekend vs Weekday pattern
        let weekendSpending = transactions.filter {
            let weekday = calendar.component(.weekday, from: $0.date)
            return weekday == 1 || weekday == 7
        }.reduce(0) { $0 + $1.amount }

        let weekdaySpending = total - weekendSpending
        if weekendSpending > weekdaySpending / 5 * 2 {
            insights.append(SpendingInsight(
                id: UUID(),
                title: "🎉 Weekend spender",
                description: "Вы тратите \(formatCurrency(weekendSpending)) по выходным — это заметно больше, чем в среднем за будний день. Попробуйте планировать досуг заранее.",
                category: .pattern,
                severity: .info,
                priority: 50,
                action: .none,
                createdAt: Date()
            ))
        }

        return insights
    }

    // MARK: - Helpers

    private func calculateTrend(_ transactions: [Transaction]) -> Double {
        guard transactions.count > 1 else { return 1.0 }
        let sorted = transactions.sorted { $0.date < $1.date }
        let firstHalf = Array(sorted.prefix(sorted.count / 2))
        let secondHalf = Array(sorted.suffix(sorted.count / 2))

        let firstAvg = firstHalf.reduce(0) { $0 + $1.amount } / max(1, Double(firstHalf.count))
        let secondAvg = secondHalf.reduce(0) { $0 + $1.amount } / max(1, Double(secondHalf.count))

        guard firstAvg > 0 else { return 1.0 }
        return secondAvg / firstAvg
    }

    private func groupByDay(_ transactions: [Transaction]) -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.map { (date: $0.key, value: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.date < $1.date }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func calculateOverallConfidence(for insights: [SpendingInsight]) -> Double {
        guard !insights.isEmpty else { return 0 }
        // Упрощенная оценка уверенности
        let baseConfidence = min(0.95, Double(insights.count) * 0.15)
        return baseConfidence
    }

    private func observeTransactions() {
        transactionService.transactionsPublisher
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] transactions in
                guard let self = self else { return }
                Task {
                    await self.generateInsights(for: transactions)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
public struct SpendingInsight: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let description: String
    public let category: InsightCategory
    public let severity: InsightSeverity
    public let priority: Int // 0-100
    public let action: InsightAction
    public let createdAt: Date

    public static func == (lhs: SpendingInsight, rhs: SpendingInsight) -> Bool {
        lhs.id == rhs.id
    }
}

@available(iOS 26.0, *)
public enum InsightCategory: String, CaseIterable {
    case trend, anomaly, prediction, projection, categoryAnalysis, pattern, recommendation
}

@available(iOS 26.0, *)
public enum InsightSeverity: String, CaseIterable {
    case critical, warning, info, success

    public var color: String {
        switch self {
        case .critical: return "#FF3B30"
        case .warning: return "#FF9500"
        case .info: return "#007AFF"
        case .success: return "#34C759"
        }
    }
}

@available(iOS 26.0, *)
public enum InsightAction {
    case none
    case viewTransactions
    case reviewTransaction(UUID)
    case setBudget(TransactionCategory)
    case viewBudget
    case viewCategory(TransactionCategory)
    case addLoyaltyCard(String)
}

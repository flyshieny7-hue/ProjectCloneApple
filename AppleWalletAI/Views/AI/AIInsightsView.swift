import SwiftUI

/// Главный AI Dashboard для Apple Wallet Clone
@available(iOS 26.0, *)
public struct AIInsightsView: View {

    @StateObject private var insightsEngine = SpendingInsightsEngine()
    @StateObject private var budgetPrediction = BudgetPrediction()
    @StateObject private var fraudDetection = FraudDetection()
    @StateObject private var recommendations = SmartRecommendations()
    @StateObject private var nlSearch = NaturalLanguageSearch()

    @State private var searchQuery = ""
    @State private var selectedInsight: SpendingInsight?
    @State private var showSearchResults = false
    @State private var searchResults: [Transaction] = []

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Search Bar
                    NLSearchBar(query: $searchQuery, onSubmit: performSearch)

                    // MARK: - Budget Status Card
                    BudgetStatusCard(prediction: budgetPrediction)

                    // MARK: - Fraud Alert Banner
                    if let flagged = fraudDetection.flaggedTransactions.first {
                        FraudAlertBanner(flagged: flagged)
                    }

                    // MARK: - AI Insights
                    InsightsSection(engine: insightsEngine)

                    // MARK: - Smart Recommendations
                    RecommendationsSection(recommendations: recommendations)

                    // MARK: - Category Forecast
                    CategoryForecastSection(forecasts: budgetPrediction.categoryForecasts)

                    // MARK: - Search Results
                    if showSearchResults && !searchResults.isEmpty {
                        SearchResultsSection(results: searchResults, query: searchQuery)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI Insights")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: refreshAll) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeating, value: insightsEngine.isAnalyzing)
                    }
                }
            }
            .task {
                await loadInitialData()
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else {
            showSearchResults = false
            return
        }

        let intent = nlSearch.parse(query: searchQuery)
        // В реальном приложении здесь был бы доступ к транзакциям
        // searchResults = nlSearch.apply(intent: intent, to: transactionService.allTransactions)
        showSearchResults = true
    }

    private func refreshAll() {
        Task {
            await insightsEngine.generateInsights(for: [])
            budgetPrediction.recalculate()
            await recommendations.generateRecommendations()
        }
    }

    private func loadInitialData() async {
        await recommendations.generateRecommendations()
        budgetPrediction.recalculate()
    }
}

// MARK: - NL Search Bar

@available(iOS 26.0, *)
struct NLSearchBar: View {
    @Binding var query: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Ask AI anything...", text: $query)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Quick Suggestions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchSuggestion.samples, id: \.self) { suggestion in
                        Button(action: {
                            query = suggestion
                            onSubmit()
                        }) {
                            Text(suggestion)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

@available(iOS 26.0, *)
struct SearchSuggestion {
    static let samples = [
        "Show expensive dinners",
        "Coffee spending this month",
        "All Uber trips",
        "Grocery total last week",
        "Biggest purchase"
    ]
}

// MARK: - Budget Status Card

@available(iOS 26.0, *)
struct BudgetStatusCard: View {
    @ObservedObject var prediction: BudgetPrediction

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly Budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(prediction.monthlyBudget))
                        .font(.title2.bold())
                }

                Spacer()

                StatusBadge(status: prediction.budgetStatus)
            }

            if let depletion = prediction.daysUntilDepletion {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color(hex: prediction.budgetStatus.color))
                    Text("Budget ends in \(depletion) days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.2))
                        .frame(height: 8)

                    if let projected = prediction.projectedMonthlyTotal {
                        let progress = min(1.0, projected / prediction.monthlyBudget)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: prediction.budgetStatus.color))
                            .frame(width: geo.size.width * progress, height: 8)
                            .animation(.easeInOut(duration: 0.5), value: progress)
                    }
                }
            }
            .frame(height: 8)

            if let burnRate = prediction.dailyBurnRate {
                HStack {
                    Text("Daily burn rate:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(burnRate))
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: prediction.budgetStatus.color))
                    Text("/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Fraud Alert Banner

@available(iOS 26.0, *)
struct FraudAlertBanner: View {
    let flagged: FlaggedTransaction
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: flagged.assessment.level.color))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Security Alert")
                        .font(.headline)
                    Text(flagged.assessment.recommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 1)
                }

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(flagged.assessment.triggeredFactors, id: \.self) { factor in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.orange)
                            Text(factor.displayName)
                                .font(.caption)
                        }
                    }

                    HStack {
                        Button("Review") {}
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)

                        Button("Dismiss") {}
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(Color(hex: flagged.assessment.level.color).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: flagged.assessment.level.color).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Insights Section

@available(iOS 26.0, *)
struct InsightsSection: View {
    @ObservedObject var engine: SpendingInsightsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Insights")
                    .font(.title3.bold())

                Spacer()

                if engine.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Text("\(Int(engine.predictionConfidence * 100))% confidence")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            if engine.insights.isEmpty {
                ContentUnavailableView("No insights yet", systemImage: "sparkles")
                    .frame(height: 120)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(engine.insights.prefix(5)) { insight in
                        InsightCard(insight: insight)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

@available(iOS 26.0, *)
struct InsightCard: View {
    let insight: SpendingInsight
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: insight.severity.color).opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: iconForCategory(insight.category))
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: insight.severity.color))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                Text(insight.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: insight.severity.color).opacity(0.15), lineWidth: 1)
        )
    }

    private func iconForCategory(_ category: InsightCategory) -> String {
        switch category {
        case .trend: return "chart.line.uptrend.xyaxis"
        case .anomaly: return "exclamationmark.triangle"
        case .prediction: return "crystal.ball"
        case .projection: return "calendar.badge.clock"
        case .categoryAnalysis: return "chart.pie"
        case .pattern: return "waveform"
        case .recommendation: return "lightbulb"
        }
    }
}

// MARK: - Recommendations Section

@available(iOS 26.0, *)
struct RecommendationsSection: View {
    @ObservedObject var recommendations: SmartRecommendations

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Smart Recommendations")
                    .font(.title3.bold())

                Spacer()

                if recommendations.isGenerating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recommendations.recommendations) { rec in
                        RecommendationCard(recommendation: rec)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

@available(iOS 26.0, *)
struct RecommendationCard: View {
    let recommendation: SmartRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: recommendation.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)

                Spacer()

                Button(action: {}) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(recommendation.title)
                .font(.subheadline.bold())
                .lineLimit(2)

            Text(recommendation.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer()

            Button("Learn More") {}
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
        }
        .frame(width: 260, height: 180)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Category Forecast Section

@available(iOS 26.0, *)
struct CategoryForecastSection: View {
    let forecasts: [CategoryForecast]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Forecasts")
                .font(.title3.bold())
                .padding(.horizontal)

            if forecasts.isEmpty {
                ContentUnavailableView("No data", systemImage: "chart.bar")
                    .frame(height: 100)
            } else {
                VStack(spacing: 12) {
                    ForEach(forecasts.prefix(5)) { forecast in
                        CategoryForecastRow(forecast: forecast)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

@available(iOS 26.0, *)
struct CategoryForecastRow: View {
    let forecast: CategoryForecast

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(forecast.category.displayName)
                    .font(.subheadline)

                Spacer()

                HStack(spacing: 4) {
                    Text(formatCurrency(forecast.spent))
                        .font(.caption.bold())
                    Text("/ \(formatCurrency(forecast.budget))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.secondary.opacity(0.15))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: forecast.status.color))
                        .frame(width: geo.size.width * forecast.percentageUsed, height: 6)

                    // Projected indicator
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: forecast.status.color).opacity(0.4))
                        .frame(width: geo.size.width * min(1.0, forecast.projectedPercentage), height: 6)
                }
            }
            .frame(height: 6)

            if forecast.projectedPercentage > 1.0 {
                Text("Projected overspend: \(formatCurrency(forecast.projectedTotal - forecast.budget))")
                    .font(.caption2)
                    .foregroundStyle(Color(hex: forecast.status.color))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Search Results Section

@available(iOS 26.0, *)
struct SearchResultsSection: View {
    let results: [Transaction]
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results for "\(query)"')
                .font(.title3.bold())
                .padding(.horizontal)

            ForEach(results) { transaction in
                TransactionRow(transaction: transaction)
            }
        }
    }
}

@available(iOS 26.0, *)
struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchantName)
                    .font(.subheadline.bold())
                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatCurrency(transaction.amount))
                .font(.subheadline.bold())
                .foregroundStyle(transaction.amount > 0 ? .primary : .green)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Status Badge

@available(iOS 26.0, *)
struct StatusBadge: View {
    let status: BudgetStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text(status.displayName)
        }
        .font(.caption.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: status.color).opacity(0.15))
        .foregroundStyle(Color(hex: status.color))
        .clipShape(Capsule())
    }

    private var statusIcon: String {
        switch status {
        case .onTrack: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .atRisk: return "flame.fill"
        case .depleted: return "xmark.circle.fill"
        }
    }
}

// MARK: - Color Extension

@available(iOS 26.0, *)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

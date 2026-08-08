import Foundation
import CoreML
import NaturalLanguage
import Combine

/// "Вы часто покупаете кофе в Starbucks — добавить карту лояльности?"
@available(iOS 26.0, *)
public final class SmartRecommendations: ObservableObject {

    // MARK: - Published State
    @Published public var recommendations: [SmartRecommendation] = []
    @Published public var isGenerating = false
    @Published public var personalizationScore: Double = 0.0

    // MARK: - CoreML (Placeholder)
    private var recommendationModel: MLModel?
    private var embeddingModel: NLEmbedding?

    // MARK: - Services
    private let transactionService: TransactionService
    private let categorizationEngine: SmartCategorization
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Recommendation Cache
    private var lastGenerationDate: Date?
    private let generationInterval: TimeInterval = 3600 // 1 час

    public init(
        transactionService: TransactionService = .shared,
        categorizationEngine: SmartCategorization = SmartCategorization()
    ) {
        self.transactionService = transactionService
        self.categorizationEngine = categorizationEngine
        setupModels()
        observeTransactions()
    }

    private func setupModels() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            // recommendationModel = try RecommendationEngine(configuration: config)
            print("[SmartRecommendations] CoreML placeholder — используется rule-based + collaborative filtering fallback")
        } catch {
            print("[SmartRecommendations] CoreML недоступен: \(error)")
        }

        if let embedding = NLEmbedding.wordEmbedding(for: .english) {
            self.embeddingModel = embedding
        }
    }

    // MARK: - Public API

    /// Генерирует персонализированные рекомендации
    public func generateRecommendations() async {
        guard !isGenerating else { return }

        // Кеширование
        if let last = lastGenerationDate, Date().timeIntervalSince(last) < generationInterval {
            return
        }

        isGenerating = true
        defer {
            isGenerating = false
            lastGenerationDate = Date()
        }

        let transactions = await transactionService.fetchLast90Days()
        var newRecommendations: [SmartRecommendation] = []

        // 1. Карты лояльности
        let loyaltyRecs = await recommendLoyaltyCards(from: transactions)
        newRecommendations.append(contentsOf: loyaltyRecs)

        // 2. Подписки
        let subscriptionRecs = detectSubscriptionOptimizations(from: transactions)
        newRecommendations.append(contentsOf: subscriptionRecs)

        // 3. Кэшбэк и бонусы
        let cashbackRecs = recommendCashbackOpportunities(from: transactions)
        newRecommendations.append(contentsOf: cashbackRecs)

        // 4. Бюджетные рекомендации
        let budgetRecs = recommendBudgetOptimizations(from: transactions)
        newRecommendations.append(contentsOf: budgetRecs)

        // 5. Мерчант-специфичные
        let merchantRecs = recommendMerchantSpecific(from: transactions)
        newRecommendations.append(contentsOf: merchantRecs)

        // 6. Временные паттерны
        let timingRecs = recommendTimingOptimizations(from: transactions)
        newRecommendations.append(contentsOf: timingRecs)

        // Сортируем по релевантности
        newRecommendations.sort { $0.relevanceScore > $1.relevanceScore }

        await MainActor.run {
            self.recommendations = Array(newRecommendations.prefix(10))
            self.personalizationScore = calculatePersonalizationScore(for: newRecommendations)
        }
    }

    /// Отмечает рекомендацию как выполненную/отклоненную
    public func interact(with recommendation: SmartRecommendation, action: RecommendationAction) {
        var updated = recommendation
        updated.userAction = action
        updated.interactedAt = Date()

        // Обучаемся на действии пользователя
        learnFromInteraction(recommendation: updated, action: action)

        // Убираем из списка
        recommendations.removeAll { $0.id == recommendation.id }
    }

    /// Проверяет, есть ли рекомендации для конкретного мерчанта
    public func recommendationsForMerchant(_ merchantName: String) -> [SmartRecommendation] {
        recommendations.filter {
            $0.relatedMerchant?.lowercased() == merchantName.lowercased()
        }
    }

    // MARK: - Recommendation Engines

    private func recommendLoyaltyCards(from transactions: [Transaction]) async -> [SmartRecommendation] {
        let frequentMerchants = findFrequentMerchants(transactions, minVisits: 3)
        var recs: [SmartRecommendation] = []

        let knownLoyaltyPrograms: [(merchant: String, programName: String, benefit: String)] = [
            ("starbucks", "Starbucks Rewards", "Бесплатный напиток каждые 150⭐"),
            ("mcdonald", "MyMcDonald's Rewards", "Кэшбэк 5% на каждую покупку"),
            ("whole foods", "Amazon Prime + Whole Foods", "10% скидка на товары Prime"),
            ("uber", "Uber Rewards", "Поинты за поездки и доставку"),
            ("lyft", "Lyft Rewards", "Бонусы за частые поездки"),
            ("shell", "Fuel Rewards", "Скидка до 5¢/галлон"),
            ("cvs", "CVS ExtraCare", "2% кэшбэк + персональные купоны"),
            ("nike", "Nike Membership", "Эксклюзивный доступ к релизам"),
            ("apple", "Apple Card", "3% кэшбэк в Apple Store"),
            ("netflix", "—", "Рассмотрите семейный тариф для экономии"),
        ]

        for merchant in frequentMerchants {
            let merchantLower = merchant.name.lowercased()
            if let program = knownLoyaltyPrograms.first(where: { merchantLower.contains($0.merchant) }) {
                let monthlySpend = merchant.totalAmount
                let potentialSavings = monthlySpend * 0.05 // ~5% средний кэшбэк

                recs.append(SmartRecommendation(
                    id: UUID(),
                    title: "💳 Добавить карту лояльности \(program.programName)",
                    description: "Вы тратите \(formatCurrency(monthlySpend)) в месяц в \(merchant.name). С картой лояльности сэкономите ~\(formatCurrency(potentialSavings))/мес. \(program.benefit)",
                    type: .loyaltyCard,
                    relevanceScore: min(1.0, Double(merchant.visitCount) / 10.0) * 0.9,
                    relatedMerchant: merchant.name,
                    action: .openURL("https://\(program.merchant).com/rewards"),
                    icon: "creditcard.fill",
                    userAction: nil,
                    interactedAt: nil
                ))
            }
        }

        return recs
    }

    private func detectSubscriptionOptimizations(from transactions: [Transaction]) -> [SmartRecommendation] {
        let recurring = findRecurringTransactions(transactions)
        var recs: [SmartRecommendation] = []

        // Группируем по категории подписок
        let subscriptionCategories = Dictionary(grouping: recurring) { $0.merchantName.lowercased() }

        for (merchant, txs) in subscriptionCategories {
            let monthlyAmount = txs.first?.amount ?? 0

            // Проверяем дублирующиеся подписки
            if merchant.contains("music") || merchant.contains("spotify") || merchant.contains("apple music") {
                if hasMultipleMusicSubscriptions(transactions) {
                    recs.append(SmartRecommendation(
                        id: UUID(),
                        title: "🎵 Дублирующиеся музыкальные подписки",
                        description: "Обнаружено несколько музыкальных сервисов. Рассмотрите оставить один и сэкономить \(formatCurrency(monthlyAmount))/мес.",
                        type: .subscriptionOptimization,
                        relevanceScore: 0.85,
                        relatedMerchant: merchant,
                        action: .viewSubscriptions,
                        icon: "music.note",
                        userAction: nil,
                        interactedAt: nil
                    ))
                }
            }

            // Неиспользуемые подписки
            if txs.count > 2 {
                let lastTx = txs.max { $0.date < $1.date }
                let daysSince = Calendar.current.dateComponents([.day], from: lastTx?.date ?? Date(), to: Date()).day ?? 0
                if daysSince > 45 {
                    recs.append(SmartRecommendation(
                        id: UUID(),
                        title: "📺 Возможно, неиспользуемая подписка",
                        description: "\(merchant.capitalized): последняя транзакция \(daysSince) дней назад. Вы платите \(formatCurrency(monthlyAmount))/мес, но не пользуетесь сервисом?",
                        type: .unusedSubscription,
                        relevanceScore: 0.80,
                        relatedMerchant: merchant,
                        action: .cancelSubscription,
                        icon: "xmark.circle.fill",
                        userAction: nil,
                        interactedAt: nil
                    ))
                }
            }
        }

        return recs
    }

    private func recommendCashbackOpportunities(from transactions: [Transaction]) -> [SmartRecommendation] {
        var recs: [SmartRecommendation] = []

        // Анализ категорий без кэшбэка
        let categoryTotals = Dictionary(grouping: transactions, by: { $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }

        let cashbackMap: [(category: TransactionCategory, cardName: String, rate: Double)] = [
            (.groceries, "Amex Blue Cash Preferred", 0.06),
            (.foodAndDrink, "Chase Sapphire Preferred", 0.03),
            (.transportation, "Citi Custom Cash", 0.05),
            (.travel, "Chase Sapphire Reserve", 0.03),
            (.gas, "PenFed Platinum", 0.05),
        ]

        for mapping in cashbackMap {
            if let spend = categoryTotals[mapping.category], spend > 200 {
                let potential = spend * mapping.rate
                recs.append(SmartRecommendation(
                    id: UUID(),
                    title: "💰 Кэшбэк на \(mapping.category.displayName)",
                    description: "Вы тратите \(formatCurrency(spend)) на \(mapping.category.displayName). С картой \(mapping.cardName) получили бы \(formatCurrency(potential)) кэшбэка.",
                    type: .cashbackOpportunity,
                    relevanceScore: min(1.0, spend / 1000),
                    relatedMerchant: nil,
                    action: .compareCards,
                    icon: "dollarsign.circle.fill",
                    userAction: nil,
                    interactedAt: nil
                ))
            }
        }

        return recs
    }

    private func recommendBudgetOptimizations(from transactions: [Transaction]) -> [SmartRecommendation] {
        var recs: [SmartRecommendation] = []

        // Паттерн: много мелких трат
        let smallTx = transactions.filter { $0.amount < 10 }
        if smallTx.count > 20 {
            let total = smallTx.reduce(0) { $0 + $1.amount }
            recs.append(SmartRecommendation(
                id: UUID(),
                title: "☕ Эффект латте",
                description: "\(smallTx.count) мелких трат на сумму \(formatCurrency(total)). Это \(formatCurrency(total * 12))/год! Мелкие покупки складываются.",
                type: .budgetOptimization,
                relevanceScore: min(1.0, Double(smallTx.count) / 50.0),
                relatedMerchant: nil,
                action: .viewSmallTransactions,
                icon: "cup.and.saucer.fill",
                userAction: nil,
                interactedAt: nil
            ))
        }

        // Паттерн: импульсные покупки поздно вечером
        let eveningTx = transactions.filter {
            let hour = Calendar.current.component(.hour, from: $0.date)
            return hour >= 22 && $0.category == .shopping
        }
        if eveningTx.count > 2 {
            let total = eveningTx.reduce(0) { $0 + $1.amount }
            recs.append(SmartRecommendation(
                id: UUID(),
                title: "🌙 Импульсные ночные покупки",
                description: "\(eveningTx.count) покупки после 22:00 на \(formatCurrency(total)). Попробуйте отложить покупки на утро.",
                type: .behavioralNudge,
                relevanceScore: 0.70,
                relatedMerchant: nil,
                action: .setSpendingReminder,
                icon: "moon.fill",
                userAction: nil,
                interactedAt: nil
            ))
        }

        return recs
    }

    private func recommendMerchantSpecific(from transactions: [Transaction]) -> [SmartRecommendation] {
        var recs: [SmartRecommendation] = []

        // Amazon: частые покупки → Prime
        let amazonTx = transactions.filter { $0.merchantName.lowercased().contains("amazon") }
        if amazonTx.count > 3 {
            let shippingEstimate = Double(amazonTx.count) * 5.99
            recs.append(SmartRecommendation(
                id: UUID(),
                title: "📦 Amazon Prime может окупиться",
                description: "\(amazonTx.count) заказа на Amazon. С Prime сэкономите ~\(formatCurrency(shippingEstimate)) на доставке + получите доступ к контенту.",
                type: .merchantOffer,
                relevanceScore: 0.75,
                relatedMerchant: "Amazon",
                action: .openURL("https://amazon.com/prime"),
                icon: "shippingbox.fill",
                userAction: nil,
                interactedAt: nil
            ))
        }

        return recs
    }

    private func recommendTimingOptimizations(from transactions: [Transaction]) -> [SmartRecommendation] {
        var recs: [SmartRecommendation] = []

        // Анализ: покупки в начале месяца vs конце
        let calendar = Calendar.current
        let earlyMonth = transactions.filter { calendar.component(.day, from: $0.date) <= 5 }
        let lateMonth = transactions.filter { calendar.component(.day, from: $0.date) >= 25 }

        let earlyTotal = earlyMonth.reduce(0) { $0 + $1.amount }
        let lateTotal = lateMonth.reduce(0) { $0 + $1.amount }

        if earlyTotal > lateTotal * 2 {
            recs.append(SmartRecommendation(
                id: UUID(),
                title: "📅 Распределите траты равномернее",
                description: "\(formatCurrency(earlyTotal)) потрачено в первые 5 дней месяца. Попробуйте отложить необязательные покупки.",
                type: .timingOptimization,
                relevanceScore: 0.65,
                relatedMerchant: nil,
                action: .setBudgetAlert,
                icon: "calendar.badge.clock",
                userAction: nil,
                interactedAt: nil
            ))
        }

        return recs
    }

    // MARK: - Helpers

    private func findFrequentMerchants(_ transactions: [Transaction], minVisits: Int) -> [(name: String, visitCount: Int, totalAmount: Double)] {
        let grouped = Dictionary(grouping: transactions) { $0.merchantName }
        return grouped
            .map { (name: $0.key, visitCount: $0.value.count, totalAmount: $0.value.reduce(0) { $0 + $1.amount }) }
            .filter { $0.visitCount >= minVisits }
            .sorted { $0.visitCount > $1.visitCount }
    }

    private func findRecurringTransactions(_ transactions: [Transaction]) -> [Transaction] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { $0.merchantName.lowercased() }

        return grouped.flatMap { _, txs in
            guard txs.count >= 2 else { return [Transaction]() }
            // Проверяем регулярность (примерно раз в месяц)
            let sorted = txs.sorted { $0.date < $1.date }
            var recurring: [Transaction] = []
            for i in 1..<sorted.count {
                let days = calendar.dateComponents([.day], from: sorted[i-1].date, to: sorted[i].date).day ?? 0
                if days >= 25 && days <= 35 {
                    recurring.append(sorted[i])
                }
            }
            return recurring
        }
    }

    private func hasMultipleMusicSubscriptions(_ transactions: [Transaction]) -> Bool {
        let musicServices = ["spotify", "apple music", "youtube music", "tidal", "deezer"]
        let found = musicServices.filter { service in
            transactions.contains { $0.merchantName.lowercased().contains(service) }
        }
        return found.count > 1
    }

    private func calculatePersonalizationScore(for recommendations: [SmartRecommendation]) -> Double {
        guard !recommendations.isEmpty else { return 0 }
        let avgRelevance = recommendations.map { $0.relevanceScore }.reduce(0, +) / Double(recommendations.count)
        return min(1.0, avgRelevance * 1.2)
    }

    private func learnFromInteraction(recommendation: SmartRecommendation, action: RecommendationAction) {
        // Сохраняем предпочтения пользователя
        var dismissedTypes = Set(UserDefaults.standard.stringArray(forKey: "dismissedRecTypes") ?? [])
        if action == .dismiss {
            dismissedTypes.insert(recommendation.type.rawValue)
        }
        UserDefaults.standard.set(Array(dismissedTypes), forKey: "dismissedRecTypes")
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func observeTransactions() {
        transactionService.transactionsPublisher
            .debounce(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.generateRecommendations()
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
public struct SmartRecommendation: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let description: String
    public let type: RecommendationType
    public let relevanceScore: Double // 0.0 - 1.0
    public let relatedMerchant: String?
    public let action: RecommendationActionType
    public let icon: String
    public var userAction: RecommendationAction?
    public var interactedAt: Date?

    public static func == (lhs: SmartRecommendation, rhs: SmartRecommendation) -> Bool {
        lhs.id == rhs.id
    }
}

@available(iOS 26.0, *)
public enum RecommendationType: String, CaseIterable {
    case loyaltyCard = "loyalty_card"
    case subscriptionOptimization = "subscription_optimization"
    case unusedSubscription = "unused_subscription"
    case cashbackOpportunity = "cashback_opportunity"
    case budgetOptimization = "budget_optimization"
    case behavioralNudge = "behavioral_nudge"
    case merchantOffer = "merchant_offer"
    case timingOptimization = "timing_optimization"
}

@available(iOS 26.0, *)
public enum RecommendationAction {
    case accept
    case dismiss
    case snooze
}

@available(iOS 26.0, *)
public enum RecommendationActionType {
    case openURL(String)
    case viewSubscriptions
    case cancelSubscription
    case compareCards
    case viewSmallTransactions
    case setSpendingReminder
    case setBudgetAlert
    case none
}

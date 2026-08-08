import Foundation
import CoreML
import NaturalLanguage

/// Автоматическая категоризация транзакций с CoreML + Rule-based fallback
@available(iOS 26.0, *)
public final class SmartCategorization: ObservableObject {

    // MARK: - CoreML Model (Placeholder)
    private var categorizationModel: MLModel?
    private var embeddingModel: NLEmbedding?

    // MARK: - Rule-Based Engine
    private let ruleEngine: CategorizationRuleEngine
    private let merchantDictionary: MerchantCategoryDictionary

    // MARK: - Learning
    private var userCorrections: [String: TransactionCategory] = [:]
    private let correctionsKey = "com.applewallet.ai.userCorrections"

    // MARK: - Published
    @Published public var confidenceThreshold: Double = 0.75
    @Published public var lastCategorizationConfidence: Double = 0.0

    public init() {
        self.ruleEngine = CategorizationRuleEngine()
        self.merchantDictionary = MerchantCategoryDictionary()
        setupCoreML()
        loadUserCorrections()
    }

    // MARK: - Setup
    private func setupCoreML() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            // categorizationModel = try TransactionCategorizer(configuration: config)
            print("[SmartCategorization] CoreML model placeholder — используется rule-based + NLP")
        } catch {
            print("[SmartCategorization] CoreML недоступен: \(error)")
        }

        // NLP Embeddings для семантического сопоставления
        if let embedding = NLEmbedding.wordEmbedding(for: .english) {
            self.embeddingModel = embedding
        }
    }

    // MARK: - Public API

    /// Категоризирует транзакцию с максимальной точностью
    public func categorize(transaction: Transaction) -> CategorizationResult {
        // 1. Проверяем пользовательские корректировки
        if let userCategory = userCorrections[transaction.merchantName.lowercased()] {
            return CategorizationResult(
                category: userCategory,
                confidence: 0.99,
                source: .userCorrected,
                reasoning: "Ранее вы вручную установили эту категорию"
            )
        }

        // 2. Проверяем словарь мерчантов
        if let dictCategory = merchantDictionary.category(for: transaction.merchantName) {
            return CategorizationResult(
                category: dictCategory,
                confidence: 0.95,
                source: .merchantDictionary,
                reasoning: "Известный мерчант в базе данных"
            )
        }

        // 3. Пробуем CoreML (placeholder — всегда fallback)
        if let mlResult = tryCoreMLCategorization(transaction) {
            return mlResult
        }

        // 4. Rule-based анализ
        let ruleResult = ruleEngine.categorize(transaction)

        // 5. NLP семантический анализ для уточнения
        let nlpResult = enhanceWithNLP(transaction, ruleResult: ruleResult)

        lastCategorizationConfidence = nlpResult.confidence
        return nlpResult
    }

    /// Batch категоризация
    public func categorizeBatch(_ transactions: [Transaction]) -> [Transaction] {
        transactions.map { tx in
            var mutable = tx
            let result = categorize(transaction: tx)
            mutable.category = result.category
            mutable.categorizationConfidence = result.confidence
            mutable.categorizationSource = result.source
            return mutable
        }
    }

    /// Обучение на пользовательской корректировке
    public func learnCorrection(merchant: String, correctCategory: TransactionCategory) {
        let key = merchant.lowercased()
        userCorrections[key] = correctCategory
        saveUserCorrections()

        // Обновляем словарь мерчантов
        merchantDictionary.learn(merchant: merchant, category: correctCategory)

        print("[SmartCategorization] Обучено: \(merchant) → \(correctCategory.displayName)")
    }

    /// Smart split для чеков (разделение чека на категории)
    public func smartSplit(receiptItems: [ReceiptItem]) -> [CategorySplit] {
        var splits: [TransactionCategory: Double] = [:]

        for item in receiptItems {
            // Используем NLP для определения категории по названию товара
            let category = inferCategoryFromItemName(item.name)
            splits[category, default: 0] += item.amount
        }

        return splits.map { CategorySplit(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - CoreML Placeholder

    private func tryCoreMLCategorization(_ transaction: Transaction) -> CategorizationResult? {
        guard categorizationModel != nil else { return nil }
        // Placeholder: в реальности здесь был бы prediction
        // let input = TransactionCategorizerInput(merchant: transaction.merchantName, amount: transaction.amount, ...)
        // let output = try? categorizationModel.prediction(from: input)
        return nil
    }

    // MARK: - NLP Enhancement

    private func enhanceWithNLP(_ transaction: Transaction, ruleResult: CategorizationResult) -> CategorizationResult {
        let merchant = transaction.merchantName.lowercased()
        let description = transaction.description?.lowercased() ?? ""

        // Семантический анализ через embeddings
        var semanticScore: [TransactionCategory: Double] = [:]

        if let embedding = embeddingModel {
            for category in TransactionCategory.allCases {
                let categoryTerms = category.semanticTerms
                var totalDistance: Double = 0
                var count = 0

                for term in categoryTerms {
                    if let merchantVector = embedding.vector(for: merchant),
                       let termVector = embedding.vector(for: term) {
                        let distance = cosineSimilarity(merchantVector, termVector)
                        totalDistance += distance
                        count += 1
                    }
                }

                if count > 0 {
                    semanticScore[category] = totalDistance / Double(count)
                }
            }
        }

        // Комбинируем rule-based и semantic
        var bestCategory = ruleResult.category
        var bestScore = ruleResult.confidence

        if let topSemantic = semanticScore.max(by: { $0.value < $1.value }),
           topSemantic.value > 0.6 && topSemantic.value > bestScore {
            bestCategory = topSemantic.key
            bestScore = topSemantic.value
        }

        return CategorizationResult(
            category: bestCategory,
            confidence: bestScore,
            source: bestScore > 0.85 ? .nlpSemantic : .ruleBased,
            reasoning: generateReasoning(for: transaction, category: bestCategory)
        )
    }

    private func inferCategoryFromItemName(_ name: String) -> TransactionCategory {
        let lowercased = name.lowercased()

        let mappings: [(keywords: [String], category: TransactionCategory)] = [
            (["coffee", "latte", "espresso", "cappuccino", "americano"], .foodAndDrink),
            (["beer", "wine", "cocktail", "alcohol", "liquor"], .foodAndDrink),
            (["gas", "fuel", "petrol", "diesel"], .transportation),
            (["pharmacy", "drug", "medicine", "pill", "prescription"], .health),
            (["book", "magazine", "kindle"], .entertainment),
            (["movie", "cinema", "ticket", "concert"], .entertainment),
            (["shirt", "pants", "shoes", "dress", "apparel"], .shopping),
            (["grocery", "supermarket", "bread", "milk", "egg"], .groceries),
            (["uber", "taxi", "lyft", "ride"], .transportation),
            (["flight", "hotel", "airbnb", "booking"], .travel),
        ]

        for mapping in mappings {
            if mapping.keywords.contains(where: { lowercased.contains($0) }) {
                return mapping.category
            }
        }

        return .other
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard normA > 0 && normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

    private func generateReasoning(for transaction: Transaction, category: TransactionCategory) -> String {
        let merchant = transaction.merchantName
        switch category {
        case .foodAndDrink:
            return "\(merchant) распознан как заведение общепита"
        case .groceries:
            return "\(merchant) идентифицирован как продуктовый магазин"
        case .transportation:
            return "\(merchant) связан с транспортом или поездками"
        case .shopping:
            return "\(merchant) классифицирован как магазин розничной торговли"
        case .entertainment:
            return "\(merchant) относится к развлечениям"
        default:
            return "Категория определена на основе паттернов трат"
        }
    }

    // MARK: - Persistence

    private func loadUserCorrections() {
        if let data = UserDefaults.standard.data(forKey: correctionsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            userCorrections = decoded.compactMapValues { TransactionCategory(rawValue: $0) }
        }
    }

    private func saveUserCorrections() {
        let encodable = userCorrections.mapValues { $0.rawValue }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: correctionsKey)
        }
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
public struct CategorizationResult {
    public let category: TransactionCategory
    public let confidence: Double
    public let source: CategorizationSource
    public let reasoning: String
}

@available(iOS 26.0, *)
public enum CategorizationSource: String {
    case userCorrected = "user_corrected"
    case merchantDictionary = "merchant_dictionary"
    case coreML = "coreml"
    case ruleBased = "rule_based"
    case nlpSemantic = "nlp_semantic"
}

@available(iOS 26.0, *)
public struct CategorySplit {
    public let category: TransactionCategory
    public let amount: Double
}

@available(iOS 26.0, *)
public struct ReceiptItem {
    public let name: String
    public let amount: Double
    public let quantity: Int
}

// MARK: - Rule Engine

@available(iOS 26.0, *)
final class CategorizationRuleEngine {

    func categorize(_ transaction: Transaction) -> CategorizationResult {
        let merchant = transaction.merchantName.lowercased()
        let amount = transaction.amount

        // Правила по мерчантам
        let merchantRules: [(predicate: (String) -> Bool, category: TransactionCategory, confidence: Double)] = [
            ({ $0.contains("starbucks") || $0.contains("coffee") }, .foodAndDrink, 0.92),
            ({ $0.contains("uber") || $0.contains("lyft") || $0.contains("taxi") }, .transportation, 0.95),
            ({ $0.contains("shell") || $0.contains("bp") || $0.contains("exxon") }, .transportation, 0.88),
            ({ $0.contains("netflix") || $0.contains("spotify") || $0.contains("apple") && $0.contains("music") }, .entertainment, 0.94),
            ({ $0.contains("amazon") || $0.contains("ebay") || $0.contains("shop") }, .shopping, 0.80),
            ({ $0.contains("grocery") || $0.contains("whole foods") || $0.contains("trader") }, .groceries, 0.93),
            ({ $0.contains("restaurant") || $0.contains("cafe") || $0.contains("grill") }, .foodAndDrink, 0.85),
            ({ $0.contains("pharmacy") || $0.contains("cvs") || $0.contains("walgreens") }, .health, 0.87),
            ({ $0.contains("gym") || $0.contains("fitness") }, .health, 0.90),
            ({ $0.contains("airline") || $0.contains("hotel") || $0.contains("booking") }, .travel, 0.91),
        ]

        for rule in merchantRules {
            if rule.predicate(merchant) {
                return CategorizationResult(
                    category: rule.category,
                    confidence: rule.confidence,
                    source: .ruleBased,
                    reasoning: "Соответствие правилу мерчанта"
                )
            }
        }

        // Правила по сумме
        if amount > 500 {
            return CategorizationResult(
                category: .shopping,
                confidence: 0.60,
                source: .ruleBased,
                reasoning: "Крупная сумма — вероятно, покупка товаров"
            )
        }

        if amount < 15 {
            return CategorizationResult(
                category: .foodAndDrink,
                confidence: 0.55,
                source: .ruleBased,
                reasoning: "Небольшая сумма — вероятно, кофе/перекус"
            )
        }

        return CategorizationResult(
            category: .other,
            confidence: 0.40,
            source: .ruleBased,
            reasoning: "Недостаточно данных для точной категоризации"
        )
    }
}

// MARK: - Merchant Dictionary

@available(iOS 26.0, *)
final class MerchantCategoryDictionary {
    private var dictionary: [String: TransactionCategory] = [
        "starbucks": .foodAndDrink,
        "mcdonald's": .foodAndDrink,
        "uber": .transportation,
        "lyft": .transportation,
        "shell": .transportation,
        "netflix": .entertainment,
        "spotify": .entertainment,
        "amazon": .shopping,
        "whole foods": .groceries,
        "cvs": .health,
        "walgreens": .health,
        "apple store": .shopping,
        "nike": .shopping,
        "airbnb": .travel,
        "delta": .travel,
        "shell oil": .transportation,
    ]

    func category(for merchant: String) -> TransactionCategory? {
        let key = merchant.lowercased()
        return dictionary[key] ?? dictionary.first { key.contains($0.key) }?.value
    }

    func learn(merchant: String, category: TransactionCategory) {
        dictionary[merchant.lowercased()] = category
    }
}

import Foundation
import NaturalLanguage
import CoreML

/// "Show me all expensive dinners last month" → фильтр
@available(iOS 26.0, *)
public final class NaturalLanguageSearch: ObservableObject {

    // MARK: - Core Components
    private let tagger: NLTagger
    private var embeddingModel: NLEmbedding?
    private let dateParser: DateExpressionParser
    private let amountParser: AmountExpressionParser
    private let categoryResolver: CategorySemanticResolver

    // MARK: - Published
    @Published public var lastQuery: String = ""
    @Published public var parsedIntent: SearchIntent?
    @Published public var isProcessing = false

    public init() {
        self.tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .sentimentScore])
        self.dateParser = DateExpressionParser()
        self.amountParser = AmountExpressionParser()
        self.categoryResolver = CategorySemanticResolver()

        if let embedding = NLEmbedding.wordEmbedding(for: .english) {
            self.embeddingModel = embedding
        }
    }

    // MARK: - Public API

    /// Основной метод: парсит NL запрос в SearchIntent
    public func parse(query: String) -> SearchIntent {
        isProcessing = true
        defer { isProcessing = false }

        lastQuery = query
        let lowercased = query.lowercased()

        // 1. Определяем тип запроса
        let intentType = detectIntentType(lowercased)

        // 2. Извлекаем временной диапазон
        let dateRange = dateParser.parse(from: lowercased)

        // 3. Извлекаем суммовые фильтры
        let amountFilter = amountParser.parse(from: lowercased)

        // 4. Извлекаем категории
        let categories = categoryResolver.resolve(from: lowercased)

        // 5. Извлекаем мерчантов
        let merchants = extractMerchants(from: lowercased)

        // 6. Извлекаем сортировку
        let sortOrder = extractSortOrder(from: lowercased)

        // 7. Извлекаем лимит
        let limit = extractLimit(from: lowercased)

        let intent = SearchIntent(
            originalQuery: query,
            intentType: intentType,
            dateRange: dateRange,
            amountFilter: amountFilter,
            categories: categories,
            merchants: merchants,
            sortOrder: sortOrder,
            limit: limit,
            confidence: calculateConfidence(query: lowercased, parsed: (dateRange, amountFilter, categories))
        )

        parsedIntent = intent
        return intent
    }

    /// Применяет SearchIntent к массиву транзакций
    public func apply(intent: SearchIntent, to transactions: [Transaction]) -> [Transaction] {
        var filtered = transactions

        // Фильтр по дате
        if let range = intent.dateRange {
            filtered = filtered.filter { range.contains($0.date) }
        }

        // Фильтр по сумме
        if let amountFilter = intent.amountFilter {
            filtered = filtered.filter { amountFilter.matches($0.amount) }
        }

        // Фильтр по категориям
        if !intent.categories.isEmpty {
            filtered = filtered.filter { tx in
                intent.categories.contains(tx.category)
            }
        }

        // Фильтр по мерчантам
        if !intent.merchants.isEmpty {
            filtered = filtered.filter { tx in
                intent.merchants.contains { tx.merchantName.lowercased().contains($0.lowercased()) }
            }
        }

        // Сортировка
        switch intent.sortOrder {
        case .amountAscending:
            filtered.sort { $0.amount < $1.amount }
        case .amountDescending:
            filtered.sort { $0.amount > $1.amount }
        case .dateAscending:
            filtered.sort { $0.date < $1.date }
        case .dateDescending:
            filtered.sort { $0.date > $1.date }
        case .none:
            break
        }

        // Лимит
        if let limit = intent.limit {
            filtered = Array(filtered.prefix(limit))
        }

        return filtered
    }

    /// One-shot search
    public func search(query: String, in transactions: [Transaction]) -> [Transaction] {
        let intent = parse(query: query)
        return apply(intent: intent, to: transactions)
    }

    /// Генерирует описание примененных фильтров
    public func explain(intent: SearchIntent) -> String {
        var parts: [String] = []

        switch intent.intentType {
        case .find: parts.append("Поиск транзакций")
        case .summarize: parts.append("Суммарный отчет")
        case .compare: parts.append("Сравнение")
        case .trend: parts.append("Анализ тренда")
        }

        if let range = intent.dateRange {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append("за период \(formatter.string(from: range.start)) — \(formatter.string(from: range.end))")
        }

        if !intent.categories.isEmpty {
            let catNames = intent.categories.map { $0.displayName }.joined(separator: ", ")
            parts.append("в категориях: \(catNames)")
        }

        if let amount = intent.amountFilter {
            parts.append("с суммой \(amount.description)")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Intent Detection

    private func detectIntentType(_ query: String) -> SearchIntentType {
        if query.contains("sum") || query.contains("total") || query.contains("spent") || query.contains("потратил") {
            return .summarize
        }
        if query.contains("compare") || query.contains("vs") || query.contains("versus") || query.contains("сравни") {
            return .compare
        }
        if query.contains("trend") || query.contains("more") || query.contains("less") || query.contains("рост") {
            return .trend
        }
        return .find
    }

    // MARK: - Entity Extraction

    private func extractMerchants(from query: String) -> [String] {
        let knownMerchants = [
            "starbucks", "amazon", "uber", "lyft", "netflix", "spotify",
            "mcdonald", "apple", "nike", "shell", "whole foods", "cvs",
            "walmart", "target", "costco", "airbnb", "delta"
        ]

        return knownMerchants.filter { query.contains($0) }
    }

    private func extractSortOrder(from query: String) -> SortOrder {
        if query.contains("most expensive") || query.contains("highest") || query.contains("biggest") || query.contains("desc") {
            return .amountDescending
        }
        if query.contains("cheapest") || query.contains("lowest") || query.contains("smallest") || query.contains("asc") {
            return .amountAscending
        }
        if query.contains("latest") || query.contains("recent") || query.contains("newest") {
            return .dateDescending
        }
        if query.contains("oldest") || query.contains("first") {
            return .dateAscending
        }
        return .none
    }

    private func extractLimit(from query: String) -> Int? {
        let patterns = [
            "top (\d+)", "first (\d+)", "last (\d+)", "(\d+) most",
            "первые (\d+)", "последние (\d+)", "топ (\d+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
               let range = Range(match.range(at: 1), in: query),
               let number = Int(query[range]) {
                return number
            }
        }

        return nil
    }

    private func calculateConfidence(
        query: String,
        parsed: (dateRange: DateRange?, amountFilter: AmountFilter?, categories: [TransactionCategory])
    ) -> Double {
        var score = 0.5 // Базовая уверенность

        if parsed.dateRange != nil { score += 0.2 }
        if parsed.amountFilter != nil { score += 0.15 }
        if !parsed.categories.isEmpty { score += 0.15 }

        // Штраф за нераспознанные слова
        let commonWords = ["show", "me", "all", "my", "the", "find", "get", "list", "покажи", "все", "мои"]
        let words = query.split(separator: " ")
        let unrecognized = words.filter { !commonWords.contains(String($0)) && parsed.categories.isEmpty }
        if unrecognized.count > 5 {
            score -= 0.1
        }

        return min(1.0, max(0.0, score))
    }
}

// MARK: - Date Expression Parser

@available(iOS 26.0, *)
final class DateExpressionParser {
    func parse(from query: String) -> DateRange? {
        let calendar = Calendar.current
        let now = Date()

        // "last month"
        if query.contains("last month") || query.contains("прошлый месяц") || query.contains("прошлом месяце") {
            guard let start = calendar.date(byAdding: .month, value: -1, to: now),
                  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start)),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                return nil
            }
            return DateRange(start: monthStart, end: calendar.date(byAdding: .day, value: -1, to: monthEnd)!)
        }

        // "this month"
        if query.contains("this month") || query.contains("этот месяц") || query.contains("в этом месяце") {
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                return nil
            }
            return DateRange(start: monthStart, end: calendar.date(byAdding: .day, value: -1, to: monthEnd)!)
        }

        // "last week"
        if query.contains("last week") || query.contains("прошлая неделя") || query.contains("на прошлой неделе") {
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else {
                return nil
            }
            return DateRange(start: lastWeekStart, end: calendar.date(byAdding: .day, value: -1, to: weekStart)!)
        }

        // "this week"
        if query.contains("this week") || query.contains("на этой неделе") || query.contains("эта неделя") {
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
                return nil
            }
            return DateRange(start: weekStart, end: now)
        }

        // "last 7 days"
        if query.contains("last 7 days") || query.contains("last week") || query.contains("последние 7 дней") {
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            return DateRange(start: start, end: now)
        }

        // "last 30 days"
        if query.contains("last 30 days") || query.contains("last month") || query.contains("последние 30 дней") {
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            return DateRange(start: start, end: now)
        }

        // "yesterday"
        if query.contains("yesterday") || query.contains("вчера") {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  let start = calendar.startOfDay(for: yesterday) else { return nil }
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return DateRange(start: start, end: calendar.date(byAdding: .second, value: -1, to: end)!)
        }

        // "today"
        if query.contains("today") || query.contains("сегодня") {
            let start = calendar.startOfDay(for: now)
            return DateRange(start: start, end: now)
        }

        // "last year"
        if query.contains("last year") || query.contains("прошлый год") {
            guard let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now)),
                  let lastYearStart = calendar.date(byAdding: .year, value: -1, to: yearStart) else {
                return nil
            }
            return DateRange(start: lastYearStart, end: calendar.date(byAdding: .day, value: -1, to: yearStart)!)
        }

        return nil
    }
}

// MARK: - Amount Expression Parser

@available(iOS 26.0, *)
final class AmountExpressionParser {
    func parse(from query: String) -> AmountFilter? {
        // "expensive" / "большие" / "дорогие" → > $50
        if query.contains("expensive") || query.contains("big") || query.contains("large") || query.contains("дорог") || query.contains("большие") {
            return AmountFilter(min: 50, max: nil, description: "более $50")
        }

        // "cheap" / "small" / "маленькие" / "дешевые" → < $20
        if query.contains("cheap") || query.contains("small") || query.contains("little") || query.contains("дешев") || query.contains("маленькие") {
            return AmountFilter(min: nil, max: 20, description: "менее $20")
        }

        // "more than $X" / "более $X"
        let moreThanPattern = "(?:more than|over|above|более|больше|свыше)\s*\$?(\d+)"
        if let regex = try? NSRegularExpression(pattern: moreThanPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let range = Range(match.range(at: 1), in: query),
           let amount = Double(query[range]) {
            return AmountFilter(min: amount, max: nil, description: "более \(formatCurrency(amount))")
        }

        // "less than $X" / "менее $X"
        let lessThanPattern = "(?:less than|under|below|менее|меньше|до)\s*\$?(\d+)"
        if let regex = try? NSRegularExpression(pattern: lessThanPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let range = Range(match.range(at: 1), in: query),
           let amount = Double(query[range]) {
            return AmountFilter(min: nil, max: amount, description: "менее \(formatCurrency(amount))")
        }

        // "between $X and $Y"
        let betweenPattern = "(?:between|от)\s*\$?(\d+)\s*(?:and|до|и)\s*\$?(\d+)"
        if let regex = try? NSRegularExpression(pattern: betweenPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let range1 = Range(match.range(at: 1), in: query),
           let range2 = Range(match.range(at: 2), in: query),
           let min = Double(query[range1]),
           let max = Double(query[range2]) {
            return AmountFilter(min: min, max: max, description: "от \(formatCurrency(min)) до \(formatCurrency(max))")
        }

        return nil
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Category Semantic Resolver

@available(iOS 26.0, *)
final class CategorySemanticResolver {
    private let semanticMappings: [(terms: [String], category: TransactionCategory)] = [
        (["food", "dinner", "lunch", "breakfast", "restaurant", "eat", "dining", "еда", "ужин", "обед", "ресторан"], .foodAndDrink),
        (["grocery", "groceries", "supermarket", "food store", "продукты", "магазин"], .groceries),
        (["transport", "taxi", "uber", "lyft", "bus", "train", "metro", "транспорт", "такси"], .transportation),
        (["shopping", "clothes", "shoes", "buy", "purchase", "магазин", "одежда", "покупки"], .shopping),
        (["entertainment", "movie", "cinema", "game", "fun", "развлечения", "кино", "игры"], .entertainment),
        (["travel", "flight", "hotel", "vacation", "trip", "путешествие", "отель", "рейс"], .travel),
        (["health", "doctor", "pharmacy", "medicine", "gym", "здоровье", "врач", "аптека"], .health),
        (["coffee", "starbucks", "cafe", "кофе", "кафе"], .foodAndDrink),
        (["gas", "fuel", "petrol", "бензин", "топливо"], .gas),
        (["bill", "utility", "electric", "water", "internet", "счет", "коммунальные"], .utilities),
    ]

    func resolve(from query: String) -> [TransactionCategory] {
        var found: [TransactionCategory] = []
        for mapping in semanticMappings {
            if mapping.terms.contains(where: { query.contains($0) }) {
                if !found.contains(mapping.category) {
                    found.append(mapping.category)
                }
            }
        }
        return found
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
public struct SearchIntent {
    public let originalQuery: String
    public let intentType: SearchIntentType
    public let dateRange: DateRange?
    public let amountFilter: AmountFilter?
    public let categories: [TransactionCategory]
    public let merchants: [String]
    public let sortOrder: SortOrder
    public let limit: Int?
    public let confidence: Double
}

@available(iOS 26.0, *)
public enum SearchIntentType {
    case find
    case summarize
    case compare
    case trend
}

@available(iOS 26.0, *)
public struct DateRange {
    public let start: Date
    public let end: Date

    public func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

@available(iOS 26.0, *)
public struct AmountFilter {
    public let min: Double?
    public let max: Double?
    public let description: String

    public func matches(_ amount: Double) -> Bool {
        if let min = min, amount < min { return false }
        if let max = max, amount > max { return false }
        return true
    }
}

@available(iOS 26.0, *)
public enum SortOrder {
    case amountAscending
    case amountDescending
    case dateAscending
    case dateDescending
    case none
}

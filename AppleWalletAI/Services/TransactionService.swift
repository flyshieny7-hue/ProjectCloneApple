import Foundation
import Combine

/// Сервис для работы с транзакциями (Singleton)
@available(iOS 26.0, *)
public final class TransactionService: ObservableObject {

    public static let shared = TransactionService()

    // MARK: - Published
    @Published public var transactions: [Transaction] = []
    @Published public var currentPeriodTransactions: [Transaction] = []

    public var transactionsPublisher: AnyPublisher<[Transaction], Never> {
        $transactions.eraseToAnyPublisher()
    }

    // MARK: - Storage
    private let storageKey = "com.applewallet.transactions"
    private let queue = DispatchQueue(label: "com.applewallet.transactions", qos: .userInitiated)

    private init() {
        loadTransactions()
        updateCurrentPeriod()
    }

    // MARK: - Public API

    public func fetchLast90Days() async -> [Transaction] {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        return transactions.filter { $0.date > cutoff }
    }

    public func fetchLast30Days() async -> [Transaction] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        return transactions.filter { $0.date > cutoff }
    }

    public func fetchCurrentPeriodTransactions() async -> [Transaction] {
        updateCurrentPeriod()
        return currentPeriodTransactions
    }

    public func recentTransactions(hours: Int) -> [Transaction] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return transactions.filter { $0.date > cutoff }
    }

    public func addTransaction(_ transaction: Transaction) {
        transactions.append(transaction)
        saveTransactions()
        updateCurrentPeriod()
    }

    public func addTransactions(_ newTransactions: [Transaction]) {
        transactions.append(contentsOf: newTransactions)
        saveTransactions()
        updateCurrentPeriod()
    }

    public func updateTransaction(_ transaction: Transaction) {
        if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
            transactions[index] = transaction
            saveTransactions()
            updateCurrentPeriod()
        }
    }

    public func deleteTransaction(id: UUID) {
        transactions.removeAll { $0.id == id }
        saveTransactions()
        updateCurrentPeriod()
    }

    public func transactions(for category: TransactionCategory) -> [Transaction] {
        transactions.filter { $0.category == category }
    }

    public func transactions(for merchant: String) -> [Transaction] {
        transactions.filter { $0.merchantName.lowercased().contains(merchant.lowercased()) }
    }

    public func totalSpent(in dateRange: ClosedRange<Date>) -> Double {
        transactions
            .filter { dateRange.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - Demo Data

    public func loadDemoData() {
        let calendar = Calendar.current
        let now = Date()

        let demoTransactions: [Transaction] = [
            Transaction(amount: 5.67, merchantName: "Starbucks", date: now.addingTimeInterval(-3600), category: .foodAndDrink),
            Transaction(amount: 45.20, merchantName: "Whole Foods", date: now.addingTimeInterval(-86400), category: .groceries),
            Transaction(amount: 12.50, merchantName: "Uber", date: now.addingTimeInterval(-172800), category: .transportation),
            Transaction(amount: 89.99, merchantName: "Nike Store", date: now.addingTimeInterval(-259200), category: .shopping),
            Transaction(amount: 15.99, merchantName: "Netflix", date: now.addingTimeInterval(-345600), category: .entertainment),
            Transaction(amount: 5.67, merchantName: "Starbucks", date: now.addingTimeInterval(-432000), category: .foodAndDrink),
            Transaction(amount: 120.00, merchantName: "Shell", date: now.addingTimeInterval(-518400), category: .gas),
            Transaction(amount: 250.00, merchantName: "Delta Airlines", date: now.addingTimeInterval(-604800), category: .travel),
            Transaction(amount: 34.50, merchantName: "CVS Pharmacy", date: now.addingTimeInterval(-691200), category: .health),
            Transaction(amount: 150.00, merchantName: "Electric Company", date: now.addingTimeInterval(-777600), category: .utilities),
            Transaction(amount: 5.67, merchantName: "Starbucks", date: now.addingTimeInterval(-864000), category: .foodAndDrink),
            Transaction(amount: 78.90, merchantName: "Amazon", date: now.addingTimeInterval(-950400), category: .shopping),
            Transaction(amount: 22.00, merchantName: "Movie Theater", date: now.addingTimeInterval(-1036800), category: .entertainment),
            Transaction(amount: 8.50, merchantName: "Starbucks", date: now.addingTimeInterval(-1123200), category: .foodAndDrink),
            Transaction(amount: 55.00, merchantName: "Gym Membership", date: now.addingTimeInterval(-1209600), category: .health),
        ]

        transactions = demoTransactions
        saveTransactions()
        updateCurrentPeriod()
    }

    // MARK: - Private

    private func updateCurrentPeriod() {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return }
        currentPeriodTransactions = transactions.filter { $0.date >= monthStart }
    }

    private func saveTransactions() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let data = try? JSONEncoder().encode(self.transactions) {
                UserDefaults.standard.set(data, forKey: self.storageKey)
            }
        }
    }

    private func loadTransactions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([Transaction].self, from: data) else {
            return
        }
        transactions = loaded
    }
}

import Foundation
import CoreData
import Combine
import CloudKit

/// Менеджер офлайн-хранилища с полной функциональностью без интернета
/// iOS 26, CoreData + sync queue, conflict resolution, background sync
@MainActor
final class OfflineStorage: ObservableObject {

    // MARK: - Singleton
    static let shared = OfflineStorage()

    // MARK: - Published Properties
    @Published var isOffline: Bool = false
    @Published var pendingChangesCount: Int = 0
    @Published var lastOfflineDate: Date?
    @Published var syncQueueStatus: SyncQueueStatus = .empty
    @Published var storageSize: Int64 = 0

    // MARK: - Types
    enum SyncQueueStatus: String {
        case empty = "Empty"
        case processing = "Processing"
        case failed = "Failed"
        case synced = "Synced"
    }

    enum OfflineError: LocalizedError {
        case storageFull
        case saveFailed
        case syncQueueCorrupted
        case conflictResolutionFailed
        case dataMigrationFailed
        case encryptionFailed
        case maxQueueSizeExceeded

        var errorDescription: String? {
            switch self {
            case .storageFull: return "Local storage is full"
            case .saveFailed: return "Failed to save data locally"
            case .syncQueueCorrupted: return "Sync queue data is corrupted"
            case .conflictResolutionFailed: return "Failed to resolve sync conflict"
            case .dataMigrationFailed: return "Failed to migrate local data"
            case .encryptionFailed: return "Failed to encrypt sensitive data"
            case .maxQueueSizeExceeded: return "Maximum sync queue size exceeded"
            }
        }
    }

    struct PendingChange: Codable, Identifiable {
        let id: String
        let recordType: String
        let recordID: String
        let operation: ChangeOperation
        let data: Data
        let timestamp: Date
        let retryCount: Int
        let lastError: String?

        enum ChangeOperation: String, Codable {
            case create = "create"
            case update = "update"
            case delete = "delete"
        }
    }

    // MARK: - Constants
    private enum Constants {
        static let maxQueueSize = 5000
        static let maxStorageSize: Int64 = 500 * 1024 * 1024 // 500MB
        static let syncQueueKey = "com.wallet.offline.syncQueue"
        static let pendingCardsKey = "com.wallet.offline.pendingCards"
        static let pendingTransactionsKey = "com.wallet.offline.pendingTransactions"
        static let pendingBudgetsKey = "com.wallet.offline.pendingBudgets"
        static let cleanupInterval: TimeInterval = 86400 // 24 hours
        static let maxRetryCount = 5
        static let retryBackoffBase: TimeInterval = 2.0
    }

    // MARK: - Properties
    private let container: NSPersistentContainer
    private var syncQueue: [PendingChange] = []
    private let queueLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    private let backgroundQueue = DispatchQueue(label: "com.wallet.offline", qos: .utility)
    private var cleanupTimer: Timer?

    // MARK: - Initialization
    private init() {
        self.container = CoreDataStack.shared.container
        loadSyncQueue()
        observeNetworkChanges()
        setupStorageMonitoring()
        startCleanupTimer()
    }

    // MARK: - Network Observation

    private func observeNetworkChanges() {
        NotificationCenter.default.publisher(for: .NWPathUpdate)
            .sink { [weak self] notification in
                guard let path = notification.object as? NWPath else { return }
                let isOnline = path.status == .satisfied

                Task { @MainActor in
                    self?.isOffline = !isOnline

                    if isOnline {
                        self?.lastOfflineDate = nil
                        // Пытаемся синхронизировать накопленные изменения
                        await self?.processSyncQueue()
                    } else {
                        self?.lastOfflineDate = Date()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func setupStorageMonitoring() {
        updateStorageSize()

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStorageSize()
            }
        }
    }

    private func updateStorageSize() {
        let storeURL = container.persistentStoreDescriptions.first?.url
        if let url = storeURL {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                storageSize = attributes[.size] as? Int64 ?? 0
            } catch {
                storageSize = 0
            }
        }
    }

    // MARK: - CoreData Operations (Offline)

    /// Сохраняет карту локально
    func saveCard(_ card: CardModel) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let entity = Card(context: context)
            entity.id = card.id
            entity.cardNumber = card.cardNumber
            entity.cardHolderName = card.cardHolderName
            entity.expirationDate = card.expirationDate
            entity.cardType = card.cardType.rawValue
            entity.balance = card.balance
            entity.currency = card.currency
            entity.isActive = card.isActive
            entity.lastModified = Date()
            entity.isPendingSync = true

            try context.save()
        }

        // Добавляем в очередь синхронизации
        try await queueChange(
            recordType: "WalletCard",
            recordID: card.id,
            operation: .create,
            data: try JSONEncoder().encode(card)
        )

        AnalyticsCollector.shared.logEvent("card_saved_offline")
    }

    /// Сохраняет транзакцию локально
    func saveTransaction(_ transaction: TransactionModel) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let entity = Transaction(context: context)
            entity.id = transaction.id
            entity.amount = transaction.amount
            entity.currency = transaction.currency
            entity.merchantName = transaction.merchantName
            entity.category = transaction.category.rawValue
            entity.transactionDate = transaction.date
            entity.transactionType = transaction.type.rawValue
            entity.status = transaction.status.rawValue
            entity.lastModified = Date()
            entity.isPendingSync = true

            try context.save()
        }

        try await queueChange(
            recordType: "WalletTransaction",
            recordID: transaction.id,
            operation: .create,
            data: try JSONEncoder().encode(transaction)
        )

        // Обновляем бюджет локально
        await updateBudgetForTransaction(transaction)

        AnalyticsCollector.shared.logEvent("transaction_saved_offline")
    }

    /// Сохраняет бюджет локально
    func saveBudget(_ budget: BudgetModel) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let entity = Budget(context: context)
            entity.id = budget.id
            entity.name = budget.name
            entity.limit = budget.limit
            entity.spent = budget.spent
            entity.period = budget.period.rawValue
            entity.startDate = budget.startDate
            entity.endDate = budget.endDate
            entity.category = budget.category?.rawValue
            entity.isActive = budget.isActive
            entity.lastModified = Date()
            entity.isPendingSync = true

            try context.save()
        }

        try await queueChange(
            recordType: "WalletBudget",
            recordID: budget.id,
            operation: .create,
            data: try JSONEncoder().encode(budget)
        )

        AnalyticsCollector.shared.logEvent("budget_saved_offline")
    }

    /// Обновляет существующую запись
    func updateEntity<T: NSManagedObject>(
        type: T.Type,
        id: String,
        updates: @escaping (T) -> Void
    ) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let fetchRequest = T.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            fetchRequest.fetchLimit = 1

            guard let entity = try context.fetch(fetchRequest).first as? T else {
                throw OfflineError.saveFailed
            }

            updates(entity)

            if let syncable = entity as? SyncableEntity {
                syncable.isPendingSync = true
                syncable.lastModified = Date()
            }

            try context.save()
        }

        // Добавляем в очередь
        try await queueChange(
            recordType: String(describing: type),
            recordID: id,
            operation: .update,
            data: Data()
        )
    }

    /// Удаляет запись локально
    func deleteEntity<T: NSManagedObject>(type: T.Type, id: String) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let fetchRequest = T.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)

            let entities = try context.fetch(fetchRequest)
            for entity in entities {
                context.delete(entity)
            }

            try context.save()
        }

        try await queueChange(
            recordType: String(describing: type),
            recordID: id,
            operation: .delete,
            data: Data()
        )
    }

    // MARK: - Sync Queue Management

    private func queueChange(
        recordType: String,
        recordID: String,
        operation: PendingChange.ChangeOperation,
        data: Data
    ) async throws {
        queueLock.lock()
        defer { queueLock.unlock() }

        guard syncQueue.count < Constants.maxQueueSize else {
            throw OfflineError.maxQueueSizeExceeded
        }

        // Проверяем на дубликаты
        if let existingIndex = syncQueue.firstIndex(where: {
            $0.recordID == recordID && $0.recordType == recordType
        }) {
            // Обновляем существующую запись
            let existing = syncQueue[existingIndex]
            let updated = PendingChange(
                id: existing.id,
                recordType: recordType,
                recordID: recordID,
                operation: operation,
                data: data,
                timestamp: Date(),
                retryCount: existing.retryCount,
                lastError: existing.lastError
            )
            syncQueue[existingIndex] = updated
        } else {
            let change = PendingChange(
                id: UUID().uuidString,
                recordType: recordType,
                recordID: recordID,
                operation: operation,
                data: data,
                timestamp: Date(),
                retryCount: 0,
                lastError: nil
            )
            syncQueue.append(change)
        }

        pendingChangesCount = syncQueue.count
        syncQueueStatus = .processing

        // Сохраняем очередь
        try saveSyncQueue()
    }

    /// Обрабатывает очередь синхронизации
    func processSyncQueue() async {
        guard !syncQueue.isEmpty else {
            syncQueueStatus = .empty
            return
        }

        guard !isOffline else {
            syncQueueStatus = .failed
            return
        }

        syncQueueStatus = .processing

        var processedCount = 0
        var failedChanges: [PendingChange] = []

        for change in syncQueue {
            do {
                try await processChange(change)
                processedCount += 1
            } catch {
                var updatedChange = change
                updatedChange.retryCount += 1

                if updatedChange.retryCount < Constants.maxRetryCount {
                    let delay = Constants.retryBackoffBase * pow(2.0, Double(updatedChange.retryCount))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    failedChanges.append(updatedChange)
                } else {
                    // Max retries reached, log error
                    AnalyticsCollector.shared.logError(error, context: "SyncQueueMaxRetries")
                }
            }
        }

        queueLock.lock()
        syncQueue = failedChanges
        pendingChangesCount = syncQueue.count
        queueLock.unlock()

        syncQueueStatus = failedChanges.isEmpty ? .synced : .failed

        try? saveSyncQueue()

        AnalyticsCollector.shared.logEvent("sync_queue_processed", parameters: [
            "processed": processedCount,
            "failed": failedChanges.count
        ])
    }

    private func processChange(_ change: PendingChange) async throws {
        switch change.operation {
        case .create, .update:
            let record = CKRecord(recordType: change.recordType, recordID: CKRecord.ID(recordName: change.recordID))

            // Десериализуем данные
            if !change.data.isEmpty {
                if change.recordType == "WalletCard" {
                    let card = try JSONDecoder().decode(CardModel.self, from: change.data)
                    populateCardRecord(record, from: card)
                } else if change.recordType == "WalletTransaction" {
                    let transaction = try JSONDecoder().decode(TransactionModel.self, from: change.data)
                    populateTransactionRecord(record, from: transaction)
                } else if change.recordType == "WalletBudget" {
                    let budget = try JSONDecoder().decode(BudgetModel.self, from: change.data)
                    populateBudgetRecord(record, from: budget)
                }
            }

            let (saveResult, _) = try await CloudKitManager.shared.privateDatabase.modifyRecords(
                saving: [record],
                deleting: [],
                atomically: true
            )

            for result in saveResult {
                if case .failure(let error) = result.1 {
                    throw error
                }
            }

        case .delete:
            let recordID = CKRecord.ID(recordName: change.recordID)
            let (_, deleteResults) = try await CloudKitManager.shared.privateDatabase.modifyRecords(
                saving: [],
                deleting: [recordID],
                atomically: true
            )

            for result in deleteResults {
                if case .failure(let error) = result.1 {
                    throw error
                }
            }
        }

        // Отмечаем как синхронизированное локально
        await markAsSynced(recordID: change.recordID, recordType: change.recordType)
    }

    private func markAsSynced(recordID: String, recordType: String) async {
        let context = container.newBackgroundContext()

        await context.perform {
            let fetchRequest: NSFetchRequest<NSManagedObject>

            switch recordType {
            case "WalletCard":
                fetchRequest = Card.fetchRequest()
            case "WalletTransaction":
                fetchRequest = Transaction.fetchRequest()
            case "WalletBudget":
                fetchRequest = Budget.fetchRequest()
            default:
                return
            }

            fetchRequest.predicate = NSPredicate(format: "id == %@", recordID)

            do {
                if let entity = try context.fetch(fetchRequest).first as? SyncableEntity {
                    entity.isPendingSync = false
                    entity.lastSyncDate = Date()
                    try context.save()
                }
            } catch {
                AnalyticsCollector.shared.logError(error, context: "MarkAsSynced")
            }
        }
    }

    // MARK: - Data Retrieval (Offline)

    func getPendingCards() async throws -> [CKRecord] {
        let context = container.newBackgroundContext()

        return try await context.perform {
            let fetchRequest: NSFetchRequest<Card> = Card.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isPendingSync == YES")

            let cards = try context.fetch(fetchRequest)
            return cards.compactMap { card in
                guard let recordID = card.cloudKitRecordID else { return nil }
                let record = CKRecord(recordType: "WalletCard", recordID: CKRecord.ID(recordName: recordID))
                self.populateCardRecord(record, from: card)
                return record
            }
        }
    }

    func getPendingTransactions() async throws -> [CKRecord] {
        let context = container.newBackgroundContext()

        return try await context.perform {
            let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isPendingSync == YES")

            let transactions = try context.fetch(fetchRequest)
            return transactions.compactMap { transaction in
                guard let recordID = transaction.cloudKitRecordID else { return nil }
                let record = CKRecord(recordType: "WalletTransaction", recordID: CKRecord.ID(recordName: recordID))
                self.populateTransactionRecord(record, from: transaction)
                return record
            }
        }
    }

    func getPendingBudgets() async throws -> [CKRecord] {
        let context = container.newBackgroundContext()

        return try await context.perform {
            let fetchRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isPendingSync == YES")

            let budgets = try context.fetch(fetchRequest)
            return budgets.compactMap { budget in
                guard let recordID = budget.cloudKitRecordID else { return nil }
                let record = CKRecord(recordType: "WalletBudget", recordID: CKRecord.ID(recordName: recordID))
                self.populateBudgetRecord(record, from: budget)
                return record
            }
        }
    }

    // MARK: - Budget Updates

    private func updateBudgetForTransaction(_ transaction: TransactionModel) async {
        guard transaction.type == .expense else { return }

        let context = container.newBackgroundContext()

        await context.perform {
            let fetchRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "category == %@ AND isActive == YES",
                transaction.category.rawValue
            )

            do {
                let budgets = try context.fetch(fetchRequest)
                for budget in budgets {
                    budget.spent += transaction.amount
                    budget.isPendingSync = true
                    budget.lastModified = Date()
                }
                try context.save()
            } catch {
                AnalyticsCollector.shared.logError(error, context: "BudgetUpdate")
            }
        }
    }

    // MARK: - Sync Queue Persistence

    private func saveSyncQueue() throws {
        let data = try JSONEncoder().encode(syncQueue)
        UserDefaults.standard.set(data, forKey: Constants.syncQueueKey)
    }

    private func loadSyncQueue() {
        guard let data = UserDefaults.standard.data(forKey: Constants.syncQueueKey) else { return }

        do {
            syncQueue = try JSONDecoder().decode([PendingChange].self, from: data)
            pendingChangesCount = syncQueue.count
        } catch {
            syncQueue = []
            AnalyticsCollector.shared.logError(error, context: "LoadSyncQueue")
        }
    }

    /// Очищает очередь после успешной синхронизации
    func clearPendingChanges() async {
        queueLock.lock()
        syncQueue.removeAll()
        pendingChangesCount = 0
        queueLock.unlock()

        try? saveSyncQueue()
        syncQueueStatus = .empty
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: Constants.cleanupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.cleanupOldData()
            }
        }
    }

    private func cleanupOldData() async {
        let context = container.newBackgroundContext()
        let cutoffDate = Date(timeIntervalSinceNow: -90 * 86400) // 90 days

        await context.perform {
            // Удаляем старые синхронизированные транзакции
            let transactionFetch: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            transactionFetch.predicate = NSPredicate(
                format: "isPendingSync == NO AND transactionDate < %@",
                cutoffDate as NSDate
            )

            do {
                let oldTransactions = try context.fetch(transactionFetch)
                for transaction in oldTransactions {
                    context.delete(transaction)
                }

                try context.save()

                AnalyticsCollector.shared.logEvent("old_data_cleaned", parameters: [
                    "transactions_removed": oldTransactions.count
                ])
            } catch {
                AnalyticsCollector.shared.logError(error, context: "CleanupOldData")
            }
        }

        updateStorageSize()
    }

    // MARK: - Record Population Helpers

    private func populateCardRecord(_ record: CKRecord, from card: CardModel) {
        record["cardNumber"] = card.cardNumber
        record["cardHolderName"] = card.cardHolderName
        record["expirationDate"] = card.expirationDate
        record["cardType"] = card.cardType.rawValue
        record["balance"] = card.balance
        record["currency"] = card.currency
        record["isActive"] = card.isActive
    }

    private func populateCardRecord(_ record: CKRecord, from card: Card) {
        record["cardNumber"] = card.cardNumber
        record["cardHolderName"] = card.cardHolderName
        record["expirationDate"] = card.expirationDate
        record["cardType"] = card.cardType
        record["balance"] = card.balance
        record["currency"] = card.currency
        record["isActive"] = card.isActive
    }

    private func populateTransactionRecord(_ record: CKRecord, from transaction: TransactionModel) {
        record["amount"] = transaction.amount
        record["currency"] = transaction.currency
        record["merchantName"] = transaction.merchantName
        record["category"] = transaction.category.rawValue
        record["transactionDate"] = transaction.date
        record["transactionType"] = transaction.type.rawValue
        record["status"] = transaction.status.rawValue
    }

    private func populateTransactionRecord(_ record: CKRecord, from transaction: Transaction) {
        record["amount"] = transaction.amount
        record["currency"] = transaction.currency
        record["merchantName"] = transaction.merchantName
        record["category"] = transaction.category
        record["transactionDate"] = transaction.transactionDate
        record["transactionType"] = transaction.transactionType
        record["status"] = transaction.status
    }

    private func populateBudgetRecord(_ record: CKRecord, from budget: BudgetModel) {
        record["name"] = budget.name
        record["limit"] = budget.limit
        record["spent"] = budget.spent
        record["period"] = budget.period.rawValue
        record["startDate"] = budget.startDate
        record["endDate"] = budget.endDate
        record["category"] = budget.category?.rawValue
        record["isActive"] = budget.isActive
    }

    private func populateBudgetRecord(_ record: CKRecord, from budget: Budget) {
        record["name"] = budget.name
        record["limit"] = budget.limit
        record["spent"] = budget.spent
        record["period"] = budget.period
        record["startDate"] = budget.startDate
        record["endDate"] = budget.endDate
        record["category"] = budget.category
        record["isActive"] = budget.isActive
    }
}

// MARK: - Protocols
protocol SyncableEntity {
    var isPendingSync: Bool { get set }
    var lastSyncDate: Date? { get set }
    var lastModified: Date? { get set }
}

// MARK: - Model Types
struct CardModel: Codable {
    let id: String
    let cardNumber: String
    let cardHolderName: String
    let expirationDate: Date
    let cardType: CardType
    let balance: Double
    let currency: String
    let isActive: Bool

    enum CardType: String, Codable {
        case credit, debit, prepaid, virtual
    }
}

struct TransactionModel: Codable {
    let id: String
    let amount: Double
    let currency: String
    let merchantName: String
    let category: Category
    let date: Date
    let type: TransactionType
    let status: TransactionStatus

    enum Category: String, Codable {
        case food, transport, entertainment, shopping, bills, health, other
    }

    enum TransactionType: String, Codable {
        case income, expense, transfer
    }

    enum TransactionStatus: String, Codable {
        case pending, completed, failed, reversed
    }
}

struct BudgetModel: Codable {
    let id: String
    let name: String
    let limit: Double
    let spent: Double
    let period: Period
    let startDate: Date
    let endDate: Date
    let category: Category?
    let isActive: Bool

    enum Period: String, Codable {
        case daily, weekly, monthly, yearly
    }

    enum Category: String, Codable {
        case food, transport, entertainment, shopping, bills, health, other
    }
}

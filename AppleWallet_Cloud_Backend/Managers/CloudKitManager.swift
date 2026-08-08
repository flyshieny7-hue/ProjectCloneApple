import Foundation
import CloudKit
import CoreData
import Combine

/// Менеджер синхронизации с CloudKit для карт, транзакций и бюджетов
/// iOS 26, использует CKDatabase, CKRecordZone, CKSubscription
@MainActor
final class CloudKitManager: ObservableObject {

    // MARK: - Singleton
    static let shared = CloudKitManager()

    // MARK: - Published Properties
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var isCloudKitAvailable: Bool = false
    @Published var pendingChangesCount: Int = 0

    // MARK: - Types
    enum SyncStatus: Equatable {
        case idle
        case syncing(percentage: Double)
        case completed
        case failed(Error)
        case offline

        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.completed, .completed), (.offline, .offline):
                return true
            case (.syncing(let p1), .syncing(let p2)):
                return p1 == p2
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    enum CloudKitError: LocalizedError {
        case accountNotAvailable
        case networkUnavailable
        case quotaExceeded
        case conflictResolutionFailed
        case recordNotFound
        case batchOperationFailed([Error])
        case zoneNotFound
        case subscriptionFailed
        case decryptionFailed
        case maxRetriesExceeded

        var errorDescription: String? {
            switch self {
            case .accountNotAvailable: return "iCloud account not available"
            case .networkUnavailable: return "Network connection unavailable"
            case .quotaExceeded: return "iCloud storage quota exceeded"
            case .conflictResolutionFailed: return "Failed to resolve sync conflict"
            case .recordNotFound: return "Record not found in CloudKit"
            case .batchOperationFailed: return "Batch operation failed"
            case .zoneNotFound: return "Custom zone not found"
            case .subscriptionFailed: return "Failed to create subscription"
            case .decryptionFailed: return "Failed to decrypt sensitive data"
            case .maxRetriesExceeded: return "Maximum retry attempts exceeded"
            }
        }
    }

    // MARK: - Constants
    private enum Constants {
        static let zoneName = "WalletZone"
        static let cardsRecordType = "WalletCard"
        static let transactionsRecordType = "WalletTransaction"
        static let budgetsRecordType = "WalletBudget"
        static let syncTokenKey = "CloudKitSyncToken"
        static let maxRetries = 5
        static let baseRetryDelay: TimeInterval = 1.0
        static let maxRetryDelay: TimeInterval = 60.0
        static let batchSize = 400
        static let syncInterval: TimeInterval = 300 // 5 minutes
    }

    // MARK: - Properties
    private let container: NSPersistentContainer
    private let cloudContainer: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase?
    private var customZone: CKRecordZone?
    private var cancellables = Set<AnyCancellable>()
    private let syncQueue = DispatchQueue(label: "com.wallet.cloudkit.sync", qos: .userInitiated)
    private var retryCount = 0
    private var syncTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Initialization
    private init() {
        self.container = CoreDataStack.shared.container
        self.cloudContainer = CKContainer.default()
        self.privateDatabase = cloudContainer.privateCloudDatabase
        self.sharedDatabase = cloudContainer.sharedCloudDatabase

        setupCloudKit()
        setupPeriodicSync()
        observeNetworkChanges()
    }

    // MARK: - Setup
    private func setupCloudKit() {
        Task { @MainActor in
            do {
                let status = try await cloudContainer.accountStatus()
                isCloudKitAvailable = (status == .available)

                if isCloudKitAvailable {
                    try await setupCustomZone()
                    try await setupSubscriptions()
                    try await initialSync()
                }
            } catch {
                syncStatus = .failed(error)
                AnalyticsCollector.shared.logError(error, context: "CloudKitSetup")
            }
        }
    }

    private func setupCustomZone() async throws {
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        let (saveResult, _) = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])

        for result in saveResult {
            switch result {
            case .success(let savedZone):
                customZone = savedZone
            case .failure(let error):
                throw CloudKitError.zoneNotFound
            }
        }
    }

    private func setupSubscriptions() async throws {
        guard let zone = customZone else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: "wallet-changes")
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let (saveResult, _) = try await privateDatabase.modifySubscriptions(
            saving: [subscription],
            deleting: []
        )

        for result in saveResult {
            if case .failure(let error) = result {
                throw CloudKitError.subscriptionFailed
            }
        }
    }

    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: Constants.syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performSync()
            }
        }
    }

    private func observeNetworkChanges() {
        NotificationCenter.default.publisher(for: .NWPathUpdate)
            .sink { [weak self] notification in
                guard let path = notification.object as? NWPath else { return }
                if path.status == .satisfied {
                    Task { @MainActor in
                        await self?.performSync()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Sync Methods

    /// Выполняет полную синхронизацию всех данных
    func performSync() async {
        guard isCloudKitAvailable else {
            syncStatus = .offline
            return
        }

        beginBackgroundTask()
        defer { endBackgroundTask() }

        syncStatus = .syncing(percentage: 0)

        do {
            // Синхронизация карт
            try await syncCards()
            syncStatus = .syncing(percentage: 33)

            // Синхронизация транзакций
            try await syncTransactions()
            syncStatus = .syncing(percentage: 66)

            // Синхронизация бюджетов
            try await syncBudgets()
            syncStatus = .syncing(percentage: 100)

            lastSyncDate = Date()
            syncStatus = .completed
            retryCount = 0

            // Очищаем очередь офлайн-изменений
            await OfflineStorage.shared.clearPendingChanges()

        } catch {
            await handleSyncError(error)
        }
    }

    /// Синхронизация карт
    func syncCards() async throws {
        let context = container.newBackgroundContext()

        // Получаем локальные изменения
        let pendingCards = try await OfflineStorage.shared.getPendingCards()

        // Загружаем удаленные изменения
        let remoteChanges = try await fetchRemoteChanges(recordType: Constants.cardsRecordType)

        // Разрешаем конфликты
        try await resolveConflicts(
            local: pendingCards,
            remote: remoteChanges,
            in: context
        )

        // Отправляем локальные изменения
        try await uploadRecords(pendingCards, recordType: Constants.cardsRecordType)
    }

    /// Синхронизация транзакций
    func syncTransactions() async throws {
        let pendingTransactions = try await OfflineStorage.shared.getPendingTransactions()
        let remoteChanges = try await fetchRemoteChanges(recordType: Constants.transactionsRecordType)

        let context = container.newBackgroundContext()
        try await resolveConflicts(
            local: pendingTransactions,
            remote: remoteChanges,
            in: context
        )

        try await uploadRecords(pendingTransactions, recordType: Constants.transactionsRecordType)
    }

    /// Синхронизация бюджетов
    func syncBudgets() async throws {
        let pendingBudgets = try await OfflineStorage.shared.getPendingBudgets()
        let remoteChanges = try await fetchRemoteChanges(recordType: Constants.budgetsRecordType)

        let context = container.newBackgroundContext()
        try await resolveConflicts(
            local: pendingBudgets,
            remote: remoteChanges,
            in: context
        )

        try await uploadRecords(pendingBudgets, recordType: Constants.budgetsRecordType)
    }

    // MARK: - Fetch Operations

    private func fetchRemoteChanges(recordType: String) async throws -> [CKRecord] {
        guard let zone = customZone else {
            throw CloudKitError.zoneNotFound
        }

        var allRecords: [CKRecord] = []
        var continuationToken: CKQueryOperation.Cursor?

        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

        repeat {
            let (matchResults, cursor) = try await privateDatabase.records(
                matching: query,
                inZoneWith: zone.zoneID,
                resultsLimit: Constants.batchSize
            )

            for result in matchResults {
                switch result.1 {
                case .success(let record):
                    allRecords.append(record)
                case .failure(let error):
                    AnalyticsCollector.shared.logError(error, context: "FetchRemote\(recordType)")
                }
            }

            continuationToken = cursor
        } while continuationToken != nil

        return allRecords
    }

    // MARK: - Upload Operations

    private func uploadRecords(_ records: [CKRecord], recordType: String) async throws {
        guard !records.isEmpty else { return }

        // Батчинг для оптимизации
        let batches = records.chunked(into: Constants.batchSize)

        for batch in batches {
            let (saveResults, _) = try await privateDatabase.modifyRecords(
                saving: batch,
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )

            var errors: [Error] = []
            for result in saveResults {
                if case .failure(let error) = result.1 {
                    errors.append(error)
                }
            }

            if !errors.isEmpty {
                throw CloudKitError.batchOperationFailed(errors)
            }
        }
    }

    // MARK: - Conflict Resolution

    private func resolveConflicts(
        local: [CKRecord],
        remote: [CKRecord],
        in context: NSManagedObjectContext
    ) async throws {
        let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.recordID, $0) })
        let remoteDict = Dictionary(uniqueKeysWithValues: remote.map { ($0.recordID, $0) })

        // Обрабатываем конфликты по каждой записи
        for (recordID, remoteRecord) in remoteDict {
            if let localRecord = localDict[recordID] {
                // Конфликт: выбираем запись с более поздней датой модификации
                let localDate = localRecord.modificationDate ?? Date.distantPast
                let remoteDate = remoteRecord.modificationDate ?? Date.distantPast

                if remoteDate > localDate {
                    // Удаленная версия новее
                    try await applyRemoteRecord(remoteRecord, in: context)
                } else {
                    // Локальная версия новее, оставляем как есть
                    // Она будет отправлена при следующей синхронизации
                }
            } else {
                // Только удаленная запись
                try await applyRemoteRecord(remoteRecord, in: context)
            }
        }

        // Удаляем локальные записи, которых нет в удаленных (если не помечены как удаленные)
        for (recordID, localRecord) in localDict where remoteDict[recordID] == nil {
            if let deletionDate = localRecord.value(forKey: "deletionDate") as? Date {
                // Локально удалена, отправляем удаление
                try await deleteRemoteRecord(recordID)
            }
        }

        try context.save()
    }

    private func applyRemoteRecord(_ record: CKRecord, in context: NSManagedObjectContext) async throws {
        await context.perform {
            // Преобразуем CKRecord в CoreData entity
            switch record.recordType {
            case Constants.cardsRecordType:
                self.updateCard(from: record, in: context)
            case Constants.transactionsRecordType:
                self.updateTransaction(from: record, in: context)
            case Constants.budgetsRecordType:
                self.updateBudget(from: record, in: context)
            default:
                break
            }
        }
    }

    private func updateCard(from record: CKRecord, in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Card> = Card.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "cloudKitRecordID == %@", record.recordID.recordName)

        do {
            let cards = try context.fetch(fetchRequest)
            let card = cards.first ?? Card(context: context)

            card.cloudKitRecordID = record.recordID.recordName
            card.cardNumber = record.encryptedString(forKey: "cardNumber")
            card.cardHolderName = record.string(forKey: "cardHolderName")
            card.expirationDate = record.date(forKey: "expirationDate")
            card.cardType = record.string(forKey: "cardType")
            card.balance = record.double(forKey: "balance")
            card.currency = record.string(forKey: "currency")
            card.isActive = record.bool(forKey: "isActive")
            card.lastModified = record.modificationDate

        } catch {
            AnalyticsCollector.shared.logError(error, context: "UpdateCard")
        }
    }

    private func updateTransaction(from record: CKRecord, in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "cloudKitRecordID == %@", record.recordID.recordName)

        do {
            let transactions = try context.fetch(fetchRequest)
            let transaction = transactions.first ?? Transaction(context: context)

            transaction.cloudKitRecordID = record.recordID.recordName
            transaction.amount = record.double(forKey: "amount")
            transaction.currency = record.string(forKey: "currency")
            transaction.merchantName = record.string(forKey: "merchantName")
            transaction.category = record.string(forKey: "category")
            transaction.transactionDate = record.date(forKey: "transactionDate")
            transaction.transactionType = record.string(forKey: "transactionType")
            transaction.status = record.string(forKey: "status")
            transaction.lastModified = record.modificationDate

        } catch {
            AnalyticsCollector.shared.logError(error, context: "UpdateTransaction")
        }
    }

    private func updateBudget(from record: CKRecord, in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "cloudKitRecordID == %@", record.recordID.recordName)

        do {
            let budgets = try context.fetch(fetchRequest)
            let budget = budgets.first ?? Budget(context: context)

            budget.cloudKitRecordID = record.recordID.recordName
            budget.name = record.string(forKey: "name")
            budget.limit = record.double(forKey: "limit")
            budget.spent = record.double(forKey: "spent")
            budget.period = record.string(forKey: "period")
            budget.startDate = record.date(forKey: "startDate")
            budget.endDate = record.date(forKey: "endDate")
            budget.category = record.string(forKey: "category")
            budget.lastModified = record.modificationDate

        } catch {
            AnalyticsCollector.shared.logError(error, context: "UpdateBudget")
        }
    }

    private func deleteRemoteRecord(_ recordID: CKRecord.ID) async throws {
        let (_, _) = try await privateDatabase.modifyRecords(
            saving: [],
            deleting: [recordID],
            atomically: true
        )
    }

    // MARK: - Error Handling & Retry

    private func handleSyncError(_ error: Error) async {
        let ckError = error as? CKError

        switch ckError?.code {
        case .networkUnavailable, .networkFailure:
            syncStatus = .offline
            // Сохраняем для будущей синхронизации
            await OfflineStorage.shared.queuePendingSync()

        case .quotaExceeded:
            syncStatus = .failed(CloudKitError.quotaExceeded)
            // Уведомляем пользователя
            await PushNotificationManager.shared.sendLocalNotification(
                title: "iCloud Storage Full",
                body: "Unable to sync wallet data. Please free up iCloud storage.",
                category: .syncError
            )

        case .serverRecordChanged:
            // Конфликт, пробуем разрешить
            if retryCount < Constants.maxRetries {
                retryCount += 1
                let delay = min(Constants.baseRetryDelay * pow(2.0, Double(retryCount)), Constants.maxRetryDelay)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await performSync()
            } else {
                syncStatus = .failed(CloudKitError.maxRetriesExceeded)
            }

        default:
            syncStatus = .failed(error)
            AnalyticsCollector.shared.logError(error, context: "CloudKitSync")

            // Экспоненциальный бэкофф
            if retryCount < Constants.maxRetries {
                retryCount += 1
                let delay = min(Constants.baseRetryDelay * pow(2.0, Double(retryCount)), Constants.maxRetryDelay)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await performSync()
            }
        }
    }

    // MARK: - Background Tasks

    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // MARK: - Encryption Helpers

    private func encryptSensitiveData(_ data: String) -> Data? {
        guard let dataToEncrypt = data.data(using: .utf8) else { return nil }

        do {
            let encrypted = try iCloudKeychainSync.shared.encrypt(dataToEncrypt)
            return encrypted
        } catch {
            AnalyticsCollector.shared.logError(error, context: "Encryption")
            return nil
        }
    }

    private func decryptSensitiveData(_ data: Data) -> String? {
        do {
            let decrypted = try iCloudKeychainSync.shared.decrypt(data)
            return String(data: decrypted, encoding: .utf8)
        } catch {
            AnalyticsCollector.shared.logError(error, context: "Decryption")
            return nil
        }
    }

    // MARK: - Cleanup

    deinit {
        syncTimer?.invalidate()
        endBackgroundTask()
    }
}

// MARK: - CKRecord Extensions
extension CKRecord {
    func encryptedString(forKey key: String) -> String? {
        guard let data = self.value(forKey: key) as? Data else { return nil }
        return CloudKitManager.shared.decryptSensitiveData(data)
    }

    func string(forKey key: String) -> String? {
        return self.value(forKey: key) as? String
    }

    func date(forKey key: String) -> Date? {
        return self.value(forKey: key) as? Date
    }

    func double(forKey key: String) -> Double {
        return self.value(forKey: key) as? Double ?? 0.0
    }

    func bool(forKey key: String) -> Bool {
        return self.value(forKey: key) as? Bool ?? false
    }
}

// MARK: - Array Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

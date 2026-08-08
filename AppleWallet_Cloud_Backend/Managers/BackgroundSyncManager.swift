import Foundation
import BackgroundTasks
import CloudKit
import CoreData
import Combine

/// Менеджер фоновой синхронизации для обновления баланса и транзакций
/// iOS 26, использует BGTaskScheduler, silent push, background fetch
@MainActor
final class BackgroundSyncManager: ObservableObject {

    // MARK: - Singleton
    static let shared = BackgroundSyncManager()

    // MARK: - Published Properties
    @Published var lastBackgroundSync: Date?
    @Published var isBackgroundSyncEnabled: Bool = true
    @Published var backgroundSyncFrequency: SyncFrequency = .balanced
    @Published var pendingSyncOperations: Int = 0

    // MARK: - Types
    enum SyncFrequency: String, CaseIterable {
        case aggressive = "Aggressive"
        case balanced = "Balanced"
        case conservative = "Conservative"
        case manual = "Manual"

        var interval: TimeInterval {
            switch self {
            case .aggressive: return 300      // 5 minutes
            case .balanced: return 900        // 15 minutes
            case .conservative: return 3600   // 1 hour
            case .manual: return 0
            }
        }

        var backgroundTaskIdentifier: String {
            switch self {
            case .aggressive: return "com.wallet.sync.aggressive"
            case .balanced: return "com.wallet.sync.balanced"
            case .conservative: return "com.wallet.sync.conservative"
            case .manual: return "com.wallet.sync.manual"
            }
        }
    }

    enum BackgroundSyncError: LocalizedError {
        case taskRegistrationFailed
        case syncAlreadyInProgress
        case insufficientBattery
        case networkConstraints
        case dataProcessingFailed
        case maxAttemptsReached

        var errorDescription: String? {
            switch self {
            case .taskRegistrationFailed: return "Failed to register background task"
            case .syncAlreadyInProgress: return "Background sync already in progress"
            case .insufficientBattery: return "Battery too low for background sync"
            case .networkConstraints: return "Network constraints prevent sync"
            case .dataProcessingFailed: return "Failed to process synced data"
            case .maxAttemptsReached: return "Maximum sync attempts reached"
            }
        }
    }

    // MARK: - Constants
    private enum Constants {
        static let balanceSyncTaskIdentifier = "com.wallet.background.balanceSync"
        static let transactionSyncTaskIdentifier = "com.wallet.background.transactionSync"
        static let budgetSyncTaskIdentifier = "com.wallet.background.budgetSync"
        static let maxSyncDuration: TimeInterval = 25 // iOS limit ~30s
        static let batteryThreshold: Float = 0.20
        static let retryAttempts = 3
        static let exponentialBackoffBase: TimeInterval = 5.0
    }

    // MARK: - Properties
    private var cancellables = Set<AnyCancellable>()
    private let syncQueue = OperationQueue()
    private var isSyncing = false
    private var syncAttempts = 0
    private var backgroundTasks: [String: BGTask] = [:]

    // MARK: - Initialization
    private init() {
        setupOperationQueue()
        registerBackgroundTasks()
        observeAppState()
    }

    private func setupOperationQueue() {
        syncQueue.maxConcurrentOperationCount = 1
        syncQueue.qualityOfService = .utility
    }

    // MARK: - Background Task Registration

    private func registerBackgroundTasks() {
        // Регистрируем задачи для BGTaskScheduler
        let taskIdentifiers = [
            Constants.balanceSyncTaskIdentifier,
            Constants.transactionSyncTaskIdentifier,
            Constants.budgetSyncTaskIdentifier
        ]

        for identifier in taskIdentifiers {
            let registered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier,
                using: nil
            ) { [weak self] task in
                Task { @MainActor in
                    await self?.handleBackgroundTask(task)
                }
            }

            if !registered {
                AnalyticsCollector.shared.logError(
                    BackgroundSyncError.taskRegistrationFailed,
                    context: "BGTaskRegistration: \(identifier)"
                )
            }
        }
    }

    /// Запрашивает выполнение background sync
    func scheduleBackgroundSync() {
        guard isBackgroundSyncEnabled else { return }
        guard backgroundSyncFrequency != .manual else { return }

        // Проверяем батарею
        let batteryLevel = UIDevice.current.batteryLevel
        guard batteryLevel < 0 || batteryLevel > Constants.batteryThreshold else {
            AnalyticsCollector.shared.logEvent("sync_skipped_low_battery")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Constants.balanceSyncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: backgroundSyncFrequency.interval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AnalyticsCollector.shared.logError(error, context: "ScheduleBackgroundSync")
        }
    }

    // MARK: - Background Task Handling

    private func handleBackgroundTask(_ task: BGTask) async {
        guard !isSyncing else {
            task.setTaskCompleted(success: false)
            return
        }

        isSyncing = true
        pendingSyncOperations += 1

        // Настраиваем expiration handler
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.isSyncing = false
                self?.pendingSyncOperations -= 1
            }
        }

        do {
            switch task.identifier {
            case Constants.balanceSyncTaskIdentifier:
                try await performBalanceSync()

            case Constants.transactionSyncTaskIdentifier:
                try await performTransactionSync()

            case Constants.budgetSyncTaskIdentifier:
                try await performBudgetSync()

            default:
                break
            }

            task.setTaskCompleted(success: true)
            lastBackgroundSync = Date()
            syncAttempts = 0

        } catch {
            AnalyticsCollector.shared.logError(error, context: "BackgroundSync")

            syncAttempts += 1
            if syncAttempts < Constants.retryAttempts {
                scheduleRetry()
            }

            task.setTaskCompleted(success: false)
        }

        isSyncing = false
        pendingSyncOperations -= 1

        // Планируем следующую задачу
        scheduleBackgroundSync()
    }

    // MARK: - Sync Operations

    /// Синхронизация баланса для конкретной карты (из silent push)
    func syncBalance(forCard cardID: String) async {
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Получаем актуальный баланс из CloudKit
            let recordID = CKRecord.ID(recordName: cardID)
            let record = try await CloudKitManager.shared.privateDatabase.record(for: recordID)

            // Обновляем локальную запись
            let context = CoreDataStack.shared.container.newBackgroundContext()
            try await context.perform {
                let fetchRequest: NSFetchRequest<Card> = Card.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", cardID)

                if let card = try context.fetch(fetchRequest).first {
                    card.balance = record.double(forKey: "balance")
                    card.lastBalanceUpdate = Date()
                    try context.save()
                }
            }

            // Отправляем local notification если баланс изменился значительно
            await notifyBalanceUpdate(cardID: cardID)

        } catch {
            AnalyticsCollector.shared.logError(error, context: "BalanceSync")
        }
    }

    /// Синхронизация последних транзакций
    func syncLatestTransactions() async {
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let lastSync = UserDefaults.standard.object(forKey: "lastTransactionSync") as? Date ?? Date.distantPast

            // Получаем транзакции после последней синхронизации
            let predicate = NSPredicate(
                format: "modificationDate > %@",
                lastSync as NSDate
            )

            let query = CKQuery(recordType: "WalletTransaction", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

            let (results, _) = try await CloudKitManager.shared.privateDatabase.records(
                matching: query,
                resultsLimit: 50
            )

            let context = CoreDataStack.shared.container.newBackgroundContext()
            var newTransactions: [CKRecord] = []

            for result in results {
                if case .success(let record) = result.1 {
                    newTransactions.append(record)
                }
            }

            if !newTransactions.isEmpty {
                try await context.perform {
                    for record in newTransactions {
                        // Обновляем или создаем транзакцию
                        self.updateOrCreateTransaction(record, in: context)
                    }
                    try context.save()
                }

                // Отправляем уведомление о новых транзакциях
                await notifyNewTransactions(count: newTransactions.count)
            }

            UserDefaults.standard.set(Date(), forKey: "lastTransactionSync")

        } catch {
            AnalyticsCollector.shared.logError(error, context: "TransactionSync")
        }
    }

    /// Синхронизация бюджетов
    func syncBudgets() async {
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await CloudKitManager.shared.syncBudgets()

            // Проверяем превышение бюджетов
            await checkBudgetLimits()

        } catch {
            AnalyticsCollector.shared.logError(error, context: "BudgetSync")
        }
    }

    // MARK: - Private Sync Methods

    private func performBalanceSync() async throws {
        let context = CoreDataStack.shared.container.newBackgroundContext()

        let fetchRequest: NSFetchRequest<Card> = Card.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isActive == YES")

        let cards = try await context.perform {
            try context.fetch(fetchRequest)
        }

        for card in cards {
            guard let cardID = card.cloudKitRecordID else { continue }

            do {
                let recordID = CKRecord.ID(recordName: cardID)
                let record = try await CloudKitManager.shared.privateDatabase.record(for: recordID)

                let newBalance = record.double(forKey: "balance")
                let oldBalance = card.balance

                if abs(newBalance - oldBalance) > 0.01 {
                    await context.perform {
                        card.balance = newBalance
                        card.lastBalanceUpdate = Date()
                    }

                    // Уведомляем если значительное изменение
                    if abs(newBalance - oldBalance) > 100 {
                        await PushNotificationManager.shared.sendLocalNotification(
                            title: "💰 Balance Updated",
                            body: "\(card.cardName ?? "Card") balance changed by \(String(format: "%.2f", abs(newBalance - oldBalance)))",
                            category: .cardUpdate
                        )
                    }
                }
            } catch {
                AnalyticsCollector.shared.logError(error, context: "CardBalanceSync: \(cardID)")
            }
        }

        try await context.perform {
            try context.save()
        }
    }

    private func performTransactionSync() async throws {
        try await syncLatestTransactions()
    }

    private func performBudgetSync() async throws {
        try await syncBudgets()
    }

    // MARK: - Notification Helpers

    private func notifyBalanceUpdate(cardID: String) async {
        let context = CoreDataStack.shared.container.newBackgroundContext()

        do {
            let fetchRequest: NSFetchRequest<Card> = Card.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", cardID)

            let card = try await context.perform {
                try context.fetch(fetchRequest).first
            }

            if let card = card {
                await PushNotificationManager.shared.sendLocalNotification(
                    title: "💳 Balance Updated",
                    body: "Your \(card.cardName ?? "card") balance has been updated",
                    category: .cardUpdate,
                    userInfo: ["cardID": cardID]
                )
            }
        } catch {
            AnalyticsCollector.shared.logError(error, context: "BalanceNotification")
        }
    }

    private func notifyNewTransactions(count: Int) async {
        await PushNotificationManager.shared.sendLocalNotification(
            title: "📝 New Transactions",
            body: "\(count) new transaction\(count == 1 ? "" : "s") synced",
            category: .transactionAlert
        )
    }

    private func checkBudgetLimits() async {
        let context = CoreDataStack.shared.container.newBackgroundContext()

        do {
            let fetchRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isActive == YES")

            let budgets = try await context.perform {
                try context.fetch(fetchRequest)
            }

            for budget in budgets {
                let percentage = (budget.spent / budget.limit) * 100

                if percentage >= 90 && !budget.ninetyPercentNotified {
                    await PushNotificationManager.shared.sendBudgetWarningNotification(
                        budgetName: budget.name ?? "Budget",
                        spent: budget.spent,
                        limit: budget.limit,
                        percentage: percentage
                    )

                    await context.perform {
                        budget.ninetyPercentNotified = true
                    }
                } else if percentage >= 100 && !budget.hundredPercentNotified {
                    await PushNotificationManager.shared.sendBudgetWarningNotification(
                        budgetName: budget.name ?? "Budget",
                        spent: budget.spent,
                        limit: budget.limit,
                        percentage: percentage
                    )

                    await context.perform {
                        budget.hundredPercentNotified = true
                    }
                }
            }

            try await context.perform {
                try context.save()
            }
        } catch {
            AnalyticsCollector.shared.logError(error, context: "BudgetCheck")
        }
    }

    // MARK: - Retry Logic

    private func scheduleRetry() {
        let delay = Constants.exponentialBackoffBase * pow(2.0, Double(syncAttempts))

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in
                await self?.scheduleBackgroundSync()
            }
        }
    }

    // MARK: - App State Observation

    private func observeAppState() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.scheduleBackgroundSync()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.cancelAllSyncOperations()
            }
            .store(in: &cancellables)
    }

    /// Отменяет все операции синхронизации
    func cancelAllSyncOperations() {
        syncQueue.cancelAllOperations()
        isSyncing = false
        pendingSyncOperations = 0
    }

    /// Принудительная синхронизация
    func forceSync() async {
        guard !isSyncing else { return }

        await performBalanceSync()
        await syncLatestTransactions()
        await syncBudgets()
    }
}

// MARK: - CoreData Helpers
extension BackgroundSyncManager {
    private func updateOrCreateTransaction(_ record: CKRecord, in context: NSManagedObjectContext) {
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
            transaction.status = record.string(forKey: "status")
            transaction.lastModified = record.modificationDate

        } catch {
            AnalyticsCollector.shared.logError(error, context: "UpdateTransaction")
        }
    }
}

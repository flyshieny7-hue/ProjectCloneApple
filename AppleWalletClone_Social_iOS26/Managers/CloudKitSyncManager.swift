import Foundation
import CloudKit
import Combine

// MARK: - Sync Status
enum CloudKitSyncStatus: String {
    case synced = "Синхронизировано"
    case syncing = "Синхронизация..."
    case error = "Ошибка"
    case offline = "Офлайн"
    case conflict = "Конфликт"
}

// MARK: - Sync Record
struct SyncRecord: Identifiable, Codable {
    let id: UUID
    var recordType: String
    var recordID: String
    var localModificationDate: Date
    var serverModificationDate: Date?
    var syncStatus: String
    var conflictResolution: String?
    var checksum: String
}

// MARK: - CloudKitSyncManager
@MainActor
final class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()

    // Published
    @Published var syncStatus: CloudKitSyncStatus = .synced
    @Published var lastSyncDate: Date?
    @Published var pendingChangesCount = 0
    @Published var isOnline = true
    @Published var syncErrors: [String] = []

    // CloudKit
    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    // Sync
    private var syncQueue: [CKRecord] = []
    private let syncQueueKey = "cloudkit_sync_queue"
    private var subscriptions: [CKSubscription] = []
    private var cancellables = Set<AnyCancellable>()

    // Caching
    private var recordCache: [String: CKRecord] = [:]
    private let cacheLimit = 1000

    // Background sync
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var syncTimer: Timer?

    private init() {
        self.container = CKContainer.default()
        self.publicDatabase = container.publicCloudDatabase
        self.privateDatabase = container.privateCloudDatabase
        self.sharedDatabase = container.sharedCloudDatabase

        setupNetworkMonitoring()
        loadSyncQueue()
        setupBackgroundSync()
    }

    // MARK: - Setup

    private func setupNetworkMonitoring() {
        // Monitor network status
        NotificationCenter.default.publisher(for: .init("NSProcessInfoPowerStateDidChangeNotification"))
            .sink { [weak self] _ in
                self?.checkNetworkStatus()
            }
            .store(in: &cancellables)
    }

    private func setupBackgroundSync() {
        // Periodic sync every 30 seconds when active
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processSyncQueue()
            }
        }
    }

    private func checkNetworkStatus() {
        // Check reachability
        isOnline = true // Simplified
    }

    // MARK: - Subscriptions

    func setupSubscriptions() async throws {
        let subscriptionIDs = [
            "group-wallet-changes",
            "budget-changes",
            "challenge-changes",
            "goal-changes",
            "transaction-changes"
        ]

        for subscriptionID in subscriptionIDs {
            let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo

            do {
                _ = try await privateDatabase.modifySubscriptions(saving: [subscription], deleting: [])
            } catch {
                print("Subscription setup error: \(error)")
            }
        }
    }

    func subscribeToBudgetChanges(callback: @escaping (SharedBudget) async -> Void) async {
        // Set up CloudKit subscription for real-time budget updates
        let predicate = NSPredicate(value: true)
        let subscription = CKQuerySubscription(
            recordType: "SharedBudget",
            predicate: predicate,
            subscriptionID: "budget-realtime",
            options: .firesOnRecordCreation
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await privateDatabase.modifySubscriptions(saving: [subscription], deleting: [])
        } catch {
            print("Budget subscription error: \(error)")
        }
    }

    // MARK: - Group Wallet Operations

    func saveGroupWallet(_ wallet: GroupWallet) async throws {
        syncStatus = .syncing
        defer { syncStatus = .synced }

        let record = CKRecord(recordType: "GroupWallet", recordID: CKRecord.ID(recordName: wallet.id.uuidString))
        record["name"] = wallet.name
        record["balance"] = wallet.balance
        record["privacyLevel"] = wallet.privacyLevel.rawValue
        record["icon"] = wallet.icon
        record["color"] = wallet.color.rawValue
        record["createdAt"] = wallet.createdAt
        record["members"] = try? JSONEncoder().encode(wallet.members)
        record["transactions"] = try? JSONEncoder().encode(wallet.transactions)

        let saved = try await privateDatabase.save(record)
        cacheRecord(saved)
    }

    func updateWallet(_ wallet: GroupWallet) async throws {
        let recordID = CKRecord.ID(recordName: wallet.id.uuidString)
        let record = try await privateDatabase.record(for: recordID)

        record["name"] = wallet.name
        record["balance"] = wallet.balance
        record["privacyLevel"] = wallet.privacyLevel.rawValue
        record["members"] = try? JSONEncoder().encode(wallet.members)
        record["transactions"] = try? JSONEncoder().encode(wallet.transactions)

        let saved = try await privateDatabase.save(record)
        cacheRecord(saved)
    }

    func deleteWallet(_ wallet: GroupWallet) async throws {
        let recordID = CKRecord.ID(recordName: wallet.id.uuidString)
        try await privateDatabase.deleteRecord(withID: recordID)
        recordCache.removeValue(forKey: recordID.recordName)
    }

    func fetchGroupWallets() async throws -> [GroupWallet] {
        let query = CKQuery(recordType: "GroupWallet", predicate: NSPredicate(value: true))
        let (results, _) = try await privateDatabase.records(matching: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100)

        return results.compactMap { result -> GroupWallet? in
            guard let record = try? result.1.get() else { return nil }
            return self.parseGroupWallet(from: record)
        }
    }

    func saveTransaction(_ transaction: GroupTransaction, to walletID: UUID) async throws {
        let record = CKRecord(recordType: "GroupTransaction")
        record["walletID"] = walletID.uuidString
        record["amount"] = transaction.amount
        record["description"] = transaction.description
        record["timestamp"] = transaction.timestamp
        record["splitType"] = transaction.splitType.rawValue
        record["splits"] = try? JSONEncoder().encode(transaction.splits)
        record["comments"] = try? JSONEncoder().encode(transaction.comments)

        _ = try await privateDatabase.save(record)
    }

    // MARK: - Split Bill Operations

    func saveSplitBillSession(_ session: SplitBillSession) async throws {
        let record = CKRecord(recordType: "SplitBillSession", recordID: CKRecord.ID(recordName: session.id.uuidString))
        record["restaurantName"] = session.restaurantName
        record["date"] = session.date
        record["items"] = try? JSONEncoder().encode(session.items)
        record["participants"] = try? JSONEncoder().encode(session.participants)
        record["splits"] = try? JSONEncoder().encode(session.splits)
        record["isCompleted"] = session.isCompleted

        _ = try await privateDatabase.save(record)
    }

    func updateSplitBillSession(_ session: SplitBillSession) async throws {
        let recordID = CKRecord.ID(recordName: session.id.uuidString)
        let record = try await privateDatabase.record(for: recordID)

        record["items"] = try? JSONEncoder().encode(session.items)
        record["splits"] = try? JSONEncoder().encode(session.splits)
        record["isCompleted"] = session.isCompleted

        _ = try await privateDatabase.save(record)
    }

    // MARK: - Shared Budget Operations

    func saveSharedBudget(_ budget: SharedBudget) async throws {
        syncStatus = .syncing
        defer { syncStatus = .synced }

        let record = CKRecord(recordType: "SharedBudget", recordID: CKRecord.ID(recordName: budget.id.uuidString))
        record["name"] = budget.name
        record["totalBudget"] = budget.totalBudget
        record["spent"] = budget.spent
        record["period"] = budget.period.rawValue
        record["startDate"] = budget.startDate
        record["endDate"] = budget.endDate
        record["members"] = try? JSONEncoder().encode(budget.members)
        record["categories"] = try? JSONEncoder().encode(budget.categories)
        record["isRecurring"] = budget.isRecurring
        record["privacySettings"] = try? JSONEncoder().encode(budget.privacySettings)

        let saved = try await privateDatabase.save(record)
        cacheRecord(saved)
    }

    func updateSharedBudget(_ budget: SharedBudget) async throws {
        let recordID = CKRecord.ID(recordName: budget.id.uuidString)
        let record = try await privateDatabase.record(for: recordID)

        record["spent"] = budget.spent
        record["members"] = try? JSONEncoder().encode(budget.members)
        record["categories"] = try? JSONEncoder().encode(budget.categories)
        record["privacySettings"] = try? JSONEncoder().encode(budget.privacySettings)

        let saved = try await privateDatabase.save(record)
        cacheRecord(saved)
    }

    func fetchSharedBudgets() async throws -> [SharedBudget] {
        let query = CKQuery(recordType: "SharedBudget", predicate: NSPredicate(value: true))
        let (results, _) = try await privateDatabase.records(matching: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100)

        return results.compactMap { result -> SharedBudget? in
            guard let record = try? result.1.get() else { return nil }
            return self.parseSharedBudget(from: record)
        }
    }

    func saveBudgetTransaction(_ transaction: BudgetTransaction, to budgetID: UUID) async throws {
        let record = CKRecord(recordType: "BudgetTransaction")
        record["budgetID"] = budgetID.uuidString
        record["amount"] = transaction.amount
        record["description"] = transaction.description
        record["timestamp"] = transaction.timestamp
        record["isApproved"] = transaction.isApproved
        record["category"] = try? JSONEncoder().encode(transaction.category)

        _ = try await privateDatabase.save(record)
    }

    func savePendingTransaction(_ transaction: BudgetTransaction, to budgetID: UUID) async throws {
        let record = CKRecord(recordType: "PendingTransaction")
        record["budgetID"] = budgetID.uuidString
        record["amount"] = transaction.amount
        record["description"] = transaction.description
        record["timestamp"] = transaction.timestamp
        record["category"] = try? JSONEncoder().encode(transaction.category)

        _ = try await privateDatabase.save(record)
    }

    // MARK: - Challenge Operations

    func saveChallenge(_ challenge: SpendingChallenge) async throws {
        let record = CKRecord(recordType: "SpendingChallenge", recordID: CKRecord.ID(recordName: challenge.id.uuidString))
        record["title"] = challenge.title
        record["description"] = challenge.description
        record["category"] = challenge.category.rawValue
        record["type"] = challenge.type.rawValue
        record["startDate"] = challenge.startDate
        record["endDate"] = challenge.endDate
        record["participants"] = try? JSONEncoder().encode(challenge.participants)
        record["rules"] = try? JSONEncoder().encode(challenge.rules)
        record["status"] = challenge.status.rawValue
        record["isPrivate"] = challenge.isPrivate

        _ = try await privateDatabase.save(record)
    }

    func updateChallenge(_ challenge: SpendingChallenge) async throws {
        let recordID = CKRecord.ID(recordName: challenge.id.uuidString)
        let record = try await privateDatabase.record(for: recordID)

        record["participants"] = try? JSONEncoder().encode(challenge.participants)
        record["status"] = challenge.status.rawValue

        _ = try await privateDatabase.save(record)
    }

    // MARK: - Savings Goal Operations

    func saveSavingsGoal(_ goal: SharedSavingsGoal) async throws {
        let record = CKRecord(recordType: "SharedSavingsGoal", recordID: CKRecord.ID(recordName: goal.id.uuidString))
        record["name"] = goal.name
        record["targetAmount"] = goal.targetAmount
        record["currentAmount"] = goal.currentAmount
        record["deadline"] = goal.deadline
        record["contributors"] = try? JSONEncoder().encode(goal.contributors)
        record["milestones"] = try? JSONEncoder().encode(goal.milestones)
        record["category"] = goal.category.rawValue
        record["color"] = goal.color.rawValue
        record["privacyLevel"] = goal.privacyLevel.rawValue

        _ = try await privateDatabase.save(record)
    }

    func updateSavingsGoal(_ goal: SharedSavingsGoal) async throws {
        let recordID = CKRecord.ID(recordName: goal.id.uuidString)
        let record = try await privateDatabase.record(for: recordID)

        record["currentAmount"] = goal.currentAmount
        record["contributors"] = try? JSONEncoder().encode(goal.contributors)
        record["milestones"] = try? JSONEncoder().encode(goal.milestones)
        record["transactions"] = try? JSONEncoder().encode(goal.transactions)

        _ = try await privateDatabase.save(record)
    }

    // MARK: - Comment Operations

    func saveComment(_ comment: TransactionComment, to threadID: UUID) async throws {
        let record = CKRecord(recordType: "TransactionComment")
        record["threadID"] = threadID.uuidString
        record["author"] = try? JSONEncoder().encode(comment.author)
        record["text"] = comment.text
        record["timestamp"] = comment.timestamp
        record["reactions"] = try? JSONEncoder().encode(comment.reactions)

        _ = try await privateDatabase.save(record)
    }

    func updateComment(_ comment: TransactionComment) async throws {
        // Find and update existing comment
    }

    func deleteComment(_ comment: TransactionComment) async throws {
        // Delete from CloudKit
    }

    // MARK: - Activity Operations

    func updateActivity(_ activity: ActivityItem) async throws {
        let record = CKRecord(recordType: "ActivityItem", recordID: CKRecord.ID(recordName: activity.id.uuidString))
        record["type"] = activity.type.rawValue
        record["actor"] = try? JSONEncoder().encode(activity.actor)
        record["target"] = activity.target
        record["description"] = activity.description
        record["timestamp"] = activity.timestamp
        record["privacyLevel"] = activity.privacyLevel.rawValue
        record["reactions"] = try? JSONEncoder().encode(activity.reactions)
        record["comments"] = try? JSONEncoder().encode(activity.comments)

        _ = try await privateDatabase.save(record)
    }

    func savePrivacySettings(_ settings: PrivacySettings) async throws {
        let record = CKRecord(recordType: "PrivacySettings", recordID: CKRecord.ID(recordName: "user-privacy"))
        record["settings"] = try? JSONEncoder().encode(settings)
        record["updatedAt"] = Date()

        _ = try await privateDatabase.save(record)
    }

    // MARK: - Sync Queue Management

    func addToSyncQueue(_ record: CKRecord) {
        syncQueue.append(record)
        pendingChangesCount = syncQueue.count
        saveSyncQueue()
    }

    func processSyncQueue() async {
        guard isOnline, !syncQueue.isEmpty else { return }

        syncStatus = .syncing

        let recordsToSync = syncQueue
        syncQueue.removeAll()

        for record in recordsToSync {
            do {
                _ = try await privateDatabase.save(record)
            } catch {
                syncQueue.append(record)
                syncErrors.append(error.localizedDescription)
            }
        }

        pendingChangesCount = syncQueue.count
        syncStatus = syncQueue.isEmpty ? .synced : .error
        saveSyncQueue()
    }

    private func saveSyncQueue() {
        // Persist queue to UserDefaults or local file
    }

    private func loadSyncQueue() {
        // Load queue from persistent storage
    }

    // MARK: - Caching

    private func cacheRecord(_ record: CKRecord) {
        if recordCache.count >= cacheLimit {
            recordCache.removeValue(forKey: recordCache.keys.first!)
        }
        recordCache[record.recordID.recordName] = record
    }

    private func cachedRecord(for recordID: CKRecord.ID) -> CKRecord? {
        return recordCache[recordID.recordName]
    }

    // MARK: - Parsing

    private func parseGroupWallet(from record: CKRecord) -> GroupWallet? {
        guard let name = record["name"] as? String,
              let balance = record["balance"] as? Double,
              let privacyString = record["privacyLevel"] as? String,
              let privacyLevel = GroupWallet.PrivacyLevel(rawValue: privacyString) else { return nil }

        return GroupWallet(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            name: name,
            members: [],
            balance: balance,
            transactions: [],
            createdAt: record["createdAt"] as? Date ?? Date(),
            privacyLevel: privacyLevel,
            icon: record["icon"] as? String ?? "person.3.fill",
            color: GroupWallet.WalletColor(rawValue: record["color"] as? String ?? "blue") ?? .blue
        )
    }

    private func parseSharedBudget(from record: CKRecord) -> SharedBudget? {
        guard let name = record["name"] as? String,
              let totalBudget = record["totalBudget"] as? Double,
              let spent = record["spent"] as? Double,
              let periodString = record["period"] as? String,
              let period = SharedBudget.BudgetPeriod(rawValue: periodString) else { return nil }

        return SharedBudget(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            name: name,
            icon: "chart.pie.fill",
            color: .emerald,
            totalBudget: totalBudget,
            spent: spent,
            period: period,
            startDate: record["startDate"] as? Date ?? Date(),
            endDate: record["endDate"] as? Date ?? Date(),
            members: [],
            categories: [],
            alerts: [],
            isRecurring: record["isRecurring"] as? Bool ?? false,
            privacySettings: BudgetPrivacySettings()
        )
    }

    // MARK: - Conflict Resolution

    func resolveConflict(localRecord: CKRecord, serverRecord: CKRecord) -> CKRecord {
        // Last-write-wins strategy with merge for specific fields
        let resolved = CKRecord(recordType: localRecord.recordType, recordID: localRecord.recordID)

        for key in localRecord.allKeys() {
            let localValue = localRecord[key]
            let serverValue = serverRecord[key]

            // Use server value for most fields, but merge arrays
            if let localArray = localValue as? [Any], let serverArray = serverValue as? [Any] {
                resolved[key] = Array(Set(localArray + serverArray))
            } else {
                resolved[key] = serverValue ?? localValue
            }
        }

        return resolved
    }

    // MARK: - Batch Operations

    func batchSave(_ records: [CKRecord]) async throws -> [CKRecord] {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)

        return try await withCheckedThrowingContinuation { continuation in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success(let modificationResult):
                    let savedRecords = records.compactMap { record -> CKRecord? in
                        switch modificationResult[record.recordID] {
                        case .success(let savedRecord):
                            return savedRecord
                        default:
                            return nil
                        }
                    }
                    continuation.resume(returning: savedRecords)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            privateDatabase.add(operation)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        syncTimer?.invalidate()
        recordCache.removeAll()
        syncQueue.removeAll()
    }
}

// MARK: - CloudKit Helpers
extension CloudKitSyncManager {
    func getSyncStatus() async -> CloudKitSyncStatus {
        return syncStatus
    }

    func forceSync() async throws {
        try await processSyncQueue()
    }

    func clearCache() {
        recordCache.removeAll()
    }
}

import Foundation
import CoreData
import Combine

/// Менеджер Handoff для бесшовного перехода между iPhone, iPad и Mac
/// iOS 26, использует NSUserActivity, CoreData sync, CloudKit
@MainActor
final class MultiDeviceHandoff: ObservableObject {

    // MARK: - Singleton
    static let shared = MultiDeviceHandoff()

    // MARK: - Published Properties
    @Published var currentActivity: UserActivity?
    @Published var isHandoffAvailable: Bool = false
    @Published var connectedDevices: [DeviceInfo] = []
    @Published var lastHandoffDate: Date?

    // MARK: - Types
    struct UserActivity: Identifiable, Codable {
        let id: String
        let type: ActivityType
        let timestamp: Date
        let deviceID: String
        let userInfo: [String: String]
        let contextData: Data?

        enum ActivityType: String, Codable, CaseIterable {
            case viewCard = "com.wallet.activity.viewCard"
            case viewTransaction = "com.wallet.activity.viewTransaction"
            case viewBudget = "com.wallet.activity.viewBudget"
            case addTransaction = "com.wallet.activity.addTransaction"
            case editBudget = "com.wallet.activity.editBudget"
            case paymentFlow = "com.wallet.activity.paymentFlow"
            case scanReceipt = "com.wallet.activity.scanReceipt"
            case settings = "com.wallet.activity.settings"
            case statistics = "com.wallet.activity.statistics"
            case search = "com.wallet.activity.search"
        }
    }

    struct DeviceInfo: Identifiable, Codable {
        let id: String
        let name: String
        let type: DeviceType
        let lastSeen: Date
        let isOnline: Bool
        let osVersion: String

        enum DeviceType: String, Codable {
            case iPhone = "iPhone"
            case iPad = "iPad"
            case mac = "Mac"
            case watch = "Apple Watch"
            case unknown = "Unknown"
        }
    }

    enum HandoffError: LocalizedError {
        case activityCreationFailed
        case activityContinuationFailed
        case deviceNotAvailable
        case dataSyncFailed
        case contextRestorationFailed
        case iCloudNotEnabled
        case incompatibleOSVersion

        var errorDescription: String? {
            switch self {
            case .activityCreationFailed: return "Failed to create handoff activity"
            case .activityContinuationFailed: return "Failed to continue activity on new device"
            case .deviceNotAvailable: return "Target device is not available"
            case .dataSyncFailed: return "Failed to sync data for handoff"
            case .contextRestorationFailed: return "Failed to restore app context"
            case .iCloudNotEnabled: return "iCloud required for handoff is not enabled"
            case .incompatibleOSVersion: return "Incompatible OS version for handoff"
            }
        }
    }

    // MARK: - Constants
    private enum Constants {
        static let activityKey = "com.wallet.handoff.activity"
        static let deviceListKey = "com.wallet.handoff.devices"
        static let maxActivityAge: TimeInterval = 3600 // 1 hour
        static let syncInterval: TimeInterval = 30
        static let handoffTimeout: TimeInterval = 60
    }

    // MARK: - Properties
    private var cancellables = Set<AnyCancellable>()
    private var currentNSActivity: NSUserActivity?
    private let handoffQueue = DispatchQueue(label: "com.wallet.handoff", qos: .userInitiated)
    private var activityTimeoutTimer: Timer?

    // MARK: - Initialization
    private init() {
        checkHandoffAvailability()
        setupDeviceMonitoring()
        observeiCloudStatus()
    }

    // MARK: - Availability Check

    private func checkHandoffAvailability() {
        // Проверяем доступность Handoff
        let isContinuityAvailable = NSUserActivity.isEligibleForHandoff
        let isiCloudAvailable = FileManager.default.ubiquityIdentityToken != nil

        isHandoffAvailable = isContinuityAvailable && isiCloudAvailable

        if !isHandoffAvailable {
            AnalyticsCollector.shared.logEvent("handoff_unavailable", parameters: [
                "continuity": isContinuityAvailable,
                "icloud": isiCloudAvailable
            ])
        }
    }

    private func observeiCloudStatus() {
        NotificationCenter.default.publisher(for: NSNotification.Name.CKAccountChanged)
            .sink { [weak self] _ in
                self?.checkHandoffAvailability()
            }
            .store(in: &cancellables)
    }

    // MARK: - Device Monitoring

    private func setupDeviceMonitoring() {
        // Мониторинг подключенных устройств через CloudKit
        Task {
            await updateConnectedDevices()
        }

        // Периодическое обновление списка устройств
        Timer.scheduledTimer(withTimeInterval: Constants.syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateConnectedDevices()
            }
        }
    }

    private func updateConnectedDevices() async {
        do {
            // Получаем список устройств из CloudKit
            let predicate = NSPredicate(
                format: "lastSeen > %@",
                Date(timeIntervalSinceNow: -300) as NSDate
            )

            let query = CKQuery(recordType: "ConnectedDevice", predicate: predicate)
            let (results, _) = try await CloudKitManager.shared.privateDatabase.records(
                matching: query,
                resultsLimit: 10
            )

            var devices: [DeviceInfo] = []
            for result in results {
                if case .success(let record) = result.1 {
                    if let device = DeviceInfo(from: record) {
                        devices.append(device)
                    }
                }
            }

            connectedDevices = devices

        } catch {
            AnalyticsCollector.shared.logError(error, context: "DeviceMonitoring")
        }
    }

    // MARK: - Activity Management

    /// Начинает новую активность для Handoff
    func beginActivity(
        type: UserActivity.ActivityType,
        userInfo: [String: Any] = [:],
        contextData: Data? = nil
    ) async throws {
        guard isHandoffAvailable else {
            throw HandoffError.iCloudNotEnabled
        }

        // Создаем NSUserActivity
        let activity = NSUserActivity(activityType: type.rawValue)
        activity.title = activityTitle(for: type)
        activity.userInfo = userInfo
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPublicIndexing = false

        // Добавляем keywords для Spotlight
        activity.keywords = activityKeywords(for: type)

        // Сохраняем дополнительный контекст
        if let contextData = contextData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("handoff_\(UUID().uuidString)")
            try contextData.write(to: tempURL)
            activity.addUserInfoEntries(from: ["contextURL": tempURL.absoluteString])
        }

        // Сохраняем в iCloud для доступа с других устройств
        try await saveActivityToCloud(activity, type: type, userInfo: userInfo)

        // Активируем
        activity.becomeCurrent()
        currentNSActivity = activity

        // Создаем локальную модель
        currentActivity = UserActivity(
            id: UUID().uuidString,
            type: type,
            timestamp: Date(),
            deviceID: await currentDeviceID(),
            userInfo: userInfo.compactMapValues { $0 as? String },
            contextData: contextData
        )

        // Устанавливаем таймаут
        setupActivityTimeout()

        AnalyticsCollector.shared.logEvent("handoff_activity_started", parameters: [
            "type": type.rawValue
        ])
    }

    /// Продолжает активность на текущем устройстве
    func continueActivity(
        type: UserActivity.ActivityType,
        userInfo: [String: Any]
    ) async throws {
        guard isHandoffAvailable else {
            throw HandoffError.iCloudNotEnabled
        }

        // Синхронизируем данные перед продолжением
        try await syncDataForActivity(type: type, userInfo: userInfo)

        // Восстанавливаем контекст
        try await restoreContext(type: type, userInfo: userInfo)

        lastHandoffDate = Date()

        AnalyticsCollector.shared.logEvent("handoff_activity_continued", parameters: [
            "type": type.rawValue
        ])
    }

    /// Завершает текущую активность
    func endCurrentActivity() {
        currentNSActivity?.invalidate()
        currentNSActivity = nil
        currentActivity = nil
        activityTimeoutTimer?.invalidate()

        AnalyticsCollector.shared.logEvent("handoff_activity_ended")
    }

    // MARK: - Cloud Sync

    private func saveActivityToCloud(
        _ activity: NSUserActivity,
        type: UserActivity.ActivityType,
        userInfo: [String: Any]
    ) async throws {
        let record = CKRecord(recordType: "HandoffActivity")
        record["activityType"] = type.rawValue
        record["userInfo"] = try JSONSerialization.data(withJSONObject: userInfo)
        record["deviceID"] = await currentDeviceID()
        record["timestamp"] = Date()
        record["deviceName"] = await currentDeviceName()

        let (saveResult, _) = try await CloudKitManager.shared.privateDatabase.modifyRecords(
            saving: [record],
            deleting: [],
            atomically: true
        )

        for result in saveResult {
            if case .failure(let error) = result.1 {
                throw HandoffError.dataSyncFailed
            }
        }
    }

    private func syncDataForActivity(
        type: UserActivity.ActivityType,
        userInfo: [String: Any]
    ) async throws {
        // Принудительная синхронизация перед handoff
        await CloudKitManager.shared.performSync()

        // Дополнительная синхронизация специфичных данных
        switch type {
        case .viewCard, .paymentFlow:
            if let cardID = userInfo["cardID"] as? String {
                await BackgroundSyncManager.shared.syncBalance(forCard: cardID)
            }

        case .viewTransaction:
            await BackgroundSyncManager.shared.syncLatestTransactions()

        case .viewBudget, .editBudget:
            await BackgroundSyncManager.shared.syncBudgets()

        default:
            break
        }
    }

    // MARK: - Context Restoration

    private func restoreContext(
        type: UserActivity.ActivityType,
        userInfo: [String: Any]
    ) async throws {
        // Восстанавливаем UI контекст
        switch type {
        case .viewCard:
            guard let cardID = userInfo["cardID"] as? String else {
                throw HandoffError.contextRestorationFailed
            }
            await restoreCardContext(cardID: cardID)

        case .viewTransaction:
            guard let transactionID = userInfo["transactionID"] as? String else {
                throw HandoffError.contextRestorationFailed
            }
            await restoreTransactionContext(transactionID: transactionID)

        case .viewBudget:
            guard let budgetID = userInfo["budgetID"] as? String else {
                throw HandoffError.contextRestorationFailed
            }
            await restoreBudgetContext(budgetID: budgetID)

        case .addTransaction:
            await restoreAddTransactionContext(userInfo: userInfo)

        case .paymentFlow:
            guard let paymentID = userInfo["paymentID"] as? String else {
                throw HandoffError.contextRestorationFailed
            }
            await restorePaymentContext(paymentID: paymentID)

        default:
            // Для простых экранов достаточно имени активности
            break
        }
    }

    private func restoreCardContext(cardID: String) async {
        // Уведомляем UI о необходимости открыть карту
        NotificationCenter.default.post(
            name: .HandoffRestoreCard,
            object: nil,
            userInfo: ["cardID": cardID]
        )
    }

    private func restoreTransactionContext(transactionID: String) async {
        NotificationCenter.default.post(
            name: .HandoffRestoreTransaction,
            object: nil,
            userInfo: ["transactionID": transactionID]
        )
    }

    private func restoreBudgetContext(budgetID: String) async {
        NotificationCenter.default.post(
            name: .HandoffRestoreBudget,
            object: nil,
            userInfo: ["budgetID": budgetID]
        )
    }

    private func restoreAddTransactionContext(userInfo: [String: Any]) async {
        NotificationCenter.default.post(
            name: .HandoffRestoreAddTransaction,
            object: nil,
            userInfo: userInfo
        )
    }

    private func restorePaymentContext(paymentID: String) async {
        NotificationCenter.default.post(
            name: .HandoffRestorePayment,
            object: nil,
            userInfo: ["paymentID": paymentID]
        )
    }

    // MARK: - Device Info

    private func currentDeviceID() async -> String {
        if let token = await UIDevice.current.identifierForVendor?.uuidString {
            return token
        }
        return UUID().uuidString
    }

    private func currentDeviceName() async -> String {
        return UIDevice.current.name
    }

    // MARK: - Helpers

    private func activityTitle(for type: UserActivity.ActivityType) -> String {
        switch type {
        case .viewCard: return "Viewing Card"
        case .viewTransaction: return "Viewing Transaction"
        case .viewBudget: return "Viewing Budget"
        case .addTransaction: return "Adding Transaction"
        case .editBudget: return "Editing Budget"
        case .paymentFlow: return "Making Payment"
        case .scanReceipt: return "Scanning Receipt"
        case .settings: return "In Settings"
        case .statistics: return "Viewing Statistics"
        case .search: return "Searching"
        }
    }

    private func activityKeywords(for type: UserActivity.ActivityType) -> Set<String> {
        switch type {
        case .viewCard:
            return ["card", "balance", "credit", "debit", "wallet"]
        case .viewTransaction:
            return ["transaction", "payment", "purchase", "history"]
        case .viewBudget:
            return ["budget", "limit", "spending", "savings"]
        case .addTransaction:
            return ["add", "new", "transaction", "expense"]
        case .paymentFlow:
            return ["pay", "payment", "transfer", "send"]
        default:
            return ["wallet", "finance"]
        }
    }

    private func setupActivityTimeout() {
        activityTimeoutTimer?.invalidate()
        activityTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.handoffTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.endCurrentActivity()
        }
    }

    // MARK: - Cleanup

    /// Очищает старые активности
    func cleanupOldActivities() async {
        let cutoffDate = Date(timeIntervalSinceNow: -Constants.maxActivityAge)

        do {
            let predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
            let query = CKQuery(recordType: "HandoffActivity", predicate: predicate)

            let (results, _) = try await CloudKitManager.shared.privateDatabase.records(
                matching: query,
                resultsLimit: 100
            )

            var recordIDsToDelete: [CKRecord.ID] = []
            for result in results {
                if case .success(let record) = result.1 {
                    recordIDsToDelete.append(record.recordID)
                }
            }

            if !recordIDsToDelete.isEmpty {
                let (_, deleteResults) = try await CloudKitManager.shared.privateDatabase.modifyRecords(
                    saving: [],
                    deleting: recordIDsToDelete,
                    atomically: false
                )

                for result in deleteResults {
                    if case .failure(let error) = result.1 {
                        AnalyticsCollector.shared.logError(error, context: "CleanupOldActivities")
                    }
                }
            }

        } catch {
            AnalyticsCollector.shared.logError(error, context: "CleanupActivities")
        }
    }
}

// MARK: - DeviceInfo from CKRecord
extension MultiDeviceHandoff.DeviceInfo {
    init?(from record: CKRecord) {
        guard let id = record["deviceID"] as? String,
              let name = record["deviceName"] as? String,
              let typeString = record["deviceType"] as? String,
              let lastSeen = record["lastSeen"] as? Date,
              let osVersion = record["osVersion"] as? String else {
            return nil
        }

        self.id = id
        self.name = name
        self.type = DeviceType(rawValue: typeString) ?? .unknown
        self.lastSeen = lastSeen
        self.isOnline = Date().timeIntervalSince(lastSeen) < 300
        self.osVersion = osVersion
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let HandoffRestoreCard = Notification.Name("HandoffRestoreCard")
    static let HandoffRestoreTransaction = Notification.Name("HandoffRestoreTransaction")
    static let HandoffRestoreBudget = Notification.Name("HandoffRestoreBudget")
    static let HandoffRestoreAddTransaction = Notification.Name("HandoffRestoreAddTransaction")
    static let HandoffRestorePayment = Notification.Name("HandoffRestorePayment")
}

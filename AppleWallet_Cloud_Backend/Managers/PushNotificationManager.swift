import Foundation
import UserNotifications
import UIKit
import Combine

/// Менеджер push-уведомлений с rich content и action buttons
/// iOS 26, поддерживает rich notifications, custom UI, actions
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {

    // MARK: - Singleton
    static let shared = PushNotificationManager()

    // MARK: - Published Properties
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isRegisteredForRemoteNotifications: Bool = false
    @Published var pendingNotifications: [UNNotificationRequest] = []

    // MARK: - Types
    enum NotificationCategory: String, CaseIterable {
        case transactionAlert = "TRANSACTION_ALERT"
        case budgetWarning = "BUDGET_WARNING"
        case paymentReminder = "PAYMENT_REMINDER"
        case securityAlert = "SECURITY_ALERT"
        case syncError = "SYNC_ERROR"
        case cardUpdate = "CARD_UPDATE"
        case promotional = "PROMOTIONAL"

        var actions: [UNNotificationAction] {
            switch self {
            case .transactionAlert:
                return [
                    UNNotificationAction(
                        identifier: "VIEW_TRANSACTION",
                        title: "View Details",
                        options: .foreground
                    ),
                    UNNotificationAction(
                        identifier: "REPORT_FRAUD",
                        title: "Report Fraud",
                        options: [.destructive, .authenticationRequired]
                    ),
                    UNNotificationAction(
                        identifier: "DISMISS",
                        title: "Dismiss",
                        options: .destructive
                    )
                ]

            case .budgetWarning:
                return [
                    UNNotificationAction(
                        identifier: "VIEW_BUDGET",
                        title: "View Budget",
                        options: .foreground
                    ),
                    UNNotificationAction(
                        identifier: "ADJUST_BUDGET",
                        title: "Adjust Limit",
                        options: .foreground
                    ),
                    UNNotificationAction(
                        identifier: "SNOOZE_24H",
                        title: "Snooze 24h",
                        options: []
                    )
                ]

            case .paymentReminder:
                return [
                    UNNotificationAction(
                        identifier: "PAY_NOW",
                        title: "Pay Now",
                        options: .foreground
                    ),
                    UNNotificationAction(
                        identifier: "REMIND_LATER",
                        title: "Remind Later",
                        options: []
                    ),
                    UNNotificationAction(
                        identifier: "SCHEDULE_PAYMENT",
                        title: "Schedule",
                        options: .foreground
                    )
                ]

            case .securityAlert:
                return [
                    UNNotificationAction(
                        identifier: "SECURE_ACCOUNT",
                        title: "Secure Account",
                        options: [.foreground, .authenticationRequired]
                    ),
                    UNNotificationAction(
                        identifier: "CALL_SUPPORT",
                        title: "Call Support",
                        options: .foreground
                    ),
                    UNNotificationAction(
                        identifier: "IGNORE",
                        title: "Ignore",
                        options: .destructive
                    )
                ]

            case .syncError:
                return [
                    UNNotificationAction(
                        identifier: "RETRY_SYNC",
                        title: "Retry Sync",
                        options: []
                    ),
                    UNNotificationAction(
                        identifier: "OPEN_SETTINGS",
                        title: "Open Settings",
                        options: .foreground
                    )
                ]

            case .cardUpdate:
                return [
                    UNNotificationAction(
                        identifier: "VIEW_CARD",
                        title: "View Card",
                        options: .foreground
                    ),
                    UNNotificationAction(
                        identifier: "UPDATE_CARD",
                        title: "Update Info",
                        options: .foreground
                    )
                ]

            case .promotional:
                return [
                    UNNotificationAction(
                        identifier: "VIEW_OFFER",
                        title: "View Offer",
                        options: .foreground
                    ),
                    UNNotificationAction(
                        identifier: "SAVE_OFFER",
                        title: "Save for Later",
                        options: []
                    ),
                    UNNotificationAction(
                        identifier: "DISMISS_PROMO",
                        title: "Dismiss",
                        options: .destructive
                    )
                ]
            }
        }
    }

    enum PushError: LocalizedError {
        case authorizationDenied
        case registrationFailed
        case tokenUnavailable
        case payloadTooLarge
        case deliveryFailed
        case invalidCategory

        var errorDescription: String? {
            switch self {
            case .authorizationDenied: return "User denied notification permissions"
            case .registrationFailed: return "Failed to register for remote notifications"
            case .tokenUnavailable: return "Push token not available"
            case .payloadTooLarge: return "Notification payload exceeds 4KB limit"
            case .deliveryFailed: return "Failed to deliver notification"
            case .invalidCategory: return "Invalid notification category"
            }
        }
    }

    // MARK: - Properties
    private let notificationCenter = UNUserNotificationCenter.current
    private var cancellables = Set<AnyCancellable>()
    private var deviceToken: Data?
    private let retryQueue = DispatchQueue(label: "com.wallet.push.retry", qos: .utility)

    // MARK: - Initialization
    private override init() {
        super.init()
        notificationCenter.delegate = self
        setupNotificationCategories()
        observeAppLifecycle()
    }

    // MARK: - Setup
    private func setupNotificationCategories() {
        var categories: Set<UNNotificationCategory> = []

        for category in NotificationCategory.allCases {
            let actions = category.actions
            let notificationCategory = UNNotificationCategory(
                identifier: category.rawValue,
                actions: actions,
                intentIdentifiers: [],
                options: [.customDismissAction, .allowInCarPlay]
            )
            categories.insert(notificationCategory)
        }

        notificationCenter.setNotificationCategories(categories)
    }

    private func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.updateAuthorizationStatus()
            }
            .store(in: &cancellables)
    }

    // MARK: - Authorization

    /// Запрашивает разрешения на уведомления
    func requestAuthorization() async throws {
        let options: UNAuthorizationOptions = [
            .alert,
            .badge,
            .sound,
            .provisional,
            .providesAppNotificationSettings,
            .criticalAlert
        ]

        let (granted, error) = await notificationCenter.requestAuthorization(options: options)

        if let error = error {
            throw error
        }

        authorizationStatus = granted ? .authorized : .denied

        if granted {
            await registerForRemoteNotifications()
        }
    }

    /// Проверяет текущий статус авторизации
    func updateAuthorizationStatus() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    // MARK: - Remote Registration

    /// Регистрирует устройство для remote push notifications
    func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Обрабатывает полученный device token
    func didRegisterForRemoteNotifications(withDeviceToken token: Data) {
        deviceToken = token
        isRegisteredForRemoteNotifications = true

        // Отправляем токен на сервер
        Task {
            await sendDeviceTokenToServer(token)
        }
    }

    /// Обрабатывает ошибку регистрации
    func didFailToRegisterForRemoteNotifications(withError error: Error) {
        isRegisteredForRemoteNotifications = false
        AnalyticsCollector.shared.logError(error, context: "PushRegistration")

        // Повторная попытка через экспоненциальный бэкофф
        retryRegistration()
    }

    private func retryRegistration() {
        var retryCount = 0
        let maxRetries = 5

        func attempt() {
            guard retryCount < maxRetries else { return }

            let delay = min(pow(2.0, Double(retryCount)), 60.0)
            retryCount += 1

            retryQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                Task { @MainActor in
                    await self?.registerForRemoteNotifications()
                }
            }
        }

        attempt()
    }

    private func sendDeviceTokenToServer(_ token: Data) async {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()

        // В реальном приложении отправляем на backend
        // Здесь логируем для аналитики
        AnalyticsCollector.shared.logEvent("device_token_registered", parameters: [
            "token_prefix": String(tokenString.prefix(8))
        ])
    }

    // MARK: - Local Notifications

    /// Отправляет локальное уведомление
    func sendLocalNotification(
        title: String,
        body: String,
        category: NotificationCategory,
        userInfo: [String: Any] = [:],
        attachmentURL: URL? = nil,
        trigger: UNNotificationTrigger? = nil
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.sound = .default
        content.userInfo = userInfo

        // Rich content attachment
        if let attachmentURL = attachmentURL {
            do {
                let attachment = try UNNotificationAttachment(
                    identifier: UUID().uuidString,
                    url: attachmentURL,
                    options: nil
                )
                content.attachments = [attachment]
            } catch {
                AnalyticsCollector.shared.logError(error, context: "NotificationAttachment")
            }
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            pendingNotifications.append(request)
        } catch {
            AnalyticsCollector.shared.logError(error, context: "LocalNotification")
        }
    }

    /// Отправляет уведомление о транзакции
    func sendTransactionNotification(
        amount: Double,
        currency: String,
        merchant: String,
        cardLast4: String,
        isInternational: Bool = false
    ) async {
        let title = isInternational ? "🌍 International Transaction" : "💳 New Transaction"
        let body = "\(merchant) - \(String(format: "%.2f", amount)) \(currency) on ••••\(cardLast4)"

        let userInfo: [String: Any] = [
            "amount": amount,
            "currency": currency,
            "merchant": merchant,
            "cardLast4": cardLast4,
            "isInternational": isInternational,
            "timestamp": Date().timeIntervalSince1970
        ]

        await sendLocalNotification(
            title: title,
            body: body,
            category: .transactionAlert,
            userInfo: userInfo
        )
    }

    /// Отправляет предупреждение о бюджете
    func sendBudgetWarningNotification(
        budgetName: String,
        spent: Double,
        limit: Double,
        percentage: Double
    ) async {
        let title = "⚠️ Budget Alert"
        let body = "You\'ve used \(String(format: "%.0f", percentage))% of your \(budgetName) budget"

        let userInfo: [String: Any] = [
            "budgetName": budgetName,
            "spent": spent,
            "limit": limit,
            "percentage": percentage
        ]

        await sendLocalNotification(
            title: title,
            body: body,
            category: .budgetWarning,
            userInfo: userInfo
        )
    }

    /// Отправляет security alert
    func sendSecurityAlert(
        alertType: SecurityAlertType,
        details: String
    ) async {
        let title = "🔒 Security Alert"
        let body = "\(alertType.rawValue): \(details)"

        let userInfo: [String: Any] = [
            "alertType": alertType.rawValue,
            "details": details,
            "requiresAction": true
        ]

        // Critical alert для security
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = NotificationCategory.securityAlert.rawValue
        content.sound = .defaultCritical
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "security_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            AnalyticsCollector.shared.logError(error, context: "SecurityAlert")
        }
    }

    enum SecurityAlertType: String {
        case suspiciousActivity = "Suspicious Activity Detected"
        case largeTransaction = "Large Transaction Alert"
        case newDevice = "New Device Login"
        case passwordChanged = "Password Changed"
        case cardLocked = "Card Automatically Locked"
    }

    // MARK: - Silent Push Handling

    /// Обрабатывает silent push для background sync
    func handleSilentPush(userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let type = userInfo["type"] as? String else {
            return .noData
        }

        switch type {
        case "balance_update":
            if let cardID = userInfo["card_id"] as? String {
                await BackgroundSyncManager.shared.syncBalance(forCard: cardID)
                return .newData
            }

        case "transaction_update":
            await BackgroundSyncManager.shared.syncLatestTransactions()
            return .newData

        case "budget_update":
            await BackgroundSyncManager.shared.syncBudgets()
            return .newData

        case "card_status_change":
            if let cardID = userInfo["card_id"] as? String,
               let newStatus = userInfo["status"] as? String {
                await updateCardStatus(cardID: cardID, status: newStatus)
                return .newData
            }

        default:
            return .noData
        }

        return .noData
    }

    private func updateCardStatus(cardID: String, status: String) async {
        let context = CoreDataStack.shared.container.newBackgroundContext()
        await context.perform {
            let fetchRequest: NSFetchRequest<Card> = Card.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", cardID)

            do {
                if let card = try context.fetch(fetchRequest).first {
                    card.status = status
                    try context.save()
                }
            } catch {
                AnalyticsCollector.shared.logError(error, context: "CardStatusUpdate")
            }
        }
    }

    // MARK: - Notification Management

    /// Удаляет все pending notifications
    func removeAllPendingNotifications() async {
        notificationCenter.removeAllPendingNotificationRequests()
        pendingNotifications.removeAll()
    }

    /// Удаляет delivered notifications
    func removeDeliveredNotifications(identifiers: [String]) async {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Получает все pending notifications
    func fetchPendingNotifications() async {
        let requests = await notificationCenter.pendingNotificationRequests()
        pendingNotifications = requests
    }

    /// Обновляет badge count
    func updateBadgeCount(_ count: Int) async {
        await MainActor.run {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }

    // MARK: - Rich Content

    /// Создает rich notification с custom UI
    func createRichNotification(
        title: String,
        body: String,
        category: NotificationCategory,
        imageData: Data? = nil,
        actions: [UNNotificationAction]? = nil
    ) async throws -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue

        // Добавляем custom actions если предоставлены
        if let actions = actions {
            let newCategory = UNNotificationCategory(
                identifier: category.rawValue,
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
            notificationCenter.setNotificationCategories([newCategory])
        }

        // Добавляем изображение
        if let imageData = imageData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")

            try imageData.write(to: tempURL)

            let attachment = try UNNotificationAttachment(
                identifier: "image",
                url: tempURL,
                options: [UNAttachmentOptions.typeHint: "public.jpeg"]
            )
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        return request
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension PushNotificationManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Показываем уведомление даже когда app foreground
        completionHandler([.banner, .sound, .badge, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let category = response.notification.request.content.categoryIdentifier

        Task {
            await handleNotificationAction(
                action: actionIdentifier,
                category: category,
                userInfo: userInfo
            )
            completionHandler()
        }
    }

    private func handleNotificationAction(
        action: String,
        category: String,
        userInfo: [AnyHashable: Any]
    ) async {
        AnalyticsCollector.shared.logEvent("notification_action", parameters: [
            "action": action,
            "category": category
        ])

        switch action {
        case "VIEW_TRANSACTION":
            if let transactionID = userInfo["transaction_id"] as? String {
                await MultiDeviceHandoff.shared.continueActivity(
                    type: .viewTransaction,
                    userInfo: ["transactionID": transactionID]
                )
            }

        case "REPORT_FRAUD":
            if let transactionID = userInfo["transaction_id"] as? String {
                await reportFraud(transactionID: transactionID)
            }

        case "VIEW_BUDGET":
            if let budgetID = userInfo["budget_id"] as? String {
                await MultiDeviceHandoff.shared.continueActivity(
                    type: .viewBudget,
                    userInfo: ["budgetID": budgetID]
                )
            }

        case "PAY_NOW":
            if let paymentID = userInfo["payment_id"] as? String {
                await processPayment(paymentID: paymentID)
            }

        case "RETRY_SYNC":
            await CloudKitManager.shared.performSync()

        case "SECURE_ACCOUNT":
            await lockAllCards()

        default:
            break
        }
    }

    private func reportFraud(transactionID: String) async {
        // Логика репорта фрода
        AnalyticsCollector.shared.logEvent("fraud_reported", parameters: [
            "transaction_id": transactionID
        ])
    }

    private func processPayment(paymentID: String) async {
        // Логика обработки платежа
        AnalyticsCollector.shared.logEvent("payment_initiated", parameters: [
            "payment_id": paymentID
        ])
    }

    private func lockAllCards() async {
        let context = CoreDataStack.shared.container.newBackgroundContext()
        await context.perform {
            let fetchRequest: NSFetchRequest<Card> = Card.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isActive == YES")

            do {
                let cards = try context.fetch(fetchRequest)
                for card in cards {
                    card.isLocked = true
                    card.lockReason = "Security alert triggered"
                }
                try context.save()
            } catch {
                AnalyticsCollector.shared.logError(error, context: "LockAllCards")
            }
        }
    }
}

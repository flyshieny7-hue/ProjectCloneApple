import Foundation
import CoreData
import Combine
import CryptoKit

/// Privacy-preserving analytics collector с differential privacy
/// iOS 26, использует local noise addition, data aggregation, opt-in consent
@MainActor
final class AnalyticsCollector: ObservableObject {

    // MARK: - Singleton
    static let shared = AnalyticsCollector()

    // MARK: - Published Properties
    @Published var isAnalyticsEnabled: Bool = true
    @Published var isPremiumUser: Bool = false
    @Published var eventsCountToday: Int = 0
    @Published var lastUploadDate: Date?

    // MARK: - Types
    struct AnalyticsEvent: Codable, Identifiable {
        let id: String
        let name: String
        let parameters: [String: String]
        let timestamp: Date
        let sessionID: String
        let deviceCategory: DeviceCategory
        let privacyLevel: PrivacyLevel

        enum DeviceCategory: String, Codable {
            case phone = "phone"
            case tablet = "tablet"
            case desktop = "desktop"
            case watch = "watch"
        }

        enum PrivacyLevel: String, Codable {
            case public_info = "public"      // Не содержит PII
            case sensitive = "sensitive"      // Требует noise
            case critical = "critical"        // Только локально
        }
    }

    struct AggregatedMetrics: Codable {
        let date: Date
        let sessionCount: Int
        let averageSessionDuration: Double
        let featureUsage: [String: Int]
        let errorCount: Int
        let crashCount: Int
        let syncSuccessRate: Double
        let deviceCategory: String
    }

    enum AnalyticsError: LocalizedError {
        case storageFull
        case encryptionFailed
        case uploadFailed
        case invalidEvent
        case privacyViolation
        case batchProcessingFailed

        var errorDescription: String? {
            switch self {
            case .storageFull: return "Local analytics storage is full"
            case .encryptionFailed: return "Failed to encrypt analytics data"
            case .uploadFailed: return "Failed to upload analytics batch"
            case .invalidEvent: return "Invalid analytics event"
            case .privacyViolation: return "Event violates privacy policy"
            case .batchProcessingFailed: return "Failed to process analytics batch"
            }
        }
    }

    // MARK: - Constants
    private enum Constants {
        static let maxLocalEvents = 10000
        static let batchSize = 100
        static let uploadInterval: TimeInterval = 86400 // 24 hours
        static let maxEventsPerDay = 1000
        static let epsilon: Double = 1.0 // Differential privacy parameter
        static let noiseScale: Double = 1.0 / Constants.epsilon
        static let analyticsKey = "com.wallet.analytics.enabled"
        static let eventsKey = "com.wallet.analytics.events"
        static let sessionIDKey = "com.wallet.analytics.session"
    }

    // MARK: - Properties
    private var events: [AnalyticsEvent] = []
    private let analyticsQueue = DispatchQueue(label: "com.wallet.analytics", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var sessionID: String
    private var uploadTimer: Timer?
    private var dailyEventCount = 0
    private var sessionStartTime: Date?

    // MARK: - Initialization
    private init() {
        self.isAnalyticsEnabled = UserDefaults.standard.bool(forKey: Constants.analyticsKey)
        self.sessionID = UserDefaults.standard.string(forKey: Constants.sessionIDKey) ?? UUID().uuidString
        self.sessionStartTime = Date()

        loadStoredEvents()
        setupPeriodicUpload()
        observeAppLifecycle()
    }

    // MARK: - Consent Management

    /// Запрашивает согласие пользователя на сбор аналитики
    func requestConsent() async -> Bool {
        // В реальном приложении показываем UI с объяснением
        // Здесь симулируем opt-in
        let consent = true // Пользователь дал согласие

        isAnalyticsEnabled = consent
        UserDefaults.standard.set(consent, forKey: Constants.analyticsKey)

        if consent {
            AnalyticsCollector.shared.logEvent("analytics_consent_granted")
        }

        return consent
    }

    /// Отзывает согласие и удаляет все данные
    func revokeConsent() async {
        isAnalyticsEnabled = false
        UserDefaults.standard.set(false, forKey: Constants.analyticsKey)

        // Удаляем все накопленные события
        await clearAllEvents()

        logEvent("analytics_consent_revoked", privacyLevel: .public_info)
    }

    // MARK: - Event Logging

    /// Логирует событие с differential privacy
    func logEvent(
        _ name: String,
        parameters: [String: Any] = [:],
        privacyLevel: AnalyticsEvent.PrivacyLevel = .public_info
    ) {
        guard isAnalyticsEnabled else { return }
        guard dailyEventCount < Constants.maxEventsPerDay else { return }

        // Проверяем на PII
        guard !containsPII(parameters) else {
            AnalyticsCollector.shared.logError(
                AnalyticsError.privacyViolation,
                context: "PII detected in event: \(name)"
            )
            return
        }

        let sanitizedParams = sanitizeParameters(parameters, privacyLevel: privacyLevel)

        // Добавляем noise для sensitive данных
        let noisedParams = privacyLevel == .sensitive
            ? addDifferentialPrivacyNoise(to: sanitizedParams)
            : sanitizedParams

        let event = AnalyticsEvent(
            id: UUID().uuidString,
            name: name,
            parameters: noisedParams,
            timestamp: Date(),
            sessionID: sessionID,
            deviceCategory: currentDeviceCategory(),
            privacyLevel: privacyLevel
        )

        analyticsQueue.async { [weak self] in
            self?.events.append(event)
            self?.dailyEventCount += 1

            // Сохраняем если достигли batch size
            if self?.events.count ?? 0 >= Constants.batchSize {
                Task { @MainActor in
                    await self?.processBatch()
                }
            }
        }

        eventsCountToday = dailyEventCount
    }

    /// Логирует ошибку
    func logError(_ error: Error, context: String) {
        let errorInfo: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error_description": error.localizedDescription,
            "context": context,
            "is_fatal": false
        ]

        logEvent("error_occurred", parameters: errorInfo, privacyLevel: .sensitive)
    }

    /// Логирует фатальный краш
    func logCrash(_ crashInfo: [String: Any]) {
        var params = crashInfo
        params["is_fatal"] = true
        params["timestamp"] = Date().timeIntervalSince1970

        logEvent("app_crash", parameters: params, privacyLevel: .critical)

        // Критические события сохраняем немедленно
        Task {
            await saveEventsImmediately()
        }
    }

    // MARK: - Differential Privacy

    /// Добавляет Laplace noise для differential privacy
    private func addDifferentialPrivacyNoise(to parameters: [String: String]) -> [String: String] {
        var noised = parameters

        // Добавляем noise к числовым значениям
        for (key, value) in parameters {
            if let numericValue = Double(value) {
                let noise = generateLaplaceNoise(scale: Constants.noiseScale)
                let noisedValue = max(0, numericValue + noise) // Не допускаем отрицательных
                noised[key] = String(format: "%.2f", noisedValue)
            }
        }

        return noised
    }

    /// Генерирует Laplace noise
    private func generateLaplaceNoise(scale: Double) -> Double {
        let u = Double.random(in: 0...1) - 0.5
        return -scale * sign(u) * log(1 - 2 * abs(u))
    }

    private func sign(_ value: Double) -> Double {
        return value >= 0 ? 1.0 : -1.0
    }

    // MARK: - PII Detection & Sanitization

    private func containsPII(_ parameters: [String: Any]) -> Bool {
        let piiKeywords = [
            "email", "phone", "address", "ssn", "password",
            "credit_card", "card_number", "name", "location",
            "coordinates", "ip_address", "device_id"
        ]

        for key in parameters.keys {
            let lowerKey = key.lowercased()
            if piiKeywords.contains(where: { lowerKey.contains($0) }) {
                return true
            }
        }

        return false
    }

    private func sanitizeParameters(
        _ parameters: [String: Any],
        privacyLevel: AnalyticsEvent.PrivacyLevel
    ) -> [String: String] {
        var sanitized: [String: String] = [:]

        for (key, value) in parameters {
            let stringValue = String(describing: value)

            switch privacyLevel {
            case .public_info:
                // Разрешаем все не-PII данные
                sanitized[key] = stringValue

            case .sensitive:
                // Хешируем идентификаторы
                if key.contains("id") || key.contains("ID") {
                    sanitized[key] = hashString(stringValue)
                } else {
                    sanitized[key] = stringValue
                }

            case .critical:
                // Только агрегированные метрики, без деталей
                sanitized[key] = "[redacted]"
            }
        }

        return sanitized
    }

    private func hashString(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // MARK: - Aggregation

    /// Создает агрегированные метрики для отправки
    func createAggregatedMetrics() -> AggregatedMetrics {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let todayEvents = events.filter {
            calendar.isDate($0.timestamp, inSameDayAs: today)
        }

        let sessions = Set(todayEvents.map { $0.sessionID }).count
        let duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0

        var featureUsage: [String: Int] = [:]
        for event in todayEvents {
            featureUsage[event.name, default: 0] += 1
        }

        let errors = todayEvents.filter { $0.name == "error_occurred" }.count
        let crashes = todayEvents.filter { $0.name == "app_crash" }.count

        return AggregatedMetrics(
            date: today,
            sessionCount: sessions,
            averageSessionDuration: duration,
            featureUsage: featureUsage,
            errorCount: errors,
            crashCount: crashes,
            syncSuccessRate: calculateSyncSuccessRate(from: todayEvents),
            deviceCategory: currentDeviceCategory().rawValue
        )
    }

    private func calculateSyncSuccessRate(from events: [AnalyticsEvent]) -> Double {
        let syncEvents = events.filter {
            $0.name.contains("sync") || $0.name.contains("cloudkit")
        }

        guard !syncEvents.isEmpty else { return 1.0 }

        let successes = syncEvents.filter {
            $0.parameters["status"] == "success"
        }.count

        return Double(successes) / Double(syncEvents.count)
    }

    // MARK: - Upload

    /// Загружает агрегированные метрики
    func uploadMetrics() async {
        guard isAnalyticsEnabled else { return }

        let metrics = createAggregatedMetrics()

        do {
            let data = try JSONEncoder().encode(metrics)
            let encrypted = try encryptForUpload(data)

            // В реальном приложении отправляем на analytics endpoint
            // Здесь сохраняем в CloudKit для демонстрации
            let record = CKRecord(recordType: "AnalyticsMetrics")
            record["metrics"] = encrypted
            record["date"] = metrics.date
            record["deviceCategory"] = metrics.deviceCategory

            let (saveResult, _) = try await CloudKitManager.shared.privateDatabase.modifyRecords(
                saving: [record],
                deleting: [],
                atomically: true
            )

            for result in saveResult {
                if case .success = result.1 {
                    // Очищаем отправленные события
                    await clearProcessedEvents()
                    lastUploadDate = Date()
                }
            }

        } catch {
            AnalyticsCollector.shared.logError(error, context: "AnalyticsUpload")
        }
    }

    private func encryptForUpload(_ data: Data) throws -> Data {
        // Используем симметричное шифрование для analytics data
        let key = SymmetricKey(size: .bits256)
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined ?? data
    }

    // MARK: - Batch Processing

    private func processBatch() async {
        guard events.count >= Constants.batchSize else { return }

        let batch = Array(events.prefix(Constants.batchSize))

        do {
            try await saveEventsToDisk(batch)
            events.removeFirst(Constants.batchSize)
        } catch {
            AnalyticsCollector.shared.logError(error, context: "BatchProcessing")
        }
    }

    private func saveEventsToDisk(_ events: [AnalyticsEvent]) async throws {
        let data = try JSONEncoder().encode(events)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analytics_\(UUID().uuidString).json")

        try data.write(to: url)
    }

    private func saveEventsImmediately() async {
        do {
            try await saveEventsToDisk(events)
            events.removeAll()
        } catch {
            print("Failed to save events: \(error)")
        }
    }

    // MARK: - Storage Management

    private func loadStoredEvents() {
        // Загружаем события из UserDefaults/диска
        // Упрощенная реализация
    }

    private func clearProcessedEvents() async {
        events.removeAll()
        dailyEventCount = 0
        eventsCountToday = 0
    }

    private func clearAllEvents() async {
        events.removeAll()
        dailyEventCount = 0
        eventsCountToday = 0

        // Удаляем файлы с диска
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("analytics_") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Periodic Upload

    private func setupPeriodicUpload() {
        uploadTimer = Timer.scheduledTimer(withTimeInterval: Constants.uploadInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.uploadMetrics()
            }
        }
    }

    // MARK: - App Lifecycle

    private func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.saveEventsImmediately()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.saveEventsImmediately()
                    await self?.uploadMetrics()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Helpers

    private func currentDeviceCategory() -> AnalyticsEvent.DeviceCategory {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .phone
        case .pad:
            return .tablet
        case .mac:
            return .desktop
        default:
            return .phone
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// Возвращает все события для отладки
    func getAllEvents() -> [AnalyticsEvent] {
        return events
    }

    /// Экспортирует события в JSON
    func exportEvents() throws -> Data {
        return try JSONEncoder().encode(events)
    }
    #endif
}

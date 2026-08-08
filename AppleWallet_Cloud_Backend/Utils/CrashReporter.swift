import Foundation
import UIKit
import Combine

/// Crash reporter с интеграцией Xcode Cloud / TestFlight
/// iOS 26, использует signal handling, exception catching, breadcrumb logging
@MainActor
final class CrashReporter: ObservableObject {

    // MARK: - Singleton
    static let shared = CrashReporter()

    // MARK: - Published Properties
    @Published var lastCrashInfo: CrashInfo?
    @Published var isCrashReporterEnabled: Bool = true
    @Published var pendingCrashReports: Int = 0
    @Published var isUploading: Bool = false

    // MARK: - Types
    struct CrashInfo: Codable, Identifiable {
        let id: String
        let timestamp: Date
        let exceptionType: String
        let exceptionReason: String?
        let stackTrace: [String]
        let threadInfo: [ThreadInfo]
        let deviceInfo: DeviceInfo
        let appInfo: AppInfo
        let breadcrumbs: [Breadcrumb]
        let memoryInfo: MemoryInfo
        let userActions: [String]
        let isFatal: Bool

        struct ThreadInfo: Codable {
            let number: Int
            let name: String?
            let isCrashed: Bool
            let stackTrace: [String]
        }

        struct DeviceInfo: Codable {
            let model: String
            let osVersion: String
            let osBuild: String
            let availableMemory: UInt64
            let totalMemory: UInt64
            let batteryLevel: Float
            let isLowPowerMode: Bool
            let thermalState: String
            let storageAvailable: Int64
        }

        struct AppInfo: Codable {
            let version: String
            let buildNumber: String
            let bundleIdentifier: String
            let installDate: Date?
            let launchCount: Int
            let sessionDuration: TimeInterval
            let previousSessionCrashed: Bool
        }

        struct MemoryInfo: Codable {
            let usedMemory: UInt64
            let freeMemory: UInt64
            let totalMemory: UInt64
            let memoryPressure: String
        }

        struct Breadcrumb: Codable {
            let timestamp: Date
            let category: String
            let message: String
            let level: BreadcrumbLevel
            let metadata: [String: String]

            enum BreadcrumbLevel: String, Codable {
                case debug, info, warning, error, critical
            }
        }
    }

    enum CrashReporterError: LocalizedError {
        case signalHandlingFailed
        case crashLogCorrupted
        case uploadFailed
        case insufficientStorage
        case symbolicationFailed
        case maxReportsReached

        var errorDescription: String? {
            switch self {
            case .signalHandlingFailed: return "Failed to setup signal handlers"
            case .crashLogCorrupted: return "Crash log data is corrupted"
            case .uploadFailed: return "Failed to upload crash report"
            case .insufficientStorage: return "Insufficient storage for crash logs"
            case .symbolicationFailed: return "Failed to symbolicate crash report"
            case .maxReportsReached: return "Maximum number of stored crash reports reached"
            }
        }
    }

    // MARK: - Constants
    private enum Constants {
        static let crashLogsDirectory = "CrashReports"
        static let maxStoredReports = 50
        static let maxBreadcrumbs = 100
        static let uploadInterval: TimeInterval = 3600 // 1 hour
        static let crashReportExtension = "crash"
        static let breadcrumbKey = "com.wallet.crashreporter.breadcrumbs"
        static let previousCrashKey = "com.wallet.crashreporter.previousCrash"
        static let launchCountKey = "com.wallet.crashreporter.launchCount"
        static let installDateKey = "com.wallet.crashreporter.installDate"
    }

    // MARK: - Properties
    private var breadcrumbs: [CrashInfo.Breadcrumb] = []
    private let crashQueue = DispatchQueue(label: "com.wallet.crashreporter", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?
    private var uploadTimer: Timer?
    private var previousExceptionHandler: NSUncaughtExceptionHandler?

    // MARK: - Initialization
    private init() {
        setupCrashHandlers()
        loadBreadcrumbs()
        setupPeriodicUpload()
        observeAppLifecycle()
        incrementLaunchCount()
    }

    // MARK: - Signal & Exception Handling

    private func setupCrashHandlers() {
        // NSException handler
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        // Signal handlers
        setupSignalHandler(.SIGABRT)
        setupSignalHandler(.SIGILL)
        setupSignalHandler(.SIGSEGV)
        setupSignalHandler(.SIGFPE)
        setupSignalHandler(.SIGBUS)
        setupSignalHandler(.SIGPIPE)

        // Check for previous crash
        checkPreviousCrash()
    }

    private func setupSignalHandler(_ signal: Int32) {
        var action = sigaction()
        action.sa_flags = SA_SIGINFO
        action.__sigaction_u.__sa_sigaction = { sig, info, context in
            CrashReporter.shared.handleSignal(sig, info: info, context: context)
        }

        sigemptyset(&action.sa_mask)
        sigaction(signal, &action, nil)
    }

    private func handleException(_ exception: NSException) {
        let crashInfo = createCrashInfo(
            exceptionType: exception.name.rawValue,
            exceptionReason: exception.reason,
            stackTrace: exception.callStackSymbols,
            isFatal: true
        )

        saveCrashReport(crashInfo)

        // Вызываем предыдущий handler
        previousExceptionHandler?(exception)
    }

    private func handleSignal(_ signal: Int32, info: UnsafeMutablePointer<siginfo_t>?, context: UnsafeMutablePointer<Void>?) {
        let signalName: String
        switch signal {
        case SIGABRT: signalName = "SIGABRT"
        case SIGILL: signalName = "SIGILL"
        case SIGSEGV: signalName = "SIGSEGV"
        case SIGFPE: signalName = "SIGFPE"
        case SIGBUS: signalName = "SIGBUS"
        case SIGPIPE: signalName = "SIGPIPE"
        default: signalName = "UNKNOWN(\(signal))"
        }

        let crashInfo = createCrashInfo(
            exceptionType: "Signal: \(signalName)",
            exceptionReason: "Fatal signal received",
            stackTrace: Thread.callStackSymbols,
            isFatal: true
        )

        saveCrashReport(crashInfo)
    }

    // MARK: - Crash Info Creation

    private func createCrashInfo(
        exceptionType: String,
        exceptionReason: String?,
        stackTrace: [String],
        isFatal: Bool
    ) -> CrashInfo {
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo

        let deviceInfo = CrashInfo.DeviceInfo(
            model: device.model,
            osVersion: device.systemVersion,
            osBuild: getOSBuild(),
            availableMemory: availableMemory(),
            totalMemory: processInfo.physicalMemory,
            batteryLevel: device.batteryLevel,
            isLowPowerMode: processInfo.isLowPowerModeEnabled,
            thermalState: thermalStateString(processInfo.thermalState),
            storageAvailable: availableStorage()
        )

        let appInfo = CrashInfo.AppInfo(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            installDate: UserDefaults.standard.object(forKey: Constants.installDateKey) as? Date,
            launchCount: UserDefaults.standard.integer(forKey: Constants.launchCountKey),
            sessionDuration: sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0,
            previousSessionCrashed: UserDefaults.standard.bool(forKey: Constants.previousCrashKey)
        )

        let memoryInfo = CrashInfo.MemoryInfo(
            usedMemory: usedMemory(),
            freeMemory: availableMemory(),
            totalMemory: processInfo.physicalMemory,
            memoryPressure: thermalStateString(processInfo.thermalState)
        )

        let threadInfo = collectThreadInfo()

        return CrashInfo(
            id: UUID().uuidString,
            timestamp: Date(),
            exceptionType: exceptionType,
            exceptionReason: exceptionReason,
            stackTrace: stackTrace,
            threadInfo: threadInfo,
            deviceInfo: deviceInfo,
            appInfo: appInfo,
            breadcrumbs: Array(breadcrumbs.suffix(50)), // Last 50 breadcrumbs
            memoryInfo: memoryInfo,
            userActions: [],
            isFatal: isFatal
        )
    }

    private func collectThreadInfo() -> [CrashInfo.ThreadInfo] {
        var threads: [CrashInfo.ThreadInfo] = []

        // Main thread
        threads.append(CrashInfo.ThreadInfo(
            number: 0,
            name: "main",
            isCrashed: true,
            stackTrace: Thread.callStackSymbols
        ))

        return threads
    }

    // MARK: - Breadcrumbs

    /// Добавляет breadcrumb для отслеживания действий пользователя
    func addBreadcrumb(
        category: String,
        message: String,
        level: CrashInfo.Breadcrumb.BreadcrumbLevel = .info,
        metadata: [String: String] = [:]
    ) {
        let breadcrumb = CrashInfo.Breadcrumb(
            timestamp: Date(),
            category: category,
            message: message,
            level: level,
            metadata: metadata
        )

        breadcrumbs.append(breadcrumb)

        // Ограничиваем количество
        if breadcrumbs.count > Constants.maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - Constants.maxBreadcrumbs)
        }

        saveBreadcrumbs()
    }

    /// Логирует действие пользователя
    func logUserAction(_ action: String, metadata: [String: String] = [:]) {
        addBreadcrumb(
            category: "user_action",
            message: action,
            level: .info,
            metadata: metadata
        )
    }

    /// Логирует навигацию
    func logNavigation(from: String, to: String) {
        addBreadcrumb(
            category: "navigation",
            message: "\(from) -> \(to)",
            level: .debug
        )
    }

    /// Логирует API call
    func logAPICall(endpoint: String, method: String, statusCode: Int? = nil) {
        var metadata: [String: String] = [
            "endpoint": endpoint,
            "method": method
        ]
        if let status = statusCode {
            metadata["status_code"] = String(status)
        }

        addBreadcrumb(
            category: "api",
            message: "\(method) \(endpoint)",
            level: statusCode == nil ? .info : (statusCode == 200 ? .info : .warning),
            metadata: metadata
        )
    }

    // MARK: - Crash Report Storage

    private func saveCrashReport(_ crashInfo: CrashInfo) {
        crashQueue.async { [weak self] in
            do {
                // Проверяем лимит
                let existingReports = self?.listCrashReports() ?? []
                if existingReports.count >= Constants.maxStoredReports {
                    // Удаляем самый старый
                    if let oldest = existingReports.first {
                        try? FileManager.default.removeItem(at: oldest)
                    }
                }

                let data = try JSONEncoder().encode(crashInfo)
                let url = self?.crashReportURL(for: crashInfo.id)

                if let url = url {
                    try data.write(to: url)

                    Task { @MainActor in
                        self?.pendingCrashReports += 1
                        self?.lastCrashInfo = crashInfo
                    }

                    // Mark previous crash
                    UserDefaults.standard.set(true, forKey: Constants.previousCrashKey)
                }
            } catch {
                AnalyticsCollector.shared.logError(error, context: "CrashReportSave")
            }
        }
    }

    private func crashReportURL(for id: String) -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let crashDir = documents.appendingPathComponent(Constants.crashLogsDirectory)
        try? FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)

        return crashDir.appendingPathComponent("\(id).\(Constants.crashReportExtension)")
    }

    private func listCrashReports() -> [URL] {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        let crashDir = documents.appendingPathComponent(Constants.crashLogsDirectory)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: crashDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return files.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 < date2
        }
    }

    // MARK: - Previous Crash Check

    private func checkPreviousCrash() {
        let hadPreviousCrash = UserDefaults.standard.bool(forKey: Constants.previousCrashKey)

        if hadPreviousCrash {
            // Загружаем последний краш
            let reports = listCrashReports()
            if let lastReport = reports.last,
               let data = try? Data(contentsOf: lastReport),
               let crashInfo = try? JSONDecoder().decode(CrashInfo.self, from: data) {
                lastCrashInfo = crashInfo
            }

            // Сбрасываем флаг
            UserDefaults.standard.set(false, forKey: Constants.previousCrashKey)
        }

        pendingCrashReports = listCrashReports().count
    }

    // MARK: - Upload

    /// Загружает все pending crash reports
    func uploadPendingReports() async {
        guard !isUploading else { return }
        isUploading = true

        defer { isUploading = false }

        let reports = listCrashReports()

        for reportURL in reports {
            do {
                let data = try Data(contentsOf: reportURL)
                let crashInfo = try JSONDecoder().decode(CrashInfo.self, from: data)

                try await uploadCrashReport(crashInfo)

                // Удаляем после успешной загрузки
                try FileManager.default.removeItem(at: reportURL)

                Task { @MainActor in
                    pendingCrashReports -= 1
                }

            } catch {
                AnalyticsCollector.shared.logError(error, context: "CrashReportUpload")
            }
        }
    }

    private func uploadCrashReport(_ crashInfo: CrashInfo) async throws {
        // В реальном приложении отправляем на crash reporting service
        // Для демонстрации сохраняем в CloudKit

        let record = CKRecord(recordType: "CrashReport")
        record["crashData"] = try JSONEncoder().encode(crashInfo)
        record["timestamp"] = crashInfo.timestamp
        record["exceptionType"] = crashInfo.exceptionType
        record["isFatal"] = crashInfo.isFatal
        record["appVersion"] = crashInfo.appInfo.version
        record["osVersion"] = crashInfo.deviceInfo.osVersion

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

        AnalyticsCollector.shared.logEvent("crash_report_uploaded", parameters: [
            "exception_type": crashInfo.exceptionType,
            "is_fatal": String(crashInfo.isFatal)
        ])
    }

    private func setupPeriodicUpload() {
        uploadTimer = Timer.scheduledTimer(withTimeInterval: Constants.uploadInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.uploadPendingReports()
            }
        }
    }

    // MARK: - Symbolication

    /// Символизирует crash report (для TestFlight builds)
    func symbolicateCrashReport(_ crashInfo: CrashInfo) -> CrashInfo {
        var symbolicated = crashInfo

        // В TestFlight builds stack trace уже содержит символы
        // Для production builds требуется dSYM
        #if DEBUG
        symbolicated.stackTrace = crashInfo.stackTrace.map { symbol in
            // Демо символизации
            if symbol.contains("0x") {
                return "\(symbol) [symbolicated]"
            }
            return symbol
        }
        #endif

        return symbolicated
    }

    // MARK: - Xcode Cloud / TestFlight Integration

    /// Подготавливает crash report для Xcode Cloud
    func prepareForXcodeCloud(_ crashInfo: CrashInfo) -> [String: Any] {
        return [
            "crash_id": crashInfo.id,
            "timestamp": crashInfo.timestamp.timeIntervalSince1970,
            "exception": crashInfo.exceptionType,
            "reason": crashInfo.exceptionReason ?? "unknown",
            "app_version": crashInfo.appInfo.version,
            "build": crashInfo.appInfo.buildNumber,
            "os_version": crashInfo.deviceInfo.osVersion,
            "device_model": crashInfo.deviceInfo.model,
            "stack_trace": crashInfo.stackTrace.joined(separator: "\n"),
            "breadcrumbs": crashInfo.breadcrumbs.map { "[\($0.level)] \($0.category): \($0.message)" },
            "is_fatal": crashInfo.isFatal
        ]
    }

    /// Экспортирует crash report в формате для TestFlight
    func exportForTestFlight() -> Data? {
        guard let lastCrash = lastCrashInfo else { return nil }
        let xcodeCloudData = prepareForXcodeCloud(lastCrash)
        return try? JSONSerialization.data(withJSONObject: xcodeCloudData, options: .prettyPrinted)
    }

    // MARK: - App Lifecycle

    private func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didFinishLaunchingNotification)
            .sink { [weak self] _ in
                self?.sessionStartTime = Date()
                self?.addBreadcrumb(
                    category: "app_lifecycle",
                    message: "App launched",
                    level: .info
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.addBreadcrumb(
                    category: "app_lifecycle",
                    message: "App entered background",
                    level: .info
                )
                Task { @MainActor in
                    await self?.saveBreadcrumbs()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.addBreadcrumb(
                    category: "app_lifecycle",
                    message: "App terminating",
                    level: .critical
                )
                Task { @MainActor in
                    await self?.saveBreadcrumbs()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Helpers

    private func getOSBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &build, &size, nil, 0)
        return String(cString: build)
    }

    private func availableMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }

    private func usedMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }

    private func availableStorage() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private func incrementLaunchCount() {
        let count = UserDefaults.standard.integer(forKey: Constants.launchCountKey) + 1
        UserDefaults.standard.set(count, forKey: Constants.launchCountKey)

        if UserDefaults.standard.object(forKey: Constants.installDateKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Constants.installDateKey)
        }
    }

    private func saveBreadcrumbs() {
        if let data = try? JSONEncoder().encode(breadcrumbs) {
            UserDefaults.standard.set(data, forKey: Constants.breadcrumbKey)
        }
    }

    private func loadBreadcrumbs() {
        guard let data = UserDefaults.standard.data(forKey: Constants.breadcrumbKey) else { return }
        breadcrumbs = (try? JSONDecoder().decode([CrashInfo.Breadcrumb].self, from: data)) ?? []
    }

    // MARK: - Cleanup

    /// Удаляет все crash reports
    func clearAllReports() {
        let reports = listCrashReports()
        for report in reports {
            try? FileManager.default.removeItem(at: report)
        }
        pendingCrashReports = 0
    }

    deinit {
        uploadTimer?.invalidate()
    }
}

// MARK: - Swift Error Reporting
extension CrashReporter {
    /// Отправляет non-fatal error
    func reportNonFatalError(_ error: Error, context: String) {
        let crashInfo = createCrashInfo(
            exceptionType: "NonFatalError: \(String(describing: type(of: error)))",
            exceptionReason: "\(context): \(error.localizedDescription)",
            stackTrace: Thread.callStackSymbols,
            isFatal: false
        )

        saveCrashReport(crashInfo)

        AnalyticsCollector.shared.logEvent("non_fatal_error", parameters: [
            "context": context,
            "error": error.localizedDescription
        ])
    }

    /// Отправляет custom exception
    func reportException(name: String, reason: String, userInfo: [String: Any] = [:]) {
        let crashInfo = createCrashInfo(
            exceptionType: name,
            exceptionReason: reason,
            stackTrace: Thread.callStackSymbols,
            isFatal: false
        )

        saveCrashReport(crashInfo)
    }
}

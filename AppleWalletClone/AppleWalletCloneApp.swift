import SwiftUI
import UIKit

@main
struct AppleWalletCloneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var restorationManager = StateRestorationManager()
    @StateObject private var performanceMonitor = PerformanceMonitor()
    @StateObject private var urlHandler = URLSchemeHandler()
    @StateObject private var tutorialManager = TutorialManager()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            MasterContentView()
                .environmentObject(appState)
                .environmentObject(restorationManager)
                .environmentObject(performanceMonitor)
                .environmentObject(urlHandler)
                .environmentObject(tutorialManager)
                .environmentObject(settings)
                .onOpenURL { url in
                    urlHandler.handle(url: url)
                }
                .onAppear {
                    restorationManager.restoreIfNeeded()
                    performanceMonitor.startMonitoring()
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAppearance()
        registerURLSchemes()
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        NotificationCenter.default.post(name: .universalLinkReceived, object: url)
        return true
    }

    private func configureAppearance() {
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = .systemBackground
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }

    private func registerURLSchemes() {
        // URL schemes registered in Info.plist
    }
}

extension Notification.Name {
    static let universalLinkReceived = Notification.Name("universalLinkReceived")
    static let shakeDetected = Notification.Name("shakeDetected")
    static let stateShouldRestore = Notification.Name("stateShouldRestore")
}

// MARK: - Global App State
class AppState: ObservableObject {
    @Published var isOnboardingComplete: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var selectedTab: Tab = .wallet
    @Published var showDebugMenu: Bool = false
    @Published var showPerformanceOverlay: Bool = false

    enum Tab: String, CaseIterable, Codable {
        case wallet, transactions, budget, settings

        var icon: String {
            switch self {
            case .wallet: return "wallet.pass"
            case .transactions: return "list.bullet.rectangle"
            case .budget: return "chart.pie"
            case .settings: return "gearshape"
            }
        }

        var title: String {
            switch self {
            case .wallet: return "Wallet"
            case .transactions: return "Activity"
            case .budget: return "Budget"
            case .settings: return "Settings"
            }
        }
    }
}

// MARK: - App Settings
class AppSettings: ObservableObject {
    @Published var hapticEnabled: Bool = true
    @Published var biometricAuth: Bool = true
    @Published var notificationsEnabled: Bool = true
    @Published var darkMode: Bool = false
    @Published var analyticsEnabled: Bool = true
    @Published var crashReporting: Bool = true
    @Published var autoLockTimeout: Double = 60
    @Published var currencyCode: String = "USD"
    @Published var language: String = "en"
    @Published var showPerformanceOverlay: Bool = false
    @Published var debugMode: Bool = false

    init() {
        loadSettings()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        hapticEnabled = defaults.bool(forKey: "hapticEnabled", defaultValue: true)
        biometricAuth = defaults.bool(forKey: "biometricAuth", defaultValue: true)
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled", defaultValue: true)
        darkMode = defaults.bool(forKey: "darkMode", defaultValue: false)
        analyticsEnabled = defaults.bool(forKey: "analyticsEnabled", defaultValue: true)
        crashReporting = defaults.bool(forKey: "crashReporting", defaultValue: true)
        autoLockTimeout = defaults.double(forKey: "autoLockTimeout", defaultValue: 60)
        currencyCode = defaults.string(forKey: "currencyCode") ?? "USD"
        language = defaults.string(forKey: "language") ?? "en"
        showPerformanceOverlay = defaults.bool(forKey: "showPerformanceOverlay", defaultValue: false)
        debugMode = defaults.bool(forKey: "debugMode", defaultValue: false)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(hapticEnabled, forKey: "hapticEnabled")
        defaults.set(biometricAuth, forKey: "biometricAuth")
        defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        defaults.set(darkMode, forKey: "darkMode")
        defaults.set(analyticsEnabled, forKey: "analyticsEnabled")
        defaults.set(crashReporting, forKey: "crashReporting")
        defaults.set(autoLockTimeout, forKey: "autoLockTimeout")
        defaults.set(currencyCode, forKey: "currencyCode")
        defaults.set(language, forKey: "language")
        defaults.set(showPerformanceOverlay, forKey: "showPerformanceOverlay")
        defaults.set(debugMode, forKey: "debugMode")
    }
}

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil { return defaultValue }
        return bool(forKey: key)
    }

    func double(forKey key: String, defaultValue: Double) -> Double {
        if object(forKey: key) == nil { return defaultValue }
        return double(forKey: key)
    }
}

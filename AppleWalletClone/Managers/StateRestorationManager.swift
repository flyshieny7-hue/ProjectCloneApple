import SwiftUI
import Combine

// MARK: - StateRestorationManager
/// Manages app state restoration after kill/background
@MainActor
final class StateRestorationManager: ObservableObject {

    // MARK: - Published Properties
    @Published var restoredTab: AppState.Tab?
    @Published var restoredPath: [Route]?
    @Published var isRestoring: Bool = false
    @Published var lastRestoredAt: Date?

    // MARK: - Keys
    private enum Keys {
        static let navigationPath = "restored_navigation_path"
        static let selectedTab = "restored_selected_tab"
        static let lastActiveTimestamp = "last_active_timestamp"
        static let appStateSnapshot = "app_state_snapshot"
        static let userSession = "restored_user_session"
    }

    // MARK: - Properties
    private var cancellables = Set<AnyCancellable>()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxRestorationAge: TimeInterval = 3600 // 1 hour

    // MARK: - Initialization
    init() {
        setupNotifications()
    }

    // MARK: - Setup
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.saveState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.saveState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkRestorationValidity()
            }
            .store(in: &cancellables)
    }

    // MARK: - Save State
    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastActiveTimestamp)

        // Save navigation path
        if let pathData = try? encoder.encode(restoredPath ?? []) {
            defaults.set(pathData, forKey: Keys.navigationPath)
        }

        // Save selected tab
        if let tabData = try? encoder.encode(restoredTab) {
            defaults.set(tabData, forKey: Keys.selectedTab)
        }

        // Save app state snapshot
        let snapshot = AppStateSnapshot(
            isOnboardingComplete: UserDefaults.standard.bool(forKey: "onboardingCompleted"),
            isAuthenticated: true,
            timestamp: Date()
        )
        if let snapshotData = try? encoder.encode(snapshot) {
            defaults.set(snapshotData, forKey: Keys.appStateSnapshot)
        }

        print("[StateRestoration] State saved at " + Date().description)
    }

    // MARK: - Restore State
    func restoreIfNeeded() {
        guard shouldRestore() else {
            clearSavedState()
            return
        }

        isRestoring = true

        let defaults = UserDefaults.standard

        // Restore navigation path
        if let pathData = defaults.data(forKey: Keys.navigationPath),
           let path = try? decoder.decode([Route].self, from: pathData) {
            restoredPath = path
        }

        // Restore selected tab
        if let tabData = defaults.data(forKey: Keys.selectedTab),
           let tab = try? decoder.decode(AppState.Tab.self, from: tabData) {
            restoredTab = tab
        }

        // Notify restoration complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRestoring = false
            self?.lastRestoredAt = Date()
            NotificationCenter.default.post(name: .stateShouldRestore, object: nil)
            print("[StateRestoration] State restored successfully")
        }
    }

    // MARK: - Validation
    private func shouldRestore() -> Bool {
        let defaults = UserDefaults.standard

        // Check if onboarding is complete
        guard defaults.bool(forKey: "onboardingCompleted") else { return false }

        // Check restoration age
        guard let lastActive = defaults.object(forKey: Keys.lastActiveTimestamp) as? TimeInterval else {
            return false
        }

        let age = Date().timeIntervalSince1970 - lastActive
        guard age < maxRestorationAge else {
            print("[StateRestoration] State too old, skipping restoration")
            return false
        }

        // Check app state snapshot
        if let snapshotData = defaults.data(forKey: Keys.appStateSnapshot),
           let snapshot = try? decoder.decode(AppStateSnapshot.self, from: snapshotData) {
            guard snapshot.isOnboardingComplete else { return false }
        }

        return true
    }

    private func checkRestorationValidity() {
        // Could add additional checks here (e.g., session expiry)
    }

    // MARK: - Clear State
    func clearSavedState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.navigationPath)
        defaults.removeObject(forKey: Keys.selectedTab)
        defaults.removeObject(forKey: Keys.lastActiveTimestamp)
        defaults.removeObject(forKey: Keys.appStateSnapshot)
        restoredPath = nil
        restoredTab = nil
        print("[StateRestoration] Saved state cleared")
    }

    // MARK: - Manual Save/Restore
    func manualSave(tab: AppState.Tab, path: [Route]) {
        restoredTab = tab
        restoredPath = path
        saveState()
    }

    func createCheckpoint(name: String) {
        let checkpoint = StateCheckpoint(
            name: name,
            tab: restoredTab,
            path: restoredPath,
            timestamp: Date()
        )
        if let data = try? encoder.encode(checkpoint) {
            var checkpoints = UserDefaults.standard.array(forKey: "state_checkpoints") as? [Data] ?? []
            checkpoints.append(data)
            if checkpoints.count > 10 { checkpoints.removeFirst() }
            UserDefaults.standard.set(checkpoints, forKey: "state_checkpoints")
        }
    }
}

// MARK: - Supporting Types
struct AppStateSnapshot: Codable {
    let isOnboardingComplete: Bool
    let isAuthenticated: Bool
    let timestamp: Date
}

struct StateCheckpoint: Codable {
    let name: String
    let tab: AppState.Tab?
    let path: [Route]?
    let timestamp: Date
}

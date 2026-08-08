import Foundation
import SwiftUI
import Combine

/// Главный координатор безопасности приложения
/// Объединяет все компоненты security layer
@MainActor
final class AppSecurityManager: ObservableObject {

    static let shared = AppSecurityManager()

    @Published var isLocked = true
    @Published var isJailbroken = false
    @Published var isScreenCaptured = false
    @Published var securityLevel: SecurityLevel = .standard

    let keychain = KeychainManager.shared
    let biometricAuth = BiometricAuthManager.shared
    let encryption = CardEncryption.shared
    let jailbreakDetector = JailbreakDetector.shared

    private var cancellables = Set<AnyCancellable>()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    enum SecurityLevel: String, CaseIterable {
        case basic = "Basic"
        case standard = "Standard"
        case high = "High"
        case maximum = "Maximum"

        var description: String {
            switch self {
            case .basic: return "PIN only"
            case .standard: return "PIN + Biometrics"
            case .high: return "PIN + Biometrics + Encryption"
            case .maximum: return "All protections + Secure Enclave"
            }
        }
    }

    private init() {
        setupObservers()
        initializeSecurity()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Отслеживание скриншотов
        NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
            .sink { [weak self] _ in
                self?.isScreenCaptured = UIScreen.main.isCaptured
            }
            .store(in: &cancellables)

        // Отслеживание jailbreak
        jailbreakDetector.$isJailbroken
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isJailbroken in
                self?.isJailbroken = isJailbroken
            }
            .store(in: &cancellables)

        // Блокировка при уходе в background
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.lockApp()
            }
            .store(in: &cancellables)

        // Проверка при возвращении
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.checkSecurityState()
            }
            .store(in: &cancellables)
    }

    private func initializeSecurity() {
        // Генерация master key при первом запуске
        _ = encryption.ensureMasterKey()

        // Проверка jailbreak
        isJailbroken = jailbreakDetector.isJailbroken

        // Проверка скриншотов
        isScreenCaptured = UIScreen.main.isCaptured

        // Установка уровня безопасности
        updateSecurityLevel()
    }

    // MARK: - App Lock

    func lockApp() {
        isLocked = true
        biometricAuth.lock()

        // Очистка чувствительных данных из памяти
        clearSensitiveCache()
    }

    func unlockApp() {
        isLocked = false
        biometricAuth.unlock()
    }

    func authenticateUser() async -> Bool {
        let result = await biometricAuth.authenticate()
        switch result {
        case .success:
            unlockApp()
            return true
        case .failure:
            return false
        }
    }

    // MARK: - Card Operations

    func addCard(
        cardholderName: String,
        cardNumber: String,
        cvv: String,
        expiryMonth: String,
        expiryYear: String,
        pin: String? = nil
    ) -> Card? {
        // Проверка jailbreak
        guard jailbreakDetector.canPerformSecureOperations() else {
            return nil
        }

        // Валидация
        guard Card.isValidCardNumber(cardNumber) else { return nil }
        guard cvv.count >= 3 && cvv.count <= 4 else { return nil }

        let cardType = Card.detectCardType(from: cardNumber)

        let card = Card(
            cardholderName: cardholderName,
            cardNumber: cardNumber,
            cvv: cvv,
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            cardType: cardType,
            pin: pin
        )

        return card
    }

    func deleteCard(_ card: Card) {
        card.deleteSecureData()
        // Удаление из SwiftData выполняется вне этого менеджера
    }

    // MARK: - Security Checks

    func checkSecurityState() {
        // Проверяем, нужно ли блокировать
        if !biometricAuth.isAuthenticated {
            isLocked = true
        }

        // Обновляем статус jailbreak
        jailbreakDetector.performDetection()

        // Проверяем скриншоты
        isScreenCaptured = UIScreen.main.isCaptured
    }

    func updateSecurityLevel() {
        let hasBiometrics = biometricAuth.biometricType != .none
        let hasPIN = biometricAuth.hasPIN()
        let hasEncryption = encryption.ensureMasterKey() != SymmetricKey(size: .bits128)

        if hasBiometrics && hasPIN && hasEncryption {
            securityLevel = .maximum
        } else if hasBiometrics && hasPIN {
            securityLevel = .high
        } else if hasPIN {
            securityLevel = .standard
        } else {
            securityLevel = .basic
        }
    }

    // MARK: - Anti-debugging

    func enableAntiDebugging() {
        #if !DEBUG
        // ptrace PT_DENY_ATTACH
        let ptraceRequest = PT_DENY_ATTACH
        ptrace(ptraceRequest, 0, 0, 0)
        #endif
    }

    // MARK: - Cleanup

    private func clearSensitiveCache() {
        // Очистка кешей, clipboard и т.д.
        UIPasteboard.general.string = nil
    }

    // MARK: - Security Report

    func generateSecurityReport() -> SecurityReport {
        return SecurityReport(
            isJailbroken: isJailbroken,
            isScreenCaptured: isScreenCaptured,
            biometricType: biometricAuth.biometricType,
            hasPIN: biometricAuth.hasPIN(),
            securityLevel: securityLevel,
            jailbreakMethods: jailbreakDetector.detectedMethods,
            isDebuggerAttached: jailbreakDetector.isBeingDebugged
        )
    }
}

// MARK: - Security Report

struct SecurityReport {
    let isJailbroken: Bool
    let isScreenCaptured: Bool
    let biometricType: BiometricAuthManager.BiometricType
    let hasPIN: Bool
    let securityLevel: AppSecurityManager.SecurityLevel
    let jailbreakMethods: [JailbreakDetector.DetectionMethod]
    let isDebuggerAttached: Bool

    var isSecure: Bool {
        !isJailbroken && !isDebuggerAttached
    }

    var summary: String {
        var parts: [String] = []
        parts.append("Security Level: \(securityLevel.rawValue)")
        parts.append("Biometrics: \(biometricType.rawValue)")
        parts.append("PIN: \(hasPIN ? "Set" : "Not set")")
        parts.append("Jailbreak: \(isJailbroken ? "DETECTED" : "Clean")")
        parts.append("Debugger: \(isDebuggerAttached ? "Attached" : "Not attached")")
        return parts.joined(separator: "\n")
    }
}

// MARK: - View Modifier

struct SecurityLockModifier: ViewModifier {
    @StateObject private var securityManager = AppSecurityManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: securityManager.isLocked ? 20 : 0)
                .disabled(securityManager.isLocked)

            if securityManager.isLocked {
                AppLockView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: securityManager.isLocked)
    }
}

extension View {
    func withSecurityLock() -> some View {
        modifier(SecurityLockModifier())
    }
}

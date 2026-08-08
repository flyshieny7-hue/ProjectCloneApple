import LocalAuthentication
import Combine
import SwiftUI

/// Менеджер биометрической аутентификации с fallback на PIN
@MainActor
final class BiometricAuthManager: ObservableObject {

    static let shared = BiometricAuthManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var biometricType: BiometricType = .none
    @Published private(set) var isAvailable = false
    @Published private(set) var lastError: AuthenticationError?

    private let context = LAContext()
    private var pinCode: String?
    private var cancellables = Set<AnyCancellable>()

    enum BiometricType: String, CaseIterable {
        case none = "Нет биометрии"
        case touchID = "Touch ID"
        case faceID = "Face ID"
        case opticID = "Optic ID"

        var icon: String {
            switch self {
            case .none: return "lock.fill"
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            case .opticID: return "eye.fill"
            }
        }

        var animationName: String {
            switch self {
            case .faceID, .opticID: return "faceid"
            case .touchID: return "touchid"
            default: return "lock.fill"
            }
        }
    }

    enum AuthenticationError: LocalizedError {
        case biometricFailed
        case pinMismatch
        case pinNotSet
        case cancelled
        case systemError(String)
        case notAvailable
        case lockout

        var errorDescription: String? {
            switch self {
            case .biometricFailed: return "Биометрия не распознана"
            case .pinMismatch: return "Неверный PIN-код"
            case .pinNotSet: return "PIN-код не установлен"
            case .cancelled: return "Аутентификация отменена"
            case .systemError(let msg): return msg
            case .notAvailable: return "Биометрия недоступна"
            case .lockout: return "Слишком много попыток. Попробуйте позже."
            }
        }
    }

    private init() {
        evaluateBiometricType()
    }

    // MARK: - Biometric Evaluation

    func evaluateBiometricType() {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if canEvaluate {
            switch context.biometryType {
            case .faceID: biometricType = .faceID
            case .touchID: biometricType = .touchID
            case .opticID: biometricType = .opticID
            default: biometricType = .none
            }
            isAvailable = true
        } else {
            biometricType = .none
            isAvailable = false
        }
    }

    // MARK: - Authentication

    func authenticateWithBiometrics(reason: String = "Разблокируйте приложение") async -> Result<Void, AuthenticationError> {
        let context = LAContext()
        context.localizedCancelTitle = "Отмена"
        context.localizedFallbackTitle = "Использовать PIN"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if success {
                await MainActor.run {
                    self.isAuthenticated = true
                    self.lastError = nil
                }
                return .success(())
            } else {
                return .failure(.biometricFailed)
            }
        } catch let error as LAError {
            let authError: AuthenticationError
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                authError = .cancelled
            case .biometryLockout:
                authError = .lockout
            case .biometryNotAvailable:
                authError = .notAvailable
            default:
                authError = .systemError(error.localizedDescription)
            }
            await MainActor.run {
                self.lastError = authError
            }
            return .failure(authError)
        } catch {
            return .failure(.systemError(error.localizedDescription))
        }
    }

    func authenticateWithPIN(_ pin: String, cardID: UUID? = nil) async -> Result<Void, AuthenticationError> {
        let storedPIN: String?

        if let cardID = cardID {
            storedPIN = KeychainManager.shared.retrievePIN(cardID: cardID)
        } else {
            storedPIN = KeychainManager.shared.retrieveString(account: "app_pin_code")
        }

        guard let stored = storedPIN else {
            await MainActor.run { self.lastError = .pinNotSet }
            return .failure(.pinNotSet)
        }

        if pin == stored {
            await MainActor.run {
                self.isAuthenticated = true
                self.lastError = nil
            }
            return .success(())
        } else {
            await MainActor.run {
                self.lastError = .pinMismatch
            }
            return .failure(.pinMismatch)
        }
    }

    func authenticate(reason: String = "Разблокируйте приложение", cardID: UUID? = nil) async -> Result<Void, AuthenticationError> {
        // Сначала пробуем биометрию
        if isAvailable {
            let result = await authenticateWithBiometrics(reason: reason)
            switch result {
            case .success: return result
            case .failure(let error):
                if case .cancelled = error {
                    // Пользователь отменил — предлагаем PIN
                    return .failure(.cancelled)
                }
                // При lockout или других ошибках переходим на PIN
            }
        }

        // Fallback на PIN
        return .failure(.notAvailable)
    }

    // MARK: - PIN Management

    func setPIN(_ pin: String, cardID: UUID? = nil) -> Bool {
        guard pin.count >= 4, pin.count <= 6, pin.allSatisfy({ $0.isNumber }) else {
            return false
        }

        if let cardID = cardID {
            return KeychainManager.shared.savePIN(pin, cardID: cardID)
        } else {
            return KeychainManager.shared.saveString(pin, account: "app_pin_code")
        }
    }

    func hasPIN(cardID: UUID? = nil) -> Bool {
        if let cardID = cardID {
            return KeychainManager.shared.retrievePIN(cardID: cardID) != nil
        } else {
            return KeychainManager.shared.retrieveString(account: "app_pin_code") != nil
        }
    }

    func lock() {
        isAuthenticated = false
    }

    func unlock() {
        isAuthenticated = true
    }
}

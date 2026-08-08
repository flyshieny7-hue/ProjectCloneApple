import Foundation
import Security
import CryptoKit
import LocalAuthentication

/// Менеджер синхронизации зашифрованных данных через iCloud Keychain
/// iOS 26, использует SecItem API, CryptoKit, biometric auth
@MainActor
final class iCloudKeychainSync: ObservableObject {

    // MARK: - Singleton
    static let shared = iCloudKeychainSync()

    // MARK: - Published Properties
    @Published var isKeychainAccessible: Bool = false
    @Published var biometricAuthAvailable: Bool = false
    @Published var lastSyncDate: Date?

    // MARK: - Types
    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case invalidStatus
        case conversionFailed
        case encryptionFailed
        case biometricAuthFailed
        case keychainLocked
        case syncDisabled
        case invalidAccessGroup

        var errorDescription: String? {
            switch self {
            case .itemNotFound: return "Item not found in keychain"
            case .duplicateItem: return "Item already exists in keychain"
            case .invalidStatus: return "Invalid keychain status"
            case .conversionFailed: return "Failed to convert data"
            case .encryptionFailed: return "Encryption/Decryption failed"
            case .biometricAuthFailed: return "Biometric authentication failed"
            case .keychainLocked: return "Keychain is locked"
            case .syncDisabled: return "iCloud Keychain sync is disabled"
            case .invalidAccessGroup: return "Invalid access group"
            }
        }
    }

    enum KeychainItem {
        case cardNumber(cardID: String)
        case cardCVV(cardID: String)
        case userPIN
        case encryptionKey
        case syncToken
        case biometricKey

        var service: String {
            switch self {
            case .cardNumber: return "com.wallet.keychain.card.number"
            case .cardCVV: return "com.wallet.keychain.card.cvv"
            case .userPIN: return "com.wallet.keychain.user.pin"
            case .encryptionKey: return "com.wallet.keychain.encryption"
            case .syncToken: return "com.wallet.keychain.sync"
            case .biometricKey: return "com.wallet.keychain.biometric"
            }
        }

        var account: String {
            switch self {
            case .cardNumber(let id): return "card_\(id)_number"
            case .cardCVV(let id): return "card_\(id)_cvv"
            case .userPIN: return "user_pin"
            case .encryptionKey: return "encryption_key"
            case .syncToken: return "sync_token"
            case .biometricKey: return "biometric_key"
            }
        }
    }

    // MARK: - Constants
    private enum Constants {
        static let accessGroup = "com.wallet.shared"
        static let biometricReason = "Authenticate to access secure wallet data"
        static let maxRetryAttempts = 3
        static let keychainRetryDelay: TimeInterval = 0.5
    }

    // MARK: - Properties
    private let context = LAContext()
    private var symmetricKey: SymmetricKey?
    private let keychainQueue = DispatchQueue(label: "com.wallet.keychain", qos: .userInitiated)

    // MARK: - Initialization
    private init() {
        checkKeychainAccessibility()
        checkBiometricAvailability()
        setupEncryptionKey()
    }

    // MARK: - Availability Checks

    private func checkKeychainAccessibility() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "test_accessibility",
            kSecReturnAttributes as String: true
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        isKeychainAccessible = (status == errSecSuccess || status == errSecItemNotFound)
    }

    private func checkBiometricAvailability() {
        var error: NSError?
        biometricAuthAvailable = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }

    // MARK: - Encryption Key Management

    private func setupEncryptionKey() {
        do {
            if let keyData = try retrieve(item: .encryptionKey) {
                symmetricKey = SymmetricKey(data: keyData)
            } else {
                // Генерируем новый ключ
                let newKey = SymmetricKey(size: .bits256)
                try store(item: .encryptionKey, data: newKey.withUnsafeBytes { Data($0) })
                symmetricKey = newKey
            }
        } catch {
            AnalyticsCollector.shared.logError(error, context: "EncryptionKeySetup")
        }
    }

    // MARK: - CRUD Operations

    /// Сохраняет данные в iCloud Keychain
    func store(item: KeychainItem, data: Data, biometricRequired: Bool = false) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: biometricRequired
                ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: true // iCloud sync
        ]

        if biometricRequired {
            let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                nil
            )
            query[kSecAttrAccessControl as String] = accessControl
        }

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Обновляем существующий
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: item.service,
                kSecAttrAccount as String: item.account
            ]

            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)

            guard updateStatus == errSecSuccess else {
                throw KeychainError.invalidStatus
            }
        } else if status != errSecSuccess {
            throw KeychainError.invalidStatus
        }
    }

    /// Получает данные из iCloud Keychain
    func retrieve(item: KeychainItem, prompt: String? = nil) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let prompt = prompt {
            query[kSecUseOperationPrompt as String] = prompt
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.invalidStatus
        }

        guard let data = result as? Data else {
            throw KeychainError.conversionFailed
        }

        return data
    }

    /// Удаляет данные из iCloud Keychain
    func delete(item: KeychainItem) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
            kSecAttrSynchronizable as String: true
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.invalidStatus
        }
    }

    /// Обновляет данные в iCloud Keychain
    func update(item: KeychainItem, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            throw KeychainError.invalidStatus
        }
    }

    // MARK: - Encryption/Decryption

    /// Шифрует данные с использованием симметричного ключа
    func encrypt(_ data: Data) throws -> Data {
        guard let key = symmetricKey else {
            throw KeychainError.encryptionFailed
        }

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined ?? data
        } catch {
            throw KeychainError.encryptionFailed
        }
    }

    /// Дешифрует данные
    func decrypt(_ data: Data) throws -> Data {
        guard let key = symmetricKey else {
            throw KeychainError.encryptionFailed
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw KeychainError.encryptionFailed
        }
    }

    // MARK: - Biometric Authentication

    /// Запрашивает биометрическую аутентификацию
    func authenticateWithBiometrics(reason: String = Constants.biometricReason) async throws -> Bool {
        guard biometricAuthAvailable else {
            throw KeychainError.biometricAuthFailed
        }

        let context = LAContext()
        context.localizedReason = reason

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch {
            throw KeychainError.biometricAuthFailed
        }
    }

    /// Сохраняет данные с требованием биометрии
    func storeWithBiometricProtection(item: KeychainItem, data: Data) throws {
        try store(item: item, data: data, biometricRequired: true)
    }

    /// Получает данные с биометрической аутентификацией
    func retrieveWithBiometric(item: KeychainItem, prompt: String) async throws -> Data? {
        let authenticated = try await authenticateWithBiometrics(reason: prompt)
        guard authenticated else { return nil }

        return try retrieve(item: item, prompt: prompt)
    }

    // MARK: - Card Data Management

    /// Сохраняет зашифрованный номер карты
    func storeCardNumber(cardID: String, number: String) throws {
        guard let data = number.data(using: .utf8) else {
            throw KeychainError.conversionFailed
        }

        let encrypted = try encrypt(data)
        try store(item: .cardNumber(cardID: cardID), data: encrypted, biometricRequired: true)
    }

    /// Получает расшифрованный номер карты
    func retrieveCardNumber(cardID: String) async throws -> String? {
        guard let encryptedData = try retrieveWithBiometric(
            item: .cardNumber(cardID: cardID),
            prompt: "Authenticate to view card number"
        ) else {
            return nil
        }

        let decrypted = try decrypt(encryptedData)
        return String(data: decrypted, encoding: .utf8)
    }

    /// Сохраняет CVV
    func storeCardCVV(cardID: String, cvv: String) throws {
        guard let data = cvv.data(using: .utf8) else {
            throw KeychainError.conversionFailed
        }

        let encrypted = try encrypt(data)
        try store(item: .cardCVV(cardID: cardID), data: encrypted, biometricRequired: true)
    }

    /// Получает CVV
    func retrieveCardCVV(cardID: String) async throws -> String? {
        guard let encryptedData = try retrieveWithBiometric(
            item: .cardCVV(cardID: cardID),
            prompt: "Authenticate to view CVV"
        ) else {
            return nil
        }

        let decrypted = try decrypt(encryptedData)
        return String(data: decrypted, encoding: .utf8)
    }

    /// Удаляет все данные карты
    func deleteCardData(cardID: String) throws {
        try delete(item: .cardNumber(cardID: cardID))
        try delete(item: .cardCVV(cardID: cardID))
    }

    // MARK: - PIN Management

    /// Сохраняет PIN код
    func storePIN(_ pin: String) throws {
        guard let data = pin.data(using: .utf8) else {
            throw KeychainError.conversionFailed
        }

        let encrypted = try encrypt(data)
        try store(item: .userPIN, data: encrypted, biometricRequired: true)
    }

    /// Проверяет PIN код
    func verifyPIN(_ pin: String) async throws -> Bool {
        guard let encryptedData = try retrieve(item: .userPIN) else {
            return false
        }

        let decrypted = try decrypt(encryptedData)
        guard let storedPIN = String(data: decrypted, encoding: .utf8) else {
            return false
        }

        return storedPIN == pin
    }

    // MARK: - Sync Token

    /// Сохраняет токен синхронизации
    func storeSyncToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.conversionFailed
        }

        try store(item: .syncToken, data: data)
        lastSyncDate = Date()
    }

    /// Получает токен синхронизации
    func retrieveSyncToken() throws -> String? {
        guard let data = try retrieve(item: .syncToken) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Cleanup

    /// Удаляет все wallet данные из keychain
    func clearAllWalletData() throws {
        let items: [KeychainItem] = [
            .userPIN,
            .encryptionKey,
            .syncToken,
            .biometricKey
        ]

        for item in items {
            try? delete(item: item)
        }

        // Удаляем данные всех карт (требуется enumeration)
        // В реальном приложении храним список card IDs
    }

    /// Проверяет статус синхронизации iCloud Keychain
    func checkSyncStatus() async -> Bool {
        // Проверяем наличие sync token
        return (try? retrieveSyncToken()) != nil
    }
}

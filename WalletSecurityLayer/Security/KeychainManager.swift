import Foundation
import Security
import CryptoKit

/// Универсальный менеджер Keychain для хранения чувствительных данных
/// CVV, номера карт, PIN-коды — всё шифруется перед сохранением
@MainActor
final class KeychainManager: ObservableObject {

    static let shared = KeychainManager()

    private let service = "com.walletapp.security"
    private let accessGroup: String?

    /// Уровни доступа к Keychain
    enum Accessibility {
        case whenUnlocked
        case afterFirstUnlock
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlockThisDeviceOnly
        case whenPasscodeSetThisDeviceOnly

        var secAttr: CFString {
            switch self {
            case .whenUnlocked: return kSecAttrAccessibleWhenUnlocked
            case .afterFirstUnlock: return kSecAttrAccessibleAfterFirstUnlock
            case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenPasscodeSetThisDeviceOnly: return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            }
        }
    }

    private init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    // MARK: - Save

    @discardableResult
    func save(
        data: Data,
        account: String,
        accessibility: Accessibility = .whenUnlockedThisDeviceOnly
    ) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility.secAttr
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Удаляем существующую запись
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    @discardableResult
    func saveString(
        _ string: String,
        account: String,
        accessibility: Accessibility = .whenUnlockedThisDeviceOnly
    ) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data: data, account: account, accessibility: accessibility)
    }

    // MARK: - Retrieve

    func retrieve(account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    func retrieveString(account: String) -> String? {
        guard let data = retrieve(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    @discardableResult
    func delete(account: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Card-specific helpers

    func saveCardNumber(_ number: String, cardID: UUID) -> Bool {
        let key = "card_\(cardID.uuidString)_number"
        return saveString(number, account: key, accessibility: .whenUnlockedThisDeviceOnly)
    }

    func retrieveCardNumber(cardID: UUID) -> String? {
        let key = "card_\(cardID.uuidString)_number"
        return retrieveString(account: key)
    }

    func deleteCardNumber(cardID: UUID) -> Bool {
        let key = "card_\(cardID.uuidString)_number"
        return delete(account: key)
    }

    func saveCVV(_ cvv: String, cardID: UUID) -> Bool {
        let key = "card_\(cardID.uuidString)_cvv"
        return saveString(cvv, account: key, accessibility: .whenUnlockedThisDeviceOnly)
    }

    func retrieveCVV(cardID: UUID) -> String? {
        let key = "card_\(cardID.uuidString)_cvv"
        return retrieveString(account: key)
    }

    func deleteCVV(cardID: UUID) -> Bool {
        let key = "card_\(cardID.uuidString)_cvv"
        return delete(account: key)
    }

    func savePIN(_ pin: String, cardID: UUID) -> Bool {
        let key = "card_\(cardID.uuidString)_pin"
        return saveString(pin, account: key, accessibility: .whenPasscodeSetThisDeviceOnly)
    }

    func retrievePIN(cardID: UUID) -> String? {
        let key = "card_\(cardID.uuidString)_pin"
        return retrieveString(account: key)
    }

    func deletePIN(cardID: UUID) -> Bool {
        let key = "card_\(cardID.uuidString)_pin"
        return delete(account: key)
    }

    // MARK: - Master Key для шифрования

    func saveMasterKey(_ key: SymmetricKey) -> Bool {
        let keyData = key.withUnsafeBytes { Data($0) }
        return save(data: keyData, account: "master_encryption_key", accessibility: .whenUnlockedThisDeviceOnly)
    }

    func retrieveMasterKey() -> SymmetricKey? {
        guard let data = retrieve(account: "master_encryption_key") else { return nil }
        return SymmetricKey(data: data)
    }

    func generateAndSaveMasterKey() -> SymmetricKey {
        if let existing = retrieveMasterKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        _ = saveMasterKey(key)
        return key
    }

    // MARK: - Secure Enclave Key

    func saveSecureEnclaveKey(_ privateKey: SecKey, identifier: String) -> Bool {
        let tag = "se_\(identifier)".data(using: .utf8)!

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecValueRef as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(attributes as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    func retrieveSecureEnclaveKey(identifier: String) -> SecKey? {
        let tag = "se_\(identifier)".data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecReturnRef as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return (result as! SecKey)
    }

    // MARK: - Cleanup

    func deleteAllCardData(cardID: UUID) {
        deleteCardNumber(cardID: cardID)
        deleteCVV(cardID: cardID)
        deletePIN(cardID: cardID)
    }
}

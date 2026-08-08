import Foundation
import CryptoKit
import Security

/// Менеджер шифрования карт с использованием AES-256-GCM
/// Интеграция с SecureEnclave для защиты ключей
@MainActor
final class CardEncryption {

    static let shared = CardEncryption()

    private let keychain = KeychainManager.shared
    private var masterKey: SymmetricKey?

    private init() {
        self.masterKey = keychain.retrieveMasterKey()
    }

    // MARK: - Master Key

    func ensureMasterKey() -> SymmetricKey {
        if let key = masterKey {
            return key
        }
        let key = keychain.generateAndSaveMasterKey()
        masterKey = key
        return key
    }

    // MARK: - AES-256-GCM Encryption

    /// Шифрует строку с использованием AES-256-GCM
    func encrypt(_ string: String) throws -> Data {
        let key = ensureMasterKey()
        let data = Data(string.utf8)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        // Собираем nonce + ciphertext + tag
        var result = Data()
        result.append(Data(nonce))
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)

        return result
    }

    /// Дешифрует данные
    func decrypt(_ data: Data) throws -> String {
        let key = ensureMasterKey()

        // Разбираем: nonce (12 bytes) + ciphertext + tag (16 bytes)
        guard data.count > 28 else {
            throw EncryptionError.invalidData
        }

        let nonceData = data.prefix(12)
        let tagData = data.suffix(16)
        let ciphertext = data.dropFirst(12).dropLast(16)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tagData)
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw EncryptionError.decodingFailed
        }
        return string
    }

    // MARK: - Secure Enclave Encryption

    /// Создает ключ в Secure Enclave для дополнительной защиты
    func createSecureEnclaveKey(identifier: String) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: "se_\(identifier)",
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw EncryptionError.secureEnclaveError(error.localizedDescription)
            }
            throw EncryptionError.keyGenerationFailed
        }

        // Сохраняем ссылку в Keychain
        _ = keychain.saveSecureEnclaveKey(privateKey, identifier: identifier)

        return privateKey
    }

    /// Получает публичный ключ для шифрования
    func getPublicKey(for identifier: String) throws -> SecKey {
        guard let privateKey = keychain.retrieveSecureEnclaveKey(identifier: identifier) else {
            throw EncryptionError.keyNotFound
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw EncryptionError.publicKeyExtractionFailed
        }

        return publicKey
    }

    /// Шифрует данные с помощью публичного ключа (Secure Enclave)
    func encryptWithSecureEnclave(_ data: Data, identifier: String) throws -> Data {
        let publicKey = try getPublicKey(for: identifier)

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .eciesEncryptionCofactorX963SHA256AESGCM,
            data as CFData,
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                throw EncryptionError.encryptionFailed(error.localizedDescription)
            }
            throw EncryptionError.encryptionFailed("Unknown error")
        }

        return encrypted as Data
    }

    /// Дешифрует данные с помощью приватного ключа (Secure Enclave)
    func decryptWithSecureEnclave(_ data: Data, identifier: String) throws -> Data {
        guard let privateKey = keychain.retrieveSecureEnclaveKey(identifier: identifier) else {
            throw EncryptionError.keyNotFound
        }

        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(
            privateKey,
            .eciesEncryptionCofactorX963SHA256AESGCM,
            data as CFData,
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                throw EncryptionError.decryptionFailed(error.localizedDescription)
            }
            throw EncryptionError.decryptionFailed("Unknown error")
        }

        return decrypted as Data
    }

    // MARK: - Hash

    /// Создает SHA-256 hash для хранения в SwiftData
    func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Создает хеш с солью для дополнительной защиты
    func hashWithSalt(_ string: String, salt: String = "WalletAppSalt2026") -> String {
        let combined = string + salt
        return hash(combined)
    }

    // MARK: - Card-specific helpers

    /// Полное сохранение карты: шифрует в Keychain, возвращает hash для SwiftData
    func secureStoreCard(
        cardID: UUID,
        cardNumber: String,
        cvv: String,
        pin: String? = nil
    ) -> (numberHash: String, cvvHash: String) {
        let encryption = CardEncryption.shared

        // 1. Шифруем и сохраняем номер карты
        if let encryptedNumber = try? encryption.encrypt(cardNumber) {
            _ = KeychainManager.shared.saveCardNumber(encryptedNumber.base64EncodedString(), cardID: cardID)
        }

        // 2. Шифруем и сохраняем CVV
        if let encryptedCVV = try? encryption.encrypt(cvv) {
            _ = KeychainManager.shared.saveCVV(encryptedCVV.base64EncodedString(), cardID: cardID)
        }

        // 3. Сохраняем PIN если есть
        if let pin = pin {
            _ = KeychainManager.shared.savePIN(pin, cardID: cardID)
        }

        // 4. Возвращаем hash для SwiftData
        let numberHash = hash(cardNumber)
        let cvvHash = hash(cvv)

        return (numberHash, cvvHash)
    }

    /// Дешифрует номер карты из Keychain
    func decryptCardNumber(cardID: UUID) -> String? {
        guard let encryptedBase64 = KeychainManager.shared.retrieveCardNumber(cardID: cardID),
              let encryptedData = Data(base64Encoded: encryptedBase64) else {
            return nil
        }
        return try? decrypt(encryptedData)
    }

    /// Дешифрует CVV из Keychain
    func decryptCVV(cardID: UUID) -> String? {
        guard let encryptedBase64 = KeychainManager.shared.retrieveCVV(cardID: cardID),
              let encryptedData = Data(base64Encoded: encryptedBase64) else {
            return nil
        }
        return try? decrypt(encryptedData)
    }

    // MARK: - Errors

    enum EncryptionError: Error, LocalizedError {
        case invalidData
        case decodingFailed
        case keyGenerationFailed
        case secureEnclaveError(String)
        case keyNotFound
        case publicKeyExtractionFailed
        case encryptionFailed(String)
        case decryptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidData: return "Неверный формат зашифрованных данных"
            case .decodingFailed: return "Ошибка декодирования"
            case .keyGenerationFailed: return "Не удалось сгенерировать ключ"
            case .secureEnclaveError(let msg): return "Secure Enclave: \(msg)"
            case .keyNotFound: return "Ключ не найден"
            case .publicKeyExtractionFailed: return "Не удалось извлечь публичный ключ"
            case .encryptionFailed(let msg): return "Ошибка шифрования: \(msg)"
            case .decryptionFailed(let msg): return "Ошибка дешифрования: \(msg)"
            }
        }
    }
}

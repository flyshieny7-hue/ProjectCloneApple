import Foundation
import SwiftData
import CryptoKit

/// Модель карты с защищённым хранением чувствительных данных
/// cardNumber и cvv хранятся в Keychain (шифрованные), в SwiftData — только hash
@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var cardholderName: String
    var expiryMonth: String
    var expiryYear: String
    var cardTypeRaw: String
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    // В SwiftData храним только hash чувствительных данных
    var cardNumberHash: String
    var cvvHash: String

    // Не храним в SwiftData — только в Keychain
    @Transient var cardNumber: String? {
        get {
            CardEncryption.shared.decryptCardNumber(cardID: id)
        }
        set {
            // Setter для удобства, но реальное сохранение через secureStore
        }
    }

    @Transient var cvv: String? {
        get {
            CardEncryption.shared.decryptCVV(cardID: id)
        }
        set {
            // Setter для удобства
        }
    }

    var cardType: CardType? {
        get { CardType(rawValue: cardTypeRaw) }
        set { cardTypeRaw = newValue?.rawValue ?? CardType.other.rawValue }
    }

    /// Инициализатор для создания новой карты с безопасным хранением
    init(
        cardholderName: String,
        cardNumber: String,
        cvv: String,
        expiryMonth: String,
        expiryYear: String,
        cardType: CardType = .other,
        pin: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = UUID()
        self.cardholderName = cardholderName
        self.expiryMonth = expiryMonth
        self.expiryYear = expiryYear
        self.cardTypeRaw = cardType.rawValue
        self.isDefault = isDefault
        self.createdAt = Date()
        self.updatedAt = Date()

        // Сохраняем чувствительные данные в Keychain
        let hashes = CardEncryption.shared.secureStoreCard(
            cardID: self.id,
            cardNumber: cardNumber,
            cvv: cvv,
            pin: pin
        )

        self.cardNumberHash = hashes.numberHash
        self.cvvHash = hashes.cvvHash
    }

    /// Обновление чувствительных данных
    func updateSensitiveData(
        cardNumber: String? = nil,
        cvv: String? = nil,
        pin: String? = nil
    ) {
        if let number = cardNumber {
            if let encrypted = try? CardEncryption.shared.encrypt(number) {
                _ = KeychainManager.shared.saveCardNumber(
                    encrypted.base64EncodedString(),
                    cardID: id
                )
                self.cardNumberHash = CardEncryption.shared.hash(number)
            }
        }

        if let cvvValue = cvv {
            if let encrypted = try? CardEncryption.shared.encrypt(cvvValue) {
                _ = KeychainManager.shared.saveCVV(
                    encrypted.base64EncodedString(),
                    cardID: id
                )
                self.cvvHash = CardEncryption.shared.hash(cvvValue)
            }
        }

        if let pin = pin {
            _ = KeychainManager.shared.savePIN(pin, cardID: id)
        }

        self.updatedAt = Date()
    }

    /// Удаление всех данных карты
    func deleteSecureData() {
        KeychainManager.shared.deleteAllCardData(cardID: id)
    }

    /// Получение маскированного номера для отображения
    func maskedNumber() -> String {
        guard let number = cardNumber else {
            return "•••• •••• •••• ••••"
        }
        let lastFour = String(number.suffix(4))
        return "•••• •••• •••• \(lastFour)"
    }

    /// Проверка PIN
    func verifyPIN(_ pin: String) -> Bool {
        guard let storedPIN = KeychainManager.shared.retrievePIN(cardID: id) else {
            return false
        }
        return storedPIN == pin
    }

    /// Валидация номера карты (Luhn algorithm)
    static func isValidCardNumber(_ number: String) -> Bool {
        let cleaned = number.filter { $0.isNumber }
        guard cleaned.count >= 13 && cleaned.count <= 19 else { return false }

        var sum = 0
        var isEven = false

        for char in cleaned.reversed() {
            guard let digit = char.wholeNumberValue else { return false }

            if isEven {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
            isEven.toggle()
        }

        return sum % 10 == 0
    }

    /// Определение типа карты по номеру
    static func detectCardType(from number: String) -> CardType {
        let cleaned = number.filter { $0.isNumber }

        if cleaned.hasPrefix("4") {
            return .visa
        } else if cleaned.hasPrefix("5") || cleaned.hasPrefix("2") {
            return .mastercard
        } else if cleaned.hasPrefix("34") || cleaned.hasPrefix("37") {
            return .amex
        } else if cleaned.hasPrefix("6") {
            return .discover
        }

        return .other
    }
}

// MARK: - Preview

extension Card {
    static var preview: Card {
        // Для preview создаем карту без реального шифрования
        let card = Card(
            cardholderName: "IVAN PETROV",
            cardNumber: "4532123456789012",
            cvv: "123",
            expiryMonth: "12",
            expiryYear: "28",
            cardType: .visa,
            pin: "1234"
        )
        return card
    }
}

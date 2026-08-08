# Wallet Security Layer

Полный Security Layer для Apple Wallet Clone (SwiftUI, iOS 26).

## Структура

```
Security/
├── KeychainManager.swift       # Хранение CVV, card numbers, PIN codes в Keychain
├── BiometricAuthManager.swift  # Face ID / Touch ID с fallback на PIN
└── AppSecurityManager.swift    # Главный координатор безопасности

Views/Security/
├── AppLockView.swift           # Экран блокировки с анимированным замком
├── SecureCardView.swift        # Маскирование номеров карты, tap-to-reveal
└── SecureTextField.swift       # Защищенные поля ввода (CVV, PIN, номер)

Utils/
├── CardEncryption.swift        # AES-256-GCM + SecureEnclave
└── JailbreakDetector.swift     # Детекция jailbreak

Models/
└── Card.swift                  # @Model с шифрованием в Keychain
```

## Функциональность

### KeychainManager
- Универсальный менеджер Keychain с разными уровнями доступа
- Специальные методы для карт: `saveCardNumber`, `saveCVV`, `savePIN`
- Хранение master encryption key
- Интеграция с Secure Enclave для private keys

### BiometricAuthManager
- Поддержка Face ID, Touch ID, Optic ID
- Fallback на PIN-код при отмене/ошибке биометрии
- Управление состоянием аутентификации

### AppLockView
- Анимированный замок (SVG-like через Path)
- PIN-pad с haptic feedback
- Shake animation при ошибке
- Auto-hide PIN через 10 секунд
- Screenshot protection overlay

### SecureCardView
- Градиентные карты по типу (Visa, Mastercard, Amex)
- Маскирование номера: `•••• •••• •••• 9012`
- Tap-to-reveal с загрузкой из Keychain
- Long-press для копирования номера
- Toast notification

### CardEncryption
- AES-256-GCM с автоматической генерацией nonce
- Secure Enclave: ECIES шифрование через EC keys
- SHA-256 hash для хранения в SwiftData
- `secureStoreCard` — единый метод для сохранения

### JailbreakDetector
- 7 методов детекции: suspicious apps, paths, permissions, sandbox, DYLD, symbols, URL schemes
- Проверка на debugger (ptrace, sysctl)
- Блокировка операций в production
- `canPerformSecureOperations()`

### Card (@Model)
- `cardNumberHash` и `cvvHash` в SwiftData
- Реальные данные в Keychain (AES-256-GCM)
- `@Transient` getters для дешифрования
- Luhn validation
- Auto-detect card type

### AppSecurityManager
- Единая точка входа для всех security операций
- Автоблокировка при background
- Anti-debugging (ptrace PT_DENY_ATTACH)
- Security report generation
- View modifier `.withSecurityLock()`

## Использование

```swift
import SwiftUI
import SwiftData

@main
struct WalletApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .withSecurityLock() // Блокировка экрана
                .environmentObject(AppSecurityManager.shared)
        }
        .modelContainer(for: Card.self)
    }
}

// Добавление карты
let card = AppSecurityManager.shared.addCard(
    cardholderName: "IVAN PETROV",
    cardNumber: "4532123456789012",
    cvv: "123",
    expiryMonth: "12",
    expiryYear: "28",
    pin: "1234"
)

// Отображение
SecureCardView(card: card)

// Аутентификация
Task {
    let success = await AppSecurityManager.shared.authenticateUser()
}
```

## Требования
- iOS 17.0+
- Swift 6.0
- SwiftData
- LocalAuthentication
- CryptoKit

## Безопасность
- Никакие чувствительные данные не хранятся в SwiftData
- Keychain с `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- PIN: `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`
- Secure Enclave для криптографических ключей
- Anti-screenshot: blur overlay при `UIScreen.isCaptured`
- Jailbreak detection с блокировкой операций

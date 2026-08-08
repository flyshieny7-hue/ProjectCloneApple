import SwiftUI

// MARK: - AppleWalletCloneApp
/// Точка входа в приложение Apple Wallet Clone.
/// Инициализирует все accessibility сервисы.
@main
struct AppleWalletCloneApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            WalletHomeScreen()
                .withAccessibilityManager()
                .environmentObject(AccessibilityManager.shared)
                .environmentObject(VoiceControlCommands.shared)
        }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Настройка accessibility при старте
        setupAccessibility()

        // Регистрация голосовых команд
        registerVoiceCommands()

        return true
    }

    private func setupAccessibility() {
        // Проверяем и логируем текущие настройки доступности
        let manager = AccessibilityManager.shared

        print("=== Accessibility Status ===")
        print("VoiceOver: \(manager.isVoiceOverRunning)")
        print("Reduce Motion: \(manager.isReduceMotionEnabled)")
        print("Switch Control: \(manager.isSwitchControlRunning)")
        print("AssistiveTouch: \(manager.isAssistiveTouchRunning)")
        print("High Contrast: \(manager.isHighContrastEnabled)")
        print("Color Blind Mode: \(manager.colorBlindMode.displayName)")
        print("===========================")

        // Анонсируем доступность VoiceOver
        if manager.isVoiceOverRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Apple Wallet Clone запущен. Используйте ротор для навигации по категориям. Скажите 'Покажи команды' для списка голосовых команд."
                )
            }
        }
    }

    private func registerVoiceCommands() {
        let voiceControl = VoiceControlCommands.shared

        voiceControl.registerCommand("покажи карты") {
            UIAccessibility.post(notification: .announcement, argument: "Открыт экран карт")
        }

        voiceControl.registerCommand("покажи баланс") {
            UIAccessibility.post(notification: .announcement, argument: "Баланс озвучен")
        }

        voiceControl.registerCommand("отправь пятьдесят долларов") {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Инициирован перевод 50 долларов. Подтвердите операцию."
            )
        }

        voiceControl.registerCommand("отправь сто рублей") {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Инициирован перевод 100 рублей. Подтвердите операцию."
            )
        }

        voiceControl.registerCommand("оплати счёт") {
            UIAccessibility.post(notification: .announcement, argument: "Открыта форма оплаты счёта")
        }

        voiceControl.registerCommand("включи высокий контраст") {
            AccessibilityManager.shared.setHighContrast(true)
        }
    }
}

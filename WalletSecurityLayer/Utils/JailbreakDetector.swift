import Foundation
import UIKit
import Darwin
import MachO

/// Детектор Jailbreak для iOS
/// Проверяет наличие признаков взлома устройства
@MainActor
final class JailbreakDetector: ObservableObject {

    static let shared = JailbreakDetector()

    @Published private(set) var isJailbroken = false
    @Published private(set) var detectedMethods: [DetectionMethod] = []

    enum DetectionMethod: String, CaseIterable {
        case suspiciousApps = "Suspicious Apps"
        case suspiciousPaths = "Suspicious Paths"
        case filePermissions = "File Permissions"
        case sandboxViolation = "Sandbox Violation"
        case dyldCheck = "DYLD Check"
        case symbolCheck = "Symbol Check"
        case canOpenURL = "Can Open URL"

        var description: String {
            switch self {
            case .suspiciousApps: return "Обнаружены приложения для jailbreak"
            case .suspiciousPaths: return "Найдены подозрительные пути в файловой системе"
            case .filePermissions: return "Нарушены ограничения файловой системы"
            case .sandboxViolation: return "Обнаружено нарушение sandbox"
            case .dyldCheck: return "Обнаружены подозрительные DYLD переменные"
            case .symbolCheck: return "Найдены символы jailbreak"
            case .canOpenURL: return "Обнаружены URL-схемы jailbreak"
            }
        }
    }

    private init() {
        performDetection()
    }

    // MARK: - Public API

    func performDetection() {
        var methods: [DetectionMethod] = []

        if checkSuspiciousApps() { methods.append(.suspiciousApps) }
        if checkSuspiciousPaths() { methods.append(.suspiciousPaths) }
        if checkFilePermissions() { methods.append(.filePermissions) }
        if checkSandboxViolation() { methods.append(.sandboxViolation) }
        if checkDYLD() { methods.append(.dyldCheck) }
        if checkSymbols() { methods.append(.symbolCheck) }
        if checkURLSchemes() { methods.append(.canOpenURL) }

        detectedMethods = methods
        isJailbroken = !methods.isEmpty

        if isJailbroken {
            handleJailbreakDetected()
        }
    }

    func verifyIntegrity() -> Bool {
        return !isJailbroken
    }

    // MARK: - Detection Methods

    /// Проверка наличия приложений для jailbreak
    private func checkSuspiciousApps() -> Bool {
        let suspiciousApps = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Applications/Installer.app",
            "/Applications/Filza.app",
            "/Applications/iFile.app",
            "/Applications/Blackra1n.app"
        ]

        return suspiciousApps.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Проверка подозрительных путей
    private func checkSuspiciousPaths() -> Bool {
        let suspiciousPaths = [
            "/var/lib/apt",
            "/var/lib/dpkg",
            "/var/lib/cydia",
            "/var/cache/apt",
            "/var/log/syslog",
            "/var/tmp/cydia.log",
            "/usr/libexec/cydia",
            "/usr/sbin/frida-server",
            "/usr/bin/ssh",
            "/usr/bin/sshd",
            "/etc/apt",
            "/etc/ssh/sshd_config",
            "/private/var/lib/apt",
            "/private/var/stash",
            "/private/var/mobile/Library/SBSettings",
            "/private/var/lib/cydia",
            "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist"
        ]

        return suspiciousPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Проверка прав доступа к файлам
    private func checkFilePermissions() -> Bool {
        let testPaths = [
            "/private/jailbreak.txt",
            "/private/var/mobile/test.txt"
        ]

        for path in testPaths {
            do {
                try "jailbreak_test".write(toFile: path, atomically: true, encoding: .utf8)
                try? FileManager.default.removeItem(atPath: path)
                return true
            } catch {
                continue
            }
        }

        // Проверка доступа к root
        if FileManager.default.fileExists(atPath: "/private/var/mobile") {
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: "/private/var/mobile")
                if files.count > 0 {
                    return true
                }
            } catch {
                return false
            }
        }

        return false
    }

    /// Проверка нарушения sandbox
    private func checkSandboxViolation() -> Bool {
        let path = "/private/" + UUID().uuidString
        do {
            try "test".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// Проверка DYLD переменных
    private func checkDYLD() -> Bool {
        let envVars = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_FORCE_FLAT_NAMESPACE"
        ]

        for key in envVars {
            if getenv(key) != nil {
                return true
            }
        }

        // Проверка на frida и другие библиотеки
        let suspiciousLibraries = [
            "FridaGadget",
            "frida",
            "cynject",
            "libcycript"
        ]

        for library in suspiciousLibraries {
            if checkLoadedLibrary(library) {
                return true
            }
        }

        return false
    }

    /// Проверка загруженных библиотек
    private func checkLoadedLibrary(_ name: String) -> Bool {
        var count = UInt32(0)
        guard let images = _dyld_image_count() else { return false }

        for i in 0..<images {
            if let imageName = _dyld_get_image_name(i) {
                let nameString = String(cString: imageName)
                if nameString.contains(name) {
                    return true
                }
            }
        }
        return false
    }

    /// Проверка символов
    private func checkSymbols() -> Bool {
        let suspiciousSymbols = [
            "MSHookMessageEx",
            "MSHookFunction",
            "Substrate",
            "cycript",
            "frida"
        ]

        for symbol in suspiciousSymbols {
            if dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) != nil {
                return true
            }
        }

        return false
    }

    /// Проверка URL-схем
    private func checkURLSchemes() -> Bool {
        let suspiciousSchemes = [
            "cydia://",
            "sileo://",
            "zbra://"
        ]

        guard let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else {
            return false
        }

        // Проверяем, можем ли мы открыть Cydia
        if let url = URL(string: "cydia://package/com.example.package") {
            if UIApplication.shared.canOpenURL(url) {
                return true
            }
        }

        return false
    }

    // MARK: - Response

    private func handleJailbreakDetected() {
        // Логирование
        #if DEBUG
        print("⚠️ Jailbreak detected! Methods: \(detectedMethods.map(\.rawValue).joined(separator: ", "))")
        #endif

        // Можно отправить аналитику или заблокировать функции
        NotificationCenter.default.post(
            name: .init("JailbreakDetected"),
            object: nil,
            userInfo: ["methods": detectedMethods]
        )
    }

    /// Возвращает предупреждение для пользователя
    func alertContent() -> (title: String, message: String) {
        return (
            title: "Небезопасное устройство",
            message: "Обнаружены признаки взлома (jailbreak). Для вашей безопасности некоторые функции могут быть ограничены."
        )
    }

    /// Проверяет, можно ли выполнять операции с картами
    func canPerformSecureOperations() -> Bool {
        #if DEBUG
        return true // В дебаге не блокируем
        #else
        return !isJailbroken
        #endif
    }
}

// MARK: - Security Extensions

extension JailbreakDetector {
    /// Дополнительная проверка на эмулятор
    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Проверка на отладчик
    var isBeingDebugged: Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let sysctlResult = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)

        guard sysctlResult == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// Проверка на reverse engineering
    func checkReverseEngineering() -> Bool {
        // Проверка на наличие отладчика
        if isBeingDebugged {
            return true
        }

        // Проверка ptrace
        let ptraceRequest = PT_DENY_ATTACH
        let result = ptrace(ptraceRequest, 0, 0, 0)

        return result == -1
    }
}

// Для ptrace
#if arch(arm64)
let PT_DENY_ATTACH: Int32 = 26
#else
let PT_DENY_ATTACH: Int32 = 10
#endif

// Для sysctl
let CTL_KERN = 1
let KERN_PROC = 14
let KERN_PROC_PID = 1
let P_TRACED = 0x00000800

struct kinfo_proc {
    var kp_proc: proc
}

struct proc {
    var p_flag: Int32
    // Остальные поля опущены для упрощения
    var padding: [UInt8] = Array(repeating: 0, count: 300)
}

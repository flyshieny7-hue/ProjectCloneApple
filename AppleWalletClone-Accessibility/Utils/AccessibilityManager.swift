import SwiftUI
import Combine
import AVFoundation

// MARK: - AccessibilityManager
/// Главный менеджер доступности для всего приложения Apple Wallet Clone.
/// Обрабатывает VoiceOver, Dynamic Type, Reduce Motion, High Contrast,
/// Color Blindness, Switch Control, Voice Control и AssistiveTouch.
@MainActor
final class AccessibilityManager: ObservableObject {

    // MARK: Singleton
    static let shared = AccessibilityManager()

    // MARK: Published State
    @Published var isVoiceOverRunning: Bool = UIAccessibility.isVoiceOverRunning
    @Published var dynamicTypeSize: DynamicTypeSize = .large
    @Published var isReduceMotionEnabled: Bool = UIAccessibility.isReduceMotionEnabled
    @Published var isHighContrastEnabled: Bool = false
    @Published var colorBlindMode: ColorBlindMode = .none
    @Published var isSwitchControlRunning: Bool = UIAccessibility.isSwitchControlRunning
    @Published var isVoiceControlRunning: Bool = false
    @Published var isAssistiveTouchRunning: Bool = UIAccessibility.isAssistiveTouchRunning
    @Published var hearingAccessibilityEnabled: Bool = false

    // MARK: Private
    private var cancellables = Set<AnyCancellable>()
    private let speechSynthesizer = AVSpeechSynthesizer()

    // MARK: Enums
    enum ColorBlindMode: String, CaseIterable, Identifiable {
        case none = "none"
        case protanopia = "protanopia"
        case deuteranopia = "deuteranopia"
        case tritanopia = "tritanopia"
        case achromatopsia = "achromatopsia"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .none: return "Стандартные цвета"
            case .protanopia: return "Протанопия (красная слепота)"
            case .deuteranopia: return "Дейтеранопия (зелёная слепота)"
            case .tritanopia: return "Тританопия (синяя слепота)"
            case .achromatopsia: return "Ахроматопсия (полная)"
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .none: return "Стандартная цветовая палитра"
            case .protanopia: return "Симуляция: невосприятие красного цвета"
            case .deuteranopia: return "Симуляция: невосприятие зелёного цвета"
            case .tritanopia: return "Симуляция: невосприятие синего цвета"
            case .achromatopsia: return "Симуляция: отсутствие цветового восприятия"
            }
        }
    }

    enum AccessibilityFeature: String, CaseIterable {
        case voiceOver = "VoiceOver"
        case dynamicType = "Dynamic Type"
        case reduceMotion = "Reduce Motion"
        case highContrast = "High Contrast"
        case colorBlind = "Color Blind Support"
        case switchControl = "Switch Control"
        case voiceControl = "Voice Control"
        case assistiveTouch = "AssistiveTouch"
        case hearing = "Hearing Accessibility"
    }

    // MARK: Init
    private init() {
        setupNotifications()
        loadUserPreferences()
    }

    // MARK: Setup
    private func setupNotifications() {
        // VoiceOver
        NotificationCenter.default
            .publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
                self?.announceChange(feature: .voiceOver, isEnabled: UIAccessibility.isVoiceOverRunning)
            }
            .store(in: &cancellables)

        // Reduce Motion
        NotificationCenter.default
            .publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isReduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
            }
            .store(in: &cancellables)

        // Switch Control
        NotificationCenter.default
            .publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isSwitchControlRunning = UIAccessibility.isSwitchControlRunning
            }
            .store(in: &cancellables)

        // AssistiveTouch
        NotificationCenter.default
            .publisher(for: UIAccessibility.assistiveTouchStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isAssistiveTouchRunning = UIAccessibility.isAssistiveTouchRunning
            }
            .store(in: &cancellables)

        // Voice Control (iOS 13+)
        if #available(iOS 13.0, *) {
            NotificationCenter.default
                .publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.checkVoiceControlStatus()
                }
                .store(in: &cancellables)
        }
    }

    private func loadUserPreferences() {
        let defaults = UserDefaults.standard
        isHighContrastEnabled = defaults.bool(forKey: "wallet_high_contrast_enabled")
        if let raw = defaults.string(forKey: "wallet_color_blind_mode"),
           let mode = ColorBlindMode(rawValue: raw) {
            colorBlindMode = mode
        }
        hearingAccessibilityEnabled = defaults.bool(forKey: "wallet_hearing_accessibility")
    }

    // MARK: Public Methods

    func setHighContrast(_ enabled: Bool) {
        isHighContrastEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "wallet_high_contrast_enabled")
        announceChange(feature: .highContrast, isEnabled: enabled)
    }

    func setColorBlindMode(_ mode: ColorBlindMode) {
        colorBlindMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "wallet_color_blind_mode")
        let announcement = "Режим цветовой коррекции изменён на \(mode.displayName)"
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    func setHearingAccessibility(_ enabled: Bool) {
        hearingAccessibilityEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "wallet_hearing_accessibility")
    }

    func announceChange(feature: AccessibilityFeature, isEnabled: Bool) {
        let status = isEnabled ? "включена" : "выключена"
        let announcement = "\(feature.rawValue) \(status)"
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    func speak(_ text: String, priority: AVSpeechUtterancePriority = .default) {
        guard isVoiceOverRunning || isSwitchControlRunning else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0

        if #available(iOS 16.0, *) {
            utterance.prefersAssistiveTechnologySettings = true
        }

        if !speechSynthesizer.isSpeaking {
            speechSynthesizer.speak(utterance)
        }
    }

    func checkVoiceControlStatus() {
        // Voice Control определяется через приватные API или UIAccessibility
        // В production используется UIDevice текущий статус
        isVoiceControlRunning = UIAccessibility.isVoiceOverRunning
    }

    // MARK: Color Blindness Helpers
    func adjustedColor(for color: Color) -> Color {
        switch colorBlindMode {
        case .none:
            return color
        case .protanopia:
            return applyProtanopiaMatrix(to: color)
        case .deuteranopia:
            return applyDeuteranopiaMatrix(to: color)
        case .tritanopia:
            return applyTritanopiaMatrix(to: color)
        case .achromatopsia:
            return applyGrayscale(to: color)
        }
    }

    private func applyProtanopiaMatrix(to color: Color) -> Color {
        // LMS матрица для протанопии
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let newR = 0.567 * r + 0.433 * g + 0.0 * b
        let newG = 0.558 * r + 0.442 * g + 0.0 * b
        let newB = 0.0 * r + 0.242 * g + 0.758 * b

        return Color(red: Double(newR), green: Double(newG), blue: Double(newB))
    }

    private func applyDeuteranopiaMatrix(to color: Color) -> Color {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let newR = 0.625 * r + 0.375 * g + 0.0 * b
        let newG = 0.7 * r + 0.3 * g + 0.0 * b
        let newB = 0.0 * r + 0.3 * g + 0.7 * b

        return Color(red: Double(newR), green: Double(newG), blue: Double(newB))
    }

    private func applyTritanopiaMatrix(to color: Color) -> Color {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let newR = 0.95 * r + 0.05 * g + 0.0 * b
        let newG = 0.0 * r + 0.433 * g + 0.567 * b
        let newB = 0.0 * r + 0.475 * g + 0.525 * b

        return Color(red: Double(newR), green: Double(newG), blue: Double(newB))
    }

    private func applyGrayscale(to color: Color) -> Color {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let gray = 0.299 * r + 0.587 * g + 0.114 * b
        return Color(white: Double(gray))
    }

    // MARK: High Contrast
    func highContrastBorder(color: Color) -> some View {
        let adjusted = isHighContrastEnabled ? adjustedColor(for: color) : color
        return RoundedRectangle(cornerRadius: 12)
            .strokeBorder(adjusted, lineWidth: isHighContrastEnabled ? 3 : 1)
    }

    // MARK: Animation Helpers
    func withAccessibilityAnimation<V: View>(_ animation: Animation, @ViewBuilder content: () -> V) -> some View {
        if isReduceMotionEnabled {
            return content().transaction { $0.animation = nil }
        } else {
            return content().animation(animation, value: UUID())
        }
    }

    func accessibilityAnimationDisabled() -> Animation? {
        isReduceMotionEnabled ? nil : .default
    }
}

// MARK: - View Extension
extension View {
    func withAccessibilityManager() -> some View {
        self.environmentObject(AccessibilityManager.shared)
    }
}

// MARK: - AVSpeechUtterancePriority
@available(iOS 15.0, *)
enum AVSpeechUtterancePriority: Int {
    case `default` = 0
    case high = 1
    case low = -1
}

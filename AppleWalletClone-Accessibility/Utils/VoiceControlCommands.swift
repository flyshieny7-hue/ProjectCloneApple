import SwiftUI
import Speech
import AVFoundation

// MARK: - VoiceControlCommands
/// Менеджер голосового управления для Apple Wallet Clone.
/// Поддерживает команды: "Tap Chase", "Show balance", "Send fifty dollars",
/// "Pay bill", "Transfer money" и другие.
@MainActor
final class VoiceControlCommands: ObservableObject {

    // MARK: Singleton
    static let shared = VoiceControlCommands()

    // MARK: Published State
    @Published var isListening: Bool = false
    @Published var lastRecognizedCommand: String = ""
    @Published var availableCommands: [VoiceCommand] = []
    @Published var commandFeedback: String = ""

    // MARK: Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru_RU"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var commandHandlers: [String: () -> Void] = [:]

    // MARK: Init
    private init() {
        setupCommands()
        requestAuthorization()
    }

    // MARK: VoiceCommand Model
    struct VoiceCommand: Identifiable {
        let id = UUID()
        let phrase: String
        let description: String
        let category: CommandCategory
        let accessibilityLabel: String

        enum CommandCategory: String, CaseIterable {
            case navigation = "Навигация"
            case cards = "Карты"
            case payments = "Платежи"
            case transfers = "Переводы"
            case balance = "Баланс"
            case settings = "Настройки"
        }
    }

    // MARK: Setup
    private func setupCommands() {
        availableCommands = [
            // Навигация
            VoiceCommand(
                phrase: "Покажи карты",
                description: "Открывает экран со списком карт",
                category: .navigation,
                accessibilityLabel: "Команда: показать карты"
            ),
            VoiceCommand(
                phrase: "Покажи транзакции",
                description: "Открывает историю транзакций",
                category: .navigation,
                accessibilityLabel: "Команда: показать транзакции"
            ),
            VoiceCommand(
                phrase: "Назад",
                description: "Возвращает на предыдущий экран",
                category: .navigation,
                accessibilityLabel: "Команда: назад"
            ),

            // Карты
            VoiceCommand(
                phrase: "Выбери карту",
                description: "Выбирает карту по номеру или названию",
                category: .cards,
                accessibilityLabel: "Команда: выбрать карту"
            ),
            VoiceCommand(
                phrase: "Покажи баланс",
                description: "Озвучивает баланс выбранной карты",
                category: .balance,
                accessibilityLabel: "Команда: показать баланс"
            ),
            VoiceCommand(
                phrase: "Скрыть баланс",
                description: "Скрывает отображение баланса",
                category: .balance,
                accessibilityLabel: "Команда: скрыть баланс"
            ),

            // Платежи
            VoiceCommand(
                phrase: "Оплати счёт",
                description: "Открывает форму оплаты по шаблону",
                category: .payments,
                accessibilityLabel: "Команда: оплатить счёт"
            ),
            VoiceCommand(
                phrase: "Отправь пятьдесят долларов",
                description: "Инициирует перевод 50 USD",
                category: .transfers,
                accessibilityLabel: "Команда: отправить 50 долларов"
            ),
            VoiceCommand(
                phrase: "Отправь сто рублей",
                description: "Инициирует перевод 100 RUB",
                category: .transfers,
                accessibilityLabel: "Команда: отправить 100 рублей"
            ),
            VoiceCommand(
                phrase: "Пополни телефон",
                description: "Открывает пополнение телефона",
                category: .payments,
                accessibilityLabel: "Команда: пополнить телефон"
            ),

            // Настройки
            VoiceCommand(
                phrase: "Включи высокий контраст",
                description: "Активирует режим высокого контраста",
                category: .settings,
                accessibilityLabel: "Команда: включить высокий контраст"
            ),
            VoiceCommand(
                phrase: "Включи VoiceOver",
                description: "Активирует VoiceOver",
                category: .settings,
                accessibilityLabel: "Команда: включить VoiceOver"
            ),
            VoiceCommand(
                phrase: "Покажи команды",
                description: "Открывает список голосовых команд",
                category: .settings,
                accessibilityLabel: "Команда: показать доступные команды"
            )
        ]
    }

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    print("Speech recognition not available: \(status)")
                @unknown default:
                    break
                }
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Microphone permission: \(granted)")
        }
    }

    // MARK: Public Methods

    func registerCommand(_ phrase: String, handler: @escaping () -> Void) {
        commandHandlers[phrase.lowercased()] = handler
    }

    func startListening() {
        guard !isListening else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }

            recognitionRequest.shouldReportPartialResults = true
            if #available(iOS 16.0, *) {
                recognitionRequest.requiresOnDeviceRecognition = true
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true

            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self, let result = result else { return }

                let transcription = result.bestTranscription.formattedString.lowercased()
                self.lastRecognizedCommand = transcription

                if result.isFinal {
                    self.processCommand(transcription)
                    self.stopListening()
                }
            }

        } catch {
            print("Failed to start listening: \(error)")
            isListening = false
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    func processCommand(_ command: String) {
        let normalizedCommand = command.lowercased().trimmingCharacters(in: .whitespaces)

        // Проверяем зарегистрированные обработчики
        for (phrase, handler) in commandHandlers {
            if normalizedCommand.contains(phrase) {
                handler()
                provideFeedback("Выполнено: \(phrase)")
                return
            }
        }

        // Встроенные команды
        switch normalizedCommand {
        case let cmd where cmd.contains("баланс"):
            provideFeedback("Баланс озвучен")
            UIAccessibility.post(notification: .announcement, argument: "Запрос баланса через голосовое управление")

        case let cmd where cmd.contains("отправь") || cmd.contains("переведи"):
            handleTransferCommand(normalizedCommand)

        case let cmd where cmd.contains("оплати") || cmd.contains("заплати"):
            provideFeedback("Открыта форма оплаты")

        case let cmd where cmd.contains("контраст"):
            AccessibilityManager.shared.setHighContrast(true)
            provideFeedback("Высокий контраст включён")

        case let cmd where cmd.contains("команды"):
            provideFeedback("Доступные команды открыты")

        default:
            provideFeedback("Команда не распознана. Скажите 'Покажи команды' для списка.")
        }
    }

    private func handleTransferCommand(_ command: String) {
        // Парсинг суммы из текста
        let amount = parseAmount(from: command)
        let currency = parseCurrency(from: command)

        provideFeedback("Подготовка перевода: \(amount.formatted(.currency(code: currency)))")
        UIAccessibility.post(
            notification: .announcement,
            argument: "Инициирован перевод на сумму \(amount.formatted(.currency(code: currency))). Подтвердите операцию."
        )
    }

    private func parseAmount(from command: String) -> Double {
        // Упрощённый парсер сумм на русском
        let words = command.split(separator: " ")
        var amount: Double = 0

        for word in words {
            let clean = word.lowercased()
                .replacingOccurrences(of: "рублей", with: "")
                .replacingOccurrences(of: "долларов", with: "")
                .replacingOccurrences(of: "евро", with: "")
                .replacingOccurrences(of: ",", with: ".")

            if let num = Double(clean) {
                amount = num
            }
        }

        // Поддержка текстовых чисел
        let numberMap: [String: Double] = [
            "пятьдесят": 50, "сто": 100, "двести": 200, "пятьсот": 500,
            "тысячу": 1000, "пять тысяч": 5000, "десять тысяч": 10000
        ]

        for (text, num) in numberMap {
            if command.contains(text) {
                amount = num
                break
            }
        }

        return amount > 0 ? amount : 100
    }

    private func parseCurrency(from command: String) -> String {
        if command.contains("доллар") || command.contains("usd") { return "USD" }
        if command.contains("евро") || command.contains("eur") { return "EUR" }
        if command.contains("рубл") || command.contains("rub") { return "RUB" }
        return "RUB"
    }

    private func provideFeedback(_ message: String) {
        commandFeedback = message
        UIAccessibility.post(notification: .announcement, argument: message)

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: Accessibility Labels for UI Elements
    func accessibilityLabelForCommand(_ phrase: String) -> String {
        return "Голосовая команда: \(phrase). Двойное нажатие для активации."
    }
}

// MARK: - VoiceControlOverlay
struct VoiceControlOverlay: View {
    @StateObject private var voiceControl = VoiceControlCommands.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            if voiceControl.isListening {
                listeningIndicator
            }

            if !voiceControl.commandFeedback.isEmpty {
                feedbackBanner
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Панель голосового управления")
    }

    @ViewBuilder
    private var listeningIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .symbolEffect(.pulse)

            Text("Слушаю...")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 16, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button(action: {
                voiceControl.stopListening()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Остановить прослушивание")
            .accessibilityHint("Двойное нажатие для отмены голосового ввода")
        }
        .padding()
        .background(Color.blue)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.green)

            Text(voiceControl.commandFeedback)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 15))
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.green, lineWidth: 2)
        )
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                voiceControl.commandFeedback = ""
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - VoiceControlCommandsList
struct VoiceControlCommandsList: View {
    @StateObject private var voiceControl = VoiceControlCommands.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(VoiceCommand.CommandCategory.allCases, id: \.self) { category in
                    Section(header: Text(category.rawValue)) {
                        let commands = voiceControl.availableCommands.filter { $0.category == category }
                        ForEach(commands) { command in
                            CommandRow(command: command)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Голосовые команды")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .accessibilityLabel("Закрыть список команд")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Список доступных голосовых команд")
        .accessibilityHint("Проведите по списку для просмотра команд. Нажмите для прослушивания произношения.")
    }
}

struct CommandRow: View {
    let command: VoiceControlCommands.VoiceCommand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(command.phrase)")
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 17, weight: .semibold))

                Spacer()

                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            }

            Text(command.description)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 16 : 14))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(command.accessibilityLabel)
        .accessibilityValue(command.description)
        .accessibilityHint("Скажите эту фразу для выполнения команды")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - View Extension
extension View {
    func withVoiceControlOverlay() -> some View {
        self.overlay(VoiceControlOverlay(), alignment: .top)
    }
}

// MARK: - Preview
#Preview {
    VoiceControlCommandsList()
}

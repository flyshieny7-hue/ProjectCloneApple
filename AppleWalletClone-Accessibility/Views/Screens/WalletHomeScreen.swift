import SwiftUI

// MARK: - WalletHomeScreen
/// Главный экран кошелька с полным accessibility слоем.
/// Интегрирует все компоненты доступности.
struct WalletHomeScreen: View {

    @StateObject private var accessibilityManager = AccessibilityManager.shared
    @StateObject private var voiceControl = VoiceControlCommands.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedCard: PaymentCard? = nil
    @State private var showingBalance: Bool = false
    @State private var showingSettings: Bool = false
    @State private var showingCommands: Bool = false
    @State private var soundEvent: HearingAccessibilityIndicator.SoundType? = nil

    private let sampleCards = [
        PaymentCard(
            cardName: "Зарплатная карта",
            bankName: "Сбербанк",
            bankIcon: "building.columns.fill",
            lastFourDigits: "4521",
            expiryDate: "12/28",
            balance: 125430.50,
            currency: "RUB",
            themeColor: .green,
            cardType: .debit,
            paymentSystem: .visa,
            isDefault: true
        ),
        PaymentCard(
            cardName: "Кредитная карта",
            bankName: "Тинькофф",
            bankIcon: "creditcard.fill",
            lastFourDigits: "8899",
            expiryDate: "06/27",
            balance: -45000.00,
            currency: "RUB",
            themeColor: .red,
            cardType: .credit,
            paymentSystem: .mastercard,
            isDefault: false
        ),
        PaymentCard(
            cardName: "Накопительный счёт",
            bankName: "ВТБ",
            bankIcon: "banknote.fill",
            lastFourDigits: "3344",
            expiryDate: "—",
            balance: 250000.00,
            currency: "RUB",
            themeColor: .blue,
            cardType: .debit,
            paymentSystem: .mir,
            isDefault: false
        )
    ]

    private let sampleTransactions = [
        WalletTransaction(
            merchantName: "Пятёрочка",
            amount: -1250.00,
            currency: "RUB",
            date: Date(),
            category: .food,
            status: .completed,
            location: "Москва, Ленина 12",
            paymentMethod: "Карта Visa •••• 4521",
            cashback: 25.00
        ),
        WalletTransaction(
            merchantName: "Метро",
            amount: -55.00,
            currency: "RUB",
            date: Date().addingTimeInterval(-3600),
            category: .transport,
            status: .completed,
            location: "Москва, Арбатская",
            paymentMethod: "Карта Visa •••• 4521",
            cashback: 0
        ),
        WalletTransaction(
            merchantName: "Зарплата",
            amount: 85000.00,
            currency: "RUB",
            date: Date().addingTimeInterval(-86400),
            category: .salary,
            status: .completed,
            location: "Сбербанк",
            paymentMethod: "Перевод",
            cashback: 0
        ),
        WalletTransaction(
            merchantName: "Аптека",
            amount: -890.00,
            currency: "RUB",
            date: Date().addingTimeInterval(-172800),
            category: .health,
            status: .completed,
            location: "Москва, Пушкина 5",
            paymentMethod: "Карта Visa •••• 4521",
            cashback: 17.80
        )
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: dynamicTypeSize >= .accessibility2 ? 32 : 24) {
                    // Header
                    headerSection

                    // Карусель карт
                    cardsSection

                    // Быстрые действия
                    quickActionsSection

                    // Транзакции с Rotor
                    transactionsSection

                    // Accessibility Settings
                    accessibilitySettingsSection
                }
                .padding(.vertical)
            }
            .navigationTitle("Кошелёк")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gear")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .accessibilityLabel("Настройки доступности")
                    .accessibilityHint("Открыть настройки VoiceOver, контраста и других функций")
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingCommands = true
                    }) {
                        Image(systemName: "mic.circle")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .accessibilityLabel("Голосовые команды")
                    .accessibilityHint("Показать список доступных голосовых команд")
                }
            }
            .sheet(isPresented: $showingSettings) {
                AccessibilitySettingsScreen()
            }
            .sheet(isPresented: $showingCommands) {
                VoiceControlCommandsList()
            }
            .withVoiceControlOverlay()
            .overlay(
                Group {
                    if let sound = soundEvent {
                        VStack {
                            HearingAccessibilityIndicator(soundType: sound, isActive: true)
                            Spacer()
                        }
                        .padding(.top, 100)
                    }
                }
            )
        }
        .environmentObject(accessibilityManager)
        .environmentObject(voiceControl)
    }

    // MARK: Sections
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ваши карты")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 32 : 28, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            Text("\(sampleCards.count) карт доступно")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 17))
                .foregroundColor(.secondary)
                .accessibilityLabel("Доступно \(sampleCards.count) карт")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cardsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(sampleCards) { card in
                    if accessibilityManager.isHighContrastEnabled {
                        HighContrastCard(
                            card: card,
                            isSelected: selectedCard?.id == card.id,
                            onTap: { selectCard(card) },
                            onShowBalance: { showBalance(for: card) },
                            onShowDetails: { /* navigate to details */ }
                        )
                    } else {
                        AccessibleCardView(
                            card: card,
                            isSelected: selectedCard?.id == card.id,
                            onTap: { selectCard(card) },
                            onDoubleTap: { showBalance(for: card) },
                            onLongPress: { showCardMenu(for: card) }
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Список карт. Проведите для навигации.")
        .accessibilityHint("Нажмите для выбора карты. Дважды нажмите для баланса.")
    }

    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Быстрые действия")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 22 : 18, weight: .semibold))
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickActionButton(
                    title: "Перевод",
                    icon: "arrow.left.arrow.right",
                    color: .blue,
                    action: { triggerSound(.payment) }
                )
                QuickActionButton(
                    title: "Оплата",
                    icon: "qrcode",
                    color: .green,
                    action: { triggerSound(.success) }
                )
                QuickActionButton(
                    title: "Пополнение",
                    icon: "plus.circle",
                    color: .orange,
                    action: { triggerSound(.notification) }
                )
                QuickActionButton(
                    title: "История",
                    icon: "clock.arrow.circlepath",
                    color: .purple,
                    action: {}
                )
            }
            .padding(.horizontal)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Быстрые действия: перевод, оплата, пополнение, история")
    }

    @ViewBuilder
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последние операции")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 22 : 18, weight: .semibold))
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            AccessibilityRotorView(
                transactions: sampleTransactions,
                onNavigateToTransaction: { transaction in
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Открыты детали транзакции \(transaction.merchantName)"
                    )
                }
            )
        }
    }

    @ViewBuilder
    private var accessibilitySettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Доступность")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 22 : 18, weight: .semibold))
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 8) {
                Toggle("Высокий контраст", isOn: Binding(
                    get: { accessibilityManager.isHighContrastEnabled },
                    set: { accessibilityManager.setHighContrast($0) }
                ))
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .accessibilityLabel("Высокий контраст")
                .accessibilityHint("Увеличивает контрастность интерфейса для лучшей видимости")

                Toggle("Визуальные индикаторы звука", isOn: Binding(
                    get: { accessibilityManager.hearingAccessibilityEnabled },
                    set: { accessibilityManager.setHearingAccessibility($0) }
                ))
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .accessibilityLabel("Визуальные индикаторы звука")
                .accessibilityHint("Показывает визуальные уведомления при звуковых сигналах")

                NavigationLink(destination: ColorBlindPreview()) {
                    HStack {
                        Image(systemName: "eye")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Проверка дальтонизма")
                                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 16, weight: .medium))
                            Text("Симуляция цветовой слепоты")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .accessibilityLabel("Проверка дальтонизма")
                .accessibilityHint("Открыть инструмент проверки цветовой доступности")
            }
            .padding(.horizontal)
        }
    }

    // MARK: Actions
    private func selectCard(_ card: PaymentCard) {
        selectedCard = card
        let announcement = "Выбрана \(card.cardName)"
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    private func showBalance(for card: PaymentCard) {
        showingBalance = true
        let announcement = "Баланс \(card.cardName): \(card.balance.formatted(.currency(code: card.currency)))"
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    private func showCardMenu(for card: PaymentCard) {
        UIAccessibility.post(
            notification: .announcement,
            argument: "Меню карты \(card.cardName): перевод, блокировка, настройки"
        )
    }

    private func triggerSound(_ type: HearingAccessibilityIndicator.SoundType) {
        soundEvent = type
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            soundEvent = nil
        }
    }
}

// MARK: - QuickActionButton
struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var accessibilityManager: AccessibilityManager

    var body: some View {
        Button(action: action) {
            VStack(spacing: dynamicTypeSize >= .accessibility2 ? 12 : 8) {
                ZStack {
                    Circle()
                        .fill(accessibilityManager.adjustedColor(for: color).opacity(0.15))
                        .frame(width: dynamicTypeSize >= .accessibility3 ? 64 : 52, height: dynamicTypeSize >= .accessibility3 ? 64 : 52)

                    Image(systemName: icon)
                        .font(.system(size: dynamicTypeSize >= .accessibility3 ? 28 : 22, weight: .semibold))
                        .foregroundColor(accessibilityManager.adjustedColor(for: color))
                }

                Text(title)
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 17 : 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                accessibilityManager.isHighContrastEnabled ? Color.black : Color.clear,
                                lineWidth: accessibilityManager.isHighContrastEnabled ? 2 : 0
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint("Двойное нажатие для выполнения действия \(title)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - AccessibilitySettingsScreen
struct AccessibilitySettingsScreen: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Визуальная доступность")) {
                    Toggle("Высокий контраст", isOn: Binding(
                        get: { accessibilityManager.isHighContrastEnabled },
                        set: { accessibilityManager.setHighContrast($0) }
                    ))

                    Picker("Режим дальтонизма", selection: Binding(
                        get: { accessibilityManager.colorBlindMode },
                        set: { accessibilityManager.setColorBlindMode($0) }
                    )) {
                        ForEach(AccessibilityManager.ColorBlindMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Toggle("Уменьшить движение", isOn: Binding(
                        get: { accessibilityManager.isReduceMotionEnabled },
                        set: { _ in }
                    ))
                    .disabled(true)
                }

                Section(header: Text("Слуховая доступность")) {
                    Toggle("Визуальные индикаторы звука", isOn: Binding(
                        get: { accessibilityManager.hearingAccessibilityEnabled },
                        set: { accessibilityManager.setHearingAccessibility($0) }
                    ))
                }

                Section(header: Text("Навигация")) {
                    NavigationLink("Голосовые команды", destination: VoiceControlCommandsList())
                    NavigationLink("Проверка дальтонизма", destination: ColorBlindPreview())
                }

                Section(header: Text("Статус системы")) {
                    HStack {
                        Text("VoiceOver")
                        Spacer()
                        StatusIndicator(isActive: accessibilityManager.isVoiceOverRunning)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("VoiceOver \(accessibilityManager.isVoiceOverRunning ? "включён" : "выключён")")

                    HStack {
                        Text("Switch Control")
                        Spacer()
                        StatusIndicator(isActive: accessibilityManager.isSwitchControlRunning)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Switch Control \(accessibilityManager.isSwitchControlRunning ? "включён" : "выключён")")

                    HStack {
                        Text("AssistiveTouch")
                        Spacer()
                        StatusIndicator(isActive: accessibilityManager.isAssistiveTouchRunning)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("AssistiveTouch \(accessibilityManager.isAssistiveTouchRunning ? "включён" : "выключён")")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Доступность")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

struct StatusIndicator: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.red)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Preview
#Preview {
    WalletHomeScreen()
}

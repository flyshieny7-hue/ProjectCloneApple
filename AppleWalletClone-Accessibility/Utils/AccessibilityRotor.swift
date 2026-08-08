import SwiftUI

// MARK: - AccessibilityRotor
/// Custom Accessibility Rotor для быстрой навигации по категориям транзакций.
/// Позволяет VoiceOver пользователям быстро переключаться между
/// категориями: Еда, Транспорт, Покупки, Зарплата и т.д.
struct AccessibilityRotorView: View {

    let transactions: [WalletTransaction]
    let onNavigateToTransaction: (WalletTransaction) -> Void

    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedCategory: WalletTransaction.TransactionCategory? = nil
    @State private var filteredTransactions: [WalletTransaction] = []

    var body: some View {
        VStack(spacing: 0) {
            // Rotor header
            rotorHeader

            // Список транзакций с rotor-навигацией
            transactionList
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("История транзакций с быстрой навигацией")
        .accessibilityHint("Используйте ротор VoiceOver для переключения между категориями")
        .accessibilityRotor("Категории транзакций") {
            ForEach(WalletTransaction.TransactionCategory.allCases, id: \.self) { category in
                AccessibilityRotorEntry(label: category.localizedName, id: category) {
                    selectedCategory = category
                    filterTransactions()
                    announceCategoryChange(category)
                }
            }
        }
        .accessibilityRotor("Месяцы") {
            ForEach(monthsFromTransactions, id: \.self) { month in
                AccessibilityRotorEntry(label: month.displayName, id: month) {
                    scrollToMonth(month)
                }
            }
        }
        .accessibilityRotor("Суммы") {
            ForEach(amountRanges, id: \.self) { range in
                AccessibilityRotorEntry(label: range.label, id: range) {
                    filterByAmountRange(range)
                }
            }
        }
    }

    // MARK: Sections
    @ViewBuilder
    private var rotorHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Транзакции")
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 26 : 22, weight: .bold))
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                // Индикатор активного фильтра
                if let category = selectedCategory {
                    FilterBadge(category: category) {
                        selectedCategory = nil
                        filterTransactions()
                    }
                }
            }

            // Горизонтальный скролл категорий (визуальный)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryFilterButton(
                        title: "Все",
                        isSelected: selectedCategory == nil,
                        action: {
                            selectedCategory = nil
                            filterTransactions()
                        }
                    )

                    ForEach(WalletTransaction.TransactionCategory.allCases, id: \.self) { category in
                        CategoryFilterButton(
                            title: category.localizedName,
                            isSelected: selectedCategory == category,
                            action: {
                                selectedCategory = category
                                filterTransactions()
                                announceCategoryChange(category)
                            }
                        )
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Фильтр по категориям")
            .accessibilityHint("Нажмите для фильтрации. Используйте ротор VoiceOver для быстрой навигации.")
        }
        .padding()
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var transactionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(groupedTransactions.keys.sorted(), id: \.self) { date in
                    VStack(alignment: .leading, spacing: 8) {
                        // Заголовок секции (дата)
                        HStack {
                            Text(sectionHeaderDate(date))
                                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 14, weight: .semibold))
                                .foregroundColor(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            Spacer()

                            Text(sectionTotal(date))
                                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(sectionHeaderDate(date)), итого: \(sectionTotal(date))")

                        // Транзакции за дату
                        ForEach(groupedTransactions[date] ?? []) { transaction in
                            AccessibleTransactionRow(
                                transaction: transaction,
                                onTap: {
                                    onNavigateToTransaction(transaction)
                                },
                                onRefund: { handleRefund(transaction) },
                                onShare: { handleShare(transaction) },
                                onReport: { handleReport(transaction) }
                            )
                            .padding(.horizontal)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("\(transaction.merchantName), \(transaction.amount.formatted(.currency(code: transaction.currency)))")
                            .accessibilityHint("Нажмите для деталей. Проведите вверх/вниз для навигации между транзакциями.")
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: Helpers
    private var groupedTransactions: [Date: [WalletTransaction]] {
        let source = filteredTransactions.isEmpty ? transactions : filteredTransactions
        return Dictionary(grouping: source) { transaction in
            Calendar.current.startOfDay(for: transaction.date)
        }
    }

    private var monthsFromTransactions: [MonthEntry] {
        let calendar = Calendar.current
        let months = Set(transactions.map { calendar.component(.month, from: $0.date) })
        return months.sorted().map { MonthEntry(month: $0, year: calendar.component(.year, from: transactions.first?.date ?? Date())) }
    }

    private var amountRanges: [AmountRange] {
        [
            AmountRange(label: "Мелкие (до 100 ₽)", min: 0, max: 100),
            AmountRange(label: "Средние (100–1000 ₽)", min: 100, max: 1000),
            AmountRange(label: "Крупные (1000–10000 ₽)", min: 1000, max: 10000),
            AmountRange(label: "Очень крупные (более 10000 ₽)", min: 10000, max: .infinity)
        ]
    }

    private func filterTransactions() {
        if let category = selectedCategory {
            filteredTransactions = transactions.filter { $0.category == category }
        } else {
            filteredTransactions = []
        }

        let count = filteredTransactions.isEmpty ? transactions.count : filteredTransactions.count
        UIAccessibility.post(
            notification: .announcement,
            argument: "Показано \(count) транзакций"
        )
    }

    private func announceCategoryChange(_ category: WalletTransaction.TransactionCategory) {
        let count = transactions.filter { $0.category == category }.count
        UIAccessibility.post(
            notification: .announcement,
            argument: "Категория: \(category.localizedName). \(count) транзакций."
        )
    }

    private func scrollToMonth(_ month: MonthEntry) {
        // Логика скролла к месяцу
        UIAccessibility.post(
            notification: .announcement,
            argument: "Переход к \(month.displayName)"
        )
    }

    private func filterByAmountRange(_ range: AmountRange) {
        filteredTransactions = transactions.filter { abs($0.amount) >= range.min && abs($0.amount) < range.max }
        UIAccessibility.post(
            notification: .announcement,
            argument: "Фильтр по сумме: \(range.label). Найдено \(filteredTransactions.count) транзакций."
        )
    }

    private func sectionHeaderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func sectionTotal(_ date: Date) -> String {
        let total = groupedTransactions[date]?.reduce(0) { $0 + $1.amount } ?? 0
        return total.formatted(.currency(code: "RUB"))
    }

    private func handleRefund(_ transaction: WalletTransaction) {
        UIAccessibility.post(notification: .announcement, argument: "Возврат платежа \(transaction.merchantName) инициирован")
    }

    private func handleShare(_ transaction: WalletTransaction) {
        UIAccessibility.post(notification: .announcement, argument: "Открыто меню поделиться для транзакции \(transaction.merchantName)")
    }

    private func handleReport(_ transaction: WalletTransaction) {
        UIAccessibility.post(notification: .announcement, argument: "Форма жалобы на транзакцию \(transaction.merchantName) открыта")
    }
}

// MARK: - Supporting Types
struct MonthEntry: Hashable {
    let month: Int
    let year: Int

    var displayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.monthSymbols[month - 1].capitalized + " \(year)"
    }
}

struct AmountRange: Hashable {
    let label: String
    let min: Double
    let max: Double
}

// MARK: - CategoryFilterButton
struct CategoryFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var accessibilityManager: AccessibilityManager

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 16 : 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color(.secondarySystemBackground))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    accessibilityManager.isHighContrastEnabled && isSelected ? Color.black : Color.clear,
                                    lineWidth: 2
                                )
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Выбрано" : "")
        .accessibilityHint("Нажмите для фильтрации по категории \(title)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - FilterBadge
struct FilterBadge: View {
    let category: WalletTransaction.TransactionCategory
    let onClear: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var accessibilityManager: AccessibilityManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 14))
            Text(category.localizedName)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 14 : 12, weight: .medium))

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
            }
            .accessibilityLabel("Очистить фильтр \(category.localizedName)")
            .accessibilityHint("Нажмите чтобы показать все категории")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(accessibilityManager.adjustedColor(for: category.color).opacity(0.2))
        )
        .overlay(
            Capsule()
                .strokeBorder(accessibilityManager.adjustedColor(for: category.color), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Активный фильтр: \(category.localizedName)")
    }
}

// MARK: - AssistiveTouchMenu
/// Custom AssistiveTouch меню для сложных жестов в Wallet
struct AssistiveTouchMenu: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded: Bool = false

    let actions: [AssistiveAction]

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if isExpanded {
                    expandedMenu
                }
                mainButton
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Меню AssistiveTouch")
        .accessibilityHint("Нажмите для доступа к быстрым действиям")
    }

    @ViewBuilder
    private var mainButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
            if isExpanded {
                UIAccessibility.post(notification: .announcement, argument: "Меню AssistiveTouch открыто. \(actions.count) действий доступно.")
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.9))
                    .frame(width: 60, height: 60)
                    .shadow(radius: 4)

                Image(systemName: isExpanded ? "xmark" : "hand.tap.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel(isExpanded ? "Закрыть меню" : "Открыть AssistiveTouch")
        .accessibilityHint(isExpanded ? "Нажмите чтобы закрыть меню" : "Нажмите чтобы открыть меню быстрых действий")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var expandedMenu: some View {
        VStack(spacing: 12) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                Button(action: {
                    action.handler()
                    isExpanded = false
                    UIAccessibility.post(notification: .announcement, argument: "Выполнено: \(action.title)")
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: action.icon)
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 32)

                        Text(action.title)
                            .font(.system(size: dynamicTypeSize >= .accessibility2 ? 17 : 15, weight: .medium))
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.9))
                    )
                }
                .accessibilityLabel(action.title)
                .accessibilityHint(action.accessibilityHint)
                .accessibilityAddTraits(.isButton)
                .accessibilitySortPriority(Double(actions.count - index))
            }
        }
        .frame(width: 220)
        .padding(.trailing, 8)
    }
}

struct AssistiveAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let accessibilityHint: String
    let handler: () -> Void
}

// MARK: - HearingAccessibilityIndicator
/// Визуальные индикаторы звуков для пользователей с нарушениями слуха
struct HearingAccessibilityIndicator: View {
    let soundType: SoundType
    let isActive: Bool

    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @State private var animationPhase: Bool = false

    enum SoundType: String {
        case success = "success"
        case error = "error"
        case warning = "warning"
        case notification = "notification"
        case payment = "payment"

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .notification: return "bell.fill"
            case .payment: return "waveform"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            case .notification: return .blue
            case .payment: return .purple
            }
        }

        var description: String {
            switch self {
            case .success: return "Успешная операция"
            case .error: return "Ошибка"
            case .warning: return "Предупреждение"
            case .notification: return "Новое уведомление"
            case .payment: return "Звук оплаты"
            }
        }
    }

    var body: some View {
        if accessibilityManager.hearingAccessibilityEnabled && isActive {
            HStack(spacing: 8) {
                Image(systemName: soundType.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(soundType.color)
                    .symbolEffect(.bounce, options: .repeating, value: animationPhase)

                Text(soundType.description)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(soundType.color)

                // Визуальная волна (анимация звука)
                HStack(spacing: 3) {
                    ForEach(0..<4) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(soundType.color)
                            .frame(width: 3, height: animationPhase ? CGFloat(8 + i * 4) : 4)
                            .animation(
                                .easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.1),
                                value: animationPhase
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(soundType.color.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(soundType.color, lineWidth: 2)
                    )
            )
            .onAppear {
                animationPhase = true
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Визуальный индикатор звука: \(soundType.description)"
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Звуковое событие: \(soundType.description)")
            .accessibilityHint("Визуальное уведомление о звуковом сигнале")
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        // Rotor Preview
        AccessibilityRotorView(
            transactions: [
                WalletTransaction(
                    merchantName: "Пятёрочка",
                    amount: -1250.00,
                    currency: "RUB",
                    date: Date(),
                    category: .food,
                    status: .completed,
                    location: "Москва",
                    paymentMethod: "Карта",
                    cashback: 25.00
                ),
                WalletTransaction(
                    merchantName: "Метро",
                    amount: -55.00,
                    currency: "RUB",
                    date: Date(),
                    category: .transport,
                    status: .completed,
                    location: "Москва",
                    paymentMethod: "Карта",
                    cashback: 0
                ),
                WalletTransaction(
                    merchantName: "Зарплата",
                    amount: 85000.00,
                    currency: "RUB",
                    date: Date().addingTimeInterval(-86400),
                    category: .salary,
                    status: .completed,
                    location: "Банк",
                    paymentMethod: "Перевод",
                    cashback: 0
                )
            ],
            onNavigateToTransaction: { _ in }
        )
        .environmentObject(AccessibilityManager.shared)
    }
}

#Preview("AssistiveTouch") {
    AssistiveTouchMenu(actions: [
        AssistiveAction(
            title: "Быстрый перевод",
            icon: "arrow.left.arrow.right",
            accessibilityHint: "Открыть форму быстрого перевода",
            handler: {}
        ),
        AssistiveAction(
            title: "Оплатить QR",
            icon: "qrcode",
            accessibilityHint: "Открыть сканер QR-кода",
            handler: {}
        ),
        AssistiveAction(
            title: "Показать баланс",
            icon: "banknote",
            accessibilityHint: "Озвучить баланс всех карт",
            handler: {}
        ),
        AssistiveAction(
            title: "Блокировать карту",
            icon: "lock.fill",
            accessibilityHint: "Быстрая блокировка выбранной карты",
            handler: {}
        )
    ])
    .environmentObject(AccessibilityManager.shared)
}

#Preview("Hearing Indicator") {
    VStack(spacing: 16) {
        HearingAccessibilityIndicator(soundType: .success, isActive: true)
        HearingAccessibilityIndicator(soundType: .error, isActive: true)
        HearingAccessibilityIndicator(soundType: .payment, isActive: true)
    }
    .padding()
    .environmentObject(AccessibilityManager.shared)
}

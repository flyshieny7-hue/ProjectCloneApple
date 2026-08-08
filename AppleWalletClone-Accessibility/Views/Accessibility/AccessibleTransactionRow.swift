import SwiftUI

// MARK: - AccessibleTransactionRow
/// Полностью доступная строка транзакции с поддержкой VoiceOver,
/// Dynamic Type, High Contrast и паттернами для дальтоников.
struct AccessibleTransactionRow: View {

    // MARK: Properties
    let transaction: WalletTransaction
    let onTap: () -> Void
    let onRefund: () -> Void
    let onShare: () -> Void
    let onReport: () -> Void

    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool = false

    // MARK: Body
    var body: some View {
        Button(action: {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
            onTap()
        }) {
            rowContent
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Вернуть платёж")) {
            onRefund()
            announceAction("Возврат платежа инициирован")
        }
        .accessibilityAction(named: Text("Поделиться чеком")) {
            onShare()
            announceAction("Открыто меню поделиться")
        }
        .accessibilityAction(named: Text("Пожаловаться")) {
            onReport()
            announceAction("Форма жалобы открыта")
        }
        .accessibilityInputLabels(["Транзакция \(transaction.merchantName)", "Платёж \(transaction.amount.formatted(.currency(code: transaction.currency)))", "Покупка \(transaction.category.localizedName)"])
        .accessibilityRespondsToUserInteraction(true)
    }

    // MARK: Content
    @ViewBuilder
    private var rowContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: dynamicTypeSize >= .accessibility2 ? 16 : 12) {
                // Иконка категории
                categoryIcon

                // Основная информация
                VStack(alignment: .leading, spacing: dynamicTypeSize >= .accessibility2 ? 8 : 4) {
                    Text(transaction.merchantName)
                        .font(.system(size: dynamicTypeSize >= .accessibility2 ? 22 : 17, weight: .semibold))
                        .foregroundColor(accessibilityManager.isHighContrastEnabled ? .primary : .primary)
                        .lineLimit(2)
                        .accessibilityHidden(true)

                    HStack(spacing: 8) {
                        Text(transaction.category.localizedName)
                            .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 13))
                            .foregroundColor(.secondary)

                        // Паттерн для дальтоников
                        if accessibilityManager.colorBlindMode != .none {
                            colorBlindCategoryPattern
                        }
                    }

                    Text(transaction.formattedDate)
                        .font(.system(size: dynamicTypeSize >= .accessibility2 ? 16 : 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Сумма транзакции
                VStack(alignment: .trailing, spacing: 4) {
                    Text(transaction.amount.formatted(.currency(code: transaction.currency)))
                        .font(.system(size: dynamicTypeSize >= .accessibility2 ? 22 : 17, weight: .bold))
                        .foregroundColor(amountColor)
                        .accessibilityHidden(true)

                    // Статус транзакции
                    transactionStatusBadge
                }
            }
            .padding(.vertical, dynamicTypeSize >= .accessibility2 ? 16 : 12)
            .padding(.horizontal, 16)

            // Развёрнутые детали
            if isExpanded {
                expandedDetails
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            // High Contrast разделитель
            if accessibilityManager.isHighContrastEnabled {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(height: 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            accessibilityManager.isHighContrastEnabled ? Color.black : Color.clear,
                            lineWidth: accessibilityManager.isHighContrastEnabled ? 2 : 0
                        )
                )
        )
        .background(
            accessibilityManager.isHighContrastEnabled ? Color(.systemBackground) : Color.clear
        )
    }

    // MARK: Subviews
    @ViewBuilder
    private var categoryIcon: some View {
        ZStack {
            Circle()
                .fill(accessibilityManager.adjustedColor(for: transaction.category.color).opacity(0.15))
                .frame(
                    width: dynamicTypeSize >= .accessibility3 ? 56 : 44,
                    height: dynamicTypeSize >= .accessibility3 ? 56 : 44
                )

            Image(systemName: transaction.category.icon)
                .font(.system(size: dynamicTypeSize >= .accessibility3 ? 28 : 20))
                .foregroundColor(accessibilityManager.adjustedColor(for: transaction.category.color))
                .accessibilityHidden(true)

            // Паттерн для дальтоников поверх иконки
            if accessibilityManager.colorBlindMode != .none {
                Circle()
                    .strokeBorder(
                        accessibilityManager.adjustedColor(for: transaction.category.color),
                        lineWidth: 2,
                        antialiased: true
                    )
                    .frame(
                        width: dynamicTypeSize >= .accessibility3 ? 56 : 44,
                        height: dynamicTypeSize >= .accessibility3 ? 56 : 44
                    )
            }
        }
        .accessibilityLabel("Категория: \(transaction.category.localizedName)")
    }

    @ViewBuilder
    private var colorBlindCategoryPattern: some View {
        // Уникальный паттерн для каждой категории
        let pattern = transaction.category.colorBlindPattern
        Image(systemName: pattern)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var transactionStatusBadge: some View {
        let (text, color) = transaction.status.badgeInfo
        Text(text)
            .font(.system(size: dynamicTypeSize >= .accessibility2 ? 14 : 10, weight: .medium))
            .foregroundColor(accessibilityManager.isHighContrastEnabled ? .primary : accessibilityManager.adjustedColor(for: color))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(accessibilityManager.adjustedColor(for: color).opacity(0.15))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        accessibilityManager.isHighContrastEnabled ? accessibilityManager.adjustedColor(for: color) : Color.clear,
                        lineWidth: 1
                    )
            )
            .accessibilityLabel("Статус: \(text)")
    }

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            DetailRow(label: "Номер транзакции", value: transaction.id.uuidString.prefix(8).uppercased())
            DetailRow(label: "Место", value: transaction.location)
            DetailRow(label: "Способ оплаты", value: transaction.paymentMethod)

            if transaction.cashback > 0 {
                DetailRow(
                    label: "Кэшбэк",
                    value: "+\(transaction.cashback.formatted(.currency(code: transaction.currency)))",
                    valueColor: .green
                )
            }

            // Кнопки действий для Switch Control / Voice Control
            HStack(spacing: 12) {
                ActionButton(title: "Вернуть", icon: "arrow.uturn.backward", action: onRefund)
                ActionButton(title: "Поделиться", icon: "square.and.arrow.up", action: onShare)
                ActionButton(title: "Жалоба", icon: "exclamationmark.triangle", action: onReport)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Детали транзакции развёрнуты")
    }

    // MARK: Accessibility Properties
    private var accessibilityLabel: Text {
        let type = transaction.amount >= 0 ? "Поступление" : "Списание"
        return Text("\(type) от \(transaction.merchantName)")
    }

    private var accessibilityValue: Text {
        let amountText = transaction.amount.formatted(.currency(code: transaction.currency))
        let statusText = transaction.status.localizedName
        let dateText = transaction.formattedDate
        return Text("Сумма: \(amountText). Статус: \(statusText). Дата: \(dateText). Категория: \(transaction.category.localizedName)")
    }

    private var accessibilityHint: Text {
        if isExpanded {
            return Text("Нажмите чтобы скрыть детали. Используйте действия для возврата, поделиться или жалобы.")
        } else {
            return Text("Нажмите чтобы развернуть детали транзакции")
        }
    }

    private var amountColor: Color {
        if accessibilityManager.isHighContrastEnabled {
            return transaction.amount >= 0 ? Color(red: 0, green: 0.5, blue: 0) : Color(red: 0.7, green: 0, blue: 0)
        }
        return transaction.amount >= 0 ? .green : .primary
    }

    // MARK: Helpers
    private func announceAction(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - DetailRow
struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var accessibilityManager: AccessibilityManager

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 14))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 14, weight: .medium))
                .foregroundColor(accessibilityManager.adjustedColor(for: valueColor))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - ActionButton
struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var accessibilityManager: AccessibilityManager

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 24 : 18))
                Text(title)
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 14 : 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                accessibilityManager.isHighContrastEnabled ? Color.black : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .foregroundColor(.primary)
        }
        .accessibilityLabel(title)
        .accessibilityHint("Двойное нажатие для выполнения действия")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - WalletTransaction Model
struct WalletTransaction: Identifiable {
    let id = UUID()
    let merchantName: String
    let amount: Double
    let currency: String
    let date: Date
    let category: TransactionCategory
    let status: TransactionStatus
    let location: String
    let paymentMethod: String
    let cashback: Double

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    enum TransactionCategory: String, CaseIterable {
        case food = "food"
        case transport = "transport"
        case shopping = "shopping"
        case entertainment = "entertainment"
        case health = "health"
        case utilities = "utilities"
        case salary = "salary"
        case transfer = "transfer"

        var localizedName: String {
            switch self {
            case .food: return "Еда и рестораны"
            case .transport: return "Транспорт"
            case .shopping: return "Покупки"
            case .entertainment: return "Развлечения"
            case .health: return "Здоровье"
            case .utilities: return "Коммунальные услуги"
            case .salary: return "Зарплата"
            case .transfer: return "Перевод"
            }
        }

        var icon: String {
            switch self {
            case .food: return "fork.knife"
            case .transport: return "car.fill"
            case .shopping: return "bag.fill"
            case .entertainment: return "film.fill"
            case .health: return "heart.fill"
            case .utilities: return "bolt.fill"
            case .salary: return "banknote.fill"
            case .transfer: return "arrow.left.arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .food: return .orange
            case .transport: return .blue
            case .shopping: return .purple
            case .entertainment: return .pink
            case .health: return .red
            case .utilities: return .yellow
            case .salary: return .green
            case .transfer: return .cyan
            }
        }

        // Уникальные паттерны для дальтоников
        var colorBlindPattern: String {
            switch self {
            case .food: return "circle.grid.2x2"      // Сетка
            case .transport: return "circle.dotted"    // Точки
            case .shopping: return "diamond"           // Ромб
            case .entertainment: return "star"         // Звезда
            case .health: return "cross"               // Крест
            case .utilities: return "bolt"             // Молния
            case .salary: return "dollarsign.circle"   // Доллар
            case .transfer: return "arrow.left.right"  // Стрелки
            }
        }
    }

    enum TransactionStatus: String {
        case completed = "completed"
        case pending = "pending"
        case declined = "declined"
        case refunded = "refunded"

        var localizedName: String {
            switch self {
            case .completed: return "Выполнена"
            case .pending: return "В обработке"
            case .declined: return "Отклонена"
            case .refunded: return "Возвращена"
            }
        }

        var badgeInfo: (String, Color) {
            switch self {
            case .completed: return ("✓ Выполнена", .green)
            case .pending: return ("⏳ В обработке", .orange)
            case .declined: return ("✕ Отклонена", .red)
            case .refunded: return ("↩ Возвращена", .blue)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    List {
        AccessibleTransactionRow(
            transaction: WalletTransaction(
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
            onTap: {},
            onRefund: {},
            onShare: {},
            onReport: {}
        )
        .environmentObject(AccessibilityManager.shared)
    }
}

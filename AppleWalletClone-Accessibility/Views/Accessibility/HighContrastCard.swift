import SwiftUI

// MARK: - HighContrastCard
/// Карта с улучшенным контрастом для пользователей с нарушениями зрения.
/// Соответствует WCAG 2.1 Level AAA (контраст 7:1 для текста).
struct HighContrastCard: View {

    // MARK: Properties
    let card: PaymentCard
    let isSelected: Bool
    let onTap: () -> Void
    let onShowBalance: () -> Void
    let onShowDetails: () -> Void

    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed: Bool = false

    // MARK: Body
    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(HighContrastButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(highContrastLabel)
        .accessibilityValue(highContrastValue)
        .accessibilityHint(highContrastHint)
        .accessibilityAddTraits([.isButton, .isHeader])
        .accessibilityAction(named: Text("Показать баланс")) {
            onShowBalance()
            UIAccessibility.post(notification: .announcement, argument: "Баланс: \(card.balance.formatted(.currency(code: card.currency)))")
        }
        .accessibilityAction(named: Text("Детали карты")) {
            onShowDetails()
        }
        .accessibilityAction(named: Text("Скрыть баланс")) {
            UIAccessibility.post(notification: .announcement, argument: "Баланс скрыт")
        }
        .accessibilityRespondsToUserInteraction(true)
    }

    // MARK: Content
    @ViewBuilder
    private var cardContent: some View {
        ZStack {
            // Фон с максимальным контрастом
            highContrastBackground

            // Контент
            VStack(alignment: .leading, spacing: dynamicTypeSize >= .accessibility2 ? 20 : 16) {
                // Верхняя строка: банк + тип
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: card.bankIcon)
                            .font(.system(size: dynamicTypeSize >= .accessibility3 ? 28 : 22, weight: .bold))
                            .foregroundColor(highContrastForeground)
                            .accessibilityHidden(true)

                        Text(card.bankName)
                            .font(.system(size: dynamicTypeSize >= .accessibility3 ? 22 : 18, weight: .bold))
                            .foregroundColor(highContrastForeground)
                    }

                    Spacer()

                    Text(card.cardType.localizedName.uppercased())
                        .font(.system(size: dynamicTypeSize >= .accessibility2 ? 16 : 13, weight: .heavy))
                        .foregroundColor(highContrastBackgroundColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(highContrastForeground)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.black, lineWidth: 2)
                        )
                }

                Spacer()

                // Номер карты
                HStack(spacing: dynamicTypeSize >= .accessibility2 ? 20 : 16) {
                    ForEach(0..<3) { _ in
                        Text("••••")
                            .font(.system(size: dynamicTypeSize >= .accessibility3 ? 32 : 24, weight: .heavy, design: .monospaced))
                            .foregroundColor(highContrastForeground)
                            .accessibilityHidden(true)
                    }
                    Text(card.lastFourDigits)
                        .font(.system(size: dynamicTypeSize >= .accessibility3 ? 32 : 24, weight: .heavy, design: .monospaced))
                        .foregroundColor(highContrastForeground)
                        .accessibilityLabel("Последние цифры: \(card.lastFourDigits)")
                }

                Spacer()

                // Нижняя строка: имя + срок + платёжная система
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.cardName)
                            .font(.system(size: dynamicTypeSize >= .accessibility3 ? 22 : 18, weight: .bold))
                            .foregroundColor(highContrastForeground)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text("ДО:")
                                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 16 : 14, weight: .heavy))
                                .foregroundColor(highContrastForeground.opacity(0.9))
                            Text(card.expiryDate)
                                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 15, weight: .heavy, design: .monospaced))
                                .foregroundColor(highContrastForeground)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: card.paymentSystem.icon)
                            .font(.system(size: dynamicTypeSize >= .accessibility3 ? 40 : 32, weight: .bold))
                            .foregroundColor(highContrastForeground)
                            .accessibilityLabel(card.paymentSystem.accessibilityName)

                        Text(card.paymentSystem.rawValue.uppercased())
                            .font(.system(size: dynamicTypeSize >= .accessibility2 ? 14 : 11, weight: .heavy))
                            .foregroundColor(highContrastForeground)
                    }
                }
            }
            .padding(dynamicTypeSize >= .accessibility3 ? 28 : 20)

            // Рамка выделения
            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.yellow, lineWidth: 5)
                    .padding(2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.black, lineWidth: 2)
                            .padding(5)
                    )
            }

            // Индикатор выбора
            if isSelected {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.black, lineWidth: 2)
                                )
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundColor(.black)
                        }
                        .padding(12)
                        .accessibilityLabel("Карта выбрана")
                    }
                    Spacer()
                }
            }
        }
        .frame(
            width: highContrastCardWidth,
            height: highContrastCardHeight
        )
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(highContrastBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(highContrastBorderColor, lineWidth: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black, lineWidth: 1)
                        .padding(3)
                )
        )
        .shadow(
            color: Color.black.opacity(0.9),
            radius: 8,
            x: 0,
            y: 4
        )
        .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1.0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: isPressed)
    }

    // MARK: High Contrast Colors
    private var highContrastBackgroundColor: Color {
        // Чёрный или тёмно-синий фон для максимального контраста
        Color(red: 0.0, green: 0.0, blue: 0.15)
    }

    private var highContrastForeground: Color {
        // Ярко-жёлтый или белый текст — максимальный контраст на тёмном фоне
        Color(red: 1.0, green: 1.0, blue: 0.85)
    }

    private var highContrastBorderColor: Color {
        Color(red: 1.0, green: 0.9, blue: 0.0) // Жёлтая рамка
    }

    // MARK: Accessibility
    private var highContrastLabel: Text {
        Text("\(card.cardName), \(card.cardType.localizedName), банк \(card.bankName)")
    }

    private var highContrastValue: Text {
        Text("Номер заканчивается на \(card.lastFourDigits). Действительна до \(card.expiryDate). Платёжная система: \(card.paymentSystem.accessibilityName)")
    }

    private var highContrastHint: Text {
        Text("Активируйте для выбора карты. Используйте действия для баланса или деталей.")
    }

    // MARK: Layout
    private var highContrastCardWidth: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge:
            return 340
        case .accessibility1, .accessibility2:
            return 360
        case .accessibility3, .accessibility4, .accessibility5:
            return UIScreen.main.bounds.width - 24
        @unknown default:
            return 340
        }
    }

    private var highContrastCardHeight: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge:
            return 220
        case .accessibility1:
            return 240
        case .accessibility2, .accessibility3:
            return 280
        case .accessibility4, .accessibility5:
            return 340
        @unknown default:
            return 220
        }
    }

    @ViewBuilder
    private var highContrastBackground: some View {
        // Текстурированный фон для дополнительной различимости
        ZStack {
            highContrastBackgroundColor

            // Диагональные линии (только для визуальной текстуры)
            GeometryReader { geometry in
                Canvas { context, size in
                    let renderer = UIGraphicsImageRenderer(size: size)
                    let img = renderer.image { ctx in
                        ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.03).cgColor)
                        ctx.cgContext.setLineWidth(1)
                        for i in stride(from: 0, to: size.width + size.height, by: 30) {
                            ctx.cgContext.move(to: CGPoint(x: i, y: 0))
                            ctx.cgContext.addLine(to: CGPoint(x: i - size.height, y: size.height))
                        }
                        ctx.cgContext.strokePath()
                    }
                    context.draw(Image(uiImage: img), at: CGPoint(x: size.width/2, y: size.height/2))
                }
            }
        }
    }
}

// MARK: - HighContrastButtonStyle
struct HighContrastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        HighContrastCard(
            card: PaymentCard(
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
            isSelected: true,
            onTap: {},
            onShowBalance: {},
            onShowDetails: {}
        )

        HighContrastCard(
            card: PaymentCard(
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
            isSelected: false,
            onTap: {},
            onShowBalance: {},
            onShowDetails: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
    .environmentObject(AccessibilityManager.shared)
}

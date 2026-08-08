import SwiftUI

// MARK: - AccessibleCardView
/// Полностью доступная карта с поддержкой VoiceOver, Dynamic Type,
/// High Contrast, Color Blindness и Switch Control.
struct AccessibleCardView: View {

    // MARK: Properties
    let card: PaymentCard
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onLongPress: () -> Void

    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body
    var body: some View {
        cardContent
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(cardTraits)
            .accessibilityAction(named: Text("Показать баланс")) {
                onDoubleTap()
            }
            .accessibilityAction(named: Text("Открыть детали")) {
                onTap()
            }
            .accessibilityAction(named: Text("Быстрые действия")) {
                onLongPress()
            }
            .accessibilityInputLabels(["Карта \(card.lastFourDigits)", card.cardName])
            .accessibilityDragPoint(CGPoint(x: 0.5, y: 0.5))
            .accessibilityRespondsToUserInteraction(true)
    }

    // MARK: Content
    @ViewBuilder
    private var cardContent: some View {
        ZStack {
            // Фон карты с паттерном для дальтонизма
            cardBackground

            // Основной контент
            VStack(alignment: .leading, spacing: dynamicTypeSize >= .accessibility2 ? 16 : 12) {
                headerSection
                Spacer()
                cardNumberSection
                Spacer()
                footerSection
            }
            .padding(dynamicTypeSize >= .accessibility3 ? 24 : 16)

            // High Contrast overlay
            if accessibilityManager.isHighContrastEnabled {
                highContrastOverlay
            }

            // Color Blind pattern overlay
            if accessibilityManager.colorBlindMode != .none {
                colorBlindPatternOverlay
            }

            // Selection indicator
            if isSelected {
                selectionIndicator
            }
        }
        .frame(
            width: cardWidth,
            height: cardHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelected ? Color.blue : Color.clear,
                    lineWidth: accessibilityManager.isHighContrastEnabled ? 4 : 2
                )
        )
        .shadow(
            color: accessibilityManager.isHighContrastEnabled ? Color.black.opacity(0.8) : Color.black.opacity(0.2),
            radius: accessibilityManager.isHighContrastEnabled ? 8 : 4,
            x: 0,
            y: accessibilityManager.isHighContrastEnabled ? 4 : 2
        )
        .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onTapGesture {
            onTap()
            announceCardSelection()
        }
        .onLongPressGesture {
            onLongPress()
            UIAccessibility.post(notification: .announcement, argument: "Открыто меню быстрых действий для карты \(card.cardName)")
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onDoubleTap()
                    UIAccessibility.post(notification: .announcement, argument: "Баланс карты: \(card.balance.formatted(.currency(code: card.currency))) ")
                }
        )
    }

    // MARK: Sections
    @ViewBuilder
    private var headerSection: some View {
        HStack {
            // Логотип банка с accessibility
            Image(systemName: card.bankIcon)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 32 : 24, weight: .semibold))
                .foregroundColor(accessibilityManager.adjustedColor(for: .white))
                .accessibilityHidden(true)

            Spacer()

            // Тип карты (дебет/кредит)
            Text(card.cardType.localizedName)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 14, weight: .medium))
                .foregroundColor(accessibilityManager.adjustedColor(for: .white.opacity(0.9)))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(accessibilityManager.adjustedColor(for: .white.opacity(0.2)))
                )
                .accessibilityLabel("Тип карты: \(card.cardType.localizedName)")
        }
    }

    @ViewBuilder
    private var cardNumberSection: some View {
        HStack(spacing: dynamicTypeSize >= .accessibility2 ? 16 : 12) {
            ForEach(0..<3) { _ in
                Text("••••")
                    .font(.system(size: dynamicTypeSize >= .accessibility3 ? 28 : 20, weight: .medium, design: .monospaced))
                    .foregroundColor(accessibilityManager.adjustedColor(for: .white))
                    .accessibilityHidden(true)
            }

            Text(card.lastFourDigits)
                .font(.system(size: dynamicTypeSize >= .accessibility3 ? 28 : 20, weight: .medium, design: .monospaced))
                .foregroundColor(accessibilityManager.adjustedColor(for: .white))
                .accessibilityLabel("Последние цифры: \(card.lastFourDigits)")
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.cardName)
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 16, weight: .semibold))
                    .foregroundColor(accessibilityManager.adjustedColor(for: .white))
                    .lineLimit(1)

                Text("Истекает \(card.expiryDate)")
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 16 : 12))
                    .foregroundColor(accessibilityManager.adjustedColor(for: .white.opacity(0.8)))
            }

            Spacer()

            // Payment system icon
            Image(systemName: card.paymentSystem.icon)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 36 : 28))
                .foregroundColor(accessibilityManager.adjustedColor(for: .white))
                .accessibilityLabel(card.paymentSystem.accessibilityName)
        }
    }

    // MARK: Background & Overlays
    @ViewBuilder
    private var cardBackground: some View {
        let baseColor = accessibilityManager.adjustedColor(for: card.themeColor)

        LinearGradient(
            colors: [
                baseColor,
                baseColor.opacity(0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var highContrastOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.white, lineWidth: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.black, lineWidth: 1)
                    .padding(2)
            )
    }

    @ViewBuilder
    private var colorBlindPatternOverlay: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let pattern = createColorBlindPattern(in: size)
                context.draw(pattern, at: CGPoint(x: size.width/2, y: size.height/2))
            }
        }
        .opacity(0.15)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.blue))
                    .padding(8)
                    .accessibilityLabel("Карта выбрана")
            }
            Spacer()
        }
    }

    // MARK: Accessibility Properties
    private var accessibilityLabel: Text {
        Text("\(card.cardName), \(card.cardType.localizedName), банк \(card.bankName)")
    }

    private var accessibilityValue: Text {
        Text("Баланс: \(card.balance.formatted(.currency(code: card.currency))), заканчивается на \(card.lastFourDigits), действительна до \(card.expiryDate)")
    }

    private var accessibilityHint: Text {
        if accessibilityManager.isSwitchControlRunning {
            Text("Активируйте для выбора карты. Двойное нажатие для баланса. Долгое нажатие для меню.")
        } else {
            Text("Нажмите для открытия. Дважды нажмите для прослушивания баланса. Удерживайте для быстрых действий.")
        }
    }

    private var cardTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = .isButton
        if isSelected {
            traits.insert(.isSelected)
        }
        if card.isDefault {
            traits.insert(.isHeader)
        }
        return traits
    }

    // MARK: Helpers
    private var cardWidth: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge:
            return 320
        case .accessibility1, .accessibility2:
            return 340
        case .accessibility3, .accessibility4, .accessibility5:
            return UIScreen.main.bounds.width - 32
        @unknown default:
            return 320
        }
    }

    private var cardHeight: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge:
            return 200
        case .accessibility1:
            return 220
        case .accessibility2, .accessibility3:
            return 260
        case .accessibility4, .accessibility5:
            return 300
        @unknown default:
            return 200
        }
    }

    private func announceCardSelection() {
        let announcement = "Выбрана карта \(card.cardName). Баланс: \(card.balance.formatted(.currency(code: card.currency)))"
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    private func createColorBlindPattern(in size: CGSize) -> Image {
        // Создаём паттерн для дальтоников (полосы/точки)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let ctx = context.cgContext
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(2)

            // Диагональные полосы
            for i in stride(from: 0, to: size.width + size.height, by: 20) {
                ctx.move(to: CGPoint(x: i, y: 0))
                ctx.addLine(to: CGPoint(x: i - size.height, y: size.height))
            }
            ctx.strokePath()
        }
        return Image(uiImage: image)
    }
}

// MARK: - PaymentCard Model
struct PaymentCard: Identifiable {
    let id = UUID()
    let cardName: String
    let bankName: String
    let bankIcon: String
    let lastFourDigits: String
    let expiryDate: String
    let balance: Double
    let currency: String
    let themeColor: Color
    let cardType: CardType
    let paymentSystem: PaymentSystem
    let isDefault: Bool

    enum CardType: String {
        case debit = "debit"
        case credit = "credit"

        var localizedName: String {
            switch self {
            case .debit: return "Дебетовая"
            case .credit: return "Кредитная"
            }
        }
    }

    enum PaymentSystem: String {
        case visa = "visa"
        case mastercard = "mastercard"
        case mir = "mir"

        var icon: String {
            switch self {
            case .visa: return "creditcard"
            case .mastercard: return "creditcard.fill"
            case .mir: return "creditcard.and.123"
            }
        }

        var accessibilityName: String {
            switch self {
            case .visa: return "Платёжная система Visa"
            case .mastercard: return "Платёжная система Mastercard"
            case .mir: return "Платёжная система МИР"
            }
        }
    }
}

// MARK: - Preview
#Preview {
    AccessibleCardView(
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
        onDoubleTap: {},
        onLongPress: {}
    )
    .environmentObject(AccessibilityManager.shared)
    .padding()
}

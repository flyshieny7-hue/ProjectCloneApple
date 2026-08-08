import SwiftUI

// MARK: - ColorBlindPreview
/// Интерактивный превью для тестирования цветовой доступности.
/// Позволяет переключаться между режимами дальтонизма и видеть,
/// как интерфейс выглядит для пользователей с различными видами
/// цветовой слепоты.
struct ColorBlindPreview: View {

    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedCardIndex: Int = 0
    @State private var showPatternLegend: Bool = false

    private let sampleCards = [
        SampleCard(name: "Дебетовая", color: .green, pattern: "circle.grid.2x2", type: .debit),
        SampleCard(name: "Кредитная", color: .red, pattern: "diamond", type: .credit),
        SampleCard(name: "Накопительная", color: .blue, pattern: "star", type: .savings),
        SampleCard(name: "Бизнес", color: .purple, pattern: "bolt", type: .business)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: dynamicTypeSize >= .accessibility2 ? 32 : 20) {
                // Заголовок
                headerSection

                // Выбор режима
                modeSelector

                // Примеры карт
                cardsPreviewSection

                // Легенда паттернов
                patternLegendSection

                // Транзакции
                transactionsPreviewSection

                // Рекомендации
                recommendationsSection
            }
            .padding()
        }
        .navigationTitle("Предпросмотр дальтонизма")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Экран предпросмотра режимов цветовой коррекции")
        .accessibilityHint("Выберите режим дальтонизма для проверки доступности интерфейса")
    }

    // MARK: Sections
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Проверка цветовой доступности")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 28 : 22, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            Text("Выберите тип дальтонизма для симуляции. Убедитесь, что информация передаётся не только цветом, но и паттернами/текстом.")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 15))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Проверка цветовой доступности. Выберите тип дальтонизма для симуляции.")
    }

    @ViewBuilder
    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Режим симуляции")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AccessibilityManager.ColorBlindMode.allCases) { mode in
                        ModeButton(
                            mode: mode,
                            isSelected: accessibilityManager.colorBlindMode == mode,
                            action: {
                                accessibilityManager.setColorBlindMode(mode)
                                UIAccessibility.post(
                                    notification: .announcement,
                                    argument: "Выбран режим: \(mode.displayName)"
                                )
                            }
                        )
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Выбор режима дальтонизма")
            .accessibilityHint("Горизонтальный список режимов. Проведите для навигации.")
        }
    }

    @ViewBuilder
    private var cardsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Примеры карт")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(sampleCards.enumerated()), id: \.offset) { index, card in
                        ColorBlindCardPreview(
                            card: card,
                            isSelected: selectedCardIndex == index
                        )
                        .onTapGesture {
                            selectedCardIndex = index
                            UIAccessibility.post(
                                notification: .announcement,
                                argument: "Выбрана карта: \(card.name)"
                            )
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(card.name), тип: \(card.type.localizedName)")
                        .accessibilityValue("Цвет: \(card.color.accessibilityName)")
                        .accessibilityHint("Нажмите для выбора")
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Горизонтальный список примеров карт")
        }
    }

    @ViewBuilder
    private var patternLegendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation {
                    showPatternLegend.toggle()
                }
            }) {
                HStack {
                    Text("Легенда паттернов")
                        .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 17, weight: .semibold))

                    Spacer()

                    Image(systemName: showPatternLegend ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Легенда паттернов")
            .accessibilityHint(showPatternLegend ? "Нажмите чтобы скрыть" : "Нажмите чтобы показать легенду паттернов для дальтоников")

            if showPatternLegend {
                VStack(spacing: 12) {
                    ForEach(sampleCards) { card in
                        HStack(spacing: 12) {
                            Image(systemName: card.pattern)
                                .font(.system(size: 24))
                                .foregroundColor(accessibilityManager.adjustedColor(for: card.color))
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(accessibilityManager.adjustedColor(for: card.color).opacity(0.15))
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.name)
                                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 15, weight: .medium))
                                Text(card.type.localizedName)
                                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 16 : 13))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Паттерн-индикатор
                            PatternIndicator(pattern: card.pattern, color: card.color)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(card.name): паттерн \(card.pattern), тип \(card.type.localizedName)")
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var transactionsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Примеры транзакций")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 8) {
                ColorBlindTransactionPreview(
                    merchant: "Пятёрочка",
                    amount: -1250.00,
                    category: .food,
                    pattern: "circle.grid.2x2"
                )

                ColorBlindTransactionPreview(
                    merchant: "Метро",
                    amount: -55.00,
                    category: .transport,
                    pattern: "circle.dotted"
                )

                ColorBlindTransactionPreview(
                    merchant: "Зарплата",
                    amount: 85000.00,
                    category: .salary,
                    pattern: "banknote"
                )
            }
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Рекомендации")
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 8) {
                RecommendationRow(
                    icon: "text.badge.checkmark",
                    text: "Всегда используйте текстовые метки вместе с цветовыми индикаторами"
                )
                RecommendationRow(
                    icon: "circle.grid.2x2",
                    text: "Добавляйте уникальные паттерны для каждой категории"
                )
                RecommendationRow(
                    icon: "arrow.up.arrow.down",
                    text: "Обеспечивайте контрастность не менее 4.5:1 для текста"
                )
                RecommendationRow(
                    icon: "hand.tap",
                    text: "Тестируйте интерфейс в режиме отключённых цветов (Smart Invert)"
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 2)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Секция рекомендаций по цветовой доступности")
    }
}

// MARK: - Supporting Views
struct ModeButton: View {
    let mode: AccessibilityManager.ColorBlindMode
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var accessibilityManager: AccessibilityManager

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Цветовой индикатор режима
                ZStack {
                    Circle()
                        .fill(modeIndicatorColor)
                        .frame(width: 48, height: 48)

                    if mode != .none {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "eye")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }

                Text(mode.displayName)
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 14 : 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 80)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? Color.blue : Color.clear,
                                lineWidth: accessibilityManager.isHighContrastEnabled ? 3 : 2
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(isSelected ? "Выбрано" : "")
        .accessibilityHint(mode.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var modeIndicatorColor: Color {
        switch mode {
        case .none: return .green
        case .protanopia: return .orange
        case .deuteranopia: return .yellow
        case .tritanopia: return .purple
        case .achromatopsia: return .gray
        }
    }
}

struct ColorBlindCardPreview: View {
    let card: SampleCard
    let isSelected: Bool

    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Паттерн индикатор
            HStack {
                Spacer()
                PatternIndicator(pattern: card.pattern, color: card.color)
            }

            Spacer()

            Text(card.name)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 18 : 15, weight: .semibold))
                .foregroundColor(.white)

            Text(card.type.localizedName)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 14 : 12))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .frame(width: 140, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accessibilityManager.adjustedColor(for: card.color))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.white : Color.clear,
                    lineWidth: 3
                )
        )
        .accessibilityHidden(true) // Основная метка на родителе
    }
}

struct ColorBlindTransactionPreview: View {
    let merchant: String
    let amount: Double
    let category: WalletTransaction.TransactionCategory
    let pattern: String

    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accessibilityManager.adjustedColor(for: category.color).opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: category.icon)
                    .font(.system(size: 18))
                    .foregroundColor(accessibilityManager.adjustedColor(for: category.color))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(merchant)
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 17 : 15, weight: .medium))

                HStack(spacing: 4) {
                    PatternIndicator(pattern: pattern, color: category.color)
                    Text(category.localizedName)
                        .font(.system(size: dynamicTypeSize >= .accessibility2 ? 15 : 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(amount.formatted(.currency(code: "RUB")))
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 17 : 15, weight: .semibold))
                .foregroundColor(amount >= 0 ? accessibilityManager.adjustedColor(for: .green) : .primary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(merchant), \(category.localizedName), сумма \(amount.formatted(.currency(code: "RUB")))")
    }
}

struct PatternIndicator: View {
    let pattern: String
    let color: Color

    @EnvironmentObject private var accessibilityManager: AccessibilityManager

    var body: some View {
        Image(systemName: pattern)
            .font(.system(size: 12))
            .foregroundColor(accessibilityManager.adjustedColor(for: color))
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(accessibilityManager.adjustedColor(for: color).opacity(0.1))
            )
            .accessibilityHidden(true)
    }
}

struct RecommendationRow: View {
    let icon: String
    let text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 22 : 18))
                .foregroundColor(.blue)
                .frame(width: 28)

            Text(text)
                .font(.system(size: dynamicTypeSize >= .accessibility2 ? 17 : 15))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - SampleCard Model
struct SampleCard: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let pattern: String
    let type: CardType

    enum CardType: String {
        case debit = "debit"
        case credit = "credit"
        case savings = "savings"
        case business = "business"

        var localizedName: String {
            switch self {
            case .debit: return "Дебетовая"
            case .credit: return "Кредитная"
            case .savings: return "Накопительная"
            case .business: return "Бизнес"
            }
        }
    }
}

// MARK: - Color Extension
extension Color {
    var accessibilityName: String {
        // Упрощённая реализация
        let uiColor = UIColor(self)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if saturation < 0.1 { return "Серый" }
        switch hue {
        case 0..<0.08: return "Красный"
        case 0.08..<0.17: return "Оранжевый"
        case 0.17..<0.33: return "Жёлтый/Зелёный"
        case 0.33..<0.5: return "Зелёный/Голубой"
        case 0.5..<0.67: return "Голубой/Синий"
        case 0.67..<0.83: return "Синий/Фиолетовый"
        default: return "Красный/Розовый"
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        ColorBlindPreview()
            .environmentObject(AccessibilityManager.shared)
    }
}

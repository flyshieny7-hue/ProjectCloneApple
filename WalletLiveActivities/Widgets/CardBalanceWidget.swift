import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Card Balance Entry
struct CardBalanceEntry: TimelineEntry {
    let date: Date
    let cardName: String
    let cardLastFour: String
    let balance: Double
    let availableCredit: Double
    let currency: String
    let cardColor: String
    let recentTransactions: [MiniTransaction]
    let isLocked: Bool
    let notificationsCount: Int
}

struct MiniTransaction: Codable {
    let merchant: String
    let amount: Double
    let isDebit: Bool
    let date: Date
}

// MARK: - Provider
struct CardBalanceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CardBalanceEntry {
        CardBalanceEntry(
            date: Date(),
            cardName: "Apple Card",
            cardLastFour: "4242",
            balance: 1250.00,
            availableCredit: 8750.00,
            currency: "$",
            cardColor: "blue",
            recentTransactions: [
                MiniTransaction(merchant: "Starbucks", amount: 5.67, isDebit: true, date: Date().addingTimeInterval(-3600)),
                MiniTransaction(merchant: "Salary", amount: 3500.00, isDebit: false, date: Date().addingTimeInterval(-86400))
            ],
            isLocked: false,
            notificationsCount: 2
        )
    }

    func snapshot(for configuration: CardBalanceConfigurationIntent, in context: Context) async -> CardBalanceEntry {
        placeholder(in: context)
    }

    func timeline(for configuration: CardBalanceConfigurationIntent, in context: Context) async -> Timeline<CardBalanceEntry> {
        let entry = placeholder(in: context)
        return Timeline(entries: [entry], policy: .atEnd)
    }
}

// MARK: - Configuration Intent
struct CardBalanceConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Card Balance"
    static var description = IntentDescription("Shows your card balance and recent transactions")

    @Parameter(title: "Card", default: "Apple Card")
    var selectedCard: String

    @Parameter(title: "Show Transactions", default: true)
    var showTransactions: Bool
}

// MARK: - Card Balance Widget
struct CardBalanceWidget: Widget {
    let kind: String = "CardBalanceWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CardBalanceConfigurationIntent.self,
            provider: CardBalanceProvider()
        ) { entry in
            CardBalanceWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    widgetBackground
                }
        }
        .configurationDisplayName("Card Balance")
        .description("View your balance and recent activity")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
            .systemMedium,
            .systemLarge
        ])
    }

    private var widgetBackground: some View {
        Color.clear
    }
}

// MARK: - Widget Views
struct CardBalanceWidgetView: View {
    let entry: CardBalanceEntry
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge:
            SystemWidgetView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            SystemWidgetView(entry: entry)
        }
    }
}

// MARK: - System Widget (Lock Screen + Home Screen)
struct SystemWidgetView: View {
    let entry: CardBalanceEntry
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    // Card chip
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cardColor.opacity(0.8))
                        .frame(width: 24, height: 16)

                    Text(entry.cardName)
                        .font(.caption.bold())

                    Text("•••• \(entry.cardLastFour)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if entry.notificationsCount > 0 {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 18, height: 18)
                        Text("\(entry.notificationsCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                if entry.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Balance
            VStack(alignment: .leading, spacing: 2) {
                Text("BALANCE")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(1)

                Text("\(entry.currency)\(String(format: "%.2f", entry.balance))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Available credit
            HStack {
                Text("Available: \(entry.currency)\(String(format: "%.2f", entry.availableCredit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                // Credit utilization
                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))

                            let utilization = entry.balance / (entry.balance + entry.availableCredit)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(utilizationColor(utilization))
                                .frame(width: geo.size.width * utilization)
                        }
                    }
                    .frame(width: 40, height: 4)

                    Text("\(Int(utilization * 100))%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Recent transactions
            VStack(spacing: 6) {
                ForEach(entry.recentTransactions.prefix(3), id: \.merchant) { tx in
                    HStack {
                        ZStack {
                            Circle()
                                .fill(tx.isDebit ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                                .frame(width: 24, height: 24)
                            Image(systemName: tx.isDebit ? "arrow.up.right" : "arrow.down.left")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(tx.isDebit ? .red : .green)
                        }

                        Text(tx.merchant)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        Text("\(tx.isDebit ? "-" : "+")\(entry.currency)\(String(format: "%.2f", tx.amount))")
                            .font(.caption.bold())
                            .foregroundStyle(tx.isDebit ? .primary : .green)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            // Interactive buttons (iOS 17+)
            if #available(iOS 17.0, *) {
                HStack(spacing: 8) {
                    Button(intent: PayIntent()) {
                        Label("Pay", systemImage: "dollarsign.circle")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .buttonBorderShape(.roundedRectangle(radius: 8))

                    Button(intent: LockCardIntent(isLocked: !entry.isLocked)) {
                        Label(entry.isLocked ? "Unlock" : "Lock", systemImage: entry.isLocked ? "lock.open" : "lock")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .buttonBorderShape(.roundedRectangle(radius: 8))

                    Button(intent: ViewDetailsIntent()) {
                        Label("View", systemImage: "eye")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(cardColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var cardColor: Color {
        switch entry.cardColor.lowercased() {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "purple": return .purple
        case "gold": return .yellow
        default: return .gray
        }
    }

    private var backgroundColor: Color {
        switch renderingMode {
        case .accented:
            return Color.clear
        case .vibrant:
            return Color.gray.opacity(0.1)
        default:
            return colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color.white
        }
    }

    private func utilizationColor(_ value: Double) -> Color {
        if value < 0.3 { return .green }
        if value < 0.7 { return .yellow }
        return .red
    }

    private var utilization: Double {
        entry.balance / (entry.balance + entry.availableCredit)
    }
}

// MARK: - Accessory Views (Apple Watch, StandBy)
struct AccessoryCircularView: View {
    let entry: CardBalanceEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Image(systemName: entry.isLocked ? "lock.fill" : "creditcard.fill")
                    .font(.title3)
                    .foregroundStyle(cardColor)

                Text("\(entry.currency)\(Int(entry.balance))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var cardColor: Color {
        switch entry.cardColor.lowercased() {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "purple": return .purple
        case "gold": return .yellow
        default: return .gray
        }
    }
}

struct AccessoryRectangularView: View {
    let entry: CardBalanceEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isLocked ? "lock.fill" : "creditcard.fill")
                .font(.title3)
                .foregroundStyle(cardColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.cardName)
                    .font(.caption.bold())
                    .lineLimit(1)

                Text("\(entry.currency)\(String(format: "%.2f", entry.balance))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text("Avail: \(entry.currency)\(String(format: "%.0f", entry.availableCredit))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var cardColor: Color {
        switch entry.cardColor.lowercased() {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "purple": return .purple
        case "gold": return .yellow
        default: return .gray
        }
    }
}

struct AccessoryInlineView: View {
    let entry: CardBalanceEntry

    var body: some View {
        Text("\(Image(systemName: "creditcard")) \(entry.cardName): \(entry.currency)\(String(format: "%.0f", entry.balance))")
            .font(.caption.bold())
    }
}

// MARK: - App Intents for Interactive Widgets
@available(iOS 17.0, *)
struct PayIntent: AppIntent {
    static var title: LocalizedStringResource = "Pay"
    static var description = IntentDescription("Open payment screen")

    func perform() async throws -> some IntentResult {
        // Open Wallet app to payment flow
        await MainActor.run {
            if let url = URL(string: "wallet://pay") {
                // Open URL
            }
        }
        return .result()
    }
}

@available(iOS 17.0, *)
struct LockCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock Card"
    static var description = IntentDescription("Lock or unlock your card")

    @Parameter(title: "Lock")
    var isLocked: Bool

    init() {}

    init(isLocked: Bool) {
        self.isLocked = isLocked
    }

    func perform() async throws -> some IntentResult {
        // Toggle card lock state
        return .result()
    }
}

@available(iOS 17.0, *)
struct ViewDetailsIntent: AppIntent {
    static var title: LocalizedStringResource = "View Details"
    static var description = IntentDescription("View card details")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            if let url = URL(string: "wallet://details") {
                // Open URL
            }
        }
        return .result()
    }
}

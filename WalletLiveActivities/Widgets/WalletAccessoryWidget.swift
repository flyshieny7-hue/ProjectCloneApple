import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Accessory Entry
struct WalletAccessoryEntry: TimelineEntry {
    let date: Date
    let totalBalance: Double
    let currency: String
    let activeCards: Int
    let pendingPayments: Int
    let unreadNotifications: Int
    let quickActions: [QuickAction]
    let locationContext: LocationContext?
}

struct QuickAction: Codable {
    let id: String
    let title: String
    let icon: String
    let color: String
    let deepLink: String
}

struct LocationContext: Codable {
    let nearbyStore: String
    let storeCategory: String
    let distance: String
    let offerAvailable: Bool
}

// MARK: - Provider
struct WalletAccessoryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WalletAccessoryEntry {
        WalletAccessoryEntry(
            date: Date(),
            totalBalance: 15420.50,
            currency: "$",
            activeCards: 4,
            pendingPayments: 2,
            unreadNotifications: 3,
            quickActions: [
                QuickAction(id: "pay", title: "Pay", icon: "dollarsign.circle.fill", color: "green", deepLink: "wallet://pay"),
                QuickAction(id: "send", title: "Send", icon: "paperplane.fill", color: "blue", deepLink: "wallet://send"),
                QuickAction(id: "request", title: "Request", icon: "arrow.down.circle.fill", color: "purple", deepLink: "wallet://request")
            ],
            locationContext: LocationContext(
                nearbyStore: "Starbucks",
                storeCategory: "Coffee",
                distance: "120m",
                offerAvailable: true
            )
        )
    }

    func snapshot(for configuration: WalletAccessoryConfigurationIntent, in context: Context) async -> WalletAccessoryEntry {
        placeholder(in: context)
    }

    func timeline(for configuration: WalletAccessoryConfigurationIntent, in context: Context) async -> Timeline<WalletAccessoryEntry> {
        var entries: [WalletAccessoryEntry] = []
        let currentDate = Date()

        // Update every 15 minutes
        for minuteOffset in stride(from: 0, to: 60, by: 15) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate)!
            var entry = placeholder(in: context)
            entry.date = entryDate
            entries.append(entry)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Configuration Intent
struct WalletAccessoryConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Wallet Accessory"
    static var description = IntentDescription("Quick access to wallet functions and balances")

    @Parameter(title: "Show Location", default: true)
    var showLocation: Bool

    @Parameter(title: "Show Quick Actions", default: true)
    var showQuickActions: Bool
}

// MARK: - Wallet Accessory Widget
struct WalletAccessoryWidget: Widget {
    let kind: String = "WalletAccessoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WalletAccessoryConfigurationIntent.self,
            provider: WalletAccessoryProvider()
        ) { entry in
            WalletAccessoryWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Wallet Quick Access")
        .description("Balance, quick actions, and location-aware suggestions")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
            .systemMedium
        ])
    }
}

// MARK: - Main Widget View
struct WalletAccessoryWidgetView: View {
    let entry: WalletAccessoryEntry
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        switch family {
        case .systemSmall:
            SystemSmallView(entry: entry)
        case .systemMedium:
            SystemMediumView(entry: entry)
        case .accessoryCircular:
            WatchCircularView(entry: entry)
        case .accessoryRectangular:
            WatchRectangularView(entry: entry)
        case .accessoryInline:
            WatchInlineView(entry: entry)
        default:
            SystemSmallView(entry: entry)
        }
    }
}

// MARK: - System Small (StandBy Mode compatible)
struct SystemSmallView: View {
    let entry: WalletAccessoryEntry
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        VStack(spacing: 10) {
            // Total balance
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "wallet.bifold.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Spacer()

                    if entry.unreadNotifications > 0 {
                        NotificationBadge(count: entry.unreadNotifications)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(entry.currency)
                        .font(.title3.bold())
                    Text("\(String(format: "%.2f", entry.totalBalance))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Label("\(entry.activeCards) cards", systemImage: "creditcard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if entry.pendingPayments > 0 {
                        Label("\(entry.pendingPayments) pending", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Quick actions row
            if #available(iOS 17.0, *) {
                HStack(spacing: 6) {
                    ForEach(entry.quickActions.prefix(3), id: \.id) { action in
                        Button(intent: QuickActionIntent(actionId: action.id, deepLink: action.deepLink)) {
                            VStack(spacing: 2) {
                                Image(systemName: action.icon)
                                    .font(.caption)
                                Text(action.title)
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(actionColor(action.color))
                        .buttonBorderShape(.roundedRectangle(radius: 8))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
        )
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

    private func actionColor(_ color: String) -> Color {
        switch color.lowercased() {
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "orange": return .orange
        default: return .gray
        }
    }
}

// MARK: - System Medium (Smart Stack + Location)
struct SystemMediumView: View {
    let entry: WalletAccessoryEntry
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        HStack(spacing: 12) {
            // Left: Balance
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "wallet.bifold.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Spacer()
                    NotificationBadge(count: entry.unreadNotifications)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(entry.currency)
                            .font(.title2.bold())
                        Text("\(String(format: "%.2f", entry.totalBalance))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                    }
                }

                HStack(spacing: 12) {
                    StatBadge(icon: "creditcard", value: "\(entry.activeCards)", label: "Cards")
                    StatBadge(icon: "clock", value: "\(entry.pendingPayments)", label: "Pending")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Right: Location context or Quick Actions
            VStack(spacing: 8) {
                if let location = entry.locationContext {
                    // Smart Stack location card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text("Nearby")
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                            Spacer()
                            Text(location.distance)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(location.nearbyStore)
                            .font(.subheadline.bold())

                        Text(location.storeCategory)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if location.offerAvailable {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 8))
                                Text("Offer available")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                        }

                        if #available(iOS 17.0, *) {
                            Button(intent: QuickPayIntent(storeName: location.nearbyStore)) {
                                Label("Pay Here", systemImage: "wave.3.right")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .buttonBorderShape(.roundedRectangle(radius: 8))
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.blue.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                } else {
                    // Quick actions fallback
                    VStack(spacing: 6) {
                        Text("Quick Actions")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        if #available(iOS 17.0, *) {
                            ForEach(entry.quickActions, id: \.id) { action in
                                Button(intent: QuickActionIntent(actionId: action.id, deepLink: action.deepLink)) {
                                    Label(action.title, systemImage: action.icon)
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.bordered)
                                .tint(actionColor(action.color))
                                .buttonBorderShape(.roundedRectangle(radius: 8))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
        )
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

    private func actionColor(_ color: String) -> Color {
        switch color.lowercased() {
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        default: return .gray
        }
    }
}

// MARK: - Apple Watch Circular Complication
struct WatchCircularView: View {
    let entry: WalletAccessoryEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Image(systemName: "wallet.bifold.fill")
                    .font(.body)
                    .foregroundStyle(.tint)

                Text("\(entry.currency)\(Int(entry.totalBalance))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if entry.pendingPayments > 0 {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}

// MARK: - Apple Watch Rectangular Complication
struct WatchRectangularView: View {
    let entry: WalletAccessoryEntry

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "wallet.bifold.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.currency)\(String(format: "%.2f", entry.totalBalance))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("\(entry.activeCards) cards")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if entry.pendingPayments > 0 {
                        Circle()
                            .fill(.orange)
                            .frame(width: 5, height: 5)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Apple Watch Inline Complication
struct WatchInlineView: View {
    let entry: WalletAccessoryEntry

    var body: some View {
        Text("\(Image(systemName: "wallet.bifold")) \(entry.currency)\(Int(entry.totalBalance))")
            .font(.caption.bold())
    }
}

// MARK: - Helper Views
struct NotificationBadge: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(.red)
                .frame(width: 18, height: 18)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - App Intents
@available(iOS 17.0, *)
struct QuickActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Action"
    static var description = IntentDescription("Perform a quick wallet action")

    @Parameter(title: "Action ID")
    var actionId: String

    @Parameter(title: "Deep Link")
    var deepLink: String

    init() {}

    init(actionId: String, deepLink: String) {
        self.actionId = actionId
        self.deepLink = deepLink
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            if let url = URL(string: deepLink) {
                // Open deep link
            }
        }
        return .result()
    }
}

@available(iOS 17.0, *)
struct QuickPayIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Pay"
    static var description = IntentDescription("Quick pay at nearby store")

    @Parameter(title: "Store Name")
    var storeName: String

    init() {}

    init(storeName: String) {
        self.storeName = storeName
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            if let url = URL(string: "wallet://pay?store=\(storeName)") {
                // Open payment for store
            }
        }
        return .result()
    }
}

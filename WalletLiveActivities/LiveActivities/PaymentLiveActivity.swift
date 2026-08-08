import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Payment Attributes
struct PaymentAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: PaymentStatus
        var progress: Double
        var amount: String
        var merchantName: String
        var timestamp: Date
    }

    var paymentId: String
    var cardLastFour: String
    var cardColor: String
}

enum PaymentStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case processing = "Processing"
    case verifying = "Verifying"
    case completed = "Completed"
    case failed = "Failed"

    var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "arrow.clockwise"
        case .verifying: return "checkmark.shield"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .processing: return .blue
        case .verifying: return .indigo
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Payment Live Activity
@available(iOS 16.1, *)
struct PaymentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PaymentAttributes.self) { context in
            // Lock Screen / Notification Banner
            PaymentLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded View
                DynamicIslandExpandedView(
                    context: context
                )
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
            .widgetURL(URL(string: "wallet://payment/\(context.attributes.paymentId)"))
            .keylineTint(context.state.status.color)
        }
    }
}

// MARK: - Lock Screen View
struct PaymentLockScreenView: View {
    let context: ActivityViewContext<PaymentAttributes>
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Card indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(cardColor)
                    .frame(width: 32, height: 20)

                Text("•••• \(context.attributes.cardLastFour)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Image(systemName: context.state.status.systemImage)
                        .font(.caption2)
                    Text(context.state.status.rawValue)
                        .font(.caption2.bold())
                }
                .foregroundStyle(context.state.status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(context.state.status.color.opacity(0.15))
                .clipShape(Capsule())
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.merchantName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.amount)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Circular progress
                ZStack {
                    Circle()
                        .stroke(lineWidth: 3)
                        .opacity(0.2)
                        .foregroundStyle(context.state.status.color)

                    Circle()
                        .trim(from: 0, to: context.state.progress)
                        .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .foregroundStyle(context.state.status.color)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: context.state.progress)

                    Image(systemName: context.state.status.systemImage)
                        .font(.caption2)
                        .foregroundStyle(context.state.status.color)
                }
                .frame(width: 40, height: 40)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(context.state.status.color)
                        .frame(width: geo.size.width * context.state.progress)
                        .animation(.linear(duration: 0.3), value: context.state.progress)
                }
            }
            .frame(height: 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
        )
    }

    private var cardColor: Color {
        switch context.attributes.cardColor.lowercased() {
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
            return Color.gray.opacity(0.15)
        default:
            return colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.8)
        }
    }
}

// MARK: - Dynamic Island Expanded View
struct DynamicIslandExpandedView: View {
    let context: ActivityViewContext<PaymentAttributes>
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "apple.logo")
                    .font(.title2)
                Text("Wallet")
                    .font(.headline)
                Spacer()
                Text(context.state.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Payment details
            HStack(spacing: 16) {
                // Card visual
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(cardGradient)
                        .frame(width: 80, height: 50)

                    Image(systemName: "applepay")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.merchantName)
                        .font(.title3.bold())
                    Text("Card ending in \(context.attributes.cardLastFour)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(context.state.amount)
                    .font(.title2.bold())
            }

            // Progress section
            VStack(spacing: 8) {
                HStack {
                    ForEach(PaymentStatus.allCases, id: \.self) { status in
                        HStack(spacing: 4) {
                            Image(systemName: status == context.state.status ? 
                                  status.systemImage : 
                                  (PaymentStatus.allCases.firstIndex(of: status)! < PaymentStatus.allCases.firstIndex(of: context.state.status)! ? "checkmark.circle.fill" : "circle"))
                            .font(.caption2)
                            .foregroundStyle(statusColor(for: status))

                            Text(status.rawValue)
                                .font(.caption2)
                                .foregroundStyle(statusColor(for: status))
                        }

                        if status != .failed {
                            Spacer()
                            if status != .completed {
                                Rectangle()
                                    .fill(statusLineColor(for: status))
                                    .frame(height: 2)
                                    .frame(maxWidth: 20)
                            }
                            Spacer()
                        }
                    }
                }

                // Animated progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * context.state.progress)
                            .animation(.easeInOut(duration: 0.5), value: context.state.progress)
                    }
                }
                .frame(height: 8)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: {}) {
                    Label("Details", systemImage: "doc.text")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                if context.state.status == .failed {
                    Button(action: {}) {
                        Label("Retry", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    private var cardGradient: LinearGradient {
        switch context.attributes.cardColor.lowercased() {
        case "blue": return LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "red": return LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "green": return LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "purple": return LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "gold": return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func statusColor(for status: PaymentStatus) -> Color {
        let currentIndex = PaymentStatus.allCases.firstIndex(of: context.state.status) ?? 0
        let statusIndex = PaymentStatus.allCases.firstIndex(of: status) ?? 0

        if status == context.state.status {
            return status.color
        } else if statusIndex < currentIndex {
            return .green
        } else {
            return .gray.opacity(0.5)
        }
    }

    private func statusLineColor(for status: PaymentStatus) -> Color {
        let currentIndex = PaymentStatus.allCases.firstIndex(of: context.state.status) ?? 0
        let statusIndex = PaymentStatus.allCases.firstIndex(of: status) ?? 0
        return statusIndex < currentIndex ? .green : .gray.opacity(0.3)
    }
}

// MARK: - Compact Views
struct CompactLeadingView: View {
    let context: ActivityViewContext<PaymentAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "apple.logo")
            Text(context.state.amount)
                .font(.caption2.bold())
        }
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<PaymentAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.state.status.systemImage)
                .foregroundStyle(context.state.status.color)
            Text("\(Int(context.state.progress * 100))%")
                .font(.caption2.bold())
                .foregroundStyle(context.state.status.color)
        }
    }
}

struct MinimalView: View {
    let context: ActivityViewContext<PaymentAttributes>

    var body: some View {
        Image(systemName: context.state.status == .completed ? "checkmark.circle.fill" : "clock")
            .foregroundStyle(context.state.status.color)
    }
}

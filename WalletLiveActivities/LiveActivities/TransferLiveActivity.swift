import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Transfer Attributes
struct TransferAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: TransferStatus
        var progress: Double
        var amount: String
        var recipientName: String
        var recipientAvatar: String
        var estimatedArrival: Date
        var currentStep: Int
        var totalSteps: Int
    }

    var transferId: String
    var fromCurrency: String
    var toCurrency: String
    var transferType: TransferType
}

enum TransferStatus: String, Codable {
    case initiating = "Initiating"
    case processing = "Processing"
    case converting = "Converting"
    case sending = "Sending"
    case delivered = "Delivered"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var systemImage: String {
        switch self {
        case .initiating: return "arrow.up.circle"
        case .processing: return "gearshape.2"
        case .converting: return "arrow.2.squarepath"
        case .sending: return "paperplane.fill"
        case .delivered: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "slash.circle"
        }
    }

    var color: Color {
        switch self {
        case .initiating: return .orange
        case .processing: return .blue
        case .converting: return .purple
        case .sending: return .cyan
        case .delivered: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

enum TransferType: String, Codable {
    case instant = "Instant"
    case standard = "Standard"
    case international = "International"

    var icon: String {
        switch self {
        case .instant: return "bolt.fill"
        case .standard: return "arrow.left.arrow.right"
        case .international: return "globe"
        }
    }
}

// MARK: - Transfer Live Activity
@available(iOS 16.1, *)
struct TransferLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransferAttributes.self) { context in
            TransferLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                TransferExpandedView(context: context)
            } compactLeading: {
                TransferCompactLeading(context: context)
            } compactTrailing: {
                TransferCompactTrailing(context: context)
            } minimal: {
                TransferMinimal(context: context)
            }
            .widgetURL(URL(string: "wallet://transfer/\(context.attributes.transferId)"))
            .keylineTint(context.state.status.color)
        }
    }
}

// MARK: - Lock Screen View
struct TransferLockScreenView: View {
    let context: ActivityViewContext<TransferAttributes>
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        VStack(spacing: 12) {
            // Header with transfer type
            HStack {
                Label(context.attributes.transferType.rawValue, systemImage: context.attributes.transferType.icon)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

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

            // Recipient info
            HStack(spacing: 12) {
                // Avatar placeholder
                ZStack {
                    Circle()
                        .fill(context.state.status.color.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Text(String(context.state.recipientName.prefix(1)))
                        .font(.title3.bold())
                        .foregroundStyle(context.state.status.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.recipientName)
                        .font(.headline)
                    Text(context.state.amount)
                        .font(.title3.bold())

                    if context.attributes.fromCurrency != context.attributes.toCurrency {
                        Text("\(context.attributes.fromCurrency) → \(context.attributes.toCurrency)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Step indicator
                VStack(spacing: 4) {
                    Text("\(context.state.currentStep)/\(context.state.totalSteps)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    // Mini step dots
                    HStack(spacing: 3) {
                        ForEach(0..<context.state.totalSteps, id: \.self) { index in
                            Circle()
                                .fill(index < context.state.currentStep ? context.state.status.color : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }

            // Progress
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [context.state.status.color, context.state.status.color.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * context.state.progress)
                            .animation(.easeInOut(duration: 0.4), value: context.state.progress)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(Int(context.state.progress * 100))% complete")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if context.state.status != .delivered && context.state.status != .failed {
                        Text("ETA: \(context.state.estimatedArrival, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
        )
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

// MARK: - Expanded Dynamic Island View
struct TransferExpandedView: View {
    let context: ActivityViewContext<TransferAttributes>
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "apple.logo")
                    .font(.title2)
                Text("Transfer")
                    .font(.headline)
                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: context.attributes.transferType.icon)
                    Text(context.attributes.transferType.rawValue)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.15))
                .clipShape(Capsule())
            }

            Divider()

            // Transfer flow visualization
            HStack(spacing: 0) {
                // From
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "person.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                    Text("You")
                        .font(.caption.bold())
                    Text(context.attributes.fromCurrency)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                // Arrow with animation
                VStack(spacing: 4) {
                    ZStack {
                        // Dashed line
                        HStack(spacing: 3) {
                            ForEach(0..<8, id: \.self) { i in
                                Circle()
                                    .fill(i < Int(context.state.progress * 8) ? context.state.status.color : Color.gray.opacity(0.3))
                                    .frame(width: 4, height: 4)
                            }
                        }

                        // Animated plane
                        Image(systemName: "paperplane.fill")
                            .font(.caption)
                            .foregroundStyle(context.state.status.color)
                            .offset(x: CGFloat(context.state.progress * 60 - 30))
                            .animation(.easeInOut(duration: 0.5), value: context.state.progress)
                    }

                    Text(context.state.amount)
                        .font(.caption.bold())
                        .foregroundStyle(context.state.status.color)
                }
                .frame(maxWidth: .infinity)

                // To
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(context.state.status.color.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text(String(context.state.recipientName.prefix(1)))
                            .font(.title3.bold())
                            .foregroundStyle(context.state.status.color)
                    }
                    Text(context.state.recipientName)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text(context.attributes.toCurrency)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Step progress
            VStack(spacing: 8) {
                HStack {
                    ForEach(0..<context.state.totalSteps, id: \.self) { step in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(step < context.state.currentStep ? context.state.status.color : Color.gray.opacity(0.2))
                                    .frame(width: 28, height: 28)

                                if step < context.state.currentStep {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                } else if step == context.state.currentStep - 1 {
                                    Image(systemName: context.state.status.systemImage)
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                } else {
                                    Text("\(step + 1)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.gray)
                                }
                            }

                            Text(stepName(for: step))
                                .font(.caption2)
                                .foregroundStyle(step < context.state.currentStep ? .primary : .secondary)
                                .lineLimit(1)
                        }

                        if step < context.state.totalSteps - 1 {
                            Rectangle()
                                .fill(step < context.state.currentStep - 1 ? context.state.status.color : Color.gray.opacity(0.2))
                                .frame(height: 2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            // Status and ETA
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.status.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(context.state.status.color)

                    if context.state.status != .delivered {
                        Text("Estimated arrival: \(context.state.estimatedArrival, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Delivered successfully")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                // Circular progress
                ZStack {
                    Circle()
                        .stroke(lineWidth: 4)
                        .opacity(0.2)
                        .foregroundStyle(context.state.status.color)

                    Circle()
                        .trim(from: 0, to: context.state.progress)
                        .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [context.state.status.color, context.state.status.color.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: context.state.progress)

                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption2.bold())
                        .foregroundStyle(context.state.status.color)
                }
                .frame(width: 50, height: 50)
            }

            // Cancel button for active transfers
            if context.state.status != .delivered && context.state.status != .failed && context.state.status != .cancelled {
                Button(action: {}) {
                    Label("Cancel Transfer", systemImage: "xmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    private func stepName(for step: Int) -> String {
        let names = ["Init", "Process", "Convert", "Send", "Deliver"]
        return names[min(step, names.count - 1)]
    }
}

// MARK: - Compact Views
struct TransferCompactLeading: View {
    let context: ActivityViewContext<TransferAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.attributes.transferType.icon)
                .font(.caption2)
            Text(context.state.amount)
                .font(.caption2.bold())
        }
    }
}

struct TransferCompactTrailing: View {
    let context: ActivityViewContext<TransferAttributes>

    var body: some View {
        HStack(spacing: 4) {
            if context.state.status == .delivered {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("\(context.state.currentStep)/\(context.state.totalSteps)")
                    .font(.caption2.bold())
                    .foregroundStyle(context.state.status.color)
            }
        }
    }
}

struct TransferMinimal: View {
    let context: ActivityViewContext<TransferAttributes>

    var body: some View {
        Image(systemName: context.state.status == .delivered ? "checkmark.circle.fill" : "paperplane.fill")
            .foregroundStyle(context.state.status.color)
    }
}

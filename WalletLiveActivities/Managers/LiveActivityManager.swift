import ActivityKit
import Foundation
import Combine
import CoreLocation

// MARK: - Live Activity Manager
@available(iOS 16.1, *)
@MainActor
final class LiveActivityManager: ObservableObject {

    // MARK: - Singleton
    static let shared = LiveActivityManager()

    // MARK: - Published State
    @Published var activePaymentActivities: [String: Activity<PaymentAttributes>] = [:]
    @Published var activeTransferActivities: [String: Activity<TransferAttributes>] = [:]
    @Published var isLocationTrackingEnabled: Bool = false

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let locationManager = CLLocationManager()
    private var locationDelegate: LocationDelegate?

    // MARK: - Smart Stack Configuration
    struct SmartStackConfig {
        var enableGeofencing: Bool = true
        var enableTimeBasedSuggestions: Bool = true
        var enableUsagePatterns: Bool = true
        var nearbyStoreRadius: CLLocationDistance = 200 // meters
        var priorityMerchants: [String] = ["Starbucks", "Whole Foods", "Target", "Amazon"]
    }

    @Published var smartStackConfig = SmartStackConfig()

    // MARK: - Initialization
    private init() {
        setupLocationTracking()
        observeActivityStateChanges()
    }

    // MARK: - Payment Live Activities

    /// Start a new payment live activity
    func startPaymentActivity(
        paymentId: String,
        cardLastFour: String,
        cardColor: String,
        amount: String,
        merchantName: String
    ) throws -> Activity<PaymentAttributes> {

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.notAuthorized
        }

        let attributes = PaymentAttributes(
            paymentId: paymentId,
            cardLastFour: cardLastFour,
            cardColor: cardColor
        )

        let initialState = PaymentAttributes.ContentState(
            status: .pending,
            progress: 0.0,
            amount: amount,
            merchantName: merchantName,
            timestamp: Date()
        )

        let activity = try Activity.request(
            attributes: attributes,
            contentState: initialState,
            pushType: nil
        )

        activePaymentActivities[paymentId] = activity

        // Observe activity state
        Task {
            for await state in activity.activityStateUpdates {
                handlePaymentStateChange(paymentId: paymentId, state: state)
            }
        }

        return activity
    }

    /// Update payment progress
    func updatePaymentProgress(
        paymentId: String,
        status: PaymentStatus,
        progress: Double
    ) async {
        guard let activity = activePaymentActivities[paymentId] else { return }

        let updatedState = PaymentAttributes.ContentState(
            status: status,
            progress: progress,
            amount: activity.content.state.amount,
            merchantName: activity.content.state.merchantName,
            timestamp: Date()
        )

        await activity.update(using: updatedState)

        // Auto-end on completion or failure
        if status == .completed || status == .failed {
            // Keep for a few seconds then end
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await endPaymentActivity(paymentId: paymentId)
        }
    }

    /// End payment activity
    func endPaymentActivity(paymentId: String) async {
        guard let activity = activePaymentActivities[paymentId] else { return }

        await activity.end(dismissalPolicy: .default)
        activePaymentActivities.removeValue(forKey: paymentId)
    }

    /// End all payment activities
    func endAllPaymentActivities() async {
        for (paymentId, activity) in activePaymentActivities {
            await activity.end(dismissalPolicy: .immediate)
            activePaymentActivities.removeValue(forKey: paymentId)
        }
    }

    // MARK: - Transfer Live Activities

    /// Start a new transfer live activity
    func startTransferActivity(
        transferId: String,
        fromCurrency: String,
        toCurrency: String,
        transferType: TransferType,
        amount: String,
        recipientName: String,
        recipientAvatar: String,
        totalSteps: Int
    ) throws -> Activity<TransferAttributes> {

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.notAuthorized
        }

        let attributes = TransferAttributes(
            transferId: transferId,
            fromCurrency: fromCurrency,
            toCurrency: toCurrency,
            transferType: transferType
        )

        let initialState = TransferAttributes.ContentState(
            status: .initiating,
            progress: 0.0,
            amount: amount,
            recipientName: recipientName,
            recipientAvatar: recipientAvatar,
            estimatedArrival: Date().addingTimeInterval(300),
            currentStep: 1,
            totalSteps: totalSteps
        )

        let activity = try Activity.request(
            attributes: attributes,
            contentState: initialState,
            pushType: nil
        )

        activeTransferActivities[transferId] = activity

        // Start progress simulation for demo
        simulateTransferProgress(transferId: transferId)

        return activity
    }

    /// Update transfer state
    func updateTransferState(
        transferId: String,
        status: TransferStatus,
        progress: Double,
        currentStep: Int
    ) async {
        guard let activity = activeTransferActivities[transferId] else { return }

        let updatedState = TransferAttributes.ContentState(
            status: status,
            progress: progress,
            amount: activity.content.state.amount,
            recipientName: activity.content.state.recipientName,
            recipientAvatar: activity.content.state.recipientAvatar,
            estimatedArrival: activity.content.state.estimatedArrival,
            currentStep: currentStep,
            totalSteps: activity.content.state.totalSteps
        )

        await activity.update(using: updatedState)

        if status == .delivered || status == .failed || status == .cancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await endTransferActivity(transferId: transferId)
        }
    }

    /// End transfer activity
    func endTransferActivity(transferId: String) async {
        guard let activity = activeTransferActivities[transferId] else { return }

        await activity.end(dismissalPolicy: .default)
        activeTransferActivities.removeValue(forKey: transferId)
    }

    /// Cancel transfer
    func cancelTransfer(transferId: String) async {
        await updateTransferState(
            transferId: transferId,
            status: .cancelled,
            progress: 0.0,
            currentStep: 0
        )
    }

    // MARK: - Smart Stack & Location Integration

    /// Enable location-based Smart Stack suggestions
    func enableSmartStackLocationTracking() {
        isLocationTrackingEnabled = true
        locationManager.startUpdatingLocation()

        // Setup geofencing for priority merchants
        setupGeofencing()
    }

    /// Disable location tracking
    func disableSmartStackLocationTracking() {
        isLocationTrackingEnabled = false
        locationManager.stopUpdatingLocation()

        // Remove all geofences
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }

    /// Check if widget should appear in Smart Stack based on location
    func shouldShowWidgetInSmartStack(for storeName: String) -> Bool {
        guard smartStackConfig.enableGeofencing else { return false }
        return smartStackConfig.priorityMerchants.contains(where: { 
            storeName.lowercased().contains($0.lowercased()) 
        })
    }

    /// Request Smart Stack appearance for payment
    func requestSmartStackAppearance(paymentId: String, storeName: String) {
        guard shouldShowWidgetInSmartStack(for: storeName) else { return }

        // Update activity with relevance score for Smart Stack
        Task {
            guard let activity = activePaymentActivities[paymentId] else { return }

            // Higher relevance = higher position in Smart Stack
            let relevance = ActivityAttributes.RelevanceScore(floatLiteral: 1.0)

            // This would be used by the system to prioritize in Smart Stack
            // Note: Actual Smart Stack API is internal, this is conceptual
        }
    }

    // MARK: - Private Methods

    private func setupLocationTracking() {
        locationDelegate = LocationDelegate(manager: self)
        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
    }

    private func setupGeofencing() {
        // Setup geofences for common merchants
        let merchantLocations = [
            ("Starbucks", CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), 100.0),
            ("Whole Foods", CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094), 150.0)
        ]

        for (name, coordinate, radius) in merchantLocations {
            let region = CLCircularRegion(
                center: coordinate,
                radius: radius,
                identifier: "merchant_\(name)"
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            locationManager.startMonitoring(for: region)
        }
    }

    private func simulateTransferProgress(transferId: String) {
        Task {
            let steps: [(TransferStatus, Double, Int)] = [
                (.initiating, 0.1, 1),
                (.processing, 0.3, 2),
                (.converting, 0.5, 3),
                (.sending, 0.75, 4),
                (.delivered, 1.0, 5)
            ]

            for (status, progress, step) in steps {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await updateTransferState(
                    transferId: transferId,
                    status: status,
                    progress: progress,
                    currentStep: step
                )
            }
        }
    }

    private func observeActivityStateChanges() {
        // Monitor for system-driven activity state changes
        Task {
            for await activity in Activity<PaymentAttributes>.activityUpdates {
                activePaymentActivities[activity.attributes.paymentId] = activity
            }
        }

        Task {
            for await activity in Activity<TransferAttributes>.activityUpdates {
                activeTransferActivities[activity.attributes.transferId] = activity
            }
        }
    }

    private func handlePaymentStateChange(paymentId: String, state: ActivityState) {
        switch state {
        case .dismissed, .ended:
            activePaymentActivities.removeValue(forKey: paymentId)
        default:
            break
        }
    }

    // MARK: - Batch Operations

    /// End all active activities
    func endAllActivities() async {
        await endAllPaymentActivities()

        for (transferId, activity) in activeTransferActivities {
            await activity.end(dismissalPolicy: .immediate)
            activeTransferActivities.removeValue(forKey: transferId)
        }
    }

    /// Get summary of all active activities
    func getActiveActivitiesSummary() -> (payments: Int, transfers: Int) {
        (activePaymentActivities.count, activeTransferActivities.count)
    }
}

// MARK: - Location Delegate
@available(iOS 16.1, *)
class LocationDelegate: NSObject, CLLocationManagerDelegate {
    weak var manager: LiveActivityManager?

    init(manager: LiveActivityManager) {
        self.manager = manager
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let manager = self.manager else { return }

        let storeName = region.identifier.replacingOccurrences(of: "merchant_", with: "")

        // Post notification for Smart Stack update
        NotificationCenter.default.post(
            name: .init("SmartStackLocationEntered"),
            object: nil,
            userInfo: ["storeName": storeName]
        )

        // Trigger widget timeline reload
        WidgetCenter.shared.reloadTimelines(ofKind: "WalletAccessoryWidget")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Check nearby merchants and update widget relevance
        WidgetCenter.shared.reloadTimelines(ofKind: "WalletAccessoryWidget")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
}

// MARK: - Errors
enum LiveActivityError: Error, LocalizedError {
    case notAuthorized
    case activityNotFound
    case invalidState
    case locationNotAvailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Live Activities are not authorized for this app"
        case .activityNotFound:
            return "The requested live activity was not found"
        case .invalidState:
            return "The activity is in an invalid state"
        case .locationNotAvailable:
            return "Location services are not available"
        }
    }
}

// MARK: - Widget Center Shim (for compilation)
struct WidgetCenter {
    static let shared = WidgetCenter()
    func reloadTimelines(ofKind kind: String) {}
    func reloadAllTimelines() {}
}

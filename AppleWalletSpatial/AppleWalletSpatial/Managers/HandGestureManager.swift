//
//  HandGestureManager.swift
//  AppleWalletSpatial
//
//  HandGestureManager — жесты pinch-to-pay, grab-to-move-card
//  Supports Vision Pro hand tracking and iOS fallback
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

// MARK: - Gesture Types
enum HandGestureType {
    case pinchToPay      // Pinch fingers to confirm payment
    case grabToMove      // Grab gesture to move cards
    case swipeToDismiss  // Swipe gesture to dismiss
    case tapToSelect     // Tap gesture to select
    case rotateToFlip    // Rotation gesture to flip card
}

// MARK: - Gesture State
struct GestureState {
    var isPinching: Bool = false
    var isGrabbing: Bool = false
    var pinchStrength: Float = 0.0
    var handPosition: SIMD3<Float> = .zero
    var handRotation: simd_quatf = .init(angle: 0, axis: SIMD3(0, 1, 0))
    var lastGesture: HandGestureType?
    var gestureStartTime: Date?
}

// MARK: - Hand Gesture Manager
@available(iOS 26.0, visionOS 2.0, *)
@MainActor
class HandGestureManager: ObservableObject {

    // MARK: - Published Properties
    @Published var gestureState = GestureState()
    @Published var isTrackingHands: Bool = false
    @Published var detectedGesture: HandGestureType?
    @Published var activeHand: HandAnchor.Chirality?

    // MARK: - AR Session
    private var arSession: ARKitSession?
    private var handTrackingProvider: HandTrackingProvider?
    private var sceneReconstruction: SceneReconstructionProvider?

    // MARK: - Gesture Thresholds
    private let pinchThreshold: Float = 0.7
    private let grabThreshold: Float = 0.8
    private let swipeVelocityThreshold: Float = 0.5
    private let gestureHoldDuration: TimeInterval = 0.3

    // MARK: - Haptic Feedback
    private var hapticEngine: CHHapticEngine?

    // MARK: - Initialization
    init() {
        setupHaptics()
    }

    // MARK: - Session Management
    func startTracking() async {
        guard ARKitSession.isSupported else {
            print("ARKitSession not supported on this device")
            return
        }

        arSession = ARKitSession()
        handTrackingProvider = HandTrackingProvider()
        sceneReconstruction = SceneReconstructionProvider()

        guard let handTracking = handTrackingProvider else { return }

        do {
            try await arSession?.run([
                handTracking,
                sceneReconstruction!
            ])
            isTrackingHands = true
            await processHandUpdates()
        } catch {
            print("Failed to start hand tracking: \(error)")
            isTrackingHands = false
        }
    }

    func stopTracking() {
        arSession?.stop()
        isTrackingHands = false
        handTrackingProvider = nil
        sceneReconstruction = nil
    }

    // MARK: - Hand Update Processing
    private func processHandUpdates() async {
        guard let handTracking = handTrackingProvider else { return }

        for await update in handTracking.anchorUpdates {
            let handAnchor = update.anchor

            guard handAnchor.isTracked else { continue }

            await MainActor.run {
                activeHand = handAnchor.chirality
                analyzeHandGesture(handAnchor)
            }
        }
    }

    // MARK: - Gesture Analysis
    private func analyzeHandGesture(_ handAnchor: HandAnchor) {
        guard let handSkeleton = handAnchor.handSkeleton else { return }

        // Get joint transforms
        let thumbTip = handSkeleton.joint(.thumbTip)
        let indexTip = handSkeleton.joint(.indexFingerTip)
        let middleTip = handSkeleton.joint(.middleFingerTip)
        let ringTip = handSkeleton.joint(.ringFingerTip)
        let littleTip = handSkeleton.joint(.littleFingerTip)
        let wrist = handSkeleton.joint(.wrist)

        // Calculate pinch distance (thumb to index)
        let pinchDistance = distance(
            thumbTip.anchorFromJointTransform.columns.3.xyz,
            indexTip.anchorFromJointTransform.columns.3.xyz
        )

        // Calculate grab factor (how curled fingers are)
        let grabFactor = calculateGrabFactor(handSkeleton)

        // Update gesture state
        updateGestureState(
            pinchDistance: pinchDistance,
            grabFactor: grabFactor,
            handPosition: wrist.anchorFromJointTransform.columns.3.xyz,
            handRotation: extractRotation(from: wrist.anchorFromJointTransform)
        )
    }

    private func calculateGrabFactor(_ skeleton: HandSkeleton) -> Float {
        // Calculate how curled the fingers are
        let tips = [
            skeleton.joint(.indexFingerTip),
            skeleton.joint(.middleFingerTip),
            skeleton.joint(.ringFingerTip),
            skeleton.joint(.littleFingerTip)
        ]

        let bases = [
            skeleton.joint(.indexFingerMetacarpal),
            skeleton.joint(.middleFingerMetacarpal),
            skeleton.joint(.ringFingerMetacarpal),
            skeleton.joint(.littleFingerMetacarpal)
        ]

        var totalCurl: Float = 0
        for (tip, base) in zip(tips, bases) {
            let tipPos = tip.anchorFromJointTransform.columns.3.xyz
            let basePos = base.anchorFromJointTransform.columns.3.xyz
            let curl = length(tipPos - basePos)
            totalCurl += curl
        }

        // Normalize (smaller distance = more curled = stronger grab)
        return 1.0 - (totalCurl / 0.3)
    }

    private func updateGestureState(
        pinchDistance: Float,
        grabFactor: Float,
        handPosition: SIMD3<Float>,
        handRotation: simd_quatf
    ) {
        let previousPinch = gestureState.isPinching
        let previousGrab = gestureState.isGrabbing

        // Pinch detection
        let isPinching = pinchDistance < 0.02 // 2cm threshold
        gestureState.isPinching = isPinching
        gestureState.pinchStrength = 1.0 - (pinchDistance / 0.05)

        // Grab detection
        let isGrabbing = grabFactor > grabThreshold
        gestureState.isGrabbing = isGrabbing

        gestureState.handPosition = handPosition
        gestureState.handRotation = handRotation

        // Detect gesture changes
        if isPinching && !previousPinch {
            // Pinch started
            gestureState.gestureStartTime = Date()
        } else if !isPinching && previousPinch {
            // Pinch released - check if it was a tap or hold
            if let startTime = gestureState.gestureStartTime,
               Date().timeIntervalSince(startTime) < gestureHoldDuration {
                detectedGesture = .pinchToPay
                triggerHaptic(for: .pinchToPay)
            }
        }

        if isGrabbing && !previousGrab {
            detectedGesture = .grabToMove
            triggerHaptic(for: .grabToMove)
        }

        // Reset detected gesture after processing
        if detectedGesture != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.detectedGesture = nil
            }
        }
    }

    // MARK: - Spatial Tap Gesture
    var spatialTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                self.handleSpatialTap(value)
            }
    }

    private func handleSpatialTap(_ value: EntityTargetValue<SpatialTapGesture.Value>) {
        detectedGesture = .tapToSelect
        triggerHaptic(for: .tapToSelect)

        // Provide visual feedback
        if let entity = value.entity as? ModelEntity {
            var material = entity.model?.materials.first as? PhysicallyBasedMaterial
            material?.emissiveIntensity = 3.0

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                material?.emissiveIntensity = 1.0
            }
        }
    }

    // MARK: - Drag Gesture for Card Movement
    var cardDragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                self.handleCardDrag(value)
            }
            .onEnded { value in
                self.handleCardDragEnd(value)
            }
    }

    private func handleCardDrag(_ value: EntityTargetValue<DragGesture.Value>) {
        guard gestureState.isGrabbing else { return }

        let entity = value.entity
        let translation = value.translation3D

        // Move entity based on hand position
        entity.position.x += Float(translation.x) * 0.001
        entity.position.y += Float(translation.y) * 0.001
        entity.position.z += Float(translation.z) * 0.001

        // Add slight rotation based on movement
        entity.orientation *= simd_quatf(
            angle: Float(translation.x) * 0.001,
            axis: SIMD3(0, 1, 0)
        )
    }

    private func handleCardDragEnd(_ value: EntityTargetValue<DragGesture.Value>) {
        triggerHaptic(for: .grabToMove)

        // Snap to nearest position or return to original
        let entity = value.entity

        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            // Could implement snap logic here
        }
    }

    // MARK: - Rotation Gesture
    var rotationGesture: some Gesture {
        RotateGesture3D()
            .targetedToAnyEntity()
            .onChanged { value in
                self.handleRotation(value)
            }
    }

    private func handleRotation(_ value: EntityTargetValue<RotateGesture3D.Value>) {
        let entity = value.entity
        let rotation = value.rotation

        entity.orientation = simd_quatf(rotation)

        if abs(rotation.angle.degrees) > 90 {
            detectedGesture = .rotateToFlip
        }
    }

    // MARK: - Haptic Feedback
    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Haptic engine error: \(error)")
        }
    }

    private func triggerHaptic(for gesture: HandGestureType) {
        guard let engine = hapticEngine else { return }

        let intensity: CHHapticEventParameter = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: gesture == .pinchToPay ? 1.0 : 0.7
        )
        let sharpness: CHHapticEventParameter = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: gesture == .pinchToPay ? 0.8 : 0.5
        )

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensity, sharpness],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Haptic playback error: \(error)")
        }
    }

    // MARK: - Utility Functions
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return length(a - b)
    }

    private func length(_ vector: SIMD3<Float>) -> Float {
        return sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    }

    private func extractRotation(from transform: simd_float4x4) -> simd_quatf {
        return simd_quatf(transform)
    }
}

// MARK: - SIMD Extensions
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        return SIMD3(x, y, z)
    }
}

// MARK: - Preview Helper
@available(iOS 26.0, visionOS 2.0, *)
struct HandGestureDebugView: View {
    @StateObject private var gestureManager = HandGestureManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("Hand Gesture Debug")
                .font(.title)

            HStack {
                StatusIndicator(
                    label: "Pinching",
                    isActive: gestureManager.gestureState.isPinching
                )
                StatusIndicator(
                    label: "Grabbing",
                    isActive: gestureManager.gestureState.isGrabbing
                )
            }

            Text("Pinch Strength: \(String(format: "%.2f", gestureManager.gestureState.pinchStrength))")

            if let gesture = gestureManager.detectedGesture {
                Text("Detected: \(String(describing: gesture))")
                    .foregroundStyle(.green)
            }

            Button(gestureManager.isTrackingHands ? "Stop Tracking" : "Start Tracking") {
                Task {
                    if gestureManager.isTrackingHands {
                        gestureManager.stopTracking()
                    } else {
                        await gestureManager.startTracking()
                    }
                }
            }
        }
        .padding()
    }
}

struct StatusIndicator: View {
    let label: String
    let isActive: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            Text(label)
        }
    }
}

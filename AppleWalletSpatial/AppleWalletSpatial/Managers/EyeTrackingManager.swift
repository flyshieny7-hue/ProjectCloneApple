//
//  EyeTrackingManager.swift
//  AppleWalletSpatial
//
//  EyeTrackingFocus — фокусировка взглядом на карте увеличивает её
//  Supports Vision Pro eye tracking and iOS fallback
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

// MARK: - Focus State
struct EyeFocusState {
    var isTracking: Bool = false
    var gazePoint: CGPoint = .zero
    var gazeDirection: SIMD3<Float> = .zero
    var focusedEntity: Entity?
    var focusDuration: TimeInterval = 0
    var focusStartTime: Date?
    var lastBlinkTime: Date?
    var blinkCount: Int = 0
}

// MARK: - Eye Tracking Manager
@available(iOS 26.0, visionOS 2.0, *)
@MainActor
class EyeTrackingManager: ObservableObject {

    // MARK: - Published Properties
    @Published var focusState = EyeFocusState()
    @Published var isTrackingEyes: Bool = false
    @Published var focusedEntity: Entity?
    @Published var focusIntensity: Float = 0.0

    // MARK: - AR Session
    private var arSession: ARKitSession?
    private var worldTrackingProvider: WorldTrackingProvider?

    // MARK: - Focus Configuration
    private let focusThreshold: TimeInterval = 0.5    // Time before focus activates
    private let dwellThreshold: TimeInterval = 1.5    // Time for dwell click
    private let maxFocusDistance: Float = 2.0         // Maximum focus distance in meters
    private let focusScaleMultiplier: Float = 1.3     // Scale when focused

    // MARK: - Callbacks
    var onFocusChanged: ((Entity?) -> Void)?
    var onDwellSelect: ((Entity) -> Void)?
    var onBlink: (() -> Void)?

    // MARK: - Tracking
    private var gazeRaycastTask: Task<Void, Never>?
    private var trackedEntities: [Entity] = []

    // MARK: - Initialization
    init() {
        // Setup notification observers for app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        gazeRaycastTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Session Management
    func startTracking() async {
        guard ARKitSession.isSupported else {
            print("ARKitSession not supported")
            return
        }

        arSession = ARKitSession()
        worldTrackingProvider = WorldTrackingProvider()

        guard let worldTracking = worldTrackingProvider else { return }

        do {
            try await arSession?.run([worldTracking])
            isTrackingEyes = true
            await processEyeTrackingUpdates()
        } catch {
            print("Failed to start eye tracking: \(error)")
            isTrackingEyes = false
        }
    }

    func stopTracking() {
        gazeRaycastTask?.cancel()
        arSession?.stop()
        isTrackingEyes = false
        worldTrackingProvider = nil
    }

    // MARK: - Entity Registration
    func registerEntity(_ entity: Entity) {
        if !trackedEntities.contains(where: { $0 === entity }) {
            trackedEntities.append(entity)
        }
    }

    func unregisterEntity(_ entity: Entity) {
        trackedEntities.removeAll(where: { $0 === entity })
    }

    func clearTrackedEntities() {
        trackedEntities.removeAll()
    }

    // MARK: - Eye Tracking Updates
    private func processEyeTrackingUpdates() async {
        guard let worldTracking = worldTrackingProvider else { return }

        for await update in worldTracking.anchorUpdates {
            let anchor = update.anchor

            guard anchor.isTracked else { continue }

            await MainActor.run {
                updateFocusState(from: anchor)
            }
        }
    }

    private func updateFocusState(from anchor: WorldAnchor) {
        // Extract gaze direction from head pose (approximation)
        // In visionOS 2, we can get more precise eye tracking data
        let transform = anchor.originFromAnchorTransform

        // Forward direction from head transform
        let forward = SIMD3<Float>(
            -transform.columns.2.x,
            -transform.columns.2.y,
            -transform.columns.2.z
        )

        let origin = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )

        focusState.gazeDirection = forward

        // Perform raycast to find focused entity
        performGazeRaycast(origin: origin, direction: forward)
    }

    // MARK: - Gaze Raycast
    private func performGazeRaycast(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        var closestEntity: Entity?
        var closestDistance: Float = maxFocusDistance

        for entity in trackedEntities {
            guard let collision = entity.components[CollisionComponent.self] else { continue }

            // Simple sphere intersection test
            let toEntity = entity.position - origin
            let projection = dot(toEntity, direction)

            guard projection > 0 && projection < maxFocusDistance else { continue }

            let closestPoint = origin + direction * projection
            let distanceToRay = length(closestPoint - entity.position)

            // Check if gaze is within entity bounds (simplified)
            let boundsRadius: Float = 0.1 // Approximate card size

            if distanceToRay < boundsRadius && projection < closestDistance {
                closestEntity = entity
                closestDistance = projection
            }
        }

        updateFocusedEntity(closestEntity)
    }

    private func updateFocusedEntity(_ newEntity: Entity?) {
        let previousEntity = focusState.focusedEntity

        if newEntity !== previousEntity {
            // Focus changed
            if let prev = previousEntity {
                unfocusEntity(prev)
            }

            focusState.focusedEntity = newEntity
            focusState.focusStartTime = newEntity != nil ? Date() : nil
            focusState.focusDuration = 0

            if let newEntity = newEntity {
                focusEntity(newEntity)
            }

            focusedEntity = newEntity
            onFocusChanged?(newEntity)
        } else if let entity = newEntity {
            // Continuing focus on same entity
            if let startTime = focusState.focusStartTime {
                focusState.focusDuration = Date().timeIntervalSince(startTime)

                // Update focus intensity based on duration
                let progress = min(Float(focusState.focusDuration / focusThreshold), 1.0)
                focusIntensity = progress

                // Apply progressive scale
                updateEntityScale(entity, progress: progress)

                // Check for dwell selection
                if focusState.focusDuration >= dwellThreshold {
                    onDwellSelect?(entity)
                    focusState.focusStartTime = Date() // Reset to prevent repeated triggers
                }
            }
        }
    }

    // MARK: - Entity Focus Effects
    private func focusEntity(_ entity: Entity) {
        withAnimation(.easeInOut(duration: 0.3)) {
            // Increase emissive glow
            if var model = entity.components[ModelComponent.self] {
                var materials = model.materials
                for (index, material) in materials.enumerated() {
                    if var pbr = material as? PhysicallyBasedMaterial {
                        pbr.emissiveIntensity = min(pbr.emissiveIntensity * 2.0, 3.0)
                        materials[index] = pbr
                    }
                }
                model.materials = materials
                entity.components.set(model)
            }

            // Add hover effect component
            entity.components.set(HoverEffectComponent())
        }

        // Haptic feedback for focus start
        triggerFocusHaptic(intensity: 0.3)
    }

    private func unfocusEntity(_ entity: Entity) {
        withAnimation(.easeInOut(duration: 0.3)) {
            // Reset emissive glow
            if var model = entity.components[ModelComponent.self] {
                var materials = model.materials
                for (index, material) in materials.enumerated() {
                    if var pbr = material as? PhysicallyBasedMaterial {
                        pbr.emissiveIntensity = max(pbr.emissiveIntensity / 2.0, 0.5)
                        materials[index] = pbr
                    }
                }
                model.materials = materials
                entity.components.set(model)
            }

            // Reset scale
            entity.scale = SIMD3(repeating: 1.0)

            // Remove hover effect
            entity.components.remove(HoverEffectComponent.self)
        }

        focusIntensity = 0.0
    }

    private func updateEntityScale(_ entity: Entity, progress: Float) {
        let scale = 1.0 + (focusScaleMultiplier - 1.0) * progress
        entity.scale = SIMD3(repeating: scale)
    }

    // MARK: - Blink Detection
    func detectBlink() {
        let now = Date()
        focusState.lastBlinkTime = now
        focusState.blinkCount += 1

        onBlink?()

        // Reset blink count after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.focusState.blinkCount = max(0, self.focusState.blinkCount - 1)
        }
    }

    // MARK: - SwiftUI Integration
    func focusableModifier(for entity: Entity) -> some View {
        EmptyView()
            .onAppear {
                self.registerEntity(entity)
            }
            .onDisappear {
                self.unregisterEntity(entity)
            }
    }

    // MARK: - Haptic Feedback
    private func triggerFocusHaptic(intensity: Float) {
        // Use Core Haptics for focus feedback
        // Implementation similar to HandGestureManager
    }

    // MARK: - Utility Functions
    private func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return a.x * b.x + a.y * b.y + a.z * b.z
    }

    private func length(_ vector: SIMD3<Float>) -> Float {
        return sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    }

    @objc private func handleAppDidBecomeActive() {
        // Resume tracking if needed
    }
}

// MARK: - Eye Tracking View Modifier
@available(iOS 26.0, visionOS 2.0, *)
struct EyeTrackingFocusModifier: ViewModifier {
    @StateObject private var eyeTracking = EyeTrackingManager()
    let entity: Entity
    let onFocus: (() -> Void)?
    let onUnfocus: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onAppear {
                eyeTracking.registerEntity(entity)
                eyeTracking.onFocusChanged = { focusedEntity in
                    if focusedEntity === entity {
                        onFocus?()
                    } else {
                        onUnfocus?()
                    }
                }
            }
            .onDisappear {
                eyeTracking.unregisterEntity(entity)
            }
    }
}

@available(iOS 26.0, visionOS 2.0, *)
extension View {
    func eyeTrackingFocus(
        entity: Entity,
        onFocus: (() -> Void)? = nil,
        onUnfocus: (() -> Void)? = nil
    ) -> some View {
        modifier(EyeTrackingFocusModifier(
            entity: entity,
            onFocus: onFocus,
            onUnfocus: onUnfocus
        ))
    }
}

// MARK: - Focus Ring Indicator
@available(iOS 26.0, visionOS 2.0, *)
struct FocusRingIndicator: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 2)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.1), value: progress)
        }
    }
}

// MARK: - Preview
@available(iOS 26.0, visionOS 2.0, *)
#Preview {
    EyeTrackingDebugView()
}

struct EyeTrackingDebugView: View {
    @StateObject private var eyeTracking = EyeTrackingManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("Eye Tracking Debug")
                .font(.title)

            HStack {
                StatusIndicator(
                    label: "Tracking",
                    isActive: eyeTracking.isTrackingEyes
                )
                StatusIndicator(
                    label: "Focused",
                    isActive: eyeTracking.focusedEntity != nil
                )
            }

            Text("Focus Duration: \(String(format: "%.2f", eyeTracking.focusState.focusDuration))s")
            Text("Focus Intensity: \(String(format: "%.2f", eyeTracking.focusIntensity))")

            FocusRingIndicator(
                progress: Double(eyeTracking.focusIntensity),
                color: .blue
            )
            .frame(width: 60, height: 60)

            Button(eyeTracking.isTrackingEyes ? "Stop Tracking" : "Start Tracking") {
                Task {
                    if eyeTracking.isTrackingEyes {
                        eyeTracking.stopTracking()
                    } else {
                        await eyeTracking.startTracking()
                    }
                }
            }
        }
        .padding()
    }
}

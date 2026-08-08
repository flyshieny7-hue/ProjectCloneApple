//
//  SpatialWalletSpace.swift
//  AppleWalletSpatial
//
//  Immersive space для Vision Pro с карточками "парящими" в воздухе
//  Supports iPhone (fallback 2D grid) and Vision Pro (full spatial)
//

import SwiftUI
import RealityKit
import RealityKitContent

// MARK: - Card Data Model
struct WalletCard: Identifiable, Equatable {
    let id = UUID()
    let type: CardType
    let cardNumber: String
    let cardHolder: String
    let expiryDate: String
    let balance: Double
    let currency: String
    var position: SIMD3<Float>
    var rotation: SIMD3<Float>
    var isSelected: Bool = false

    static func == (lhs: WalletCard, rhs: WalletCard) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Spatial Wallet Space
@available(iOS 26.0, visionOS 2.0, *)
struct SpatialWalletSpace: View {
    @State private var cards: [WalletCard] = []
    @State private var selectedCard: WalletCard?
    @State private var isImmersive: Bool = false
    @State private var ambientLightIntensity: Float = 0.5
    @State private var cardsFloating: Bool = true

    @StateObject private var handGestureManager = HandGestureManager()
    @StateObject private var eyeTrackingManager = EyeTrackingManager()
    @StateObject private var spatialAudio = SpatialAudioManager()

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    // Sample cards
    private let sampleCards = [
        WalletCard(
            type: .titaniumElite,
            cardNumber: "4532123456789012",
            cardHolder: "JOHN DOE",
            expiryDate: "12/28",
            balance: 15420.50,
            currency: "$",
            position: SIMD3(-0.3, 0.1, -0.5),
            rotation: SIMD3(0, 0.2, 0)
        ),
        WalletCard(
            type: .platinum,
            cardNumber: "5425233434567890",
            cardHolder: "JOHN DOE",
            expiryDate: "09/27",
            balance: 8750.00,
            currency: "$",
            position: SIMD3(0, 0.15, -0.55),
            rotation: SIMD3(0, 0, 0)
        ),
        WalletCard(
            type: .gold,
            cardNumber: "378282246310005",
            cardHolder: "JOHN DOE",
            expiryDate: "03/29",
            balance: 3200.75,
            currency: "$",
            position: SIMD3(0.3, 0.1, -0.5),
            rotation: SIMD3(0, -0.2, 0)
        ),
        WalletCard(
            type: .standard,
            cardNumber: "4111111111111111",
            cardHolder: "JOHN DOE",
            expiryDate: "06/28",
            balance: 1250.30,
            currency: "$",
            position: SIMD3(0, -0.15, -0.45),
            rotation: SIMD3(0.1, 0, 0)
        )
    ]

    var body: some View {
        Group {
            #if os(visionOS)
            visionWalletSpace
            #else
            iOSWalletSpace
            #endif
        }
        .onAppear {
            cards = sampleCards
            spatialAudio.preloadSounds()
        }
    }

    // MARK: - Vision Pro Immersive Space
    @ViewBuilder
    private var visionWalletSpace: some View {
        RealityView { content in
            // Setup immersive environment
            setupImmersiveEnvironment(content: content)

            // Create floating cards
            for card in cards {
                let cardEntity = createFloatingCardEntity(card)
                content.add(cardEntity)
            }

            // Add ambient particles
            let particles = createAmbientParticles()
            content.add(particles)

            // Setup lighting
            setupSpatialLighting(content: content)

        } update: { content in
            updateCardPositions(content: content)
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handleCardTap(value.entity)
                }
        )
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    handleCardDrag(value.entity, translation: value.translation3D)
                }
                .onEnded { value in
                    handleCardDragEnd(value.entity)
                }
        )
        .simultaneousGesture(
            handGestureManager.spatialTapGesture
        )
        .onChange(of: eyeTrackingManager.focusedEntity) { _, newValue in
            handleEyeFocus(newValue)
        }
        .ornament(visibility: .visible, attachmentAnchor: .scene(.bottom)) {
            walletControls
        }
    }

    // MARK: - iOS Fallback Wallet Space
    @ViewBuilder
    private var iOSWalletSpace: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.9),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        Text("My Wallet")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.top, 20)

                        // Total balance
                        VStack(spacing: 8) {
                            Text("Total Balance")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                            Text("\(totalBalance)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 20)

                        // Cards stack
                        LazyVStack(spacing: -80) {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                SpatialCardView(
                                    cardType: card.type,
                                    cardNumber: card.cardNumber,
                                    cardHolder: card.cardHolder,
                                    expiryDate: card.expiryDate,
                                    balance: card.balance,
                                    currency: card.currency
                                )
                                .offset(y: CGFloat(index) * 10)
                                .zIndex(Double(cards.count - index))
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                                        selectCard(card)
                                    }
                                    spatialAudio.playSound(.tap)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Wallet Controls (Vision Pro)
    @ViewBuilder
    private var walletControls: some View {
        HStack(spacing: 20) {
            Button(action: { addNewCard() }) {
                Label("Add Card", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            Button(action: { toggleFloating() }) {
                Label(cardsFloating ? "Freeze" : "Float", 
                      systemImage: cardsFloating ? "pause.circle.fill" : "play.circle.fill")
            }
            .buttonStyle(.bordered)

            Button(action: { dismissImmersiveSpace() }) {
                Label("Close", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .glassBackgroundEffect()
    }

    // MARK: - RealityKit Setup
    private func setupImmersiveEnvironment(content: RealityViewContent) {
        // Create a subtle background sphere
        let sphereMesh = MeshResource.generateSphere(radius: 2.0)
        var sphereMaterial = PhysicallyBasedMaterial()
        sphereMaterial.baseColor = .init(tint: .black)
        sphereMaterial.roughness = .init(floatLiteral: 1.0)

        let sphereEntity = Entity()
        sphereEntity.components.set(ModelComponent(
            mesh: sphereMesh,
            materials: [sphereMaterial]
        ))
        sphereEntity.scale = SIMD3(repeating: -1.0) // Inward facing
        content.add(sphereEntity)
    }

    private func createFloatingCardEntity(_ card: WalletCard) -> Entity {
        let cardEntity = Entity()

        // Card mesh with depth
        let cardMesh = MeshResource.generateBox(
            width: 0.17,
            height: 0.003,
            depth: 0.11,
            cornerRadius: 0.012
        )

        let material = card.type.material
        var pbrMaterial = PhysicallyBasedMaterial()
        pbrMaterial.baseColor = .init(tint: UIColor(
            red: CGFloat(material.baseColor.x),
            green: CGFloat(material.baseColor.y),
            blue: CGFloat(material.baseColor.z),
            alpha: 1.0
        ))
        pbrMaterial.metallic = .init(floatLiteral: material.metallic)
        pbrMaterial.roughness = .init(floatLiteral: material.roughness)
        pbrMaterial.emissiveColor = .init(
            color: UIColor(
                red: CGFloat(material.emissiveColor.x),
                green: CGFloat(material.emissiveColor.y),
                blue: CGFloat(material.emissiveColor.z),
                alpha: 1.0
            )
        )
        pbrMaterial.emissiveIntensity = material.emissiveIntensity

        cardEntity.components.set(ModelComponent(
            mesh: cardMesh,
            materials: [pbrMaterial]
        ))

        // Set initial position
        cardEntity.position = card.position
        cardEntity.orientation = simd_quatf(
            angle: card.rotation.y,
            axis: SIMD3(0, 1, 0)
        )

        // Add collision for gestures
        cardEntity.components.set(CollisionComponent(
            shapes: [.generateBox(width: 0.17, height: 0.003, depth: 0.11)]
        ))

        // Add hover effect component
        cardEntity.components.set(HoverEffectComponent())

        // Store card ID for identification
        cardEntity.name = card.id.uuidString

        return cardEntity
    }

    private func createAmbientParticles() -> Entity {
        let particlesEntity = Entity()

        // Create floating light particles
        for _ in 0..<30 {
            let particle = Entity()
            let particleMesh = MeshResource.generateSphere(radius: Float.random(in: 0.002...0.005))
            var particleMaterial = PhysicallyBasedMaterial()
            particleMaterial.baseColor = .init(tint: .white)
            particleMaterial.emissiveColor = .init(color: .white)
            particleMaterial.emissiveIntensity = Float.random(in: 0.5...2.0)

            particle.components.set(ModelComponent(
                mesh: particleMesh,
                materials: [particleMaterial]
            ))

            particle.position = SIMD3(
                Float.random(in: -1.0...1.0),
                Float.random(in: -0.5...0.8),
                Float.random(in: -1.0...0.0)
            )

            // Add floating animation
            var animation = particle.availableAnimations.first
            if animation == nil {
                // Create simple floating animation
                let fromTransform = Transform(
                    scale: .one,
                    rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                    translation: particle.position
                )
                let toTransform = Transform(
                    scale: .one,
                    rotation: simd_quatf(angle: .pi * 2, axis: SIMD3(0, 1, 0)),
                    translation: particle.position + SIMD3(0, 0.1, 0)
                )
            }

            particlesEntity.addChild(particle)
        }

        return particlesEntity
    }

    private func setupSpatialLighting(content: RealityViewContent) {
        // Main directional light
        let mainLight = Entity()
        mainLight.components.set(DirectionalLightComponent(
            color: .white,
            intensity: 2000,
            isRealWorldProxy: false
        ))
        mainLight.orientation = simd_quatf(
            angle: -.pi / 4,
            axis: SIMD3(1, 0, 0)
        )
        content.add(mainLight)

        // Ambient light
        let ambientLight = Entity()
        ambientLight.components.set(AmbientLightComponent(
            color: .init(red: 0.3, green: 0.35, blue: 0.4, alpha: 1.0),
            intensity: ambientLightIntensity
        ))
        content.add(ambientLight)

        // Point lights for card highlights
        for i in 0..<4 {
            let pointLight = Entity()
            pointLight.components.set(PointLightComponent(
                color: .white,
                intensity: 500,
                attenuationRadius: 1.0
            ))
            pointLight.position = SIMD3(
                Float(i % 2 == 0 ? -0.5 : 0.5),
                0.5,
                Float(i < 2 ? -0.3 : -0.7)
            )
            content.add(pointLight)
        }
    }

    // MARK: - Gesture Handlers
    private func handleCardTap(_ entity: Entity) {
        guard let card = cards.first(where: { $0.id.uuidString == entity.name }) else { return }

        spatialAudio.playSound(.tap)

        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            selectCard(card)
        }

        // Haptic feedback
        #if os(visionOS)
        let haptic = HapticFeedbackEvent(intensity: 0.5, sharpness: 0.7)
        // Play haptic
        #endif
    }

    private func handleCardDrag(_ entity: Entity, translation: SIMD3<Double>) {
        guard cardsFloating else { return }

        var newPosition = entity.position
        newPosition.x += Float(translation.x) * 0.001
        newPosition.y += Float(translation.y) * 0.001
        newPosition.z += Float(translation.z) * 0.001

        entity.position = newPosition

        spatialAudio.playSound(.swipe)
    }

    private func handleCardDragEnd(_ entity: Entity) {
        // Snap back or keep position based on gesture
        spatialAudio.playSound(.success)
    }

    private func handleEyeFocus(_ entity: Entity?) {
        guard let entity = entity,
              let card = cards.first(where: { $0.id.uuidString == entity.name }) else { return }

        // Scale up focused card
        withAnimation(.easeInOut(duration: 0.3)) {
            entity.scale = SIMD3(repeating: 1.2)
        }

        spatialAudio.playSound(.focus)
    }

    private func updateCardPositions(content: RealityViewContent) {
        guard cardsFloating else { return }

        // Apply gentle floating animation
        for entity in content.entities {
            guard cards.contains(where: { $0.id.uuidString == entity.name }) else { continue }

            let time = Float(CACurrentMediaTime())
            let originalY = cards.first(where: { $0.id.uuidString == entity.name })?.position.y ?? 0

            entity.position.y = originalY + sin(time * 0.5 + entity.position.x * 2) * 0.02
            entity.orientation = simd_quatf(
                angle: sin(time * 0.3) * 0.05,
                axis: SIMD3(0, 1, 0)
            )
        }
    }

    // MARK: - Actions
    private func selectCard(_ card: WalletCard) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index].isSelected.toggle()
            selectedCard = cards[index].isSelected ? cards[index] : nil
        }
    }

    private func addNewCard() {
        spatialAudio.playSound(.success)
        // Present add card flow
    }

    private func toggleFloating() {
        withAnimation(.spring(duration: 0.5)) {
            cardsFloating.toggle()
        }
    }

    private var totalBalance: String {
        let total = cards.reduce(0) { $0 + $1.balance }
        return "\(cards.first?.currency ?? "$")\(String(format: "%.2f", total))"
    }
}

// MARK: - Preview
@available(iOS 26.0, visionOS 2.0, *)
#Preview {
    SpatialWalletSpace()
}

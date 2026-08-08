//
//  SpatialTransactionFlow.swift
//  AppleWalletSpatial
//
//  3D анимация перевода денег между картами
//  Supports iPhone (fallback 2D) and Vision Pro (full spatial)
//

import SwiftUI
import RealityKit
import RealityKitContent

// MARK: - Transaction Model
struct Transaction: Identifiable {
    let id = UUID()
    let fromCard: WalletCard
    let toCard: WalletCard
    let amount: Double
    let currency: String
    let timestamp: Date
    var status: TransactionStatus = .pending

    enum TransactionStatus: String {
        case pending = "Pending"
        case processing = "Processing"
        case completed = "Completed"
        case failed = "Failed"
    }
}

// MARK: - Spatial Transaction Flow
@available(iOS 26.0, visionOS 2.0, *)
struct SpatialTransactionFlow: View {
    let transaction: Transaction
    let onComplete: () -> Void

    @State private var animationProgress: Double = 0.0
    @State private var particleEntities: [Entity] = []
    @State private var isAnimating: Bool = false
    @State private var showSuccessEffect: Bool = false
    @State private var moneyOrbPosition: SIMD3<Float> = .zero
    @State private var trailPositions: [SIMD3<Float>] = []

    @StateObject private var spatialAudio = SpatialAudioManager()

    var body: some View {
        Group {
            #if os(visionOS)
            visionTransactionFlow
            #else
            iOSTransactionFlow
            #endif
        }
        .onAppear {
            startTransactionAnimation()
        }
    }

    // MARK: - Vision Pro 3D Transaction Flow
    @ViewBuilder
    private var visionTransactionFlow: some View {
        RealityView { content in
            // Create source card
            let sourceCard = createTransactionCardEntity(
                transaction.fromCard,
                position: SIMD3(-0.3, 0, -0.5)
            )
            content.add(sourceCard)

            // Create destination card
            let destCard = createTransactionCardEntity(
                transaction.toCard,
                position: SIMD3(0.3, 0, -0.5)
            )
            content.add(destCard)

            // Create money orb (animated particle)
            let moneyOrb = createMoneyOrbEntity()
            moneyOrb.position = SIMD3(-0.3, 0, -0.5)
            content.add(moneyOrb)

            // Create connection beam
            let beam = createTransactionBeam()
            content.add(beam)

            // Create floating amount text
            let amountText = createAmountTextEntity()
            amountText.position = SIMD3(0, 0.2, -0.5)
            content.add(amountText)

        } update: { content in
            updateTransactionAnimation(content: content)
        }
        .frame(depth: 200)
        .ornament(visibility: .visible, attachmentAnchor: .scene(.bottom)) {
            transactionStatusBar
        }
    }

    // MARK: - iOS Fallback Transaction Flow
    @ViewBuilder
    private var iOSTransactionFlow: some View {
        ZStack {
            // Background
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                // Header
                Text("Transfer")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Cards with animated flow
                HStack(spacing: 30) {
                    // Source card
                    VStack(spacing: 12) {
                        SpatialCardView(
                            cardType: transaction.fromCard.type,
                            cardNumber: transaction.fromCard.cardNumber,
                            cardHolder: transaction.fromCard.cardHolder,
                            expiryDate: transaction.fromCard.expiryDate,
                            balance: transaction.fromCard.balance,
                            currency: transaction.currency
                        )
                        .scaleEffect(0.8)

                        Text("From")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Animated flow indicator
                    ZStack {
                        // Connection line
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.green.opacity(0.3),
                                        Color.green.opacity(0.8),
                                        Color.green.opacity(0.3)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 80, height: 4)

                        // Animated orb
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.green, .green.opacity(0.3)],
                                    center: .center,
                                    startRadius: 5,
                                    endRadius: 20
                            ))
                            .frame(width: 24, height: 24)
                            .shadow(color: .green.opacity(0.6), radius: 10)
                            .offset(x: CGFloat(animationProgress * 80 - 40))
                            .overlay(
                                Text("\(transaction.currency)\(String(format: "%.0f", transaction.amount))")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .offset(x: CGFloat(animationProgress * 80 - 40), y: -20)
                            )
                    }

                    // Destination card
                    VStack(spacing: 12) {
                        SpatialCardView(
                            cardType: transaction.toCard.type,
                            cardNumber: transaction.toCard.cardNumber,
                            cardHolder: transaction.toCard.cardHolder,
                            expiryDate: transaction.toCard.expiryDate,
                            balance: transaction.toCard.balance,
                            currency: transaction.currency
                        )
                        .scaleEffect(0.8)

                        Text("To")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                // Amount display
                VStack(spacing: 8) {
                    Text("\(transaction.currency)\(String(format: "%.2f", transaction.amount))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)

                    Text(transaction.status.rawValue)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(statusColor.opacity(0.2))
                        .clipShape(Capsule())
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.6), .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(animationProgress), height: 8)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
        }
    }

    // MARK: - Transaction Status Bar (Vision Pro)
    @ViewBuilder
    private var transactionStatusBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(transaction.currency)\(String(format: "%.2f", transaction.amount))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(transaction.status.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            Spacer()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: CGFloat(animationProgress))
                    .stroke(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding()
        .frame(width: 400)
        .glassBackgroundEffect()
    }

    // MARK: - RealityKit Entity Creation
    private func createTransactionCardEntity(_ card: WalletCard, position: SIMD3<Float>) -> Entity {
        let entity = Entity()

        let mesh = MeshResource.generateBox(
            width: 0.15,
            height: 0.003,
            depth: 0.095,
            cornerRadius: 0.01
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

        entity.components.set(ModelComponent(mesh: mesh, materials: [pbrMaterial]))
        entity.position = position

        return entity
    }

    private func createMoneyOrbEntity() -> Entity {
        let orb = Entity()

        // Main orb
        let orbMesh = MeshResource.generateSphere(radius: 0.025)
        var orbMaterial = PhysicallyBasedMaterial()
        orbMaterial.baseColor = .init(tint: .green)
        orbMaterial.emissiveColor = .init(color: .green)
        orbMaterial.emissiveIntensity = 2.0
        orbMaterial.metallic = .init(floatLiteral: 0.8)

        orb.components.set(ModelComponent(mesh: orbMesh, materials: [orbMaterial]))

        // Glow halo
        let haloMesh = MeshResource.generateSphere(radius: 0.04)
        var haloMaterial = PhysicallyBasedMaterial()
        haloMaterial.baseColor = .init(tint: .clear)
        haloMaterial.emissiveColor = .init(color: UIColor.green.withAlphaComponent(0.3))
        haloMaterial.emissiveIntensity = 1.0

        let haloEntity = Entity()
        haloEntity.components.set(ModelComponent(mesh: haloMesh, materials: [haloMaterial]))
        orb.addChild(haloEntity)

        return orb
    }

    private func createTransactionBeam() -> Entity {
        let beam = Entity()

        // Create a curved beam between cards
        let beamMesh = MeshResource.generateBox(
            width: 0.6,
            height: 0.005,
            depth: 0.005
        )

        var beamMaterial = PhysicallyBasedMaterial()
        beamMaterial.baseColor = .init(tint: .clear)
        beamMaterial.emissiveColor = .init(color: UIColor.green.withAlphaComponent(0.5))
        beamMaterial.emissiveIntensity = 1.5

        beam.components.set(ModelComponent(mesh: beamMesh, materials: [beamMaterial]))
        beam.position = SIMD3(0, 0, -0.5)

        return beam
    }

    private func createAmountTextEntity() -> Entity {
        let textEntity = Entity()

        let textMesh = MeshResource.generateText(
            "\(transaction.currency)\(String(format: "%.2f", transaction.amount))",
            extrusionDepth: 0.002,
            font: .systemFont(ofSize: 0.03, weight: .bold),
            containerFrame: .zero,
            alignment: .center
        )

        var textMaterial = PhysicallyBasedMaterial()
        textMaterial.baseColor = .init(tint: .green)
        textMaterial.emissiveColor = .init(color: .green)
        textMaterial.emissiveIntensity = 2.0

        textEntity.components.set(ModelComponent(mesh: textMesh, materials: [textMaterial]))

        return textEntity
    }

    // MARK: - Animation Updates
    private func updateTransactionAnimation(content: RealityViewContent) {
        guard let moneyOrb = content.entities.first(where: { 
            $0.children.contains(where: { child in
                // Check for halo child to identify orb
                true
            })
        }) else { return }

        // Interpolate position from source to destination
        let startPos = SIMD3<Float>(-0.3, 0, -0.5)
        let endPos = SIMD3<Float>(0.3, 0, -0.5)

        let progress = Float(animationProgress)
        moneyOrb.position = mix(startPos, endPos, t: progress)

        // Add arc to the path
        moneyOrb.position.y = sin(progress * .pi) * 0.15

        // Rotate orb
        moneyOrb.orientation = simd_quatf(
            angle: progress * .pi * 4,
            axis: SIMD3(0, 1, 0)
        )

        // Scale pulse
        let scale = 1.0 + sin(progress * .pi * 6) * 0.2
        moneyOrb.scale = SIMD3(repeating: scale)
    }

    // MARK: - Animation Control
    private func startTransactionAnimation() {
        isAnimating = true
        spatialAudio.playSound(.swipe)

        withAnimation(.easeInOut(duration: 2.0)) {
            animationProgress = 1.0
        }

        // Completion handler
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(duration: 0.5)) {
                showSuccessEffect = true
            }
            spatialAudio.playSound(.success)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onComplete()
            }
        }
    }

    // MARK: - Helpers
    private var statusColor: Color {
        switch transaction.status {
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }
}

// MARK: - Preview
@available(iOS 26.0, visionOS 2.0, *)
#Preview {
    SpatialTransactionFlow(
        transaction: Transaction(
            fromCard: WalletCard(
                type: .titaniumElite,
                cardNumber: "4532123456789012",
                cardHolder: "JOHN DOE",
                expiryDate: "12/28",
                balance: 15420.50,
                currency: "$",
                position: .zero,
                rotation: .zero
            ),
            toCard: WalletCard(
                type: .gold,
                cardNumber: "378282246310005",
                cardHolder: "JOHN DOE",
                expiryDate: "03/29",
                balance: 3200.75,
                currency: "$",
                position: .zero,
                rotation: .zero
            ),
            amount: 500.00,
            currency: "$",
            timestamp: Date()
        ),
        onComplete: {}
    )
}

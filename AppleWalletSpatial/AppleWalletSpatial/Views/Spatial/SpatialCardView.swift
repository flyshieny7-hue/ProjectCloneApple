//
//  SpatialCardView.swift
//  AppleWalletSpatial
//
//  Spatial Card View — 3D карта с depth, glass material, volumetric glow
//  Supports iPhone (fallback 2D) and Vision Pro (full spatial)
//

import SwiftUI
import RealityKit
import RealityKitContent

// MARK: - Card Type Enum
enum CardType: String, CaseIterable {
    case titaniumElite = "Titanium Elite"
    case platinum = "Platinum"
    case gold = "Gold"
    case standard = "Standard"

    var material: CardMaterial {
        switch self {
        case .titaniumElite:
            return CardMaterial(
                baseColor: .init(red: 0.15, green: 0.15, blue: 0.15),
                metallic: 1.0,
                roughness: 0.15,
                emissiveColor: .init(red: 0.4, green: 0.4, blue: 0.5),
                emissiveIntensity: 0.3,
                cardName: "TITANIUM ELITE"
            )
        case .platinum:
            return CardMaterial(
                baseColor: .init(red: 0.75, green: 0.75, blue: 0.78),
                metallic: 1.0,
                roughness: 0.1,
                emissiveColor: .init(red: 0.9, green: 0.9, blue: 0.95),
                emissiveIntensity: 0.15,
                cardName: "PLATINUM"
            )
        case .gold:
            return CardMaterial(
                baseColor: .init(red: 0.85, green: 0.65, blue: 0.15),
                metallic: 1.0,
                roughness: 0.2,
                emissiveColor: .init(red: 1.0, green: 0.8, blue: 0.2),
                emissiveIntensity: 0.2,
                cardName: "GOLD"
            )
        case .standard:
            return CardMaterial(
                baseColor: .init(red: 0.1, green: 0.3, blue: 0.6),
                metallic: 0.3,
                roughness: 0.5,
                emissiveColor: .init(red: 0.2, green: 0.5, blue: 1.0),
                emissiveIntensity: 0.1,
                cardName: "STANDARD"
            )
        }
    }
}

// MARK: - Card Material
struct CardMaterial {
    let baseColor: SIMD3<Float>
    let metallic: Float
    let roughness: Float
    let emissiveColor: SIMD3<Float>
    let emissiveIntensity: Float
    let cardName: String
}

// MARK: - Spatial Card View
@available(iOS 26.0, visionOS 2.0, *)
struct SpatialCardView: View {
    let cardType: CardType
    let cardNumber: String
    let cardHolder: String
    let expiryDate: String
    let balance: Double
    let currency: String

    @State private var isHovered: Bool = false
    @State private var isFocused: Bool = false
    @State private var rotationX: Double = 0
    @State private var rotationY: Double = 0
    @State private var scale: Double = 1.0
    @State private var glowIntensity: Double = 0.0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            #if os(visionOS)
            visionCardView
            #else
            iOSCardView
            #endif
        }
    }

    // MARK: - Vision Pro Spatial Card
    @ViewBuilder
    private var visionCardView: some View {
        RealityView { content in
            let cardEntity = createSpatialCardEntity()
            content.add(cardEntity)

            // Add volumetric glow
            let glowEntity = createVolumetricGlow()
            cardEntity.addChild(glowEntity)

            // Add depth layers
            let depthLayer = createDepthLayer()
            cardEntity.addChild(depthLayer)
        } update: { content in
            if let cardEntity = content.entities.first {
                updateCardTransform(cardEntity)
            }
        }
        .frame(depth: 120)
        .glassBackgroundEffect(
            displayMode: .always,
            in: .rect(cornerRadius: 24)
        )
        .hoverEffect { effect, isActive, _ in
            effect.scaleEffect(isActive ? 1.08 : 1.0)
        }
        .onHover { hovering in
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                isHovered = hovering
                scale = hovering ? 1.15 : 1.0
                glowIntensity = hovering ? 1.0 : 0.0
            }
        }
        .onAppear {
            // Entrance animation
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                scale = 1.0
            }
        }
    }

    // MARK: - iOS Fallback Card
    @ViewBuilder
    private var iOSCardView: some View {
        ZStack {
            // Card background with glass effect
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: Double(cardType.material.baseColor.x),
                                  green: Double(cardType.material.baseColor.y),
                                  blue: Double(cardType.material.baseColor.z)),
                            Color(red: Double(cardType.material.baseColor.x) * 0.7,
                                  green: Double(cardType.material.baseColor.y) * 0.7,
                                  blue: Double(cardType.material.baseColor.z) * 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.4),
                                    .white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )

            // Metallic shine effect
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.15),
                            .white.opacity(0.0),
                            .white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Card content
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(cardType.material.cardName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .tracking(2)

                    Spacer()

                    // Contactless icon
                    Image(systemName: "wave.3.forward")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Chip
                HStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.yellow.opacity(0.8), .orange.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )

                    Spacer()
                }

                // Card number
                Text(maskedCardNumber)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(4)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CARD HOLDER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(cardHolder.uppercased())
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("EXPIRES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(expiryDate)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }

                // Balance
                HStack {
                    Text("\(currency)\(String(format: "%.2f", balance))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()
                }
            }
            .padding(24)
        }
        .frame(width: 340, height: 210)
        .rotation3DEffect(
            .degrees(rotationX),
            axis: (x: 1, y: 0, z: 0)
        )
        .rotation3DEffect(
            .degrees(rotationY),
            axis: (x: 0, y: 1, z: 0)
        )
        .scaleEffect(scale)
        .shadow(
            color: Color(red: Double(cardType.material.baseColor.x),
                        green: Double(cardType.material.baseColor.y),
                        blue: Double(cardType.material.baseColor.z)).opacity(0.4),
            radius: isHovered ? 30 : 15,
            x: 0,
            y: isHovered ? 20 : 10
        )
        .onHover { hovering in
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                isHovered = hovering
                scale = hovering ? 1.05 : 1.0
                rotationX = hovering ? -5 : 0
                rotationY = hovering ? 5 : 0
            }
        }
    }

    // MARK: - RealityKit Entity Creation
    private func createSpatialCardEntity() -> Entity {
        let cardEntity = Entity()

        // Main card mesh
        let cardMesh = MeshResource.generateBox(
            width: 0.17,
            height: 0.002,
            depth: 0.11,
            cornerRadius: 0.012
        )

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(
            red: CGFloat(cardType.material.baseColor.x),
            green: CGFloat(cardType.material.baseColor.y),
            blue: CGFloat(cardType.material.baseColor.z),
            alpha: 1.0
        ))
        material.metallic = .init(floatLiteral: cardType.material.metallic)
        material.roughness = .init(floatLiteral: cardType.material.roughness)
        material.emissiveColor = .init(
            color: UIColor(
                red: CGFloat(cardType.material.emissiveColor.x),
                green: CGFloat(cardType.material.emissiveColor.y),
                blue: CGFloat(cardType.material.emissiveColor.z),
                alpha: 1.0
            )
        )
        material.emissiveIntensity = cardType.material.emissiveIntensity

        let cardModel = ModelComponent(mesh: cardMesh, materials: [material])
        cardEntity.components.set(cardModel)

        // Add card text as child entities
        let textEntity = createCardTextEntity()
        textEntity.position = SIMD3(0, 0.0015, 0)
        cardEntity.addChild(textEntity)

        return cardEntity
    }

    private func createVolumetricGlow() -> Entity {
        let glowEntity = Entity()

        let glowMesh = MeshResource.generateBox(
            width: 0.18,
            height: 0.001,
            depth: 0.115,
            cornerRadius: 0.013
        )

        var glowMaterial = PhysicallyBasedMaterial()
        glowMaterial.baseColor = .init(tint: .clear)
        glowMaterial.emissiveColor = .init(
            color: UIColor(
                red: CGFloat(cardType.material.emissiveColor.x),
                green: CGFloat(cardType.material.emissiveColor.y),
                blue: CGFloat(cardType.material.emissiveColor.z),
                alpha: 0.3
            )
        )
        glowMaterial.emissiveIntensity = Float(glowIntensity)

        let glowModel = ModelComponent(mesh: glowMesh, materials: [glowMaterial])
        glowEntity.components.set(glowModel)

        return glowEntity
    }

    private func createDepthLayer() -> Entity {
        let depthEntity = Entity()

        // Embossed chip
        let chipMesh = MeshResource.generateBox(
            width: 0.025,
            height: 0.001,
            depth: 0.019,
            cornerRadius: 0.003
        )

        var chipMaterial = PhysicallyBasedMaterial()
        chipMaterial.baseColor = .init(tint: .systemYellow)
        chipMaterial.metallic = .init(floatLiteral: 0.8)
        chipMaterial.roughness = .init(floatLiteral: 0.3)

        let chipModel = ModelComponent(mesh: chipMesh, materials: [chipMaterial])
        depthEntity.components.set(chipModel)
        depthEntity.position = SIMD3(-0.055, 0.0015, -0.025)

        return depthEntity
    }

    private func createCardTextEntity() -> Entity {
        let textEntity = Entity()

        // Card name text
        let cardNameMesh = MeshResource.generateText(
            cardType.material.cardName,
            extrusionDepth: 0.0005,
            font: .systemFont(ofSize: 0.008, weight: .bold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )

        var textMaterial = PhysicallyBasedMaterial()
        textMaterial.baseColor = .init(tint: .white)
        textMaterial.metallic = .init(floatLiteral: 0.9)

        let textModel = ModelComponent(mesh: cardNameMesh, materials: [textMaterial])
        textEntity.components.set(textModel)
        textEntity.position = SIMD3(-0.05, 0, -0.04)

        return textEntity
    }

    private func updateCardTransform(_ entity: Entity) {
        var transform = entity.transform
        transform.scale = SIMD3(repeating: Float(scale))
        entity.transform = transform
    }

    // MARK: - Helpers
    private var maskedCardNumber: String {
        let last4 = String(cardNumber.suffix(4))
        return "•••• •••• •••• \(last4)"
    }
}

// MARK: - Preview
@available(iOS 26.0, visionOS 2.0, *)
#Preview {
    SpatialCardView(
        cardType: .titaniumElite,
        cardNumber: "4532123456789012",
        cardHolder: "JOHN DOE",
        expiryDate: "12/28",
        balance: 15420.50,
        currency: "$"
    )
}

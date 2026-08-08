//
//  RealityKitCardModels.swift
//  AppleWalletSpatial
//
//  RealityKit card models — металлические текстуры для elite карт
//

import SwiftUI
import RealityKit
import RealityKitContent

// MARK: - Card Model Factory
@available(iOS 26.0, visionOS 2.0, *)
enum CardModelFactory {

    // MARK: - Generate Elite Card Model
    static func createEliteCardModel(
        type: CardType,
        position: SIMD3<Float> = .zero,
        scale: SIMD3<Float> = .one
    ) -> Entity {
        let cardEntity = Entity()
        cardEntity.position = position
        cardEntity.scale = scale

        // Main card body
        let cardBody = createCardBody(type: type)
        cardEntity.addChild(cardBody)

        // Metallic layer
        let metallicLayer = createMetallicLayer(type: type)
        cardEntity.addChild(metallicLayer)

        // Embossed details
        let embossedDetails = createEmbossedDetails(type: type)
        cardEntity.addChild(embossedDetails)

        // Chip
        let chip = createChip()
        cardEntity.addChild(chip)

        // Text elements
        let textElements = createTextElements(type: type)
        cardEntity.addChild(textElements)

        // Edge bevel
        let edgeBevel = createEdgeBevel(type: type)
        cardEntity.addChild(edgeBevel)

        return cardEntity
    }

    // MARK: - Card Body
    private static func createCardBody(type: CardType) -> Entity {
        let entity = Entity()

        let mesh = MeshResource.generateBox(
            width: 0.17,
            height: 0.002,
            depth: 0.11,
            cornerRadius: 0.012
        )

        let material = type.material
        var pbrMaterial = PhysicallyBasedMaterial()

        // Base color with subtle variation
        pbrMaterial.baseColor = .init(tint: UIColor(
            red: CGFloat(material.baseColor.x),
            green: CGFloat(material.baseColor.y),
            blue: CGFloat(material.baseColor.z),
            alpha: 1.0
        ))

        // Metallic properties for elite cards
        pbrMaterial.metallic = .init(floatLiteral: material.metallic)
        pbrMaterial.roughness = .init(floatLiteral: material.roughness)

        // Specular highlights
        pbrMaterial.specular = .init(floatLiteral: 0.8)

        // Clear coat for glass-like finish
        pbrMaterial.clearcoat = .init(floatLiteral: type == .titaniumElite ? 0.6 : 0.3)
        pbrMaterial.clearcoatRoughness = .init(floatLiteral: 0.1)

        // Emissive for glow effect
        pbrMaterial.emissiveColor = .init(
            color: UIColor(
                red: CGFloat(material.emissiveColor.x),
                green: CGFloat(material.emissiveColor.y),
                blue: CGFloat(material.emissiveColor.z),
                alpha: 1.0
            )
        )
        pbrMaterial.emissiveIntensity = material.emissiveIntensity

        entity.components.set(ModelComponent(mesh: mesh, materials: [pbrMaterial]))

        return entity
    }

    // MARK: - Metallic Layer
    private static func createMetallicLayer(type: CardType) -> Entity {
        let entity = Entity()

        // Thin metallic overlay for brushed metal effect
        let mesh = MeshResource.generateBox(
            width: 0.168,
            height: 0.0005,
            depth: 0.108,
            cornerRadius: 0.011
        )

        var pbrMaterial = PhysicallyBasedMaterial()

        switch type {
        case .titaniumElite:
            // Brushed titanium
            pbrMaterial.baseColor = .init(tint: UIColor(white: 0.25, alpha: 1.0))
            pbrMaterial.metallic = .init(floatLiteral: 1.0)
            pbrMaterial.roughness = .init(floatLiteral: 0.2)
            pbrMaterial.anisotropy = .init(floatLiteral: 0.8)

        case .platinum:
            // Polished platinum
            pbrMaterial.baseColor = .init(tint: UIColor(white: 0.85, alpha: 1.0))
            pbrMaterial.metallic = .init(floatLiteral: 1.0)
            pbrMaterial.roughness = .init(floatLiteral: 0.05)
            pbrMaterial.anisotropy = .init(floatLiteral: 0.3)

        case .gold:
            // Brushed gold
            pbrMaterial.baseColor = .init(tint: UIColor(
                red: 0.9, green: 0.75, blue: 0.3, alpha: 1.0
            ))
            pbrMaterial.metallic = .init(floatLiteral: 1.0)
            pbrMaterial.roughness = .init(floatLiteral: 0.15)
            pbrMaterial.anisotropy = .init(floatLiteral: 0.6)

        case .standard:
            // Matte plastic
            pbrMaterial.baseColor = .init(tint: UIColor(
                red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0
            ))
            pbrMaterial.metallic = .init(floatLiteral: 0.0)
            pbrMaterial.roughness = .init(floatLiteral: 0.7)
        }

        entity.components.set(ModelComponent(mesh: mesh, materials: [pbrMaterial]))
        entity.position.y = 0.0015

        return entity
    }

    // MARK: - Embossed Details
    private static func createEmbossedDetails(type: CardType) -> Entity {
        let entity = Entity()

        // Decorative lines
        let lineMesh = MeshResource.generateBox(
            width: 0.14,
            height: 0.0003,
            depth: 0.002
        )

        var lineMaterial = PhysicallyBasedMaterial()
        lineMaterial.baseColor = .init(tint: UIColor(white: 0.9, alpha: 1.0))
        lineMaterial.metallic = .init(floatLiteral: 0.9)
        lineMaterial.roughness = .init(floatLiteral: 0.1)

        let topLine = Entity()
        topLine.components.set(ModelComponent(mesh: lineMesh, materials: [lineMaterial]))
        topLine.position = SIMD3(0, 0.0018, -0.04)
        entity.addChild(topLine)

        let bottomLine = Entity()
        bottomLine.components.set(ModelComponent(mesh: lineMesh, materials: [lineMaterial]))
        bottomLine.position = SIMD3(0, 0.0018, 0.04)
        entity.addChild(bottomLine)

        // Corner accents for elite cards
        if type == .titaniumElite || type == .platinum {
            let cornerMesh = MeshResource.generateSphere(radius: 0.008)
            var cornerMaterial = PhysicallyBasedMaterial()
            cornerMaterial.baseColor = .init(tint: .white)
            cornerMaterial.metallic = .init(floatLiteral: 1.0)
            cornerMaterial.emissiveColor = .init(color: .white)
            cornerMaterial.emissiveIntensity = 0.5

            let corners = [
                SIMD3(-0.075, 0.0018, -0.05),
                SIMD3(0.075, 0.0018, -0.05),
                SIMD3(-0.075, 0.0018, 0.05),
                SIMD3(0.075, 0.0018, 0.05)
            ]

            for cornerPos in corners {
                let corner = Entity()
                corner.components.set(ModelComponent(mesh: cornerMesh, materials: [cornerMaterial]))
                corner.position = cornerPos
                entity.addChild(corner)
            }
        }

        return entity
    }

    // MARK: - Chip
    private static func createChip() -> Entity {
        let entity = Entity()

        // Chip body
        let chipMesh = MeshResource.generateBox(
            width: 0.025,
            height: 0.001,
            depth: 0.019,
            cornerRadius: 0.003
        )

        var chipMaterial = PhysicallyBasedMaterial()
        chipMaterial.baseColor = .init(tint: UIColor(
            red: 0.95, green: 0.85, blue: 0.3, alpha: 1.0
        ))
        chipMaterial.metallic = .init(floatLiteral: 0.8)
        chipMaterial.roughness = .init(floatLiteral: 0.3)

        entity.components.set(ModelComponent(mesh: chipMesh, materials: [chipMaterial]))
        entity.position = SIMD3(-0.055, 0.002, -0.025)

        // Chip contacts
        let contactMesh = MeshResource.generateBox(
            width: 0.02,
            height: 0.0002,
            depth: 0.015
        )

        var contactMaterial = PhysicallyBasedMaterial()
        contactMaterial.baseColor = .init(tint: UIColor(
            red: 0.3, green: 0.25, blue: 0.1, alpha: 1.0
        ))
        contactMaterial.metallic = .init(floatLiteral: 0.9)

        let contacts = Entity()
        contacts.components.set(ModelComponent(mesh: contactMesh, materials: [contactMaterial]))
        contacts.position = SIMD3(-0.055, 0.0026, -0.025)
        entity.addChild(contacts)

        return entity
    }

    // MARK: - Text Elements
    private static func createTextElements(type: CardType) -> Entity {
        let entity = Entity()

        // Card name
        let nameMesh = MeshResource.generateText(
            type.material.cardName,
            extrusionDepth: 0.0003,
            font: .systemFont(ofSize: 0.007, weight: .bold),
            containerFrame: .zero,
            alignment: .center
        )

        var nameMaterial = PhysicallyBasedMaterial()
        nameMaterial.baseColor = .init(tint: .white)
        nameMaterial.metallic = .init(floatLiteral: 0.9)
        nameMaterial.emissiveColor = .init(color: .white)
        nameMaterial.emissiveIntensity = 0.3

        let nameEntity = Entity()
        nameEntity.components.set(ModelComponent(mesh: nameMesh, materials: [nameMaterial]))
        nameEntity.position = SIMD3(-0.05, 0.002, -0.04)
        entity.addChild(nameEntity)

        return entity
    }

    // MARK: - Edge Bevel
    private static func createEdgeBevel(type: CardType) -> Entity {
        let entity = Entity()

        // Subtle bevel around card edge
        let bevelMesh = MeshResource.generateBox(
            width: 0.172,
            height: 0.001,
            depth: 0.112,
            cornerRadius: 0.013
        )

        var bevelMaterial = PhysicallyBasedMaterial()
        bevelMaterial.baseColor = .init(tint: UIColor(
            red: CGFloat(type.material.baseColor.x) * 1.2,
            green: CGFloat(type.material.baseColor.y) * 1.2,
            blue: CGFloat(type.material.baseColor.z) * 1.2,
            alpha: 0.3
        ))
        bevelMaterial.metallic = .init(floatLiteral: type.material.metallic)
        bevelMaterial.roughness = .init(floatLiteral: 0.1)

        entity.components.set(ModelComponent(mesh: bevelMesh, materials: [bevelMaterial]))
        entity.position.y = -0.001

        return entity
    }
}

// MARK: - Card Animation Extensions
@available(iOS 26.0, visionOS 2.0, *)
extension Entity {

    /// Animate card flip
    func animateFlip(duration: TimeInterval = 0.6) {
        let fromRotation = self.orientation
        let toRotation = fromRotation * simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))

        var transform = self.transform
        transform.rotation = toRotation

        self.move(
            to: transform,
            relativeTo: self.parent,
            duration: duration,
            timingFunction: .easeInOut
        )
    }

    /// Animate card hover
    func animateHover(intensity: Float = 0.02, duration: TimeInterval = 2.0) {
        let originalY = self.position.y

        // Create floating animation
        let animation = FromToByAnimation(
            name: "hover",
            from: Transform(translation: SIMD3(self.position.x, originalY - intensity, self.position.z)),
            to: Transform(translation: SIMD3(self.position.x, originalY + intensity, self.position.z)),
            duration: duration,
            bindTarget: .transform,
            repeatMode: .autoReverse
        )

        if let resource = try? AnimationResource.generate(with: animation) {
            self.playAnimation(resource)
        }
    }

    /// Animate card selection
    func animateSelection(selected: Bool, duration: TimeInterval = 0.3) {
        let targetScale: SIMD3<Float> = selected ? SIMD3(repeating: 1.15) : .one

        var transform = self.transform
        transform.scale = targetScale

        self.move(
            to: transform,
            relativeTo: self.parent,
            duration: duration,
            timingFunction: .spring()
        )
    }

    /// Animate card entrance
    func animateEntrance(delay: TimeInterval = 0) {
        self.scale = .zero

        var transform = self.transform
        transform.scale = .one

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.move(
                to: transform,
                relativeTo: self.parent,
                duration: 0.6,
                timingFunction: .easeOut
            )
        }
    }
}

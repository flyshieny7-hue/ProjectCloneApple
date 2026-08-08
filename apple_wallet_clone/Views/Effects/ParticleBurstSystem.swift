import SwiftUI

struct ParticleBurstSystem: View {
    @State private var particles: [Particle] = []
    @State private var isReducedMotion: Bool = false
    @State private var isLowPower: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(particle.opacity)
                        .blur(radius: isReducedMotion || isLowPower ? 0 : 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                spawnBurst(at: location, in: geo.size)
            }
        }
        .onAppear {
            isReducedMotion = reduceMotion
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func spawnBurst(at point: CGPoint, in size: CGSize) {
        guard !isReducedMotion && !isLowPower else { return }

        let count = 30
        let colors: [Color] = [.cyan, .purple, .pink, .yellow, .white]

        for i in 0..<count {
            let angle = Double(i) * (2 * .pi / Double(count))
            let velocity = CGFloat.random(in: 100...300)
            let dx = cos(angle) * velocity
            let dy = sin(angle) * velocity

            var particle = Particle(
                id: UUID(),
                position: point,
                velocity: CGVector(dx: dx, dy: dy),
                color: colors.randomElement()!,
                size: CGFloat.random(in: 4...12),
                opacity: 1.0,
                lifetime: Double.random(in: 0.5...1.5)
            )

            particles.append(particle)

            withAnimation(.easeOut(duration: particle.lifetime)) {
                if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                    particles[index].position.x += dx * 0.5
                    particles[index].position.y += dy * 0.5
                    particles[index].opacity = 0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + particle.lifetime) {
                particles.removeAll { $0.id == particle.id }
            }
        }
    }
}

struct Particle: Identifiable {
    let id: UUID
    var position: CGPoint
    var velocity: CGVector
    let color: Color
    let size: CGFloat
    var opacity: Double
    let lifetime: Double
}

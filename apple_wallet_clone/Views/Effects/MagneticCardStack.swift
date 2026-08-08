import SwiftUI

struct MagneticCardStack: View {
    let cards: [WalletCard]
    @State private var cardOffsets: [UUID: CGSize] = [:]
    @State private var dragState: [UUID: CGSize] = [:]
    @State private var isReducedMotion: Bool = false
    @State private var isLowPower: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                ForEach(cards) { card in
                    LiquidCardView(card: card)
                        .frame(width: 320, height: 200)
                        .offset(
                            x: (cardOffsets[card.id]?.width ?? 0) + (dragState[card.id]?.width ?? 0),
                            y: (cardOffsets[card.id]?.height ?? 0) + (dragState[card.id]?.height ?? 0)
                        )
                        .rotationEffect(
                            .degrees(Double((cardOffsets[card.id]?.width ?? 0) / 20))
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragState[card.id] = value.translation
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                        dragState[card.id] = .zero
                                    }
                                }
                        )
                        .onAppear {
                            // Initial magnetic spread
                            let index = cards.firstIndex(where: { $0.id == card.id }) ?? 0
                            let spread = CGFloat(index) * 30 - CGFloat(cards.count) * 15
                            cardOffsets[card.id] = CGSize(width: spread, height: CGFloat(index) * 10)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                isReducedMotion = reduceMotion
                isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                startMagneticAnimation(center: center)
            }
        }
    }

    private func startMagneticAnimation(center: CGPoint) {
        guard !isReducedMotion && !isLowPower else { return }

        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            for card in cards {
                guard let currentOffset = cardOffsets[card.id] else { continue }

                let attractionStrength: CGFloat = 0.02
                let targetX = currentOffset.width * (1 - attractionStrength)
                let targetY = currentOffset.height * (1 - attractionStrength)

                withAnimation(.linear(duration: 0.05)) {
                    cardOffsets[card.id] = CGSize(width: targetX, height: targetY)
                }
            }
        }
    }
}

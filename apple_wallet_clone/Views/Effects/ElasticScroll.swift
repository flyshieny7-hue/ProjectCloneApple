import SwiftUI

struct ElasticScroll<Content: View>: View {
    let content: Content
    @State private var scrollOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isReducedMotion: Bool = false
    @State private var isLowPower: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .offset(y: isReducedMotion || isLowPower ? 0 : elasticOffset(for: scrollOffset))
                    .scaleEffect(
                        isReducedMotion || isLowPower ? 1.0 : elasticScale(for: scrollOffset),
                        anchor: .center
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                scrollOffset = value.translation.height
                            }
                            .onEnded { value in
                                isDragging = false
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    scrollOffset = 0
                                }
                            }
                    )
            }
        }
        .onAppear {
            isReducedMotion = reduceMotion
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func elasticOffset(for offset: CGFloat) -> CGFloat {
        let resistance: CGFloat = 0.3
        return offset * resistance
    }

    private func elasticScale(for offset: CGFloat) -> CGFloat {
        let maxScale: CGFloat = 1.1
        let scale = 1 + abs(offset) / 1000
        return min(scale, maxScale)
    }
}

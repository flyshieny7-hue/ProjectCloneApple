import SwiftUI

struct MorphingTransitions: ViewModifier {
    let isActive: Bool
    @State private var morphProgress: CGFloat = 0
    @State private var isReducedMotion: Bool = false
    @State private var isLowPower: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .clipShape(MorphingShape(progress: isReducedMotion || isLowPower ? 1 : morphProgress))
            .opacity(isReducedMotion || isLowPower ? 1 : morphProgress)
            .scaleEffect(isReducedMotion || isLowPower ? 1 : 0.8 + 0.2 * morphProgress)
            .onAppear {
                isReducedMotion = reduceMotion
                isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                if !isReducedMotion && !isLowPower {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        morphProgress = 1
                    }
                } else {
                    morphProgress = 1
                }
            }
            .onChange(of: isActive) { newValue in
                if !isReducedMotion && !isLowPower {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        morphProgress = newValue ? 1 : 0
                    }
                } else {
                    morphProgress = newValue ? 1 : 0
                }
            }
    }
}

struct MorphingShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius = 20 * progress
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 0, y: cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        path.addLine(to: CGPoint(x: w - cornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w, y: cornerRadius),
            control: CGPoint(x: w, y: 0)
        )
        path.addLine(to: CGPoint(x: w, y: h - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: w - cornerRadius, y: h),
            control: CGPoint(x: w, y: h)
        )
        path.addLine(to: CGPoint(x: cornerRadius, y: h))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h - cornerRadius),
            control: CGPoint(x: 0, y: h)
        )
        path.closeSubpath()

        return path
    }
}

extension View {
    func morphingTransition(isActive: Bool) -> some View {
        modifier(MorphingTransitions(isActive: isActive))
    }
}

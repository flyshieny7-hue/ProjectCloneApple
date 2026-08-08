import SwiftUI

// MARK: - TutorialManager
@MainActor
final class TutorialManager: ObservableObject {
    @Published var isShowingTutorial: Bool = false
    @Published var currentHint: TutorialHint?
    @Published var completedHints: Set<String> = []
    @Published var hintHistory: [TutorialHint] = []

    private let completedKey = "completed_tutorial_hints"

    init() {
        loadCompletedHints()
    }

    func showHint(_ hint: TutorialHint) {
        guard !completedHints.contains(hint.id) else { return }
        currentHint = hint
        isShowingTutorial = true
    }

    func completeCurrentHint() {
        guard let hint = currentHint else { return }
        completedHints.insert(hint.id)
        hintHistory.append(hint)
        saveCompletedHints()

        withAnimation {
            currentHint = nil
            isShowingTutorial = false
        }
    }

    func skipTutorial() {
        withAnimation {
            currentHint = nil
            isShowingTutorial = false
        }
    }

    func resetAllHints() {
        completedHints.removeAll()
        hintHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: completedKey)
    }

    private func loadCompletedHints() {
        if let data = UserDefaults.standard.data(forKey: completedKey),
           let hints = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedHints = hints
        }
    }

    private func saveCompletedHints() {
        if let data = try? JSONEncoder().encode(completedHints) {
            UserDefaults.standard.set(data, forKey: completedKey)
        }
    }

    // Predefined hints
    static let walletSwipeHint = TutorialHint(
        id: "wallet_swipe",
        title: "Swipe to Browse",
        message: "Swipe left or right to browse through your cards. Tap to see details.",
        position: .bottom,
        targetFrame: nil,
        icon: "arrow.left.arrow.right"
    )

    static let addCardHint = TutorialHint(
        id: "add_card",
        title: "Add a Card",
        message: "Tap the + button to add a new card by scanning or manual entry.",
        position: .top,
        targetFrame: nil,
        icon: "plus.circle"
    )

    static let quickPayHint = TutorialHint(
        id: "quick_pay",
        title: "Quick Pay",
        message: "Double-tap the side button to pay with your default card.",
        position: .center,
        targetFrame: nil,
        icon: "wave.3.right"
    )

    static let budgetChartHint = TutorialHint(
        id: "budget_chart",
        title: "Budget Insights",
        message: "Tap any segment to see detailed spending in that category.",
        position: .bottom,
        targetFrame: nil,
        icon: "chart.pie"
    )
}

// MARK: - TutorialHint
struct TutorialHint: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let message: String
    let position: HintPosition
    let targetFrame: CGRect?
    let icon: String

    enum HintPosition: String, Codable {
        case top, bottom, center, left, right
    }
}

// MARK: - TutorialOverlay
struct TutorialOverlay: View {
    @EnvironmentObject var tutorialManager: TutorialManager
    @State private var showContent: Bool = false
    @State private var pulseAnimation: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background
                Color.black
                    .opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture {
                        tutorialManager.skipTutorial()
                    }

                // Highlight area (if target frame provided)
                if let targetFrame = tutorialManager.currentHint?.targetFrame {
                    highlightArea(frame: targetFrame, in: geometry)
                }

                // Hint content
                if let hint = tutorialManager.currentHint {
                    hintContent(hint, in: geometry)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                showContent = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }

    // MARK: - Highlight Area
    private func highlightArea(frame: CGRect, in geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: frame.width + 16, height: frame.height + 16)
            .position(x: frame.midX, y: frame.midY)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(pulseAnimation ? 0.8 : 0.3), lineWidth: 2)
                    .frame(width: frame.width + 16, height: frame.height + 16)
                    .position(x: frame.midX, y: frame.midY)
            )
            .background(
                // Cutout effect
                Rectangle()
                    .fill(Color.black.opacity(0.7))
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .frame(width: frame.width + 16, height: frame.height + 16)
                                    .position(x: frame.midX, y: frame.midY)
                                    .blendMode(.destinationOut)
                            )
                    )
                    .ignoresSafeArea()
            )
    }

    // MARK: - Hint Content
    private func hintContent(_ hint: TutorialHint, in geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: hint.icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)

            // Title
            Text(hint.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            // Message
            Text(hint.message)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            // Action buttons
            HStack(spacing: 16) {
                Button("Skip") {
                    tutorialManager.skipTutorial()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

                Button("Got it") {
                    tutorialManager.completeCurrentHint()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(24)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.1))
                .background(.ultraThinMaterial)
                .cornerRadius(24)
        )
        .padding(.horizontal, 24)
        .position(position(for: hint.position, in: geometry))
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 30)
    }

    private func position(for position: TutorialHint.HintPosition, in geometry: GeometryProxy) -> CGPoint {
        let width = geometry.size.width
        let height = geometry.size.height

        switch position {
        case .top:
            return CGPoint(x: width / 2, y: height * 0.25)
        case .bottom:
            return CGPoint(x: width / 2, y: height * 0.75)
        case .center:
            return CGPoint(x: width / 2, y: height / 2)
        case .left:
            return CGPoint(x: width * 0.25, y: height / 2)
        case .right:
            return CGPoint(x: width * 0.75, y: height / 2)
        }
    }
}

// MARK: - CoachMark Modifier
struct CoachMarkModifier: ViewModifier {
    let hint: TutorialHint
    @EnvironmentObject var tutorialManager: TutorialManager

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: CoachMarkFrameKey.self, value: geometry.frame(in: .global))
                }
            )
            .onPreferenceChange(CoachMarkFrameKey.self) { frame in
                // Could trigger tutorial when frame is visible
            }
    }
}

struct CoachMarkFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    func coachMark(hint: TutorialHint) -> some View {
        modifier(CoachMarkModifier(hint: hint))
    }
}

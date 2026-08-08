import SwiftUI

// MARK: - OnboardingFlow
/// 5-step onboarding with animations
struct OnboardingFlow: View {
    @Binding var isPresented: Bool
    @State private var currentStep: Int = 0
    @State private var isAnimating: Bool = false
    @State private var showContent: Bool = false
    @State private var progress: CGFloat = 0

    private let totalSteps = 5

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(hex: "1a1a2e"),
                    Color(hex: "16213e"),
                    Color(hex: "0f3460")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // Page content
                TabView(selection: $currentStep) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        OnboardingStepView(step: OnboardingStep.allCases[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentStep)

                // Bottom controls
                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6)) {
                showContent = true
            }
        }
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentStep)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        HStack {
            // Skip button
            if currentStep < totalSteps - 1 {
                Button("Skip") {
                    withAnimation {
                        isPresented = false
                        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            } else {
                Spacer().frame(width: 60)
            }

            Spacer()

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(currentStep == index ? Color.white : Color.white.opacity(0.3))
                        .frame(width: currentStep == index ? 10 : 8, height: currentStep == index ? 10 : 8)
                        .animation(.spring(response: 0.3), value: currentStep)
                }
            }

            Spacer()

            // Next/Done button
            Button(action: {
                if currentStep < totalSteps - 1 {
                    withAnimation {
                        currentStep += 1
                    }
                } else {
                    withAnimation {
                        isPresented = false
                        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Text(currentStep < totalSteps - 1 ? "Next" : "Get Started")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: currentStep < totalSteps - 1 ? "arrow.right" : "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(24)
            }
        }
    }
}

// MARK: - OnboardingStep
enum OnboardingStep: CaseIterable {
    case welcome
    case cards
    case payments
    case budget
    case security

    var title: String {
        switch self {
        case .welcome: return "Welcome to Wallet"
        case .cards: return "Your Cards, Organized"
        case .payments: return "Quick & Secure Payments"
        case .budget: return "Track Your Budget"
        case .security: return "Bank-Grade Security"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "The smartest way to manage your money, cards, and payments all in one place."
        case .cards:
            return "Add all your credit, debit, and loyalty cards. Access them instantly with a tap."
        case .payments:
            return "Pay anyone, anywhere. Use NFC, QR codes, or send money directly from the app."
        case .budget:
            return "Set spending limits, track categories, and get insights to save more every month."
        case .security:
            return "Protected by Face ID, encryption, and real-time fraud monitoring. Your money is safe."
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "wallet.pass.fill"
        case .cards: return "creditcard.fill"
        case .payments: return "wave.3.right"
        case .budget: return "chart.pie.fill"
        case .security: return "lock.shield.fill"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .welcome: return [.cyan, .blue]
        case .cards: return [.orange, .red]
        case .payments: return [.green, .teal]
        case .budget: return [.purple, .pink]
        case .security: return [.indigo, .purple]
        }
    }
}

// MARK: - OnboardingStepView
struct OnboardingStepView: View {
    let step: OnboardingStep
    @State private var isVisible: Bool = false
    @State private var iconScale: CGFloat = 0.5
    @State private var iconRotation: Double = -30

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated icon
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        LinearGradient(
                            colors: step.gradientColors.map { $0.opacity(0.3) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 40)

                // Icon container
                Circle()
                    .fill(
                        LinearGradient(
                            colors: step.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .overlay(
                        Image(systemName: step.icon)
                            .font(.system(size: 60, weight: .light))
                            .foregroundColor(.white)
                    )
                    .shadow(color: step.gradientColors[0].opacity(0.5), radius: 20, x: 0, y: 10)
                    .scaleEffect(iconScale)
                    .rotationEffect(.degrees(iconRotation))
            }

            // Text content
            VStack(spacing: 16) {
                Text(step.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 20)

                Text(step.subtitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 20)
            }

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                iconScale = 1.0
                iconRotation = 0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                isVisible = true
            }
        }
        .onDisappear {
            isVisible = false
            iconScale = 0.5
            iconRotation = -30
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

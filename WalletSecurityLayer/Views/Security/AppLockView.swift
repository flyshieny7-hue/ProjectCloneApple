import SwiftUI

/// Экран блокировки с анимированным замком
struct AppLockView: View {
    @StateObject private var authManager = BiometricAuthManager.shared
    @State private var pinCode: String = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var isShaking = false
    @State private var showPinEntry = false
    @State private var lockScale: CGFloat = 1.0
    @State private var lockRotation: Double = 0
    @State private var isUnlocking = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var pinDots: [PinDotState] = Array(repeating: .empty, count: 6)

    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    private let haptic = UINotificationFeedbackGenerator()

    enum PinDotState {
        case empty, filled, error
    }

    var body: some View {
        ZStack {
            // Фон с градиентом
            LinearGradient(
                colors: [Color.black, Color(.systemGray6).opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Blur overlay для защиты от скриншотов
            ScreenshotProtectionView()

            VStack(spacing: 40) {
                Spacer()

                // Анимированный замок
                LockAnimationView(
                    isLocked: !authManager.isAuthenticated,
                    scale: $lockScale,
                    rotation: $lockRotation
                )
                .frame(width: 120, height: 120)

                VStack(spacing: 12) {
                    Text("Wallet Locked")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(authManager.biometricType == .none ? "Введите PIN-код" : "Используйте Face ID или PIN")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // PIN dots
                HStack(spacing: 16) {
                    ForEach(0..<6, id: \.self) { index in
                        PinDotView(state: pinDots[index])
                    }
                }
                .padding(.vertical, 20)
                .offset(x: shakeOffset)

                // Клавиатура или биометрия
                if showPinEntry || authManager.biometricType == .none {
                    PinPadView(pinCode: $pinCode, onSubmit: validatePIN)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Button(action: authenticateWithBiometrics) {
                        HStack(spacing: 12) {
                            Image(systemName: authManager.biometricType.icon)
                                .font(.system(size: 24))
                            Text("Разблокировать")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor)
                        )
                    }
                    .padding(.horizontal, 32)

                    Button("Использовать PIN") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showPinEntry = true
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding()
        }
        .onChange(of: pinCode) { _, newValue in
            updatePinDots(for: newValue)
            if newValue.count == 6 {
                validatePIN()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                authManager.lock()
                pinCode = ""
                showPinEntry = false
            }
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func updatePinDots(for code: String) {
        for i in 0..<6 {
            if i < code.count {
                pinDots[i] = .filled
            } else {
                pinDots[i] = .empty
            }
        }
    }

    private func authenticateWithBiometrics() {
        Task {
            let result = await authManager.authenticateWithBiometrics()
            handleAuthResult(result)
        }
    }

    private func validatePIN() {
        guard pinCode.count >= 4 else { return }

        Task {
            let result = await authManager.authenticateWithPIN(pinCode)
            handleAuthResult(result)
        }
    }

    private func handleAuthResult(_ result: Result<Void, BiometricAuthManager.AuthenticationError>) {
        switch result {
        case .success:
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                lockScale = 0.8
                lockRotation = -10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    lockScale = 1.2
                    lockRotation = 0
                }
            }
            haptic.notificationOccurred(.success)

        case .failure(let error):
            haptic.notificationOccurred(.error)
            errorMessage = error.errorDescription ?? "Ошибка аутентификации"
            showError = true

            // Shake animation
            withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                shakeOffset = 10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                    shakeOffset = -10
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                    shakeOffset = 0
                }
                pinCode = ""
                for i in 0..<6 {
                    pinDots[i] = .empty
                }
            }
        }
    }
}

// MARK: - Lock Animation View

struct LockAnimationView: View {
    let isLocked: Bool
    @Binding var scale: CGFloat
    @Binding var rotation: Double

    @State private var shackleOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Корпус замка
            RoundedRectangle(cornerRadius: 12)
                .fill(isLocked ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                .frame(width: 80, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            // Дужка
            LockShackleView(isLocked: isLocked)
                .offset(y: -30 + shackleOffset)

            // Иконка
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .onChange(of: isLocked) { _, newValue in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                shackleOffset = newValue ? 0 : -15
            }
        }
    }
}

struct LockShackleView: View {
    let isLocked: Bool

    var body: some View {
        Path { path in
            let width: CGFloat = 50
            let height: CGFloat = 40
            let radius: CGFloat = 15

            path.move(to: CGPoint(x: 0, y: height))
            path.addLine(to: CGPoint(x: 0, y: radius))
            path.addArc(
                center: CGPoint(x: radius, y: radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: width, y: height))
        }
        .stroke(
            isLocked ? Color.red.opacity(0.8) : Color.green.opacity(0.8),
            style: StrokeStyle(lineWidth: 8, lineCap: .round)
        )
        .frame(width: 50, height: 40)
    }
}

// MARK: - PIN Dot

struct PinDotView: View {
    let state: AppLockView.PinDotState

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(state == .filled ? 1.2 : 1.0)
            .animation(.spring(response: 0.2), value: state)
    }

    private var fillColor: Color {
        switch state {
        case .empty: return Color.gray.opacity(0.3)
        case .filled: return Color.accentColor
        case .error: return Color.red
        }
    }
}

// MARK: - PIN Pad

struct PinPadView: View {
    @Binding var pinCode: String
    let onSubmit: () -> Void

    private let columns = Array(repeating: GridItem(.flexible()), count: 3)
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(keys, id: \.self) { key in
                PinKeyButton(key: key) {
                    handleKeyTap(key)
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private func handleKeyTap(_ key: String) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        if key == "⌫" {
            if !pinCode.isEmpty {
                pinCode.removeLast()
            }
        } else if !key.isEmpty && pinCode.count < 6 {
            pinCode.append(key)
        }
    }
}

struct PinKeyButton: View {
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 72, height: 72)

                if key == "⌫" {
                    Image(systemName: "delete.backward.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.primary)
                } else {
                    Text(key)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
        }
        .disabled(key.isEmpty && key != "⌫")
        .opacity(key.isEmpty && key != "⌫" ? 0 : 1)
    }
}

// MARK: - Screenshot Protection

struct ScreenshotProtectionView: View {
    @State private var isScreenCaptured = false

    var body: some View {
        Group {
            if isScreenCaptured {
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        VStack {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.gray)
                            Text("Контент скрыт")
                                .font(.headline)
                                .foregroundStyle(.gray)
                                .padding(.top, 16)
                        }
                    )
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isScreenCaptured = UIScreen.main.isCaptured
            }
        }
        .onAppear {
            isScreenCaptured = UIScreen.main.isCaptured
        }
    }
}

#Preview {
    AppLockView()
}

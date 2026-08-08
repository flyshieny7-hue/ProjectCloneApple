import SwiftUI

// MARK: - AccessibleButton
/// Универсальная кнопка с полной поддержкой доступности.
/// Поддерживает VoiceOver, Switch Control, Voice Control и Dynamic Type.
struct AccessibleButton: View {

    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed: Bool = false

    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        case ghost
    }

    var body: some View {
        Button(action: {
            action()
            provideHapticFeedback()
        }) {
            HStack(spacing: dynamicTypeSize >= .accessibility2 ? 12 : 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: dynamicTypeSize >= .accessibility2 ? 22 : 18, weight: .semibold))
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.system(size: dynamicTypeSize >= .accessibility2 ? 20 : 17, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, dynamicTypeSize >= .accessibility3 ? 18 : 14)
            .padding(.horizontal, 20)
            .background(buttonBackground)
            .foregroundColor(buttonForeground)
            .overlay(buttonBorder)
            .cornerRadius(12)
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .pressEvents {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.1)) {
                isPressed = false
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint("Двойное нажатие для выполнения")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Style Configuration
    @ViewBuilder
    private var buttonBackground: some View {
        switch style {
        case .primary:
            accessibilityManager.isHighContrastEnabled ? Color.black : Color.blue
        case .secondary:
            Color(.secondarySystemBackground)
        case .destructive:
            accessibilityManager.isHighContrastEnabled ? Color(red: 0.7, green: 0, blue: 0) : Color.red
        case .ghost:
            Color.clear
        }
    }

    private var buttonForeground: Color {
        switch style {
        case .primary:
            accessibilityManager.isHighContrastEnabled ? Color(red: 1, green: 1, blue: 0.85) : .white
        case .secondary, .ghost:
            .primary
        case .destructive:
            accessibilityManager.isHighContrastEnabled ? Color(red: 1, green: 1, blue: 0.85) : .white
        }
    }

    @ViewBuilder
    private var buttonBorder: some View {
        if accessibilityManager.isHighContrastEnabled || style == .ghost {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style == .ghost ? Color.primary : (style == .primary ? Color.white : Color.black),
                    lineWidth: accessibilityManager.isHighContrastEnabled ? 3 : 1
                )
        }
    }

    private func provideHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - PressEvents Modifier
struct PressEvents: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        onPress()
                    }
                    .onEnded { _ in
                        onRelease()
                    }
            )
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEvents(onPress: onPress, onRelease: onRelease))
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        AccessibleButton(title: "Отправить перевод", icon: "arrow.up.circle.fill", style: .primary, action: {})
        AccessibleButton(title: "Отмена", icon: "xmark.circle", style: .secondary, action: {})
        AccessibleButton(title: "Удалить карту", icon: "trash", style: .destructive, action: {})
        AccessibleButton(title: "Подробнее", icon: "info.circle", style: .ghost, action: {})
    }
    .padding()
    .environmentObject(AccessibilityManager.shared)
}

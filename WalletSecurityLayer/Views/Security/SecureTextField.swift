import SwiftUI

/// Защищенное поле ввода для чувствительных данных (CVV, PIN, номер карты)
struct SecureTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var maxLength: Int? = nil
    var keyboardType: UIKeyboardType = .numberPad
    var isSecure: Bool = true
    var onCommit: (() -> Void)? = nil

    @State private var isRevealed = false
    @State private var isFocused = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ZStack {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                            .textContentType(.oneTimeCode)
                            .keyboardType(keyboardType)
                            .onChange(of: text) { _, newValue in
                                limitText(newValue)
                            }
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .onChange(of: text) { _, newValue in
                                limitText(newValue)
                            }
                    }
                }
                .font(.system(.body, design: .monospaced))

                if isSecure {
                    Button(action: toggleReveal) {
                        Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            )
        }
    }

    private func toggleReveal() {
        haptic.impactOccurred()
        withAnimation(.easeInOut(duration: 0.15)) {
            isRevealed.toggle()
        }
    }

    private func limitText(_ newValue: String) {
        if let max = maxLength {
            if newValue.count > max {
                text = String(newValue.prefix(max))
            }
        }
    }
}

// MARK: - Card Number Field

struct CardNumberField: View {
    @Binding var cardNumber: String
    @State private var displayText: String = ""

    var body: some View {
        SecureTextField(
            title: "Номер карты",
            placeholder: "0000 0000 0000 0000",
            text: $displayText,
            maxLength: 19,
            keyboardType: .numberPad,
            isSecure: true
        )
        .onChange(of: displayText) { _, newValue in
            let cleaned = newValue.filter { $0.isNumber }
            var formatted = ""
            for (index, char) in cleaned.enumerated() {
                if index > 0 && index % 4 == 0 {
                    formatted += " "
                }
                formatted.append(char)
            }
            displayText = formatted
            cardNumber = cleaned
        }
    }
}

// MARK: - CVV Field

struct CVVField: View {
    @Binding var cvv: String

    var body: some View {
        SecureTextField(
            title: "CVV/CVC",
            placeholder: "123",
            text: $cvv,
            maxLength: 4,
            keyboardType: .numberPad,
            isSecure: true
        )
    }
}

// MARK: - PIN Field

struct PINField: View {
    @Binding var pin: String
    var confirmPin: Binding<String>? = nil
    var showMismatch: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            SecureTextField(
                title: "PIN-код",
                placeholder: "••••",
                text: $pin,
                maxLength: 6,
                keyboardType: .numberPad,
                isSecure: true
            )

            if let confirm = confirmPin {
                SecureTextField(
                    title: "Подтвердите PIN",
                    placeholder: "••••",
                    text: confirm,
                    maxLength: 6,
                    keyboardType: .numberPad,
                    isSecure: true
                )

                if showMismatch && pin != confirm.wrappedValue && !confirm.wrappedValue.isEmpty {
                    Text("PIN-коды не совпадают")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SecureTextField(
            title: "Test",
            placeholder: "Enter text",
            text: .constant(""),
            isSecure: true
        )

        CardNumberField(cardNumber: .constant(""))
        CVVField(cvv: .constant(""))
        PINField(pin: .constant(""), confirmPin: .constant(""), showMismatch: true)
    }
    .padding()
}

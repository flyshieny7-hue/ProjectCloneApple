import SwiftUI

/// Компонент карты с маскированием номера, тапом для reveal и haptic feedback
struct SecureCardView: View {
    let card: Card
    @State private var isRevealed = false
    @State private var cardNumber: String = ""
    @State private var cvv: String = ""
    @State private var isLoading = false
    @State private var showCopyToast = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let selectionHaptic = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Верхняя часть карты
            HStack {
                Image(systemName: cardTypeIcon)
                    .font(.title2)
                    .foregroundStyle(.white)
                Spacer()
                Text(card.cardType?.rawValue ?? "CARD")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
                    .tracking(2)
            }
            .padding([.horizontal, .top], 20)

            Spacer()

            // Чип
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 40, height: 30)
                    .overlay(
                        HStack(spacing: 2) {
                            Rectangle()
                                .fill(Color.orange.opacity(0.5))
                                .frame(width: 1)
                            Rectangle()
                                .fill(Color.orange.opacity(0.5))
                                .frame(width: 1)
                        }
                    )
                Spacer()
            }
            .padding(.horizontal, 20)

            Spacer()

            // Номер карты
            Button(action: toggleReveal) {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { group in
                        Text(cardNumberGroup(at: group))
                            .font(.system(size: 20, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(minWidth: 50)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            // Нижняя часть
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CARD HOLDER")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1)
                    Text(card.cardholderName.uppercased())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("EXPIRES")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1)
                    Text("\(card.expiryMonth)/\(card.expiryYear)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }

                if isRevealed {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("CVV")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .tracking(1)
                        Text(cvv)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 12)
                }
            }
            .padding(20)
        }
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .overlay(
            // Security badge
            Group {
                if isRevealed {
                    HStack {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                        Text("Visible")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            , alignment: .topTrailing
        )
        .onTapGesture {
            toggleReveal()
        }
        .onLongPressGesture {
            copyCardNumber()
        }
        .onAppear {
            loadMaskedData()
        }
        .overlay(
            // Copy toast
            Group {
                if showCopyToast {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc.fill")
                            Text("Номер скопирован")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            , alignment: .top
        )
    }

    // MARK: - Computed Properties

    private var cardTypeIcon: String {
        switch card.cardType {
        case .visa: return "creditcard.fill"
        case .mastercard: return "creditcard.fill"
        case .amex: return "creditcard.fill"
        case .discover: return "creditcard.fill"
        default: return "creditcard.fill"
        }
    }

    private var cardGradient: LinearGradient {
        switch card.cardType {
        case .visa:
            return LinearGradient(colors: [Color.blue.opacity(0.9), Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mastercard:
            return LinearGradient(colors: [Color.orange.opacity(0.9), Color.red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .amex:
            return LinearGradient(colors: [Color.cyan.opacity(0.9), Color.blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Color.gray.opacity(0.8), Color.black.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - Methods

    private func loadMaskedData() {
        // Показываем маскированный номер (последние 4 из hash или из SwiftData)
        if let lastFour = card.cardNumberHash.suffix(4) {
            cardNumber = "•••• •••• •••• \(lastFour)"
        } else {
            cardNumber = "•••• •••• •••• ••••"
        }
        cvv = "•••"
    }

    private func toggleReveal() {
        haptic.impactOccurred()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isRevealed.toggle()
        }

        if isRevealed {
            // Загружаем реальные данные из Keychain
            isLoading = true
            Task {
                if let number = KeychainManager.shared.retrieveCardNumber(cardID: card.id) {
                    let formatted = formatCardNumber(number)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.cardNumber = formatted
                        }
                    }
                }
                if let cvvValue = KeychainManager.shared.retrieveCVV(cardID: card.id) {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.cvv = cvvValue
                        }
                    }
                }
                isLoading = false
            }

            // Auto-hide через 10 секунд
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if isRevealed {
                    withAnimation(.spring(response: 0.3)) {
                        isRevealed = false
                    }
                    loadMaskedData()
                }
            }
        } else {
            loadMaskedData()
        }
    }

    private func formatCardNumber(_ number: String) -> String {
        let cleaned = number.filter { $0.isNumber }
        var result = ""
        for (index, char) in cleaned.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }

    private func cardNumberGroup(at index: Int) -> String {
        let groups = cardNumber.split(separator: " ")
        if index < groups.count {
            return String(groups[index])
        }
        return "••••"
    }

    private func copyCardNumber() {
        guard isRevealed else { return }
        let cleaned = cardNumber.filter { $0.isNumber }
        UIPasteboard.general.string = cleaned

        selectionHaptic.selectionChanged()

        withAnimation {
            showCopyToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopyToast = false
            }
        }
    }
}

// MARK: - Card Type

enum CardType: String, Codable, CaseIterable {
    case visa = "VISA"
    case mastercard = "MASTERCARD"
    case amex = "AMEX"
    case discover = "DISCOVER"
    case other = "OTHER"
}

// MARK: - Preview Helper

#Preview {
    SecureCardView(card: Card.preview)
        .padding()
}

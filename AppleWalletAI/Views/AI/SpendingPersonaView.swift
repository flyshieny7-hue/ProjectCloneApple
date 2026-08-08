import SwiftUI

/// AI-аватар, который комментирует траты (fun mode)
@available(iOS 26.0, *)
public struct SpendingPersonaView: View {

    @StateObject private var persona = SpendingPersona()
    @StateObject private var insightsEngine = SpendingInsightsEngine()

    @State private var userMessage = ""
    @State private var messages: [PersonaMessage] = []
    @State private var isTyping = false
    @State private var selectedMood: PersonaMood = .chill
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Persona Header
                PersonaHeader(persona: persona, mood: selectedMood)

                // MARK: - Chat Area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                            }

                            if isTyping {
                                TypingIndicator()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // MARK: - Quick Actions
                QuickActionsBar(persona: persona) { action in
                    handleQuickAction(action)
                }

                // MARK: - Input Area
                MessageInputBar(message: $userMessage, onSend: sendMessage)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Spending Persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                PersonaSettingsView(mood: $selectedMood)
            }
            .task {
                await persona.initialize()
                addWelcomeMessage()
            }
        }
    }

    private func sendMessage() {
        guard !userMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let userMsg = PersonaMessage(
            id: UUID(),
            text: userMessage,
            sender: .user,
            timestamp: Date()
        )
        messages.append(userMsg)

        let query = userMessage
        userMessage = ""
        isTyping = true

        Task {
            let response = await persona.respond(to: query, mood: selectedMood)
            await MainActor.run {
                isTyping = false
                messages.append(response)
            }
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        isTyping = true
        Task {
            let response = await persona.handleQuickAction(action, mood: selectedMood)
            await MainActor.run {
                isTyping = false
                messages.append(response)
            }
        }
    }

    private func addWelcomeMessage() {
        let welcome = PersonaMessage(
            id: UUID(),
            text: persona.generateWelcomeMessage(mood: selectedMood),
            sender: .persona,
            timestamp: Date(),
            mood: selectedMood
        )
        messages.append(welcome)
    }
}

// MARK: - Persona Header

@available(iOS 26.0, *)
struct PersonaHeader: View {
    @ObservedObject var persona: SpendingPersona
    let mood: PersonaMood

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Animated background
                Circle()
                    .fill(mood.gradient)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(mood.primaryColor.opacity(0.3), lineWidth: 3)
                    )

                Text(mood.avatar)
                    .font(.system(size: 50))
                    .scaleEffect(persona.isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: persona.isAnimating)
            }

            Text(persona.name)
                .font(.headline)

            Text(persona.currentStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Message Bubble

@available(iOS 26.0, *)
struct MessageBubble: View {
    let message: PersonaMessage

    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.sender == .user ? Color.blue.opacity(0.15) : Color(.secondarySystemBackground))
                    .foregroundStyle(message.sender == .user ? .primary : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(message.sender == .user ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
                    )

                if let mood = message.mood {
                    HStack(spacing: 4) {
                        Text(mood.rawValue)
                            .font(.caption2)
                        Text("•")
                        Text(message.timestamp, style: .time)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if message.sender == .persona {
                Spacer(minLength: 60)
            }
        }
        .id(message.id)
    }
}

// MARK: - Typing Indicator

@available(iOS 26.0, *)
struct TypingIndicator: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .offset(y: offset)
                        .animation(
                            .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                            value: offset
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
        .onAppear { offset = -4 }
    }
}

// MARK: - Quick Actions Bar

@available(iOS 26.0, *)
struct QuickActionsBar: View {
    let persona: SpendingPersona
    let onAction: (QuickAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickAction.allCases, id: \.self) { action in
                    Button(action: { onAction(action) }) {
                        HStack(spacing: 4) {
                            Image(systemName: action.icon)
                            Text(action.displayName)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .tint(.primary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Message Input Bar

@available(iOS 26.0, *)
struct MessageInputBar: View {
    @Binding var message: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask your spending persona...", text: $message, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(message.isEmpty ? .secondary : .blue)
            }
            .disabled(message.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Persona Settings

@available(iOS 26.0, *)
struct PersonaSettingsView: View {
    @Binding var mood: PersonaMood
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Personality") {
                    ForEach(PersonaMood.allCases, id: \.self) { m in
                        Button(action: { mood = m; dismiss() }) {
                            HStack {
                                Text(m.avatar)
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text(m.rawValue.capitalized)
                                        .font(.headline)
                                    Text(m.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if mood == m {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }

                Section("About") {
                    Text("Your Spending Persona uses on-device AI to analyze your transactions and provide personalized commentary. All data stays on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Persona Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - SpendingPersona Engine

@available(iOS 26.0, *)
public final class SpendingPersona: ObservableObject {

    @Published public var name = "Fin"
    @Published public var currentStatus = "Analyzing your spending patterns..."
    @Published public var isAnimating = false

    private let transactionService: TransactionService
    private let insightsEngine: SpendingInsightsEngine
    private let budgetPrediction: BudgetPrediction

    private var recentTransactions: [Transaction] = []
    private var lastAnalysis: PersonaAnalysis?

    public init(
        transactionService: TransactionService = .shared,
        insightsEngine: SpendingInsightsEngine = SpendingInsightsEngine(),
        budgetPrediction: BudgetPrediction = BudgetPrediction()
    ) {
        self.transactionService = transactionService
        self.insightsEngine = insightsEngine
        self.budgetPrediction = budgetPrediction
    }

    public func initialize() async {
        await MainActor.run {
            isAnimating = true
        }

        // Загружаем данные
        recentTransactions = await transactionService.fetchLast30Days()

        // Генерируем анализ
        lastAnalysis = generateAnalysis()

        await MainActor.run {
            currentStatus = generateStatusMessage()
        }
    }

    public func respond(to query: String, mood: PersonaMood) async -> PersonaMessage {
        let lowercased = query.lowercased()

        // Определяем интент запроса
        let responseText: String

        if lowercased.contains("how much") || lowercased.contains("сколько") || lowercased.contains("spent") {
            responseText = respondToSpendingQuery(lowercased, mood: mood)
        } else if lowercased.contains("budget") || lowercased.contains("бюджет") {
            responseText = respondToBudgetQuery(mood: mood)
        } else if lowercased.contains("save") || lowercased.contains("экономить") || lowercased.contains("tip") {
            responseText = respondToSavingsTip(mood: mood)
        } else if lowercased.contains("coffee") || lowercased.contains("кофе") || lowercased.contains("starbucks") {
            responseText = respondToCoffeeQuery(mood: mood)
        } else if lowercased.contains("hello") || lowercased.contains("привет") || lowercased.contains("hi") {
            responseText = generateWelcomeMessage(mood: mood)
        } else {
            responseText = respondToGeneralQuery(lowercased, mood: mood)
        }

        // Simulate thinking delay
        try? await Task.sleep(nanoseconds: 500_000_000 + UInt64.random(in: 0...1_000_000_000))

        return PersonaMessage(
            id: UUID(),
            text: responseText,
            sender: .persona,
            timestamp: Date(),
            mood: mood
        )
    }

    public func handleQuickAction(_ action: QuickAction, mood: PersonaMood) async -> PersonaMessage {
        let responseText: String

        switch action {
        case .roastMe:
            responseText = generateRoast(mood: mood)
        case .spendingSummary:
            responseText = generateSpendingSummary(mood: mood)
        case .savingsTips:
            responseText = generateSavingsTips(mood: mood)
        case .budgetStatus:
            responseText = generateBudgetStatus(mood: mood)
        case .funFact:
            responseText = generateFunFact(mood: mood)
        }

        try? await Task.sleep(nanoseconds: 800_000_000)

        return PersonaMessage(
            id: UUID(),
            text: responseText,
            sender: .persona,
            timestamp: Date(),
            mood: mood
        )
    }

    public func generateWelcomeMessage(mood: PersonaMood) -> String {
        let greetings = [
            "Hey there! I'm Fin, your spending sidekick.",
            "What's up! Ready to talk money?",
            "Hello! Let's see how your wallet is doing today.",
            "Привет! Я Fin, твой финансовый помощник.",
        ]

        let greeting = greetings.randomElement()!

        switch mood {
        case .chill:
            return "\(greeting) No pressure, just here to help you stay on track."
        case .sassy:
            return "\(greeting) Brace yourself, we're about to look at some numbers."
        case .coach:
            return "\(greeting) Let's crush those financial goals together!"
        case .zen:
            return "\(greeting) Take a deep breath. Your money and I are friends."
        case .roast:
            return "\(greeting) Oh boy... let's see what you've been up to with that credit card."
        }
    }

    // MARK: - Response Generators

    private func respondToSpendingQuery(_ query: String, mood: PersonaMood) -> String {
        let total = recentTransactions.reduce(0) { $0 + $1.amount }
        let count = recentTransactions.count

        switch mood {
        case .chill:
            return "You've spent \(formatCurrency(total)) across \(count) transactions recently. Not too shabby!"
        case .sassy:
            return "Oh wow, \(formatCurrency(total)) in \(count) transactions? Someone's been busy!"
        case .coach:
            return "Great question! You've invested \(formatCurrency(total)) in \(count) transactions. Every dollar tells a story — what's yours?"
        case .zen:
            return "\(formatCurrency(total)) has flowed through your accounts. Like water, money comes and goes. The key is awareness."
        case .roast:
            return "\(formatCurrency(total))?! In \(count) transactions?! Do you even check your balance before tapping that card?"
        }
    }

    private func respondToBudgetQuery(mood: PersonaMood) -> String {
        guard let status = lastAnalysis?.budgetStatus else {
            return "I'm still crunching the numbers on your budget..."
        }

        switch mood {
        case .chill:
            return status == .onTrack 
                ? "You're cruising comfortably within budget. Keep it up!"
                : "Hmm, might want to ease up a bit. Your budget's feeling the heat."
        case .sassy:
            return status == .onTrack
                ? "Look at you, actually sticking to a budget! I'm impressed."
                : "Your budget called. It's not angry, just disappointed."
        case .coach:
            return status == .onTrack
                ? "EXCELLENT! You're dominating your budget. This is what discipline looks like!"
                : "We need to regroup. Your budget needs attention — but I believe in you!"
        case .zen:
            return "Your budget is a garden. Right now it's \(status.displayName.lowercased()). Tend to it with mindfulness."
        case .roast:
            return status == .onTrack
                ? "Wait... you're actually ON budget? Did you forget to buy something?"
                : "Your budget didn't just break, it shattered into a million pieces. Nice job."
        }
    }

    private func respondToSavingsTip(mood: PersonaMood) -> String {
        let tips = [
            "Try the 24-hour rule: wait a day before any non-essential purchase over $50.",
            "Your coffee habit costs about $150/month. Brewing at home could save you $1,800/year!",
            "Set up auto-transfer to savings on payday. You can't spend what you don't see.",
            "Review your subscriptions — you might be paying for services you forgot about.",
            "Meal prep on Sundays. It'll save you both money and decision fatigue.",
        ]

        let tip = tips.randomElement()!

        switch mood {
        case .chill: return "Here's a chill tip: \(tip)"
        case .sassy: return "Okay fine, I'll help: \(tip)"
        case .coach: return "PRO TIP: \(tip) You've got this!"
        case .zen: return "A gentle suggestion: \(tip)"
        case .roast: return "Since you clearly need help: \(tip)"
        }
    }

    private func respondToCoffeeQuery(mood: PersonaMood) -> String {
        let coffeeTx = recentTransactions.filter {
            $0.merchantName.lowercased().contains("starbucks") ||
            $0.merchantName.lowercased().contains("coffee")
        }
        let coffeeTotal = coffeeTx.reduce(0) { $0 + $1.amount }
        let count = coffeeTx.count

        switch mood {
        case .chill:
            return "\(count) coffee runs for \(formatCurrency(coffeeTotal)). Hey, caffeine is a valid expense."
        case .sassy:
            return "\(count) coffees?! Your bloodstream is 90% espresso at this point. That's \(formatCurrency(coffeeTotal)) worth of caffeine."
        case .coach:
            return "\(count) coffees = \(formatCurrency(coffeeTotal)). That's \(formatCurrency(coffeeTotal * 12)) per year! Could we optimize this?"
        case .zen:
            return "\(count) moments of caffeinated mindfulness. \(formatCurrency(coffeeTotal)) for peace of mind."
        case .roast:
            return "You spent \(formatCurrency(coffeeTotal)) on bean water. \(count) times. I have no words."
        }
    }

    private func respondToGeneralQuery(_ query: String, mood: PersonaMood) -> String {
        let responses = [
            "I'm not sure I understood that, but I'm here to help with your spending!",
            "Hmm, that's a new one. Ask me about your budget, spending, or savings tips!",
            "My AI brain is still learning. Try asking about your recent transactions!",
        ]

        switch mood {
        case .chill: return responses[0]
        case .sassy: return "Uh, I have no idea what you're talking about. Try 'how much did I spend?'"
        case .coach: return "I didn't catch that, but I'm ready to coach you! What would you like to know?"
        case .zen: return "The answer lies within... but also, could you rephrase that?"
        case .roast: return "That made zero sense. Ask me something about money, genius."
        }
    }

    private func generateRoast(mood: PersonaMood) -> String {
        guard let analysis = lastAnalysis else { return "Still analyzing your spending..." }

        let roasts = [
            "You spent \(formatCurrency(analysis.topCategoryAmount)) on \(analysis.topCategory.displayName). That's not a flex.",
            "Your weekend spending is \(Int(analysis.weekendRatio * 100))% of your budget. Ever heard of 'staying home'?",
            "\(analysis.mostFrequentMerchant)? Again? They should name a loyalty tier after you at this point.",
            "You made \(analysis.transactionCount) transactions. That's \(analysis.transactionCount / 30) per day. Chill.",
        ]

        return roasts.randomElement()!
    }

    private func generateSpendingSummary(mood: PersonaMood) -> String {
        guard let analysis = lastAnalysis else { return "Analyzing..." }

        switch mood {
        case .chill:
            return "This month: \(formatCurrency(analysis.totalSpent)) total. Top category: \(analysis.topCategory.displayName). You're doing fine!"
        case .sassy:
            return "So... \(formatCurrency(analysis.totalSpent)) gone. Poof. \(analysis.topCategory.displayName) took the biggest bite."
        case .coach:
            return "MONTHLY REPORT: \(formatCurrency(analysis.totalSpent)) invested in your lifestyle. \(analysis.topCategory.displayName) leads. Let's optimize!"
        case .zen:
            return "\(formatCurrency(analysis.totalSpent)) has journeyed through your accounts. \(analysis.topCategory.displayName) received the most energy."
        case .roast:
            return "SUMMARY: You spent \(formatCurrency(analysis.totalSpent)). \(analysis.topCategory.displayName) won. Your savings account lost."
        }
    }

    private func generateSavingsTips(mood: PersonaMood) -> String {
        return respondToSavingsTip(mood: mood)
    }

    private func generateBudgetStatus(mood: PersonaMood) -> String {
        return respondToBudgetQuery(mood: mood)
    }

    private func generateFunFact(mood: PersonaMood) -> String {
        let facts = [
            "If you saved $5/day, you'd have $1,825 in a year. That's a nice vacation!",
            "The average person makes 4 impulse purchases per week. How many were yours?",
            "Your coffee spending could buy \(Int(lastAnalysis?.totalSpent ?? 0 / 5)) fancy dinners.",
            "Fun fact: checking your spending daily increases savings by 20% on average.",
        ]

        return facts.randomElement()!
    }

    private func generateAnalysis() -> PersonaAnalysis {
        let total = recentTransactions.reduce(0) { $0 + $1.amount }
        let byCategory = Dictionary(grouping: recentTransactions, by: { $0.category })
        let topCategory = byCategory.max { $0.value.count < $1.value.count }?.key ?? .other
        let topAmount = byCategory[topCategory]?.reduce(0) { $0 + $1.amount } ?? 0

        let weekendTx = recentTransactions.filter { Calendar.current.isDateInWeekend($0.date) }
        let weekendRatio = total > 0 ? weekendTx.reduce(0) { $0 + $1.amount } / total : 0

        let merchantCounts = Dictionary(grouping: recentTransactions, by: { $0.merchantName })
        let topMerchant = merchantCounts.max { $0.value.count < $1.value.count }?.key ?? "Unknown"

        return PersonaAnalysis(
            totalSpent: total,
            transactionCount: recentTransactions.count,
            topCategory: topCategory,
            topCategoryAmount: topAmount,
            weekendRatio: weekendRatio,
            mostFrequentMerchant: topMerchant,
            budgetStatus: budgetPrediction.budgetStatus
        )
    }

    private func generateStatusMessage() -> String {
        guard let analysis = lastAnalysis else { return "Ready to chat!" }

        if analysis.budgetStatus == .atRisk {
            return "⚠️ Budget alert! You're burning through cash faster than usual."
        } else if analysis.weekendRatio > 0.4 {
            return "🎉 Weekend warrior detected! Your weekends are expensive."
        } else if analysis.transactionCount > 50 {
            return "💳 Card swiper extraordinaire! \(analysis.transactionCount) transactions this month."
        }

        return "All systems green! Your spending looks balanced."
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
public struct PersonaMessage: Identifiable {
    public let id: UUID
    public let text: String
    public let sender: MessageSender
    public let timestamp: Date
    public var mood: PersonaMood?
}

@available(iOS 26.0, *)
public enum MessageSender {
    case user
    case persona
}

@available(iOS 26.0, *)
public enum PersonaMood: String, CaseIterable {
    case chill = "chill"
    case sassy = "sassy"
    case coach = "coach"
    case zen = "zen"
    case roast = "roast"

    public var avatar: String {
        switch self {
        case .chill: return "😎"
        case .sassy: return "💅"
        case .coach: return "💪"
        case .zen: return "🧘"
        case .roast: return "🔥"
        }
    }

    public var description: String {
        switch self {
        case .chill: return "Relaxed and supportive"
        case .sassy: return "Witty with attitude"
        case .coach: return "Motivational and energetic"
        case .zen: return "Calm and mindful"
        case .roast: return "Brutally honest"
        }
    }

    public var primaryColor: Color {
        switch self {
        case .chill: return .blue
        case .sassy: return .purple
        case .coach: return .orange
        case .zen: return .green
        case .roast: return .red
        }
    }

    public var gradient: LinearGradient {
        LinearGradient(
            colors: [primaryColor.opacity(0.3), primaryColor.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@available(iOS 26.0, *)
public enum QuickAction: String, CaseIterable {
    case roastMe = "roast_me"
    case spendingSummary = "spending_summary"
    case savingsTips = "savings_tips"
    case budgetStatus = "budget_status"
    case funFact = "fun_fact"

    public var displayName: String {
        switch self {
        case .roastMe: return "Roast Me"
        case .spendingSummary: return "Summary"
        case .savingsTips: return "Tips"
        case .budgetStatus: return "Budget"
        case .funFact: return "Fun Fact"
        }
    }

    public var icon: String {
        switch self {
        case .roastMe: return "flame"
        case .spendingSummary: return "chart.pie"
        case .savingsTips: return "lightbulb"
        case .budgetStatus: return "wallet.bifold"
        case .funFact: return "sparkles"
        }
    }
}

@available(iOS 26.0, *)
struct PersonaAnalysis {
    let totalSpent: Double
    let transactionCount: Int
    let topCategory: TransactionCategory
    let topCategoryAmount: Double
    let weekendRatio: Double
    let mostFrequentMerchant: String
    let budgetStatus: BudgetStatus
}

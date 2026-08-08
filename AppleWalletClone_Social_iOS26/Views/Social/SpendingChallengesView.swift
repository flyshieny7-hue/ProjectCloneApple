import SwiftUI

// MARK: - Models
struct SpendingChallenge: Identifiable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var category: ChallengeCategory
    var type: ChallengeType
    var startDate: Date
    var endDate: Date
    var participants: [ChallengeParticipant]
    var rules: ChallengeRules
    var status: ChallengeStatus
    var rewards: [ChallengeReward]
    var isPrivate: Bool
    var createdBy: SocialContact

    enum ChallengeCategory: String, CaseIterable {
        case coffee = "Кофе"
        case food = "Еда"
        case transport = "Транспорт"
        case entertainment = "Развлечения"
        case shopping = "Шоппинг"
        case custom = "Своя категория"

        var icon: String {
            switch self {
            case .coffee: return "cup.and.saucer.fill"
            case .food: return "fork.knife"
            case .transport: return "car.fill"
            case .entertainment: return "film.fill"
            case .shopping: return "bag.fill"
            case .custom: return "star.fill"
            }
        }

        var color: Color {
            switch self {
            case .coffee: return Color(red: 0.6, green: 0.4, blue: 0.2)
            case .food: return .orange
            case .transport: return .blue
            case .entertainment: return .purple
            case .shopping: return .pink
            case .custom: return .teal
            }
        }
    }

    enum ChallengeType: String, CaseIterable {
        case leastSpent = "Кто меньше потратит"
        case underBudget = "Уложиться в бюджет"
        case noSpend = "День без трат"
        case streak = "Серия дней"
        case savingsRace = "Гонка накоплений"

        var description: String {
            switch self {
            case .leastSpent: return "Побеждает тот, кто потратит меньше всех"
            case .underBudget: return "Уложитесь в установленный лимит"
            case .noSpend: return "Целый день без расходов в категории"
            case .streak: return "Максимальная серия дней без трат"
            case .savingsRace: return "Кто больше сэкономит за период"
            }
        }
    }

    enum ChallengeStatus: String {
        case upcoming = "Скоро начнется"
        case active = "Активен"
        case completed = "Завершен"
        case cancelled = "Отменен"

        var color: Color {
            switch self {
            case .upcoming: return .orange
            case .active: return .green
            case .completed: return .blue
            case .cancelled: return .gray
            }
        }
    }
}

struct ChallengeParticipant: Identifiable, Hashable {
    let id: UUID
    var contact: SocialContact
    var currentSpent: Double
    var targetAmount: Double
    var streakDays: Int
    var longestStreak: Int
    var dailySpending: [DailySpending]
    var isActive: Bool
    var joinedAt: Date
    var rank: Int?

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentSpent / targetAmount, 1.0)
    }

    var remaining: Double {
        max(targetAmount - currentSpent, 0)
    }

    var isWinning: Bool {
        currentSpent <= targetAmount
    }
}

struct DailySpending: Identifiable {
    let id: UUID
    var date: Date
    var amount: Double
    var transactions: [String]
}

struct ChallengeRules: Codable {
    var targetAmount: Double
    var allowExclusions: Bool
    var exclusions: [String]
    var penaltyAmount: Double?
    var bonusForStreak: Bool
    var allowCarryover: Bool
}

struct ChallengeReward: Identifiable {
    let id: UUID
    var type: RewardType
    var description: String
    var value: Double?
    var isClaimed: Bool

    enum RewardType: String {
        case badge = "Значок"
        case points = "Баллы"
        case cashback = "Кэшбэк"
        case trophy = "Трофей"
        case custom = "Награда"
    }
}

// MARK: - ViewModel
@MainActor
class SpendingChallengesViewModel: ObservableObject {
    @Published var challenges: [SpendingChallenge] = []
    @Published var activeChallenges: [SpendingChallenge] = []
    @Published var completedChallenges: [SpendingChallenge] = []
    @Published var isLoading = false
    @Published var showCreateChallenge = false
    @Published var selectedChallenge: SpendingChallenge?
    @Published var userRankings: [ChallengeParticipant] = []

    private let cloudKitManager = CloudKitSyncManager.shared

    func loadChallenges() {
        Task {
            isLoading = true
            defer { isLoading = false }

            // Mock data
            challenges = createMockChallenges()
            filterChallenges()
        }
    }

    func createChallenge(title: String, description: String, category: SpendingChallenge.ChallengeCategory, type: SpendingChallenge.ChallengeType, targetAmount: Double, participants: [SocialContact], duration: Int, isPrivate: Bool) async {
        let rules = ChallengeRules(
            targetAmount: targetAmount,
            allowExclusions: true,
            exclusions: [],
            penaltyAmount: nil,
            bonusForStreak: true,
            allowCarryover: false
        )

        let challengeParticipants = participants.map { contact in
            ChallengeParticipant(
                id: UUID(),
                contact: contact,
                currentSpent: 0,
                targetAmount: targetAmount,
                streakDays: 0,
                longestStreak: 0,
                dailySpending: [],
                isActive: true,
                joinedAt: Date(),
                rank: nil
            )
        }

        let challenge = SpendingChallenge(
            id: UUID(),
            title: title,
            description: description,
            category: category,
            type: type,
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: duration, to: Date())!,
            participants: challengeParticipants,
            rules: rules,
            status: .active,
            rewards: [
                ChallengeReward(id: UUID(), type: .badge, description: "Мастер экономии", value: nil, isClaimed: false),
                ChallengeReward(id: UUID(), type: .points, description: "500 баллов", value: 500, isClaimed: false)
            ],
            isPrivate: isPrivate,
            createdBy: SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .blue, isCurrentUser: true)
        )

        do {
            try await cloudKitManager.saveChallenge(challenge)
            challenges.append(challenge)
            filterChallenges()
        } catch {
            print("Failed to create challenge: \(error)")
        }
    }

    func joinChallenge(_ challenge: SpendingChallenge) async {
        guard let index = challenges.firstIndex(where: { $0.id == challenge.id }) else { return }

        let currentUser = SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .blue, isCurrentUser: true)
        let newParticipant = ChallengeParticipant(
            id: UUID(),
            contact: currentUser,
            currentSpent: 0,
            targetAmount: challenge.rules.targetAmount,
            streakDays: 0,
            longestStreak: 0,
            dailySpending: [],
            isActive: true,
            joinedAt: Date(),
            rank: nil
        )

        challenges[index].participants.append(newParticipant)

        do {
            try await cloudKitManager.updateChallenge(challenges[index])
        } catch {
            print("Failed to join challenge")
        }
    }

    func updateSpending(for challengeID: UUID, participantID: UUID, amount: Double) {
        guard let challengeIndex = challenges.firstIndex(where: { $0.id == challengeID }),
              let participantIndex = challenges[challengeIndex].participants.firstIndex(where: { $0.id == participantID }) else { return }

        challenges[challengeIndex].participants[participantIndex].currentSpent += amount

        // Update daily spending
        let today = Calendar.current.startOfDay(for: Date())
        if let dailyIndex = challenges[challengeIndex].participants[participantIndex].dailySpending.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            challenges[challengeIndex].participants[participantIndex].dailySpending[dailyIndex].amount += amount
        } else {
            let newDaily = DailySpending(id: UUID(), date: today, amount: amount, transactions: ["Транзакция"])
            challenges[challengeIndex].participants[participantIndex].dailySpending.append(newDaily)
        }

        // Update streak
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let hadSpendingYesterday = challenges[challengeIndex].participants[participantIndex].dailySpending.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: yesterday) && $0.amount > 0 })

        if !hadSpendingYesterday {
            challenges[challengeIndex].participants[participantIndex].streakDays += 1
            challenges[challengeIndex].participants[participantIndex].longestStreak = max(
                challenges[challengeIndex].participants[participantIndex].longestStreak,
                challenges[challengeIndex].participants[participantIndex].streakDays
            )
        } else {
            challenges[challengeIndex].participants[participantIndex].streakDays = 0
        }

        updateRankings(for: challenges[challengeIndex])

        Task {
            try? await cloudKitManager.updateChallenge(challenges[challengeIndex])
        }
    }

    private func updateRankings(for challenge: SpendingChallenge) {
        guard let challengeIndex = challenges.firstIndex(where: { $0.id == challenge.id }) else { return }

        let sorted = challenge.participants.sorted { $0.currentSpent < $1.currentSpent }
        for (index, _) in sorted.enumerated() {
            if let participantIndex = challenges[challengeIndex].participants.firstIndex(where: { $0.id == sorted[index].id }) {
                challenges[challengeIndex].participants[participantIndex].rank = index + 1
            }
        }
    }

    private func filterChallenges() {
        activeChallenges = challenges.filter { $0.status == .active || $0.status == .upcoming }
        completedChallenges = challenges.filter { $0.status == .completed }
    }

    private func createMockChallenges() -> [SpendingChallenge] {
        let contacts = [
            SocialContact(id: UUID(), name: "Анна", avatar: nil, color: .pink, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Михаил", avatar: nil, color: .blue, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Елена", avatar: nil, color: .purple, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .green, isCurrentUser: true)
        ]

        let participants1 = [
            ChallengeParticipant(id: UUID(), contact: contacts[0], currentSpent: 450, targetAmount: 1000, streakDays: 3, longestStreak: 5, dailySpending: [], isActive: true, joinedAt: Date(), rank: 2),
            ChallengeParticipant(id: UUID(), contact: contacts[1], currentSpent: 890, targetAmount: 1000, streakDays: 1, longestStreak: 2, dailySpending: [], isActive: true, joinedAt: Date(), rank: 3),
            ChallengeParticipant(id: UUID(), contact: contacts[2], currentSpent: 120, targetAmount: 1000, streakDays: 5, longestStreak: 5, dailySpending: [], isActive: true, joinedAt: Date(), rank: 1),
            ChallengeParticipant(id: UUID(), contact: contacts[3], currentSpent: 670, targetAmount: 1000, streakDays: 2, longestStreak: 3, dailySpending: [], isActive: true, joinedAt: Date(), rank: 4)
        ]

        let participants2 = [
            ChallengeParticipant(id: UUID(), contact: contacts[0], currentSpent: 0, targetAmount: 0, streakDays: 2, longestStreak: 2, dailySpending: [], isActive: true, joinedAt: Date(), rank: 1),
            ChallengeParticipant(id: UUID(), contact: contacts[3], currentSpent: 0, targetAmount: 0, streakDays: 1, longestStreak: 1, dailySpending: [], isActive: true, joinedAt: Date(), rank: 2)
        ]

        return [
            SpendingChallenge(
                id: UUID(),
                title: "Кто меньше потратит на кофе",
                description: "Недельный челлендж: минимум трат на кофе и кофейни",
                category: .coffee,
                type: .leastSpent,
                startDate: Date().addingTimeInterval(-86400 * 3),
                endDate: Date().addingTimeInterval(86400 * 4),
                participants: participants1,
                rules: ChallengeRules(targetAmount: 1000, allowExclusions: true, exclusions: ["Домашний кофе"], penaltyAmount: nil, bonusForStreak: true, allowCarryover: false),
                status: .active,
                rewards: [
                    ChallengeReward(id: UUID(), type: .badge, description: "Кофейный аскет", value: nil, isClaimed: false),
                    ChallengeReward(id: UUID(), type: .cashback, description: "10% кэшбэк", value: 10, isClaimed: false)
                ],
                isPrivate: false,
                createdBy: contacts[2]
            ),
            SpendingChallenge(
                id: UUID(),
                title: "День без трат",
                description: "Серия дней без каких-либо расходов",
                category: .custom,
                type: .streak,
                startDate: Date().addingTimeInterval(-86400 * 5),
                endDate: Date().addingTimeInterval(86400 * 25),
                participants: participants2,
                rules: ChallengeRules(targetAmount: 0, allowExclusions: false, exclusions: [], penaltyAmount: nil, bonusForStreak: true, allowCarryover: true),
                status: .active,
                rewards: [
                    ChallengeReward(id: UUID(), type: .trophy, description: "Марафонец", value: nil, isClaimed: false)
                ],
                isPrivate: true,
                createdBy: contacts[0]
            ),
            SpendingChallenge(
                id: UUID(),
                title: "Уложиться в 5000₽ на еду",
                description: "Месячный бюджет на питание",
                category: .food,
                type: .underBudget,
                startDate: Date().addingTimeInterval(-86400 * 10),
                endDate: Date().addingTimeInterval(86400 * 20),
                participants: participants1,
                rules: ChallengeRules(targetAmount: 5000, allowExclusions: true, exclusions: ["Продукты домой"], penaltyAmount: 100, bonusForStreak: false, allowCarryover: false),
                status: .active,
                rewards: [
                    ChallengeReward(id: UUID(), type: .points, description: "1000 баллов", value: 1000, isClaimed: false)
                ],
                isPrivate: false,
                createdBy: contacts[1]
            )
        ]
    }
}

// MARK: - Views
struct SpendingChallengesView: View {
    @StateObject private var viewModel = SpendingChallengesViewModel()
    @State private var selectedTab = 0
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Custom Segmented Control
                    segmentedControl

                    ScrollView {
                        VStack(spacing: 16) {
                            if selectedTab == 0 {
                                activeChallengesSection
                            } else {
                                completedChallengesSection
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Челленджи")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showCreate = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateChallengeSheet(viewModel: viewModel)
            }
            .navigationDestination(item: $viewModel.selectedChallenge) { challenge in
                ChallengeDetailView(challenge: challenge, viewModel: viewModel)
            }
            .onAppear {
                viewModel.loadChallenges()
            }
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(0..<2) { index in
                Button(action: { selectedTab = index }) {
                    VStack(spacing: 8) {
                        Text(index == 0 ? "Активные" : "Завершенные")
                            .font(.subheadline.bold())
                            .foregroundStyle(selectedTab == index ? .primary : .secondary)

                        if selectedTab == index {
                            Rectangle()
                                .fill(Color.purple)
                                .frame(height: 3)
                                .matchedGeometryEffect(id: "underline", in: namespace)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    @Namespace private var namespace

    private var activeChallengesSection: some View {
        VStack(spacing: 16) {
            if viewModel.activeChallenges.isEmpty {
                emptyStateView
            } else {
                ForEach(viewModel.activeChallenges) { challenge in
                    ChallengeCard(challenge: challenge) {
                        viewModel.selectedChallenge = challenge
                    }
                }
            }
        }
    }

    private var completedChallengesSection: some View {
        VStack(spacing: 16) {
            if viewModel.completedChallenges.isEmpty {
                emptyCompletedView
            } else {
                ForEach(viewModel.completedChallenges) { challenge in
                    CompletedChallengeCard(challenge: challenge)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)
            }

            VStack(spacing: 8) {
                Text("Нет активных челленджей")
                    .font(.title2.bold())

                Text("Создайте челлендж с друзьями и соревнуйтесь в экономии")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(action: { showCreate = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Создать челлендж")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.purple)
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.top, 40)
    }

    private var emptyCompletedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Пока нет завершенных челленджей")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct ChallengeCard: View {
    let challenge: SpendingChallenge
    let action: () -> Void

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: challenge.endDate).day ?? 0
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(challenge.category.color.opacity(0.15))
                                .frame(width: 44, height: 44)

                            Image(systemName: challenge.category.icon)
                                .font(.title3)
                                .foregroundStyle(challenge.category.color)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(challenge.title)
                                .font(.headline)
                                .lineLimit(1)

                            Text(challenge.type.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(challenge.status.color)
                            .frame(width: 8, height: 8)
                        Text(challenge.status.rawValue)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(challenge.status.color.opacity(0.1))
                    )
                    .foregroundStyle(challenge.status.color)
                }

                Text(challenge.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Leaderboard Preview
                HStack(spacing: -8) {
                    ForEach(challenge.participants.sorted(by: { ($0.rank ?? 999) < ($1.rank ?? 999) }).prefix(3)) { participant in
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(participant.contact.color)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(String(participant.contact.name.prefix(1)))
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(.systemBackground), lineWidth: 2)
                                )

                            if let rank = participant.rank, rank <= 3 {
                                Text("\(rank)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 14, height: 14)
                                    .background(Circle().fill(rank == 1 ? Color.yellow : (rank == 2 ? Color.gray : Color.orange)))
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                            }
                        }
                    }

                    if challenge.participants.count > 3 {
                        Text("+\(challenge.participants.count - 3)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(.systemGray5)))
                    }
                }

                // Progress
                HStack {
                    Text("Осталось \(daysRemaining) дней")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(challenge.participants.count) участников")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(challenge.category.color.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CompletedChallengeCard: View {
    let challenge: SpendingChallenge

    var winner: ChallengeParticipant? {
        challenge.participants.min(by: { $0.currentSpent < $1.currentSpent })
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(challenge.category.color.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(.subheadline.bold())

                if let winner = winner {
                    HStack(spacing: 4) {
                        Text("Победитель:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(winner.contact.name)
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }

                Text("Завершен \(challenge.endDate, style: .date)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct ChallengeDetailView: View {
    let challenge: SpendingChallenge
    @ObservedObject var viewModel: SpendingChallengesViewModel
    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                challengeHeader

                // Stats
                challengeStats

                // Leaderboard
                leaderboardSection

                // Rules
                rulesSection

                // Rewards
                rewardsSection
            }
            .padding()
        }
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: {}) {
                        Label("Пригласить", systemImage: "person.badge.plus")
                    }

                    Button(action: {}) {
                        Label("Настройки", systemImage: "gear")
                    }

                    if challenge.createdBy.isCurrentUser {
                        Button(role: .destructive, action: {}) {
                            Label("Завершить челлендж", systemImage: "flag.checkered")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var challengeHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(challenge.category.color.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: challenge.category.icon)
                    .font(.system(size: 44))
                    .foregroundStyle(challenge.category.color)
            }

            Text(challenge.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: challenge.endDate).day ?? 0
                    Text("\(daysLeft)")
                        .font(.title2.bold())
                    Text("дней осталось")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text("\(challenge.participants.count)")
                        .font(.title2.bold())
                    Text("участников")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text(challenge.rules.targetAmount, format: .currency(code: "RUB"))
                        .font(.title2.bold())
                    Text("лимит")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
        )
    }

    private var challengeStats: some View {
        HStack(spacing: 12) {
            StatCard(title: "Лидер", value: challenge.participants.first(where: { $0.rank == 1 })?.contact.name ?? "—", icon: "crown.fill", color: .yellow)
            StatCard(title: "Ваш ранг", value: "#\(challenge.participants.first(where: { $0.contact.isCurrentUser })?.rank ?? 0)", icon: "number", color: .blue)
        }
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Таблица лидеров")
                .font(.headline)

            ForEach(challenge.participants.sorted(by: { ($0.rank ?? 999) < ($1.rank ?? 999) })) { participant in
                LeaderboardRow(participant: participant, challenge: challenge)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Правила")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                RuleRow(icon: "dollarsign.circle.fill", text: "Лимит: \(challenge.rules.targetAmount, format: .currency(code: "RUB"))", color: .blue)

                if challenge.rules.allowExclusions {
                    RuleRow(icon: "checkmark.shield.fill", text: "Исключения: \(challenge.rules.exclusions.joined(separator: ", "))", color: .green)
                }

                if challenge.rules.bonusForStreak {
                    RuleRow(icon: "flame.fill", text: "Бонус за серию дней", color: .orange)
                }

                if let penalty = challenge.rules.penaltyAmount {
                    RuleRow(icon: "exclamationmark.triangle.fill", text: "Штраф за превышение: \(penalty, format: .currency(code: "RUB"))", color: .red)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Награды")
                .font(.headline)

            ForEach(challenge.rewards) { reward in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.yellow.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: rewardIcon(for: reward.type))
                            .foregroundStyle(.yellow)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reward.type.rawValue)
                            .font(.subheadline.bold())
                        Text(reward.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if reward.isClaimed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Не получена")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private func rewardIcon(for type: ChallengeReward.RewardType) -> String {
        switch type {
        case .badge: return "medal.fill"
        case .points: return "star.fill"
        case .cashback: return "arrow.left.arrow.right.circle.fill"
        case .trophy: return "trophy.fill"
        case .custom: return "gift.fill"
        }
    }
}

struct LeaderboardRow: View {
    let participant: ChallengeParticipant
    let challenge: SpendingChallenge

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            ZStack {
                if let rank = participant.rank, rank <= 3 {
                    Circle()
                        .fill(rank == 1 ? Color.yellow.opacity(0.2) : (rank == 2 ? Color.gray.opacity(0.2) : Color.orange.opacity(0.2)))
                        .frame(width: 32, height: 32)

                    Text("\(rank)")
                        .font(.caption.bold())
                        .foregroundStyle(rank == 1 ? .yellow : (rank == 2 ? .gray : .orange))
                } else {
                    Text("\(participant.rank ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                }
            }

            // Avatar
            Circle()
                .fill(participant.contact.color)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(participant.contact.name.prefix(1)))
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(participant.contact.name)
                        .font(.subheadline.bold())

                    if participant.contact.isCurrentUser {
                        Text("(Вы)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray5))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(participant.isWinning ? Color.green : Color.red)
                            .frame(width: min(CGFloat(participant.progress) * geo.size.width, geo.size.width), height: 4)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text("\(participant.currentSpent, format: .currency(code: "RUB"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if participant.streakDays > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                            Text("\(participant.streakDays) дней")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Spacer()

            // Status
            if participant.isWinning {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("+\(participant.currentSpent - participant.targetAmount, format: .currency(code: "RUB"))")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RuleRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Create Challenge Sheet
struct CreateChallengeSheet: View {
    @ObservedObject var viewModel: SpendingChallengesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var selectedCategory: SpendingChallenge.ChallengeCategory = .coffee
    @State private var selectedType: SpendingChallenge.ChallengeType = .leastSpent
    @State private var targetAmount = ""
    @State private var duration = 7
    @State private var selectedParticipants: [SocialContact] = []
    @State private var isPrivate = false
    @State private var allowExclusions = true
    @State private var bonusForStreak = true

    var body: some View {
        NavigationStack {
            Form {
                Section("О челлендже") {
                    TextField("Название", text: $title)
                    TextField("Описание", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Категория") {
                    Picker("Категория", selection: $selectedCategory) {
                        ForEach(SpendingChallenge.ChallengeCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Тип челленджа") {
                    Picker("Тип", selection: $selectedType) {
                        ForEach(SpendingChallenge.ChallengeType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Text(selectedType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Настройки") {
                    TextField("Лимит (₽)", text: $targetAmount)
                        .keyboardType(.decimalPad)

                    Stepper("Длительность: \(duration) дней", value: $duration, in: 1...90)

                    Toggle("Приватный", isOn: $isPrivate)
                    Toggle("Разрешить исключения", isOn: $allowExclusions)
                    Toggle("Бонус за серию", isOn: $bonusForStreak)
                }

                Section("Участники") {
                    // Simplified participant picker
                    ForEach(mockSocialContacts) { contact in
                        Toggle(contact.name, isOn: Binding(
                            get: { selectedParticipants.contains(where: { $0.id == contact.id }) },
                            set: { isSelected in
                                if isSelected {
                                    selectedParticipants.append(contact)
                                } else {
                                    selectedParticipants.removeAll { $0.id == contact.id }
                                }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Новый челлендж")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        Task {
                            if let target = Double(targetAmount) {
                                await viewModel.createChallenge(
                                    title: title,
                                    description: description,
                                    category: selectedCategory,
                                    type: selectedType,
                                    targetAmount: target,
                                    participants: selectedParticipants,
                                    duration: duration,
                                    isPrivate: isPrivate
                                )
                                dismiss()
                            }
                        }
                    }
                    .disabled(title.isEmpty || targetAmount.isEmpty)
                }
            }
        }
    }
}

let mockSocialContacts = [
    SocialContact(id: UUID(), name: "Анна", avatar: nil, color: .pink, isCurrentUser: false),
    SocialContact(id: UUID(), name: "Михаил", avatar: nil, color: .blue, isCurrentUser: false),
    SocialContact(id: UUID(), name: "Елена", avatar: nil, color: .purple, isCurrentUser: false)
]

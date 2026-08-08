import SwiftUI

// MARK: - Models
struct SharedSavingsGoal: Identifiable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var targetAmount: Double
    var currentAmount: Double
    var deadline: Date?
    var contributors: [SavingsContributor]
    var milestones: [SavingsMilestone]
    var transactions: [SavingsTransaction]
    var icon: String
    var color: GoalColor
    var category: GoalCategory
    var isRecurring: Bool
    var recurringAmount: Double?
    var privacyLevel: PrivacyLevel
    var createdAt: Date

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1.0)
    }

    var remaining: Double {
        max(targetAmount - currentAmount, 0)
    }

    var isCompleted: Bool {
        currentAmount >= targetAmount
    }

    var daysRemaining: Int? {
        guard let deadline = deadline else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: deadline).day
    }

    var dailyRequired: Double? {
        guard let days = daysRemaining, days > 0 else { return nil }
        return remaining / Double(days)
    }

    enum GoalColor: String, CaseIterable {
        case ocean = "ocean"
        case forest = "forest"
        case sunset = "sunset"
        case berry = "berry"
        case gold = "gold"
        case midnight = "midnight"

        var swiftColor: Color {
            switch self {
            case .ocean: return Color(red: 0.1, green: 0.5, blue: 0.9)
            case .forest: return Color(red: 0.2, green: 0.7, blue: 0.3)
            case .sunset: return Color(red: 1.0, green: 0.5, blue: 0.2)
            case .berry: return Color(red: 0.8, green: 0.2, blue: 0.5)
            case .gold: return Color(red: 1.0, green: 0.8, blue: 0.1)
            case .midnight: return Color(red: 0.2, green: 0.2, blue: 0.5)
            }
        }
    }

    enum GoalCategory: String, CaseIterable {
        case vacation = "Отпуск"
        case car = "Автомобиль"
        case home = "Жилье"
        case education = "Образование"
        case emergency = "Резервный фонд"
        case gadget = "Гаджет"
        case wedding = "Свадьба"
        case custom = "Своя цель"

        var icon: String {
            switch self {
            case .vacation: return "airplane"
            case .car: return "car.fill"
            case .home: return "house.fill"
            case .education: return "graduationcap.fill"
            case .emergency: return "cross.case.fill"
            case .gadget: return "iphone"
            case .wedding: return "heart.fill"
            case .custom: return "star.fill"
            }
        }
    }

    enum PrivacyLevel: String {
        case open = "Открытая"
        case contributorsOnly = "Только вкладчики"
        case private_ = "Приватная"
    }
}

struct SavingsContributor: Identifiable, Hashable {
    let id: UUID
    var contact: SocialContact
    var contributedAmount: Double
    var contributionPercentage: Double
    var joinedAt: Date
    var isAutoContribute: Bool
    var autoContributeAmount: Double?
    var lastContribution: Date?

    var contributionProgress: Double {
        guard contributionPercentage > 0 else { return 0 }
        return contributedAmount / (contributionPercentage / 100)
    }
}

struct SavingsMilestone: Identifiable {
    let id: UUID
    var title: String
    var targetAmount: Double
    var isReached: Bool
    var reachedAt: Date?
    var reward: String?

    var progress: Double {
        // Calculated against total goal
        targetAmount / 1000 // placeholder
    }
}

struct SavingsTransaction: Identifiable {
    let id: UUID
    var contributor: SavingsContributor
    var amount: Double
    var timestamp: Date
    var note: String?
    var isRecurring: Bool
}

// MARK: - ViewModel
@MainActor
class SharedSavingsGoalViewModel: ObservableObject {
    @Published var goals: [SharedSavingsGoal] = []
    @Published var selectedGoal: SharedSavingsGoal?
    @Published var isLoading = false
    @Published var showAddContribution = false
    @Published var showCreateGoal = false
    @Published var contributionAmount = ""
    @Published var contributionNote = ""

    private let cloudKitManager = CloudKitSyncManager.shared

    func loadGoals() {
        Task {
            isLoading = true
            defer { isLoading = false }

            goals = createMockGoals()
        }
    }

    func createGoal(name: String, description: String, targetAmount: Double, deadline: Date?, contributors: [SocialContact], category: SharedSavingsGoal.GoalCategory, color: SharedSavingsGoal.GoalColor) async {
        let savingsContributors = contributors.map { contact in
            SavingsContributor(
                id: UUID(),
                contact: contact,
                contributedAmount: 0,
                contributionPercentage: 100.0 / Double(contributors.count),
                joinedAt: Date(),
                isAutoContribute: false,
                autoContributeAmount: nil,
                lastContribution: nil
            )
        }

        let milestones = generateMilestones(targetAmount: targetAmount)

        let goal = SharedSavingsGoal(
            id: UUID(),
            name: name,
            description: description,
            targetAmount: targetAmount,
            currentAmount: 0,
            deadline: deadline,
            contributors: savingsContributors,
            milestones: milestones,
            transactions: [],
            icon: category.icon,
            color: color,
            category: category,
            isRecurring: false,
            recurringAmount: nil,
            privacyLevel: .contributorsOnly,
            createdAt: Date()
        )

        do {
            try await cloudKitManager.saveSavingsGoal(goal)
            goals.append(goal)
        } catch {
            print("Failed to create goal: \(error)")
        }
    }

    func contribute(to goalID: UUID, amount: Double, contributor: SavingsContributor, note: String?) async {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }

        goals[index].currentAmount += amount

        if let contributorIndex = goals[index].contributors.firstIndex(where: { $0.id == contributor.id }) {
            goals[index].contributors[contributorIndex].contributedAmount += amount
            goals[index].contributors[contributorIndex].lastContribution = Date()
        }

        let transaction = SavingsTransaction(
            id: UUID(),
            contributor: contributor,
            amount: amount,
            timestamp: Date(),
            note: note,
            isRecurring: false
        )

        goals[index].transactions.append(transaction)

        // Check milestones
        checkMilestones(for: &goals[index])

        do {
            try await cloudKitManager.updateSavingsGoal(goals[index])
            await notifyContributors(of: transaction, in: goals[index])
        } catch {
            print("Failed to save contribution")
        }
    }

    func setupAutoContribute(for goalID: UUID, contributorID: UUID, amount: Double, frequency: String) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalID }),
              let contributorIndex = goals[goalIndex].contributors.firstIndex(where: { $0.id == contributorID }) else { return }

        goals[goalIndex].contributors[contributorIndex].isAutoContribute = true
        goals[goalIndex].contributors[contributorIndex].autoContributeAmount = amount

        Task {
            try? await cloudKitManager.updateSavingsGoal(goals[goalIndex])
        }
    }

    private func checkMilestones(for goal: inout SharedSavingsGoal) {
        for index in goal.milestones.indices where !goal.milestones[index].isReached {
            if goal.currentAmount >= goal.milestones[index].targetAmount {
                goal.milestones[index].isReached = true
                goal.milestones[index].reachedAt = Date()

                // Send celebration notification
                Task {
                    await celebrateMilestone(goal.milestones[index], in: goal)
                }
            }
        }
    }

    private func celebrateMilestone(_ milestone: SavingsMilestone, in goal: SharedSavingsGoal) async {
        for contributor in goal.contributors {
            await NearbyPaymentManager.shared.sendMilestoneNotification(
                to: contributor.contact,
                milestone: milestone,
                goalName: goal.name
            )
        }
    }

    private func notifyContributors(of transaction: SavingsTransaction, in goal: SharedSavingsGoal) async {
        for contributor in goal.contributors where contributor.id != transaction.contributor.id {
            await NearbyPaymentManager.shared.sendContributionNotification(
                to: contributor.contact,
                contributorName: transaction.contributor.contact.name,
                amount: transaction.amount,
                goalName: goal.name
            )
        }
    }

    private func generateMilestones(targetAmount: Double) -> [SavingsMilestone] {
        let percentages = [0.25, 0.5, 0.75, 1.0]
        let titles = ["Четверть пути", "Половина пути", "Три четверти", "Цель достигнута!"]
        let rewards = ["Бронзовый значок", "Серебряный значок", "Золотой значок", "Платиновый трофей"]

        return zip(zip(percentages, titles), rewards).map { pair in
            let ((percentage, title), reward) = pair
            return SavingsMilestone(
                id: UUID(),
                title: title,
                targetAmount: targetAmount * percentage,
                isReached: false,
                reachedAt: nil,
                reward: reward
            )
        }
    }

    private func createMockGoals() -> [SharedSavingsGoal] {
        let contacts = [
            SocialContact(id: UUID(), name: "Анна", avatar: nil, color: .pink, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Михаил", avatar: nil, color: .blue, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Елена", avatar: nil, color: .purple, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .green, isCurrentUser: true)
        ]

        let contributors1 = [
            SavingsContributor(id: UUID(), contact: contacts[0], contributedAmount: 45000, contributionPercentage: 25, joinedAt: Date(), isAutoContribute: true, autoContributeAmount: 5000, lastContribution: Date().addingTimeInterval(-86400)),
            SavingsContributor(id: UUID(), contact: contacts[1], contributedAmount: 52000, contributionPercentage: 25, joinedAt: Date(), isAutoContribute: false, autoContributeAmount: nil, lastContribution: Date().addingTimeInterval(-172800)),
            SavingsContributor(id: UUID(), contact: contacts[2], contributedAmount: 38000, contributionPercentage: 25, joinedAt: Date(), isAutoContribute: true, autoContributeAmount: 3000, lastContribution: Date().addingTimeInterval(-43200)),
            SavingsContributor(id: UUID(), contact: contacts[3], contributedAmount: 61000, contributionPercentage: 25, joinedAt: Date(), isAutoContribute: false, autoContributeAmount: nil, lastContribution: Date().addingTimeInterval(-259200))
        ]

        let milestones1 = [
            SavingsMilestone(id: UUID(), title: "Четверть пути", targetAmount: 50000, isReached: true, reachedAt: Date().addingTimeInterval(-86400 * 30), reward: "Бронзовый значок"),
            SavingsMilestone(id: UUID(), title: "Половина пути", targetAmount: 100000, isReached: true, reachedAt: Date().addingTimeInterval(-86400 * 15), reward: "Серебряный значок"),
            SavingsMilestone(id: UUID(), title: "Три четверти", targetAmount: 150000, isReached: false, reachedAt: nil, reward: "Золотой значок"),
            SavingsMilestone(id: UUID(), title: "Цель достигнута!", targetAmount: 200000, isReached: false, reachedAt: nil, reward: "Платиновый трофей")
        ]

        let contributors2 = [
            SavingsContributor(id: UUID(), contact: contacts[0], contributedAmount: 15000, contributionPercentage: 50, joinedAt: Date(), isAutoContribute: false, autoContributeAmount: nil, lastContribution: Date().addingTimeInterval(-86400 * 3)),
            SavingsContributor(id: UUID(), contact: contacts[3], contributedAmount: 12000, contributionPercentage: 50, joinedAt: Date(), isAutoContribute: true, autoContributeAmount: 2000, lastContribution: Date().addingTimeInterval(-86400))
        ]

        return [
            SharedSavingsGoal(
                id: UUID(),
                name: "Поездка в Японию",
                description: "Наша мечта — весна в Киото и сакура",
                targetAmount: 200000,
                currentAmount: 196000,
                deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date()),
                contributors: contributors1,
                milestones: milestones1,
                transactions: [],
                icon: "airplane",
                color: .ocean,
                category: .vacation,
                isRecurring: true,
                recurringAmount: 5000,
                privacyLevel: .contributorsOnly,
                createdAt: Date().addingTimeInterval(-86400 * 60)
            ),
            SharedSavingsGoal(
                id: UUID(),
                name: "Новый MacBook",
                description: "Для работы и творчества",
                targetAmount: 300000,
                currentAmount: 27000,
                deadline: Calendar.current.date(byAdding: .month, value: 8, to: Date()),
                contributors: contributors2,
                milestones: generateMilestones(targetAmount: 300000),
                transactions: [],
                icon: "laptopcomputer",
                color: .midnight,
                category: .gadget,
                isRecurring: false,
                recurringAmount: nil,
                privacyLevel: .open,
                createdAt: Date().addingTimeInterval(-86400 * 10)
            ),
            SharedSavingsGoal(
                id: UUID(),
                name: "Резервный фонд",
                description: "На черный день — 6 месяцев расходов",
                targetAmount: 500000,
                currentAmount: 125000,
                deadline: nil,
                contributors: contributors1,
                milestones: generateMilestones(targetAmount: 500000),
                transactions: [],
                icon: "cross.case.fill",
                color: .forest,
                category: .emergency,
                isRecurring: true,
                recurringAmount: 10000,
                privacyLevel: .contributorsOnly,
                createdAt: Date().addingTimeInterval(-86400 * 90)
            )
        ]
    }
}

// MARK: - Views
struct SharedSavingsGoalView: View {
    @StateObject private var viewModel = SharedSavingsGoalViewModel()
    @State private var showCreate = false
    @State private var selectedGoal: SharedSavingsGoal?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection

                        goalsGrid

                        totalProgressSection
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Накопления")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showCreate = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.teal)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateGoalSheet(viewModel: viewModel)
            }
            .navigationDestination(item: $selectedGoal) { goal in
                GoalDetailView(goal: goal, viewModel: viewModel)
            }
            .onAppear {
                viewModel.loadGoals()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Копим вместе")
                .font(.title2.bold())

            Text("Совместные цели с прогрессом, вехами и автоматическими взносами")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var goalsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
            ForEach(viewModel.goals) { goal in
                GoalCard(goal: goal) {
                    selectedGoal = goal
                }
            }

            Button(action: { showCreate = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.teal.opacity(0.6))

                    Text("Новая цель")
                        .font(.callout.bold())
                        .foregroundStyle(.teal)

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .stroke(Color.teal.opacity(0.2), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var totalProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Общий прогресс")
                .font(.headline)

            let totalTarget = viewModel.goals.reduce(0) { $0 + $1.targetAmount }
            let totalCurrent = viewModel.goals.reduce(0) { $0 + $1.currentAmount }
            let totalProgress = totalTarget > 0 ? totalCurrent / totalTarget : 0

            HStack(spacing: 20) {
                // Circular total progress
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 12)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: CGFloat(totalProgress))
                        .stroke(
                            Color.teal,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1.0), value: totalProgress)

                    VStack(spacing: 2) {
                        Text("\(Int(totalProgress * 100))%")
                            .font(.title2.bold())
                        Text("общий")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    StatRow(title: "Всего целей", value: "\(viewModel.goals.count)")
                    StatRow(title: "Накоплено", value: "\(totalCurrent, format: .currency(code: "RUB"))")
                    StatRow(title: "Осталось", value: "\(totalTarget - totalCurrent, format: .currency(code: "RUB"))")
                    StatRow(title: "Завершено", value: "\(viewModel.goals.filter(\.isCompleted).count)")
                }

                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
}

struct GoalCard: View {
    let goal: SharedSavingsGoal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(goal.color.swiftColor.opacity(0.15))
                                .frame(width: 48, height: 48)

                            Image(systemName: goal.icon)
                                .font(.title3)
                                .foregroundStyle(goal.color.swiftColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name)
                                .font(.headline)

                            Text(goal.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if goal.isCompleted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    } else if let days = goal.daysRemaining {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(days)")
                                .font(.title3.bold())
                                .foregroundStyle(days < 30 ? .orange : .primary)
                            Text("дней")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Progress
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .frame(height: 12)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(goal.color.swiftColor)
                                .frame(width: min(CGFloat(goal.progress) * geo.size.width, geo.size.width), height: 12)
                                .animation(.easeInOut(duration: 0.8), value: goal.progress)

                            // Milestone markers
                            ForEach(goal.milestones.filter(\.isReached)) { milestone in
                                Circle()
                                    .fill(.white)
                                    .frame(width: 8, height: 8)
                                    .position(
                                        x: CGFloat(milestone.targetAmount / goal.targetAmount) * geo.size.width,
                                        y: 6
                                    )
                            }
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text(goal.currentAmount, format: .currency(code: "RUB"))
                            .font(.subheadline.bold())

                        Spacer()

                        Text("из \(goal.targetAmount, format: .currency(code: "RUB"))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Contributors
                HStack {
                    HStack(spacing: -6) {
                        ForEach(goal.contributors.prefix(4)) { contributor in
                            Circle()
                                .fill(contributor.contact.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text(String(contributor.contact.name.prefix(1)))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(.systemBackground), lineWidth: 2)
                                )
                        }
                    }

                    Spacer()

                    if let daily = goal.dailyRequired {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.caption2)
                            Text("\(daily, format: .currency(code: "RUB")) / день")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(goal.color.swiftColor.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct GoalDetailView: View {
    let goal: SharedSavingsGoal
    @ObservedObject var viewModel: SharedSavingsGoalViewModel
    @State private var showContribute = false
    @State private var showAutoContribute = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero
                goalHero

                // Milestones
                milestonesSection

                // Contributors
                contributorsSection

                // Recent Transactions
                transactionsSection
            }
            .padding()
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showContribute = true }) {
                        Label("Внести", systemImage: "plus")
                    }

                    Button(action: { showAutoContribute = true }) {
                        Label("Автовзнос", systemImage: "arrow.clockwise")
                    }

                    Button(action: {}) {
                        Label("Пригласить", systemImage: "person.badge.plus")
                    }

                    Divider()

                    Button(role: .destructive, action: {}) {
                        Label("Удалить цель", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showContribute) {
            ContributeSheet(goal: goal, viewModel: viewModel)
        }
        .sheet(isPresented: $showAutoContribute) {
            AutoContributeSheet(goal: goal, viewModel: viewModel)
        }
    }

    private var goalHero: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 16)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: CGFloat(goal.progress))
                    .stroke(
                        goal.color.swiftColor,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.2), value: goal.progress)

                VStack(spacing: 4) {
                    Text("\(Int(goal.progress * 100))%")
                        .font(.system(size: 44, weight: .bold, design: .rounded))

                    if goal.isCompleted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    } else {
                        Text("\(goal.remaining, format: .currency(code: "RUB"))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(goal.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(goal.currentAmount, format: .currency(code: "RUB"))
                        .font(.title3.bold())
                    Text("Накоплено")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text(goal.targetAmount, format: .currency(code: "RUB"))
                        .font(.title3.bold())
                    Text("Цель")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    if let days = goal.daysRemaining {
                        Text("\(days)")
                            .font(.title3.bold())
                            .foregroundStyle(days < 30 ? .orange : .primary)
                        Text("дней")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("∞")
                            .font(.title3.bold())
                        Text("бессрочно")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !goal.isCompleted {
                Button(action: { showContribute = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Внести")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(goal.color.swiftColor)
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
        )
    }

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Вехи")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(goal.milestones) { milestone in
                    MilestoneItem(milestone: milestone, goal: goal)
                }
            }
        }
    }

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Вкладчики")
                .font(.headline)

            ForEach(goal.contributors.sorted(by: { $0.contributedAmount > $1.contributedAmount })) { contributor in
                ContributorRow(contributor: contributor, totalGoal: goal.targetAmount)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("История взносов")
                .font(.headline)

            if goal.transactions.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.heart.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Пока нет взносов")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 30)
            } else {
                ForEach(goal.transactions.sorted(by: { $0.timestamp > $1.timestamp })) { transaction in
                    TransactionRowItem(transaction: transaction)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
}

struct MilestoneItem: View {
    let milestone: SavingsMilestone
    let goal: SharedSavingsGoal

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(milestone.isReached ? goal.color.swiftColor.opacity(0.2) : Color(.systemGray5))
                    .frame(width: 56, height: 56)

                if milestone.isReached {
                    Image(systemName: "checkmark")
                        .font(.title3.bold())
                        .foregroundStyle(goal.color.swiftColor)
                } else {
                    Image(systemName: "flag.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Text(milestone.title)
                .font(.caption.bold())
                .foregroundStyle(milestone.isReached ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(milestone.targetAmount, format: .currency(code: "RUB"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ContributorRow: View {
    let contributor: SavingsContributor
    let totalGoal: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(contributor.contact.color)
                    .frame(width: 44, height: 44)

                Text(String(contributor.contact.name.prefix(1)))
                    .font(.callout.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contributor.contact.name)
                        .font(.subheadline.bold())

                    if contributor.contact.isCurrentUser {
                        Text("(Вы)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    Text(contributor.contributedAmount, format: .currency(code: "RUB"))
                        .font(.subheadline.bold())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemGray5))
                            .frame(height: 6)

                        let expectedAmount = totalGoal * (contributor.contributionPercentage / 100)
                        let progress = expectedAmount > 0 ? contributor.contributedAmount / expectedAmount : 0

                        RoundedRectangle(cornerRadius: 3)
                            .fill(contributor.contact.color)
                            .frame(width: min(CGFloat(progress) * geo.size.width, geo.size.width), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(contributor.contributionPercentage, format: .number)% от цели")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if contributor.isAutoContribute, let amount = contributor.autoContributeAmount {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 8))
                            Text("\(amount, format: .currency(code: "RUB"))")
                                .font(.caption2)
                        }
                        .foregroundStyle(.green)
                    }

                    if let last = contributor.lastContribution {
                        Text(last, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TransactionRowItem: View {
    let transaction: SavingsTransaction

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(transaction.contributor.contact.color.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: "arrow.up.heart.fill")
                    .foregroundStyle(transaction.contributor.contact.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.contributor.contact.name)
                    .font(.subheadline.bold())

                if let note = transaction.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(transaction.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(transaction.amount, format: .currency(code: "RUB"))")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)

                if transaction.isRecurring {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text("Авто")
                            .font(.caption2)
                    }
                    .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
        }
    }
}

// MARK: - Sheets
struct CreateGoalSheet: View {
    @ObservedObject var viewModel: SharedSavingsGoalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var targetAmount = ""
    @State private var selectedCategory: SharedSavingsGoal.GoalCategory = .vacation
    @State private var selectedColor: SharedSavingsGoal.GoalColor = .ocean
    @State private var hasDeadline = true
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date())!
    @State private var selectedContributors: [SocialContact] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Цель") {
                    TextField("Название", text: $name)
                    TextField("Описание", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Сумма") {
                    TextField("100000", text: $targetAmount)
                        .keyboardType(.decimalPad)
                }

                Section("Категория") {
                    Picker("Категория", selection: $selectedCategory) {
                        ForEach(SharedSavingsGoal.GoalCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                            }
                            .tag(category)
                        }
                    }
                }

                Section("Цвет") {
                    HStack(spacing: 12) {
                        ForEach(SharedSavingsGoal.GoalColor.allCases, id: \.self) { color in
                            GoalColorCircle(color: color, isSelected: selectedColor == color) {
                                selectedColor = color
                            }
                        }
                    }
                }

                Section("Дедлайн") {
                    Toggle("Установить дедлайн", isOn: $hasDeadline)

                    if hasDeadline {
                        DatePicker("Дата", selection: $deadline, displayedComponents: .date)
                    }
                }

                Section("Вкладчики") {
                    ForEach(mockSocialContacts) { contact in
                        Toggle(contact.name, isOn: Binding(
                            get: { selectedContributors.contains(where: { $0.id == contact.id }) },
                            set: { isSelected in
                                if isSelected {
                                    selectedContributors.append(contact)
                                } else {
                                    selectedContributors.removeAll { $0.id == contact.id }
                                }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Новая цель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        Task {
                            if let target = Double(targetAmount) {
                                await viewModel.createGoal(
                                    name: name,
                                    description: description,
                                    targetAmount: target,
                                    deadline: hasDeadline ? deadline : nil,
                                    contributors: selectedContributors,
                                    category: selectedCategory,
                                    color: selectedColor
                                )
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.isEmpty || targetAmount.isEmpty || selectedContributors.isEmpty)
                }
            }
        }
    }
}

struct GoalColorCircle: View {
    let color: SharedSavingsGoal.GoalColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.swiftColor)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? color.swiftColor : Color.clear, lineWidth: 1)
                )
                .shadow(radius: isSelected ? 4 : 0)
        }
        .buttonStyle(.plain)
    }
}

struct ContributeSheet: View {
    let goal: SharedSavingsGoal
    @ObservedObject var viewModel: SharedSavingsGoalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""
    @State private var selectedContributor: SavingsContributor?

    var body: some View {
        NavigationStack {
            Form {
                Section("Сумма") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }

                Section("Примечание") {
                    TextField("Опционально", text: $note)
                }

                Section("От кого") {
                    Picker("Вкладчик", selection: $selectedContributor) {
                        ForEach(goal.contributors) { contributor in
                            HStack {
                                Circle()
                                    .fill(contributor.contact.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Text(String(contributor.contact.name.prefix(1)))
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                    )
                                Text(contributor.contact.name)
                            }
                            .tag(contributor as SavingsContributor?)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    let remaining = goal.remaining
                    let quickAmounts = [100, 500, 1000, 5000].filter { $0 <= remaining }

                    HStack(spacing: 8) {
                        ForEach(quickAmounts, id: \.self) { quick in
                            Button(action: { amount = String(quick) }) {
                                Text("+\(quick)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        if remaining > 0 {
                            Button(action: { amount = String(format: "%.0f", remaining) }) {
                                Text("Весь остаток")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.green.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Внести")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Внести") {
                        Task {
                            if let amountValue = Double(amount),
                               let contributor = selectedContributor {
                                await viewModel.contribute(
                                    to: goal.id,
                                    amount: amountValue,
                                    contributor: contributor,
                                    note: note.isEmpty ? nil : note
                                )
                                dismiss()
                            }
                        }
                    }
                    .disabled(amount.isEmpty || selectedContributor == nil)
                }
            }
        }
    }
}

struct AutoContributeSheet: View {
    let goal: SharedSavingsGoal
    @ObservedObject var viewModel: SharedSavingsGoalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var frequency = "Ежемесячно"
    @State private var selectedContributor: SavingsContributor?

    let frequencies = ["Ежедневно", "Еженедельно", "Ежемесячно", "Ежеквартально"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Настройка") {
                    Picker("Вкладчик", selection: $selectedContributor) {
                        ForEach(goal.contributors) { contributor in
                            Text(contributor.contact.name).tag(contributor as SavingsContributor?)
                        }
                    }

                    TextField("Сумма", text: $amount)
                        .keyboardType(.decimalPad)

                    Picker("Частота", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { freq in
                            Text(freq).tag(freq)
                        }
                    }
                }

                Section("Информация") {
                    HStack {
                        Text("Следующий взнос")
                        Spacer()
                        Text("1-го числа")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Метод")
                        Spacer()
                        Text("Apple Pay")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Автовзнос")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if let amountValue = Double(amount),
                           let contributor = selectedContributor {
                            viewModel.setupAutoContribute(
                                for: goal.id,
                                contributorID: contributor.id,
                                amount: amountValue,
                                frequency: frequency
                            )
                            dismiss()
                        }
                    }
                    .disabled(amount.isEmpty || selectedContributor == nil)
                }
            }
        }
    }
}

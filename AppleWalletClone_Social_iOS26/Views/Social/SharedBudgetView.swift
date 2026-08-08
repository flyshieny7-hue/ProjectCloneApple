import SwiftUI
import CloudKit

// MARK: - Models
struct SharedBudget: Identifiable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var color: BudgetColor
    var totalBudget: Double
    var spent: Double
    var period: BudgetPeriod
    var startDate: Date
    var endDate: Date
    var members: [BudgetMember]
    var categories: [BudgetCategory]
    var alerts: [BudgetAlert]
    var isRecurring: Bool
    var privacySettings: BudgetPrivacySettings

    var remaining: Double { totalBudget - spent }
    var progress: Double { totalBudget > 0 ? spent / totalBudget : 0 }
    var isOverBudget: Bool { spent > totalBudget }

    enum BudgetPeriod: String, CaseIterable {
        case weekly = "Неделя"
        case monthly = "Месяц"
        case quarterly = "Квартал"
        case yearly = "Год"
        case custom = "Свой период"
    }

    enum BudgetColor: String, CaseIterable {
        case emerald = "emerald"
        case sapphire = "sapphire"
        case ruby = "ruby"
        case amber = "amber"
        case amethyst = "amethyst"
        case coral = "coral"

        var swiftColor: Color {
            switch self {
            case .emerald: return Color(red: 0.2, green: 0.8, blue: 0.4)
            case .sapphire: return Color(red: 0.2, green: 0.4, blue: 0.9)
            case .ruby: return Color(red: 0.9, green: 0.2, blue: 0.3)
            case .amber: return Color(red: 1.0, green: 0.7, blue: 0.1)
            case .amethyst: return Color(red: 0.6, green: 0.3, blue: 0.9)
            case .coral: return Color(red: 1.0, green: 0.5, blue: 0.4)
            }
        }
    }
}

struct BudgetMember: Identifiable, Hashable {
    let id: UUID
    var contact: Contact
    var role: MemberRole
    var spendingLimit: Double?
    var spent: Double
    var joinedAt: Date
    var notificationSettings: NotificationSettings

    enum MemberRole: String {
        case owner = "Владелец"
        case manager = "Менеджер"
        case member = "Участник"
    }

    struct NotificationSettings: Codable {
        var overspendAlerts: Bool = true
        var dailySummary: Bool = false
        var weeklyReport: Bool = true
        var categoryAlerts: Bool = true
    }
}

struct BudgetCategory: Identifiable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var allocated: Double
    var spent: Double
    var color: Color

    var remaining: Double { allocated - spent }
    var progress: Double { allocated > 0 ? spent / allocated : 0 }
}

struct BudgetAlert: Identifiable {
    let id: UUID
    var type: AlertType
    var threshold: Double
    var isEnabled: Bool
    var message: String

    enum AlertType: String {
        case percentage = "Процент"
        case fixedAmount = "Фиксированная сумма"
        case dailyAverage = "Средний дневной расход"
    }
}

struct BudgetPrivacySettings: Codable {
    var showFullDetails: Bool = true
    var showOnlyTotal: Bool = false
    var hideFromMembers: [UUID] = []
    var allowMemberSpending: Bool = true
    var requireApproval: Bool = false
    var approvalThreshold: Double = 5000
}

struct BudgetTransaction: Identifiable {
    let id: UUID
    var amount: Double
    var category: BudgetCategory
    var description: String
    var member: BudgetMember
    var timestamp: Date
    var receiptImage: Data?
    var location: String?
    var isApproved: Bool
    var approvedBy: BudgetMember?
}

// MARK: - ViewModel
@MainActor
class SharedBudgetViewModel: ObservableObject {
    @Published var budgets: [SharedBudget] = []
    @Published var selectedBudget: SharedBudget?
    @Published var isLoading = false
    @Published var showAddTransaction = false
    @Published var showPrivacySettings = false
    @Published var syncStatus: SyncStatus = .synced

    private let cloudKitManager = CloudKitSyncManager.shared
    private var syncTimer: Timer?

    enum SyncStatus: String {
        case synced = "Синхронизировано"
        case syncing = "Синхронизация..."
        case error = "Ошибка синхронизации"
        case offline = "Офлайн"
    }

    init() {
        setupRealtimeSync()
        loadBudgets()
    }

    private func setupRealtimeSync() {
        // CloudKit subscription for real-time updates
        Task {
            await cloudKitManager.subscribeToBudgetChanges { [weak self] updatedBudget in
                await MainActor.run {
                    self?.handleBudgetUpdate(updatedBudget)
                }
            }
        }

        // Periodic sync check
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkSyncStatus()
        }
    }

    private func handleBudgetUpdate(_ budget: SharedBudget) {
        if let index = budgets.firstIndex(where: { $0.id == budget.id }) {
            withAnimation {
                budgets[index] = budget
                if selectedBudget?.id == budget.id {
                    selectedBudget = budget
                }
            }
        }
    }

    private func checkSyncStatus() {
        Task {
            let status = await cloudKitManager.getSyncStatus()
            await MainActor.run {
                self.syncStatus = status
            }
        }
    }

    func loadBudgets() {
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let fetched = try await cloudKitManager.fetchSharedBudgets()
                budgets = fetched
            } catch {
                syncStatus = .error
            }
        }
    }

    func createBudget(name: String, total: Double, period: SharedBudget.BudgetPeriod, members: [Contact], categories: [BudgetCategory]) async {
        let budgetMembers = members.map { contact in
            BudgetMember(
                id: UUID(),
                contact: contact,
                role: .member,
                spendingLimit: nil,
                spent: 0,
                joinedAt: Date(),
                notificationSettings: BudgetMember.NotificationSettings()
            )
        }

        let (startDate, endDate) = calculatePeriodDates(period: period)

        let budget = SharedBudget(
            id: UUID(),
            name: name,
            icon: "chart.pie.fill",
            color: .emerald,
            totalBudget: total,
            spent: 0,
            period: period,
            startDate: startDate,
            endDate: endDate,
            members: budgetMembers,
            categories: categories,
            alerts: defaultAlerts(),
            isRecurring: true,
            privacySettings: BudgetPrivacySettings()
        )

        do {
            try await cloudKitManager.saveSharedBudget(budget)
            budgets.append(budget)
        } catch {
            syncStatus = .error
        }
    }

    func addTransaction(to budgetID: UUID, amount: Double, category: BudgetCategory, description: String, member: BudgetMember) async {
        guard let index = budgets.firstIndex(where: { $0.id == budgetID }) else { return }

        // Check approval requirement
        if budgets[index].privacySettings.requireApproval && amount > budgets[index].privacySettings.approvalThreshold {
            // Create pending transaction
            let transaction = BudgetTransaction(
                id: UUID(),
                amount: amount,
                category: category,
                description: description,
                member: member,
                timestamp: Date(),
                receiptImage: nil,
                location: nil,
                isApproved: false,
                approvedBy: nil
            )

            try? await cloudKitManager.savePendingTransaction(transaction, to: budgetID)
            await sendApprovalRequest(for: transaction, in: budgets[index])
            return
        }

        // Direct transaction
        budgets[index].spent += amount
        if let catIndex = budgets[index].categories.firstIndex(where: { $0.id == category.id }) {
            budgets[index].categories[catIndex].spent += amount
        }

        if let memberIndex = budgets[index].members.firstIndex(where: { $0.id == member.id }) {
            budgets[index].members[memberIndex].spent += amount
        }

        let transaction = BudgetTransaction(
            id: UUID(),
            amount: amount,
            category: category,
            description: description,
            member: member,
            timestamp: Date(),
            receiptImage: nil,
            location: nil,
            isApproved: true,
            approvedBy: nil
        )

        do {
            try await cloudKitManager.saveBudgetTransaction(transaction, to: budgetID)
            try await cloudKitManager.updateSharedBudget(budgets[index])
            checkAlerts(for: budgets[index])
        } catch {
            syncStatus = .error
        }
    }

    func approveTransaction(_ transaction: BudgetTransaction, in budget: SharedBudget, by approver: BudgetMember) async {
        guard let index = budgets.firstIndex(where: { $0.id == budget.id }) else { return }

        budgets[index].spent += transaction.amount
        if let catIndex = budgets[index].categories.firstIndex(where: { $0.id == transaction.category.id }) {
            budgets[index].categories[catIndex].spent += transaction.amount
        }

        var updatedTransaction = transaction
        updatedTransaction.isApproved = true
        updatedTransaction.approvedBy = approver

        try? await cloudKitManager.saveBudgetTransaction(updatedTransaction, to: budget.id)
        try? await cloudKitManager.updateSharedBudget(budgets[index])
    }

    func updatePrivacySettings(for budgetID: UUID, settings: BudgetPrivacySettings) {
        guard let index = budgets.firstIndex(where: { $0.id == budgetID }) else { return }
        budgets[index].privacySettings = settings

        Task {
            try? await cloudKitManager.updateSharedBudget(budgets[index])
        }
    }

    private func calculatePeriodDates(period: SharedBudget.BudgetPeriod) -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .weekly:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            return (start, end)
        case .monthly:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        case .quarterly:
            let quarter = (calendar.component(.month, from: now) - 1) / 3
            let startMonth = quarter * 3 + 1
            let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: startMonth, day: 1))!
            let end = calendar.date(byAdding: .month, value: 3, to: start)!
            return (start, end)
        case .yearly:
            let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1))!
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        case .custom:
            return (now, calendar.date(byAdding: .month, value: 1, to: now)!)
        }
    }

    private func defaultAlerts() -> [BudgetAlert] {
        [
            BudgetAlert(id: UUID(), type: .percentage, threshold: 50, isEnabled: true, message: "Половина бюджета израсходована"),
            BudgetAlert(id: UUID(), type: .percentage, threshold: 80, isEnabled: true, message: "Осталось 20% бюджета"),
            BudgetAlert(id: UUID(), type: .percentage, threshold: 100, isEnabled: true, message: "Бюджет исчерпан!")
        ]
    }

    private func checkAlerts(for budget: SharedBudget) {
        for alert in budget.alerts where alert.isEnabled {
            let triggered: Bool
            switch alert.type {
            case .percentage:
                triggered = budget.progress * 100 >= alert.threshold
            case .fixedAmount:
                triggered = budget.spent >= alert.threshold
            case .dailyAverage:
                let daysPassed = Calendar.current.dateComponents([.day], from: budget.startDate, to: Date()).day ?? 1
                let dailyAvg = daysPassed > 0 ? budget.spent / Double(daysPassed) : 0
                triggered = dailyAvg >= alert.threshold
            }

            if triggered {
                sendAlertNotification(alert: alert, budget: budget)
            }
        }
    }

    private func sendAlertNotification(alert: BudgetAlert, budget: SharedBudget) {
        // Send local + push notifications to all members
        for member in budget.members where member.notificationSettings.overspendAlerts {
            Task {
                await NearbyPaymentManager.shared.sendBudgetAlert(to: member.contact, message: alert.message, budgetName: budget.name)
            }
        }
    }

    private func sendApprovalRequest(for transaction: BudgetTransaction, in budget: SharedBudget) async {
        let managers = budget.members.filter { $0.role == .owner || $0.role == .manager }
        for manager in managers {
            await NearbyPaymentManager.shared.sendApprovalRequest(
                to: manager.contact,
                transaction: transaction,
                budgetName: budget.name
            )
        }
    }
}

// MARK: - Views
struct SharedBudgetView: View {
    @StateObject private var viewModel = SharedBudgetViewModel()
    @State private var showCreateBudget = false
    @State private var showBudgetDetail: SharedBudget?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Sync Status
                        syncStatusBar

                        // Header
                        headerSection

                        // Budgets List
                        budgetsList

                        // Quick Stats
                        quickStatsSection
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Семейный бюджет")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showCreateBudget = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showCreateBudget) {
                CreateBudgetSheet(viewModel: viewModel)
            }
            .navigationDestination(item: $showBudgetDetail) { budget in
                BudgetDetailView(budget: budget, viewModel: viewModel)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private var syncStatusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(syncColor)
                .frame(width: 8, height: 8)

            Text(viewModel.syncStatus.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.syncStatus == .error {
                Button(action: { viewModel.loadBudgets() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }

    private var syncColor: Color {
        switch viewModel.syncStatus {
        case .synced: return .green
        case .syncing: return .orange
        case .error: return .red
        case .offline: return .gray
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Управляйте бюджетом вместе")
                .font(.title2.bold())

            Text("Создавайте семейные бюджеты с автоматической синхронизацией между всеми устройствами")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var budgetsList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.budgets) { budget in
                BudgetCard(budget: budget) {
                    showBudgetDetail = budget
                }
            }

            // Add New
            Button(action: { showCreateBudget = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green.opacity(0.6))

                    Text("Создать бюджет")
                        .font(.callout.bold())
                        .foregroundStyle(.green)

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .stroke(Color.green.opacity(0.2), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Обзор")
                .font(.headline)

            HStack(spacing: 12) {
                StatCard(
                    title: "Всего бюджетов",
                    value: "\(viewModel.budgets.count)",
                    icon: "chart.pie.fill",
                    color: .blue
                )

                StatCard(
                    title: "Общий расход",
                    value: "\(viewModel.budgets.reduce(0) { $0 + $1.spent }, format: .currency(code: "RUB"))",
                    icon: "arrow.up.forward",
                    color: .orange
                )
            }

            HStack(spacing: 12) {
                StatCard(
                    title: "Остаток",
                    value: "\(viewModel.budgets.reduce(0) { $0 + $1.remaining }, format: .currency(code: "RUB"))",
                    icon: "arrow.down.forward",
                    color: .green
                )

                StatCard(
                    title: "Участников",
                    value: "\(viewModel.budgets.flatMap(\.members).count)",
                    icon: "person.3.fill",
                    color: .purple
                )
            }
        }
        .padding(.top, 8)
    }
}

struct BudgetCard: View {
    let budget: SharedBudget
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: budget.icon)
                            .font(.title3)
                            .foregroundStyle(budget.color.swiftColor)

                        Text(budget.name)
                            .font(.headline)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("\(budget.members.count)")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .foregroundStyle(.secondary)
                }

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(budget.isOverBudget ? Color.red : budget.color.swiftColor)
                            .frame(width: min(CGFloat(budget.progress) * geo.size.width, geo.size.width), height: 8)
                            .animation(.easeInOut(duration: 0.5), value: budget.progress)
                    }
                }
                .frame(height: 8)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Израсходовано")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(budget.spent, format: .currency(code: "RUB"))
                            .font(.subheadline.bold())
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Остаток")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(budget.remaining, format: .currency(code: "RUB"))
                            .font(.subheadline.bold())
                            .foregroundStyle(budget.isOverBudget ? .red : .green)
                    }
                }

                // Period Badge
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text("\(budget.startDate, style: .date) — \(budget.endDate, style: .date)")
                        .font(.caption2)

                    Spacer()

                    if budget.isRecurring {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.2.circlepath")
                                .font(.caption2)
                            Text("Повторяется")
                                .font(.caption2)
                        }
                        .foregroundStyle(.blue)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(budget.color.swiftColor.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct BudgetDetailView: View {
    let budget: SharedBudget
    @ObservedObject var viewModel: SharedBudgetViewModel
    @State private var showAddTransaction = false
    @State private var showPrivacySettings = false
    @State private var selectedSegment = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Budget Header
                budgetHeader

                // Segmented Control
                Picker("", selection: $selectedSegment) {
                    Text("Обзор").tag(0)
                    Text("Категории").tag(1)
                    Text("Участники").tag(2)
                    Text("История").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Content based on segment
                switch selectedSegment {
                case 0:
                    overviewTab
                case 1:
                    categoriesTab
                case 2:
                    membersTab
                case 3:
                    historyTab
                default:
                    EmptyView()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(budget.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showAddTransaction = true }) {
                        Label("Добавить расход", systemImage: "plus")
                    }

                    Button(action: { showPrivacySettings = true }) {
                        Label("Приватность", systemImage: "lock.shield")
                    }

                    Button(action: {}) {
                        Label("Настройки уведомлений", systemImage: "bell.badge")
                    }

                    Divider()

                    Button(role: .destructive, action: {}) {
                        Label("Удалить бюджет", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                }
            }
        }
        .sheet(isPresented: $showAddTransaction) {
            AddBudgetTransactionSheet(budget: budget, viewModel: viewModel)
        }
        .sheet(isPresented: $showPrivacySettings) {
            BudgetPrivacySheet(budget: budget, viewModel: viewModel)
        }
    }

    private var budgetHeader: some View {
        VStack(spacing: 16) {
            // Circular Progress
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 20)
                    .frame(width: 180, height: 180)

                Circle()
                    .trim(from: 0, to: min(CGFloat(budget.progress), 1.0))
                    .stroke(
                        budget.isOverBudget ? Color.red : budget.color.swiftColor,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: budget.progress)

                VStack(spacing: 4) {
                    Text("\(Int(budget.progress * 100))%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))

                    Text("из \(budget.totalBudget, format: .currency(code: "RUB"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)

            // Stats Row
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(budget.spent, format: .currency(code: "RUB"))
                        .font(.title3.bold())
                        .foregroundStyle(.red)
                    Text("Расход")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text(budget.remaining, format: .currency(code: "RUB"))
                        .font(.title3.bold())
                        .foregroundStyle(budget.isOverBudget ? .red : .green)
                    Text("Остаток")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: budget.endDate).day ?? 0
                    Text("\(daysLeft)")
                        .font(.title3.bold())
                        .foregroundStyle(daysLeft < 7 ? .orange : .primary)
                    Text("Дней осталось")
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
        .padding(.horizontal)
    }

    private var overviewTab: some View {
        VStack(spacing: 16) {
            // Daily Average
            VStack(alignment: .leading, spacing: 8) {
                Text("Средний дневной расход")
                    .font(.headline)

                let daysPassed = max(Calendar.current.dateComponents([.day], from: budget.startDate, to: Date()).day ?? 1, 1)
                let dailyAvg = budget.spent / Double(daysPassed)
                let projected = dailyAvg * Double(Calendar.current.dateComponents([.day], from: budget.startDate, to: budget.endDate).day ?? 30)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dailyAvg, format: .currency(code: "RUB"))
                            .font(.title2.bold())
                        Text("в день")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(projected, format: .currency(code: "RUB"))
                            .font(.title2.bold())
                            .foregroundStyle(projected > budget.totalBudget ? .red : .primary)
                        Text("прогноз на период")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if projected > budget.totalBudget {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("При текущем темпе бюджет будет превышен")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal)

            // Top Categories
            VStack(alignment: .leading, spacing: 12) {
                Text("Топ категорий")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(budget.categories.sorted(by: { $0.spent > $1.spent }).prefix(3)) { category in
                    CategoryMiniRow(category: category)
                }
                .padding(.horizontal)
            }

            // Alerts
            if !budget.alerts.filter(\.isEnabled).isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Уведомления")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(budget.alerts.filter(\.isEnabled)) { alert in
                        AlertRow(alert: alert, budget: budget)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var categoriesTab: some View {
        VStack(spacing: 12) {
            ForEach(budget.categories) { category in
                CategoryDetailRow(category: category)
            }
            .padding(.horizontal)
        }
    }

    private var membersTab: some View {
        VStack(spacing: 12) {
            ForEach(budget.members) { member in
                BudgetMemberRow(member: member, totalBudget: budget.totalBudget)
            }
            .padding(.horizontal)
        }
    }

    private var historyTab: some View {
        VStack(spacing: 12) {
            // Placeholder for transaction history
            Text("История транзакций")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            ForEach(0..<5) { _ in
                HistoryRow()
            }
            .padding(.horizontal)
        }
    }
}

struct CategoryMiniRow: View {
    let category: BudgetCategory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(category.color.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: category.icon)
                    .foregroundStyle(category.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.subheadline.bold())

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray5))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(category.color)
                            .frame(width: CGFloat(category.progress) * geo.size.width, height: 4)
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            Text(category.spent, format: .currency(code: "RUB"))
                .font(.subheadline.bold())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct CategoryDetailRow: View {
    let category: BudgetCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .foregroundStyle(category.color)
                    Text(category.name)
                        .font(.subheadline.bold())
                }

                Spacer()

                Text("\(category.spent, format: .currency(code: "RUB")) / \(category.allocated, format: .currency(code: "RUB"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(category.progress > 1.0 ? Color.red : category.color)
                        .frame(width: min(CGFloat(category.progress) * geo.size.width, geo.size.width), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Int(category.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Осталось: \(category.remaining, format: .currency(code: "RUB"))")
                    .font(.caption2)
                    .foregroundStyle(category.remaining < 0 ? .red : .secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct BudgetMemberRow: View {
    let member: BudgetMember
    let totalBudget: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.random.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(String(member.contact.name.prefix(1)))
                    .font(.callout.bold())
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.contact.name)
                        .font(.subheadline.bold())

                    if member.role == .owner {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }

                    Spacer()

                    Text(member.spent, format: .currency(code: "RUB"))
                        .font(.subheadline.bold())
                }

                if let limit = member.spendingLimit {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemGray5))
                                .frame(height: 4)

                            let progress = limit > 0 ? member.spent / limit : 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(progress > 1.0 ? Color.red : Color.blue)
                                .frame(width: min(CGFloat(progress) * geo.size.width, geo.size.width), height: 4)
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        Text("Лимит: \(limit, format: .currency(code: "RUB"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        let percentage = limit > 0 ? Int((member.spent / limit) * 100) : 0
                        Text("\(percentage)%")
                            .font(.caption2)
                            .foregroundStyle(percentage > 100 ? .red : .secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct AlertRow: View {
    let alert: BudgetAlert
    let budget: SharedBudget

    var isTriggered: Bool {
        switch alert.type {
        case .percentage:
            return budget.progress * 100 >= alert.threshold
        case .fixedAmount:
            return budget.spent >= alert.threshold
        case .dailyAverage:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isTriggered ? "exclamationmark.circle.fill" : "bell.fill")
                .foregroundStyle(isTriggered ? .orange : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.message)
                    .font(.subheadline)

                HStack(spacing: 4) {
                    Text(alert.type.rawValue)
                        .font(.caption2)
                    Text("•")
                    Text("\(Int(alert.threshold))")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: .constant(alert.isEnabled))
                .labelsHidden()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTriggered ? Color.orange.opacity(0.1) : Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isTriggered ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

struct HistoryRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: "cart.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Продукты")
                    .font(.subheadline.bold())
                Text("Вчера, 14:30")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("-2,450 ₽")
                .font(.subheadline.bold())
                .foregroundStyle(.red)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.title3.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Sheets
struct CreateBudgetSheet: View {
    @ObservedObject var viewModel: SharedBudgetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var totalBudget = ""
    @State private var selectedPeriod: SharedBudget.BudgetPeriod = .monthly
    @State private var selectedMembers: [Contact] = []
    @State private var categories: [BudgetCategory] = defaultCategories()
    @State private var selectedColor: SharedBudget.BudgetColor = .emerald

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: Семейный бюджет", text: $name)
                }

                Section("Сумма бюджета") {
                    TextField("50000", text: $totalBudget)
                        .keyboardType(.decimalPad)
                }

                Section("Период") {
                    Picker("Период", selection: $selectedPeriod) {
                        ForEach(SharedBudget.BudgetPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Цвет") {
                    HStack(spacing: 12) {
                        ForEach(SharedBudget.BudgetColor.allCases, id: \.self) { color in
                            BudgetColorCircle(color: color, isSelected: selectedColor == color) {
                                selectedColor = color
                            }
                        }
                    }
                }

                Section("Участники") {
                    ContactPicker(selectedContacts: $selectedMembers)
                }

                Section("Категории") {
                    ForEach($categories) { $category in
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundStyle(category.color)
                            Text(category.name)
                            Spacer()
                            TextField("0", value: $category.allocated, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }
            }
            .navigationTitle("Новый бюджет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        Task {
                            if let total = Double(totalBudget) {
                                await viewModel.createBudget(
                                    name: name,
                                    total: total,
                                    period: selectedPeriod,
                                    members: selectedMembers,
                                    categories: categories.filter { $0.allocated > 0 }
                                )
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.isEmpty || totalBudget.isEmpty || selectedMembers.isEmpty)
                }
            }
        }
    }
}

struct BudgetColorCircle: View {
    let color: SharedBudget.BudgetColor
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

struct AddBudgetTransactionSheet: View {
    let budget: SharedBudget
    @ObservedObject var viewModel: SharedBudgetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var description = ""
    @State private var selectedCategory: BudgetCategory?
    @State private var selectedMember: BudgetMember?

    var body: some View {
        NavigationStack {
            Form {
                Section("Сумма") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }

                Section("Описание") {
                    TextField("За что?", text: $description)
                }

                Section("Категория") {
                    Picker("Категория", selection: $selectedCategory) {
                        ForEach(budget.categories) { category in
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundStyle(category.color)
                                Text(category.name)
                            }
                            .tag(category as BudgetCategory?)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Кто потратил") {
                    Picker("Участник", selection: $selectedMember) {
                        ForEach(budget.members) { member in
                            Text(member.contact.name).tag(member as BudgetMember?)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if budget.privacySettings.requireApproval, let amt = Double(amount), amt > budget.privacySettings.approvalThreshold {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Требуется одобрение: сумма превышает \(budget.privacySettings.approvalThreshold, format: .currency(code: "RUB"))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Новый расход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            if let amountValue = Double(amount),
                               let category = selectedCategory,
                               let member = selectedMember {
                                await viewModel.addTransaction(
                                    to: budget.id,
                                    amount: amountValue,
                                    category: category,
                                    description: description,
                                    member: member
                                )
                                dismiss()
                            }
                        }
                    }
                    .disabled(amount.isEmpty || description.isEmpty || selectedCategory == nil || selectedMember == nil)
                }
            }
        }
    }
}

struct BudgetPrivacySheet: View {
    let budget: SharedBudget
    @ObservedObject var viewModel: SharedBudgetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings: BudgetPrivacySettings

    init(budget: SharedBudget, viewModel: SharedBudgetViewModel) {
        self.budget = budget
        self.viewModel = viewModel
        _settings = State(initialValue: budget.privacySettings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Видимость") {
                    Toggle("Показывать полные детали", isOn: $settings.showFullDetails)
                    Toggle("Показывать только общую сумму", isOn: $settings.showOnlyTotal)
                }

                Section("Контроль расходов") {
                    Toggle("Разрешить участникам тратить", isOn: $settings.allowMemberSpending)
                    Toggle("Требовать одобрение", isOn: $settings.requireApproval)

                    if settings.requireApproval {
                        HStack {
                            Text("Порог одобрения")
                            Spacer()
                            TextField("5000", value: $settings.approvalThreshold, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text("₽")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Скрыть от") {
                    ForEach(budget.members) { member in
                        Toggle(member.contact.name, isOn: binding(for: member))
                    }
                }
            }
            .navigationTitle("Приватность")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        viewModel.updatePrivacySettings(for: budget.id, settings: settings)
                        dismiss()
                    }
                }
            }
        }
    }

    private func binding(for member: BudgetMember) -> Binding<Bool> {
        Binding(
            get: { settings.hideFromMembers.contains(member.id) },
            set: { isHidden in
                if isHidden {
                    settings.hideFromMembers.append(member.id)
                } else {
                    settings.hideFromMembers.removeAll { $0 == member.id }
                }
            }
        )
    }
}

func defaultCategories() -> [BudgetCategory] {
    [
        BudgetCategory(id: UUID(), name: "Продукты", icon: "cart.fill", allocated: 0, spent: 0, color: .orange),
        BudgetCategory(id: UUID(), name: "Транспорт", icon: "car.fill", allocated: 0, spent: 0, color: .blue),
        BudgetCategory(id: UUID(), name: "Развлечения", icon: "film.fill", allocated: 0, spent: 0, color: .purple),
        BudgetCategory(id: UUID(), name: "Здоровье", icon: "heart.fill", allocated: 0, spent: 0, color: .red),
        BudgetCategory(id: UUID(), name: "Образование", icon: "book.fill", allocated: 0, spent: 0, color: .green),
        BudgetCategory(id: UUID(), name: "Другое", icon: "tag.fill", allocated: 0, spent: 0, color: .gray)
    ]
}

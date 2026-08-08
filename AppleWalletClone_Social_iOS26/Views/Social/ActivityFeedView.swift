import SwiftUI

// MARK: - Models
enum ActivityType: String {
    case transaction = "Транзакция"
    case goalContribution = "Взнос в цель"
    case challengeUpdate = "Обновление челленджа"
    case budgetAlert = "Уведомление бюджета"
    case splitBill = "Разделение чека"
    case invite = "Приглашение"
    case milestone = "Веха достигнута"
    case comment = "Комментарий"
    case paymentRequest = "Запрос денег"
    case nearbyPayment = "Оплата рядом"
}

struct ActivityItem: Identifiable, Hashable {
    let id: UUID
    var type: ActivityType
    var actor: SocialContact
    var target: String
    var amount: Double?
    var description: String
    var timestamp: Date
    var privacyLevel: ActivityPrivacy
    var isRead: Bool
    var relatedObjectID: UUID?
    var location: String?
    var image: Data?
    var reactions: [ActivityReaction]
    var comments: [ActivityComment]

    enum ActivityPrivacy: String, CaseIterable {
        case public_ = "Все"
        case friends = "Друзья"
        case family = "Семья"
        case private_ = "Только я"
    }

    var icon: String {
        switch type {
        case .transaction: return "creditcard.fill"
        case .goalContribution: return "arrow.up.heart.fill"
        case .challengeUpdate: return "trophy.fill"
        case .budgetAlert: return "exclamationmark.triangle.fill"
        case .splitBill: return "doc.text.fill"
        case .invite: return "person.badge.plus"
        case .milestone: return "flag.checkered"
        case .comment: return "bubble.left.fill"
        case .paymentRequest: return "arrow.down.circle.fill"
        case .nearbyPayment: return "wave.3.right"
        }
    }

    var color: Color {
        switch type {
        case .transaction: return .blue
        case .goalContribution: return .green
        case .challengeUpdate: return .purple
        case .budgetAlert: return .orange
        case .splitBill: return .teal
        case .invite: return .pink
        case .milestone: return .yellow
        case .comment: return .indigo
        case .paymentRequest: return .red
        case .nearbyPayment: return .cyan
        }
    }
}

struct ActivityReaction: Identifiable {
    let id: UUID
    var emoji: String
    var actors: [SocialContact]
}

struct ActivityComment: Identifiable {
    let id: UUID
    var author: SocialContact
    var text: String
    var timestamp: Date
}

struct PrivacySettings: Codable {
    var showTransactions: ActivityItem.ActivityPrivacy = .friends
    var showGoals: ActivityItem.ActivityPrivacy = .friends
    var showChallenges: ActivityItem.ActivityPrivacy = .public_
    var showBudgetAlerts: ActivityItem.ActivityPrivacy = .family
    var showLocation: Bool = false
    var showAmounts: Bool = true
    var allowReactions: Bool = true
    var allowComments: Bool = true
}

// MARK: - ViewModel
@MainActor
class ActivityFeedViewModel: ObservableObject {
    @Published var activities: [ActivityItem] = []
    @Published var filteredActivities: [ActivityItem] = []
    @Published var isLoading = false
    @Published var selectedFilter: ActivityFilter = .all
    @Published var privacySettings = PrivacySettings()
    @Published var showPrivacySheet = false
    @Published var unreadCount = 0

    enum ActivityFilter: String, CaseIterable {
        case all = "Все"
        case transactions = "Транзакции"
        case goals = "Накопления"
        case challenges = "Челленджи"
        case social = "Социальное"
    }

    private let cloudKitManager = CloudKitSyncManager.shared

    func loadActivities() {
        Task {
            isLoading = true
            defer { isLoading = false }

            activities = createMockActivities()
            applyFilter()
            updateUnreadCount()
        }
    }

    func applyFilter() {
        switch selectedFilter {
        case .all:
            filteredActivities = activities
        case .transactions:
            filteredActivities = activities.filter { $0.type == .transaction || $0.type == .splitBill || $0.type == .nearbyPayment }
        case .goals:
            filteredActivities = activities.filter { $0.type == .goalContribution || $0.type == .milestone }
        case .challenges:
            filteredActivities = activities.filter { $0.type == .challengeUpdate }
        case .social:
            filteredActivities = activities.filter { $0.type == .comment || $0.type == .invite || $0.type == .paymentRequest }
        }
    }

    func markAsRead(_ activity: ActivityItem) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index].isRead = true
            updateUnreadCount()
        }
    }

    func markAllAsRead() {
        for index in activities.indices {
            activities[index].isRead = true
        }
        updateUnreadCount()
    }

    func addReaction(_ emoji: String, to activityID: UUID) {
        guard let index = activities.firstIndex(where: { $0.id == activityID }) else { return }

        let currentUser = SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .blue, isCurrentUser: true)

        if let reactionIndex = activities[index].reactions.firstIndex(where: { $0.emoji == emoji }) {
            if activities[index].reactions[reactionIndex].actors.contains(currentUser) {
                activities[index].reactions[reactionIndex].actors.removeAll { $0.id == currentUser.id }
            } else {
                activities[index].reactions[reactionIndex].actors.append(currentUser)
            }
        } else {
            let newReaction = ActivityReaction(id: UUID(), emoji: emoji, actors: [currentUser])
            activities[index].reactions.append(newReaction)
        }

        Task {
            try? await cloudKitManager.updateActivity(activities[index])
        }
    }

    func addComment(_ text: String, to activityID: UUID) {
        guard let index = activities.firstIndex(where: { $0.id == activityID }) else { return }

        let currentUser = SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .blue, isCurrentUser: true)
        let comment = ActivityComment(id: UUID(), author: currentUser, text: text, timestamp: Date())

        activities[index].comments.append(comment)

        Task {
            try? await cloudKitManager.updateActivity(activities[index])
        }
    }

    func updatePrivacySettings(_ settings: PrivacySettings) {
        privacySettings = settings
        Task {
            try? await cloudKitManager.savePrivacySettings(settings)
        }
    }

    private func updateUnreadCount() {
        unreadCount = activities.filter { !$0.isRead }.count
    }

    private func createMockActivities() -> [ActivityItem] {
        let contacts = [
            SocialContact(id: UUID(), name: "Анна", avatar: nil, color: .pink, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Михаил", avatar: nil, color: .blue, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Елена", avatar: nil, color: .purple, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Дмитрий", avatar: nil, color: .orange, isCurrentUser: false),
            SocialContact(id: UUID(), name: "София", avatar: nil, color: .teal, isCurrentUser: false)
        ]

        return [
            ActivityItem(
                id: UUID(),
                type: .goalContribution,
                actor: contacts[0],
                target: "Поездка в Японию",
                amount: 5000,
                description: "Внесла ежемесячный взнос в общую цель",
                timestamp: Date().addingTimeInterval(-300),
                privacyLevel: .friends,
                isRead: false,
                relatedObjectID: nil,
                location: nil,
                image: nil,
                reactions: [ActivityReaction(id: UUID(), emoji: "❤️", actors: [contacts[1], contacts[2]])],
                comments: []
            ),
            ActivityItem(
                id: UUID(),
                type: .challengeUpdate,
                actor: contacts[1],
                target: "Кто меньше потратит на кофе",
                amount: nil,
                description: "Возглавил таблицу лидеров с серией в 5 дней!",
                timestamp: Date().addingTimeInterval(-900),
                privacyLevel: .public_,
                isRead: false,
                relatedObjectID: nil,
                location: nil,
                image: nil,
                reactions: [ActivityReaction(id: UUID(), emoji: "🔥", actors: [contacts[0], contacts[3]])],
                comments: [ActivityComment(id: UUID(), author: contacts[2], text: "Как ты это делаешь?!", timestamp: Date().addingTimeInterval(-600))]
            ),
            ActivityItem(
                id: UUID(),
                type: .transaction,
                actor: contacts[2],
                target: "Ресторан «Сакура»",
                amount: 3400,
                description: "Оплата ужина через Split Bill",
                timestamp: Date().addingTimeInterval(-1800),
                privacyLevel: .friends,
                isRead: true,
                relatedObjectID: nil,
                location: "Москва, Тверская",
                image: nil,
                reactions: [],
                comments: []
            ),
            ActivityItem(
                id: UUID(),
                type: .milestone,
                actor: contacts[0],
                target: "Новый MacBook",
                amount: nil,
                description: "Достигнута веха «Половина пути»! 150000₽ накоплено",
                timestamp: Date().addingTimeInterval(-3600),
                privacyLevel: .friends,
                isRead: true,
                relatedObjectID: nil,
                location: nil,
                image: nil,
                reactions: [ActivityReaction(id: UUID(), emoji: "🎉", actors: [contacts[1], contacts[2], contacts[3]])],
                comments: []
            ),
            ActivityItem(
                id: UUID(),
                type: .budgetAlert,
                actor: contacts[3],
                target: "Семейный бюджет",
                amount: nil,
                description: "Превышен лимит на категорию «Развлечения»",
                timestamp: Date().addingTimeInterval(-7200),
                privacyLevel: .family,
                isRead: true,
                relatedObjectID: nil,
                location: nil,
                image: nil,
                reactions: [ActivityReaction(id: UUID(), emoji: "😅", actors: [contacts[0]])],
                comments: [ActivityComment(id: UUID(), author: contacts[4], text: "Нужно быть осторожнее в следующем месяце", timestamp: Date().addingTimeInterval(-6600))]
            ),
            ActivityItem(
                id: UUID(),
                type: .nearbyPayment,
                actor: contacts[4],
                target: "Анна",
                amount: 1200,
                description: "Отправила деньги через Nearby Payment",
                timestamp: Date().addingTimeInterval(-10800),
                privacyLevel: .friends,
                isRead: true,
                relatedObjectID: nil,
                location: "Кафе «Друзья»",
                image: nil,
                reactions: [ActivityReaction(id: UUID(), emoji: "👍", actors: [contacts[0]])],
                comments: []
            ),
            ActivityItem(
                id: UUID(),
                type: .comment,
                actor: contacts[1],
                target: "Такси до аэропорта",
                amount: nil,
                description: "Прокомментировал транзакцию: «Давайте в следующий раз возьмем Яндекс»",
                timestamp: Date().addingTimeInterval(-14400),
                privacyLevel: .friends,
                isRead: true,
                relatedObjectID: nil,
                location: nil,
                image: nil,
                reactions: [],
                comments: []
            ),
            ActivityItem(
                id: UUID(),
                type: .paymentRequest,
                actor: contacts[2],
                target: "Вы",
                amount: 2500,
                description: "Запросила возврат за концертные билеты",
                timestamp: Date().addingTimeInterval(-21600),
                privacyLevel: .private_,
                isRead: false,
                relatedObjectID: nil,
                location: nil,
                image: nil,
                reactions: [],
                comments: []
            ),
            ActivityItem(
                id: UUID(),
                type: .invite,
                actor: contacts[3],
                target: "Групповой кошелек «Поездка в Сочи»",
                amount: nil,
                description: "Пригласил в новый групповой кошелек",
                timestamp: Date().addingTimeInterval(-43200),
                privacyLevel: .friends,
                isRead: true,
                relatedObjectID: nil,
                location: nil,
                image: nil,
                reactions: [ActivityReaction(id: UUID(), emoji: "✈️", actors: [contacts[0], contacts[1]])],
                comments: [ActivityComment(id: UUID(), author: contacts[0], text: "Обязательно присоединюсь!", timestamp: Date().addingTimeInterval(-40000))]
            )
        ]
    }
}

// MARK: - Views
struct ActivityFeedView: View {
    @StateObject private var viewModel = ActivityFeedViewModel()
    @State private var showPrivacySettings = false
    @State private var commentText = ""
    @State private var commentingOn: ActivityItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Filter Bar
                    filterBar

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.filteredActivities) { activity in
                                ActivityCard(activity: activity, viewModel: viewModel)
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        viewModel.loadActivities()
                    }
                }
            }
            .navigationTitle("Лента")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { viewModel.markAllAsRead() }) {
                        if viewModel.unreadCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "envelope.open.fill")
                                    .font(.caption)
                                Text("\(viewModel.unreadCount)")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                    .disabled(viewModel.unreadCount == 0)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showPrivacySettings = true }) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showPrivacySettings) {
                ActivityPrivacySheet(viewModel: viewModel)
            }
            .onAppear {
                viewModel.loadActivities()
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFeedViewModel.ActivityFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        withAnimation {
                            viewModel.selectedFilter = filter
                            viewModel.applyFilter()
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
    }
}

struct ActivityCard: View {
    let activity: ActivityItem
    @ObservedObject var viewModel: ActivityFeedViewModel
    @State private var showReactionPicker = false
    @State private var showComments = false
    @State private var commentText = ""
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(activity.actor.color.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Text(String(activity.actor.name.prefix(1)))
                        .font(.callout.bold())
                        .foregroundStyle(activity.actor.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(activity.actor.name)
                            .font(.subheadline.bold())

                        Text(activity.type.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text(activity.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        // Privacy indicator
                        HStack(spacing: 2) {
                            Image(systemName: privacyIcon)
                                .font(.system(size: 8))
                            Text(activity.privacyLevel.rawValue)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !activity.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(activity.color.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: activity.icon)
                        .font(.callout)
                        .foregroundStyle(activity.color)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 8) {
                if let amount = activity.amount, viewModel.privacySettings.showAmounts {
                    Text(amount, format: .currency(code: "RUB"))
                        .font(.title3.bold())
                        .foregroundStyle(activity.color)
                }

                Text(activity.description)
                    .font(.subheadline)

                if let location = activity.location, viewModel.privacySettings.showLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Reactions & Comments
            if viewModel.privacySettings.allowReactions || viewModel.privacySettings.allowComments {
                VStack(spacing: 8) {
                    // Reactions
                    if !activity.reactions.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(activity.reactions) { reaction in
                                Button(action: {
                                    viewModel.addReaction(reaction.emoji, to: activity.id)
                                }) {
                                    HStack(spacing: 2) {
                                        Text(reaction.emoji)
                                            .font(.callout)
                                        if reaction.actors.count > 1 {
                                            Text("\(reaction.actors.count)")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color(.systemGray5))
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Button(action: { showReactionPicker = true }) {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if viewModel.privacySettings.allowReactions {
                        Button(action: { showReactionPicker = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "face.smiling")
                                    .font(.caption)
                                Text("Реакция")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    // Comments preview
                    if !activity.comments.isEmpty && viewModel.privacySettings.allowComments {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(activity.comments.prefix(isExpanded ? 10 : 2)) { comment in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(comment.author.color)
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Text(String(comment.author.name.prefix(1)))
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundStyle(.white)
                                        )

                                    Text("**\(comment.author.name)** \(comment.text)")
                                        .font(.caption)
                                }
                            }

                            if activity.comments.count > 2 && !isExpanded {
                                Button(action: { isExpanded = true }) {
                                    Text("Ещё \(activity.comments.count - 2) комментариев")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    // Comment input
                    if viewModel.privacySettings.allowComments {
                        HStack(spacing: 8) {
                            TextField("Комментарий...", text: $commentText)
                                .font(.caption)

                            Button(action: {
                                if !commentText.isEmpty {
                                    viewModel.addComment(commentText, to: activity.id)
                                    commentText = ""
                                }
                            }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(commentText.isEmpty ? .gray : .blue)
                            }
                            .disabled(commentText.isEmpty)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray6))
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(!activity.isRead ? activity.color.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .onTapGesture {
            if !activity.isRead {
                viewModel.markAsRead(activity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showReactionPicker {
                ReactionPicker(
                    emojis: ["👍", "❤️", "🔥", "🎉", "😮", "👏", "💰", "😂"],
                    onSelect: { emoji in
                        viewModel.addReaction(emoji, to: activity.id)
                        showReactionPicker = false
                    }
                )
                .offset(x: -10, y: 40)
                .zIndex(100)
            }
        }
    }

    private var privacyIcon: String {
        switch activity.privacyLevel {
        case .public_: return "globe"
        case .friends: return "person.2"
        case .family: return "house"
        case .private_: return "lock"
        }
    }
}

struct ReactionPicker: View {
    let emojis: [String]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(emojis, id: \.self) { emoji in
                Button(action: { onSelect(emoji) }) {
                    Text(emoji)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(radius: 8)
        )
    }
}

struct ActivityPrivacySheet: View {
    @ObservedObject var viewModel: ActivityFeedViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings: PrivacySettings

    init(viewModel: ActivityFeedViewModel) {
        self.viewModel = viewModel
        _settings = State(initialValue: viewModel.privacySettings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Кто видит вашу активность") {
                    PrivacyPicker(title: "Транзакции", selection: $settings.showTransactions)
                    PrivacyPicker(title: "Накопления", selection: $settings.showGoals)
                    PrivacyPicker(title: "Челленджи", selection: $settings.showChallenges)
                    PrivacyPicker(title: "Уведомления бюджета", selection: $settings.showBudgetAlerts)
                }

                Section("Детали") {
                    Toggle("Показывать локацию", isOn: $settings.showLocation)
                    Toggle("Показывать суммы", isOn: $settings.showAmounts)
                    Toggle("Разрешить реакции", isOn: $settings.allowReactions)
                    Toggle("Разрешить комментарии", isOn: $settings.allowComments)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "eye.slash.fill")
                                .foregroundStyle(.orange)
                            Text("Ваша приватность важна")
                                .font(.subheadline.bold())
                        }

                        Text("Вы полностью контролируете, что видят ваши друзья и семья. Настройки применяются ко всей новой активности.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Приватность")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        viewModel.updatePrivacySettings(settings)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PrivacyPicker: View {
    let title: String
    @Binding var selection: ActivityItem.ActivityPrivacy

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(ActivityItem.ActivityPrivacy.allCases, id: \.self) { level in
                HStack {
                    Image(systemName: privacyIcon(for: level))
                    Text(level.rawValue)
                }
                .tag(level)
            }
        }
        .pickerStyle(.navigationLink)
    }

    private func privacyIcon(for level: ActivityItem.ActivityPrivacy) -> String {
        switch level {
        case .public_: return "globe"
        case .friends: return "person.2"
        case .family: return "house"
        case .private_: return "lock"
        }
    }
}

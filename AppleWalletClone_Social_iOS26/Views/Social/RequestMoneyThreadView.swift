import SwiftUI

// MARK: - Models
struct MoneyRequest: Identifiable, Hashable {
    let id: UUID
    var from: SocialContact
    var to: SocialContact
    var amount: Double
    var description: String
    var timestamp: Date
    var dueDate: Date?
    var status: RequestStatus
    var reminders: [RequestReminder]
    var paymentMethod: PaymentMethod?
    var threadMessages: [ThreadMessage]
    var isRecurring: Bool
    var recurringFrequency: RecurringFrequency?

    enum RequestStatus: String {
        case pending = "Ожидает"
        case paid = "Оплачено"
        case declined = "Отклонено"
        case expired = "Просрочено"
        case disputed = "Оспаривается"

        var color: Color {
            switch self {
            case .pending: return .orange
            case .paid: return .green
            case .declined: return .red
            case .expired: return .gray
            case .disputed: return .purple
            }
        }

        var icon: String {
            switch self {
            case .pending: return "clock.fill"
            case .paid: return "checkmark.circle.fill"
            case .declined: return "xmark.circle.fill"
            case .expired: return "calendar.badge.exclamationmark"
            case .disputed: return "exclamationmark.triangle.fill"
            }
        }
    }

    enum PaymentMethod: String {
        case applePay = "Apple Pay"
        case card = "Карта"
        case transfer = "Перевод"
        case cash = "Наличные"
        case nearby = "Nearby Payment"
    }

    enum RecurringFrequency: String {
        case weekly = "Еженедельно"
        case monthly = "Ежемесячно"
        case quarterly = "Ежеквартально"
    }
}

struct RequestReminder: Identifiable {
    let id: UUID
    var sentAt: Date
    var type: ReminderType
    var message: String
    var isRead: Bool

    enum ReminderType: String {
        case automatic = "Автоматическое"
        case manual = "Вручную"
        case overdue = "Просрочка"
        case final = "Финальное"
    }
}

struct ThreadMessage: Identifiable {
    let id: UUID
    var author: SocialContact
    var text: String
    var timestamp: Date
    var attachments: [MessageAttachment]
    var isSystem: Bool
}

struct MessageAttachment: Identifiable {
    let id: UUID
    var type: AttachmentType
    var data: Data?
    var url: URL?

    enum AttachmentType: String {
        case image = "Фото"
        case receipt = "Чек"
        case document = "Документ"
    }
}

// MARK: - ViewModel
@MainActor
class RequestMoneyViewModel: ObservableObject {
    @Published var requests: [MoneyRequest] = []
    @Published var sentRequests: [MoneyRequest] = []
    @Published var receivedRequests: [MoneyRequest] = []
    @Published var selectedRequest: MoneyRequest?
    @Published var isLoading = false
    @Published var showCreateRequest = false
    @Published var filterStatus: MoneyRequest.RequestStatus?

    private let cloudKitManager = CloudKitSyncManager.shared
    private var reminderTimers: [UUID: Timer] = [:]

    func loadRequests() {
        Task {
            isLoading = true
            defer { isLoading = false }

            requests = createMockRequests()
            categorizeRequests()
            setupReminders()
        }
    }

    func createRequest(to contact: SocialContact, amount: Double, description: String, dueDate: Date?, isRecurring: Bool, frequency: MoneyRequest.RecurringFrequency?) async {
        let currentUser = SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .blue, isCurrentUser: true)

        let request = MoneyRequest(
            id: UUID(),
            from: currentUser,
            to: contact,
            amount: amount,
            description: description,
            timestamp: Date(),
            dueDate: dueDate,
            status: .pending,
            reminders: [],
            paymentMethod: nil,
            threadMessages: [],
            isRecurring: isRecurring,
            recurringFrequency: frequency
        )

        requests.append(request)
        categorizeRequests()

        do {
            try await cloudKitManager.saveRequest(request)
            scheduleReminders(for: request)
        } catch {
            print("Failed to save request: \(error)")
        }
    }

    func payRequest(_ request: MoneyRequest, method: MoneyRequest.PaymentMethod) async {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }

        requests[index].status = .paid
        requests[index].paymentMethod = method

        // Add system message to thread
        let systemMessage = ThreadMessage(
            id: UUID(),
            author: request.to,
            text: "Оплачено через \(method.rawValue)",
            timestamp: Date(),
            attachments: [],
            isSystem: true
        )
        requests[index].threadMessages.append(systemMessage)

        categorizeRequests()

        // Cancel reminders
        cancelReminders(for: request.id)

        do {
            try await cloudKitManager.updateRequest(requests[index])
        } catch {
            print("Failed to update request")
        }
    }

    func declineRequest(_ request: MoneyRequest, reason: String?) {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }

        requests[index].status = .declined

        let systemMessage = ThreadMessage(
            id: UUID(),
            author: request.to,
            text: "Запрос отклонен" + (reason != nil ? ": \(reason!)" : ""),
            timestamp: Date(),
            attachments: [],
            isSystem: true
        )
        requests[index].threadMessages.append(systemMessage)

        categorizeRequests()
        cancelReminders(for: request.id)

        Task {
            try? await cloudKitManager.updateRequest(requests[index])
        }
    }

    func sendReminder(for requestID: UUID, type: RequestReminder.ReminderType = .manual) {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else { return }

        let reminder = RequestReminder(
            id: UUID(),
            sentAt: Date(),
            type: type,
            message: generateReminderMessage(for: requests[index], type: type),
            isRead: false
        )

        requests[index].reminders.append(reminder)

        // Send push notification
        Task {
            await NearbyPaymentManager.shared.sendPaymentReminder(
                to: Contact(id: requests[index].to.id, name: requests[index].to.name, phone: nil, email: nil),
                amount: requests[index].amount
            )
        }
    }

    func addMessage(to requestID: UUID, text: String, author: SocialContact) {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else { return }

        let message = ThreadMessage(
            id: UUID(),
            author: author,
            text: text,
            timestamp: Date(),
            attachments: [],
            isSystem: false
        )

        requests[index].threadMessages.append(message)

        Task {
            try? await cloudKitManager.updateRequest(requests[index])
        }
    }

    func disputeRequest(_ request: MoneyRequest, reason: String) {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }

        requests[index].status = .disputed

        let systemMessage = ThreadMessage(
            id: UUID(),
            author: request.to,
            text: "Запрос оспорен: \(reason)",
            timestamp: Date(),
            attachments: [],
            isSystem: true
        )
        requests[index].threadMessages.append(systemMessage)

        categorizeRequests()
    }

    private func categorizeRequests() {
        let currentUser = SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .blue, isCurrentUser: true)

        sentRequests = requests.filter { $0.from.id == currentUser.id }
        receivedRequests = requests.filter { $0.to.id == currentUser.id }

        // Check expired
        for index in requests.indices {
            if let dueDate = requests[index].dueDate,
               dueDate < Date(),
               requests[index].status == .pending {
                requests[index].status = .expired

                let systemMessage = ThreadMessage(
                    id: UUID(),
                    author: requests[index].to,
                    text: "Запрос просрочен",
                    timestamp: Date(),
                    attachments: [],
                    isSystem: true
                )
                requests[index].threadMessages.append(systemMessage)
            }
        }
    }

    private func setupReminders() {
        for request in requests where request.status == .pending {
            scheduleReminders(for: request)
        }
    }

    private func scheduleReminders(for request: MoneyRequest) {
        guard let dueDate = request.dueDate else { return }

        let timeUntilDue = dueDate.timeIntervalSince(Date())

        // 24 hours before
        if timeUntilDue > 86400 {
            let timer = Timer.scheduledTimer(withTimeInterval: timeUntilDue - 86400, repeats: false) { [weak self] _ in
                self?.sendReminder(for: request.id, type: .automatic)
            }
            reminderTimers[request.id] = timer
        }

        // At due date
        if timeUntilDue > 0 {
            let timer = Timer.scheduledTimer(withTimeInterval: timeUntilDue, repeats: false) { [weak self] _ in
                self?.sendReminder(for: request.id, type: .overdue)
            }
            reminderTimers[request.id] = timer
        }
    }

    private func cancelReminders(for requestID: UUID) {
        reminderTimers[requestID]?.invalidate()
        reminderTimers.removeValue(forKey: requestID)
    }

    private func generateReminderMessage(for request: MoneyRequest, type: RequestReminder.ReminderType) -> String {
        switch type {
        case .automatic:
            return "Напоминание: запрос на \(request.amount, format: .currency(code: "RUB")) истекает через 24 часа"
        case .manual:
            return "Привет! Не забудь про запрос на \(request.amount, format: .currency(code: "RUB"))"
        case .overdue:
            return "Запрос на \(request.amount, format: .currency(code: "RUB")) просрочен"
        case .final:
            return "Финальное напоминание: запрос на \(request.amount, format: .currency(code: "RUB"))"
        }
    }

    private func createMockRequests() -> [MoneyRequest] {
        let contacts = [
            SocialContact(id: UUID(), name: "Анна", avatar: nil, color: .pink, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Михаил", avatar: nil, color: .blue, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Елена", avatar: nil, color: .purple, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .green, isCurrentUser: true)
        ]

        let threadMessages1 = [
            ThreadMessage(id: UUID(), author: contacts[0], text: "Привет! Можешь вернуть за билеты?", timestamp: Date().addingTimeInterval(-86400 * 2), attachments: [], isSystem: false),
            ThreadMessage(id: UUID(), author: contacts[3], text: "Да, конечно! Забыл совсем, сейчас отправлю", timestamp: Date().addingTimeInterval(-86400), attachments: [], isSystem: false),
            ThreadMessage(id: UUID(), author: contacts[0], text: "Спасибо! 🙏", timestamp: Date().addingTimeInterval(-86000), attachments: [], isSystem: false)
        ]

        let threadMessages2 = [
            ThreadMessage(id: UUID(), author: contacts[1], text: "Долг за ужин в пятницу", timestamp: Date().addingTimeInterval(-43200), attachments: [], isSystem: false),
            ThreadMessage(id: UUID(), author: contacts[3], text: "А можешь напомнить сколько точно?", timestamp: Date().addingTimeInterval(-40000), attachments: [], isSystem: false),
            ThreadMessage(id: UUID(), author: contacts[1], text: "1250₽, я скинул чек в группу", timestamp: Date().addingTimeInterval(-36000), attachments: [], isSystem: false)
        ]

        return [
            MoneyRequest(
                id: UUID(),
                from: contacts[0],
                to: contacts[3],
                amount: 2500,
                description: "Концертные билеты",
                timestamp: Date().addingTimeInterval(-86400 * 3),
                dueDate: Date().addingTimeInterval(86400),
                status: .pending,
                reminders: [
                    RequestReminder(id: UUID(), sentAt: Date().addingTimeInterval(-86400), type: .automatic, message: "Напоминание: запрос истекает через 24 часа", isRead: true)
                ],
                paymentMethod: nil,
                threadMessages: threadMessages1,
                isRecurring: false,
                recurringFrequency: nil
            ),
            MoneyRequest(
                id: UUID(),
                from: contacts[1],
                to: contacts[3],
                amount: 1250,
                description: "Ужин в ресторане",
                timestamp: Date().addingTimeInterval(-86400),
                dueDate: Date().addingTimeInterval(86400 * 2),
                status: .pending,
                reminders: [],
                paymentMethod: nil,
                threadMessages: threadMessages2,
                isRecurring: false,
                recurringFrequency: nil
            ),
            MoneyRequest(
                id: UUID(),
                from: contacts[3],
                to: contacts[2],
                amount: 3000,
                description: "Аренда коворкинга",
                timestamp: Date().addingTimeInterval(-86400 * 5),
                dueDate: Date().addingTimeInterval(-86400),
                status: .expired,
                reminders: [
                    RequestReminder(id: UUID(), sentAt: Date().addingTimeInterval(-86400 * 2), type: .automatic, message: "Напоминание", isRead: true),
                    RequestReminder(id: UUID(), sentAt: Date().addingTimeInterval(-86400), type: .overdue, message: "Запрос просрочен", isRead: false)
                ],
                paymentMethod: nil,
                threadMessages: [],
                isRecurring: true,
                recurringFrequency: .monthly
            ),
            MoneyRequest(
                id: UUID(),
                from: contacts[2],
                to: contacts[3],
                amount: 5000,
                description: "Подарок на день рождения",
                timestamp: Date().addingTimeInterval(-86400 * 10),
                dueDate: nil,
                status: .paid,
                reminders: [],
                paymentMethod: .applePay,
                threadMessages: [
                    ThreadMessage(id: UUID(), author: contacts[3], text: "Оплачено через Apple Pay", timestamp: Date().addingTimeInterval(-86400 * 9), attachments: [], isSystem: true)
                ],
                isRecurring: false,
                recurringFrequency: nil
            ),
            MoneyRequest(
                id: UUID(),
                from: contacts[3],
                to: contacts[1],
                amount: 800,
                description: "Кофе и круассаны",
                timestamp: Date().addingTimeInterval(-86400 * 2),
                dueDate: nil,
                status: .declined,
                reminders: [],
                paymentMethod: nil,
                threadMessages: [
                    ThreadMessage(id: UUID(), author: contacts[1], text: "Запрос отклонен: Уже отдал наличными", timestamp: Date().addingTimeInterval(-86400), attachments: [], isSystem: true)
                ],
                isRecurring: false,
                recurringFrequency: nil
            )
        ]
    }
}

// MARK: - Views
struct RequestMoneyThreadView: View {
    @StateObject private var viewModel = RequestMoneyViewModel()
    @State private var selectedTab = 0
    @State private var showCreate = false
    @State private var selectedRequest: MoneyRequest?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Segmented Control
                    Picker("", selection: $selectedTab) {
                        Text("Получить").tag(0)
                        Text("Отправить").tag(1)
                        Text("История").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    ScrollView {
                        VStack(spacing: 12) {
                            switch selectedTab {
                            case 0:
                                receivedRequestsList
                            case 1:
                                sentRequestsList
                            case 2:
                                historyList
                            default:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
            .navigationTitle("Запросы денег")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showCreate = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateRequestSheet(viewModel: viewModel)
            }
            .navigationDestination(item: $selectedRequest) { request in
                RequestThreadDetailView(request: request, viewModel: viewModel)
            }
            .onAppear {
                viewModel.loadRequests()
            }
        }
    }

    private var receivedRequestsList: some View {
        ForEach(viewModel.receivedRequests.filter { $0.status == .pending || $0.status == .expired }) { request in
            RequestCard(request: request, isReceived: true) {
                selectedRequest = request
            }
        }
    }

    private var sentRequestsList: some View {
        ForEach(viewModel.sentRequests.filter { $0.status == .pending || $0.status == .expired }) { request in
            RequestCard(request: request, isReceived: false) {
                selectedRequest = request
            }
        }
    }

    private var historyList: some View {
        ForEach(viewModel.requests.filter { $0.status != .pending && $0.status != .expired }) { request in
            RequestHistoryRow(request: request) {
                selectedRequest = request
            }
        }
    }
}

struct RequestCard: View {
    let request: MoneyRequest
    let isReceived: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(isReceived ? Color.red.opacity(0.15) : Color.indigo.opacity(0.15))
                                .frame(width: 44, height: 44)

                            Image(systemName: isReceived ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .font(.title3)
                                .foregroundStyle(isReceived ? .red : .indigo)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.description)
                                .font(.subheadline.bold())

                            HStack(spacing: 4) {
                                Text(isReceived ? "От: \(request.from.name)" : "Кому: \(request.to.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if request.isRecurring, let freq = request.recurringFrequency {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.2.circlepath")
                                            .font(.system(size: 8))
                                        Text(freq.rawValue)
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.blue)
                                }
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: request.status.icon)
                            .font(.caption2)
                        Text(request.status.rawValue)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(request.status.color.opacity(0.15))
                    )
                    .foregroundStyle(request.status.color)
                }

                HStack {
                    Text(request.amount, format: .currency(code: "RUB"))
                        .font(.title3.bold())

                    Spacer()

                    if let dueDate = request.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(dueDate, style: .relative)
                                .font(.caption)
                        }
                        .foregroundStyle(dueDate < Date() ? .red : .secondary)
                    }
                }

                if !request.reminders.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("\(request.reminders.count) напоминаний")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !request.threadMessages.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("\(request.threadMessages.count) сообщений")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(request.status == .expired ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct RequestHistoryRow: View {
    let request: MoneyRequest
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: request.status.icon)
                    .font(.title3)
                    .foregroundStyle(request.status.color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.description)
                        .font(.subheadline.bold())

                    HStack(spacing: 4) {
                        Text(request.to.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let method = request.paymentMethod {
                            Text("• \(method.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()

                Text(request.amount, format: .currency(code: "RUB"))
                    .font(.subheadline.bold())
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct RequestThreadDetailView: View {
    let request: MoneyRequest
    @ObservedObject var viewModel: RequestMoneyViewModel
    @State private var messageText = ""
    @State private var showPaymentOptions = false
    @State private var showReminderOptions = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Request Header
                requestHeader

                // Thread Messages
                threadSection
            }
            .padding()
        }
        .navigationTitle(request.description)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if request.status == .pending {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showReminderOptions = true }) {
                            Label("Напомнить", systemImage: "bell.fill")
                        }

                        if !request.to.isCurrentUser {
                            Button(action: { showPaymentOptions = true }) {
                                Label("Оплатить", systemImage: "checkmark.circle.fill")
                            }
                        }

                        Button(action: {
                            viewModel.declineRequest(request, reason: nil)
                        }) {
                            Label("Отклонить", systemImage: "xmark.circle.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if request.status == .pending {
                messageInputBar
            }
        }
        .sheet(isPresented: $showPaymentOptions) {
            PaymentOptionsSheet(request: request, viewModel: viewModel)
        }
        .sheet(isPresented: $showReminderOptions) {
            ReminderOptionsSheet(request: request, viewModel: viewModel)
        }
    }

    private var requestHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.amount, format: .currency(code: "RUB"))
                        .font(.system(size: 48, weight: .bold, design: .rounded))

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: request.status.icon)
                                .font(.caption2)
                            Text(request.status.rawValue)
                                .font(.caption)
                        }
                        .foregroundStyle(request.status.color)

                        if let dueDate = request.dueDate {
                            Text("• До: \(dueDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(dueDate < Date() ? .red : .secondary)
                        }
                    }
                }

                Spacer()
            }

            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(request.from.color)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(request.from.name.prefix(1)))
                                .font(.callout.bold())
                                .foregroundStyle(.white)
                        )
                    Text(request.from.name)
                        .font(.caption)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Circle()
                        .fill(request.to.color)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(request.to.name.prefix(1)))
                                .font(.callout.bold())
                                .foregroundStyle(.white)
                        )
                    Text(request.to.name)
                        .font(.caption)
                }
            }

            if request.status == .pending && !request.to.isCurrentUser {
                Button(action: { showPaymentOptions = true }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Оплатить сейчас")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green)
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
    }

    private var threadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Переписка")
                .font(.headline)

            if request.threadMessages.isEmpty {
                emptyThreadView
            } else {
                ForEach(request.threadMessages) { message in
                    ThreadMessageBubble(message: message)
                }
            }

            if !request.reminders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Напоминания")
                        .font(.headline)
                        .padding(.top, 8)

                    ForEach(request.reminders) { reminder in
                        ReminderRow(reminder: reminder)
                    }
                }
            }
        }
    }

    private var emptyThreadView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Начните переписку")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var messageInputBar: some View {
        HStack(spacing: 12) {
            TextField("Сообщение...", text: $messageText, axis: .vertical)
                .lineLimit(1...3)

            Button(action: {
                let currentUser = SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .blue, isCurrentUser: true)
                viewModel.addMessage(to: request.id, text: messageText, author: currentUser)
                messageText = ""
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(messageText.isEmpty ? .gray : .indigo)
            }
            .disabled(messageText.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

struct ThreadMessageBubble: View {
    let message: ThreadMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !message.isSystem {
                Circle()
                    .fill(message.author.color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String(message.author.name.prefix(1)))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                if !message.isSystem {
                    Text(message.author.name)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.isSystem ? .secondary : .primary)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(message.isSystem ? Color(.systemGray6) : Color.indigo.opacity(0.1))
            )

            Spacer()
        }
    }
}

struct ReminderRow: View {
    let reminder: RequestReminder

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.message)
                    .font(.caption)

                HStack(spacing: 4) {
                    Text(reminder.type.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("• \(reminder.sentAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !reminder.isRead {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Sheets
struct CreateRequestSheet: View {
    @ObservedObject var viewModel: RequestMoneyViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var description = ""
    @State private var selectedContact: SocialContact?
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    @State private var isRecurring = false
    @State private var selectedFrequency: MoneyRequest.RecurringFrequency = .monthly

    var body: some View {
        NavigationStack {
            Form {
                Section("Кому") {
                    Picker("Контакт", selection: $selectedContact) {
                        ForEach(mockSocialContacts) { contact in
                            HStack {
                                Circle()
                                    .fill(contact.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Text(String(contact.name.prefix(1)))
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                    )
                                Text(contact.name)
                            }
                            .tag(contact as SocialContact?)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Сумма") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                }

                Section("Описание") {
                    TextField("За что?", text: $description)
                }

                Section("Срок") {
                    Toggle("Установить срок", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("До", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Повторение") {
                    Toggle("Повторяющийся запрос", isOn: $isRecurring)

                    if isRecurring {
                        Picker("Частота", selection: $selectedFrequency) {
                            ForEach(MoneyRequest.RecurringFrequency.allCases, id: \.self) { freq in
                                Text(freq.rawValue).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle("Новый запрос")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") {
                        Task {
                            if let amountValue = Double(amount),
                               let contact = selectedContact {
                                await viewModel.createRequest(
                                    to: contact,
                                    amount: amountValue,
                                    description: description,
                                    dueDate: hasDueDate ? dueDate : nil,
                                    isRecurring: isRecurring,
                                    frequency: isRecurring ? selectedFrequency : nil
                                )
                                dismiss()
                            }
                        }
                    }
                    .disabled(amount.isEmpty || description.isEmpty || selectedContact == nil)
                }
            }
        }
    }
}

struct PaymentOptionsSheet: View {
    let request: MoneyRequest
    @ObservedObject var viewModel: RequestMoneyViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethod: MoneyRequest.PaymentMethod = .applePay

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(request.amount, format: .currency(code: "RUB"))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .padding(.top, 20)

                Text(request.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    ForEach(MoneyRequest.PaymentMethod.allCases, id: \.self) { method in
                        PaymentMethodRow(method: method, isSelected: selectedMethod == method) {
                            selectedMethod = method
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                Button(action: {
                    Task {
                        await viewModel.payRequest(request, method: selectedMethod)
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Оплатить \(request.amount, format: .currency(code: "RUB"))")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black)
                    )
                }
                .padding()
            }
            .navigationTitle("Оплата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

struct PaymentMethodRow: View {
    let method: MoneyRequest.PaymentMethod
    let isSelected: Bool
    let action: () -> Void

    var icon: String {
        switch method {
        case .applePay: return "apple.logo"
        case .card: return "creditcard.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .cash: return "banknote.fill"
        case .nearby: return "wave.3.right"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 32)

                Text(method.rawValue)
                    .font(.subheadline.bold())

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.indigo)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.indigo.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.indigo : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct ReminderOptionsSheet: View {
    let request: MoneyRequest
    @ObservedObject var viewModel: RequestMoneyViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: {
                        viewModel.sendReminder(for: request.id, type: .manual)
                        dismiss()
                    }) {
                        Label("Отправить напоминание сейчас", systemImage: "paperplane.fill")
                    }

                    Button(action: {
                        viewModel.sendReminder(for: request.id, type: .automatic)
                        dismiss()
                    }) {
                        Label("Автоматическое напоминание", systemImage: "bell.fill")
                    }
                }

                Section("История напоминаний") {
                    if request.reminders.isEmpty {
                        Text("Пока нет напоминаний")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(request.reminders) { reminder in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.type.rawValue)
                                        .font(.subheadline)
                                    Text(reminder.sentAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if reminder.isRead {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Напоминания")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

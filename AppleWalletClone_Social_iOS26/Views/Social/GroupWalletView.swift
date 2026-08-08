import SwiftUI
import CloudKit

// MARK: - Models
struct GroupWallet: Identifiable, Hashable {
    let id: UUID
    var name: String
    var members: [WalletMember]
    var balance: Double
    var transactions: [GroupTransaction]
    var createdAt: Date
    var privacyLevel: PrivacyLevel
    var icon: String
    var color: WalletColor

    enum PrivacyLevel: String, CaseIterable {
        case open = "Открытый"
        case balancedOnly = "Только баланс"
        case closed = "Закрытый"
    }

    enum WalletColor: String, CaseIterable {
        case blue = "blue"
        case green = "green"
        case purple = "purple"
        case orange = "orange"
        case pink = "pink"
    }
}

struct WalletMember: Identifiable, Hashable {
    let id: UUID
    var contact: Contact
    var role: MemberRole
    var joinedAt: Date
    var permissions: MemberPermissions

    enum MemberRole: String {
        case owner = "Владелец"
        case admin = "Администратор"
        case member = "Участник"
        case viewer = "Наблюдатель"
    }

    struct MemberPermissions: OptionSet {
        let rawValue: Int
        static let viewBalance = MemberPermissions(rawValue: 1 << 0)
        static let addTransactions = MemberPermissions(rawValue: 1 << 1)
        static let inviteMembers = MemberPermissions(rawValue: 1 << 2)
        static let manageSettings = MemberPermissions(rawValue: 1 << 3)
        static let withdraw = MemberPermissions(rawValue: 1 << 4)
    }
}

struct GroupTransaction: Identifiable, Hashable {
    let id: UUID
    var amount: Double
    var description: String
    var category: TransactionCategory
    var createdBy: WalletMember
    var timestamp: Date
    var splitType: SplitType
    var splits: [TransactionSplit]
    var receiptImage: Data?
    var comments: [TransactionComment]

    enum SplitType: String {
        case equal = "Поровну"
        case percentage = "По процентам"
        case exact = "Точная сумма"
        case custom = "Пользовательская"
    }
}

struct TransactionSplit: Identifiable {
    let id: UUID
    var member: WalletMember
    var amount: Double
    var percentage: Double?
    var isPaid: Bool
}

struct TransactionComment: Identifiable {
    let id: UUID
    var author: WalletMember
    var text: String
    var reactions: [Reaction]
    var timestamp: Date
}

struct Reaction: Identifiable {
    let id: UUID
    var emoji: String
    var author: WalletMember
}

// MARK: - ViewModel
@MainActor
class GroupWalletViewModel: ObservableObject {
    @Published var wallets: [GroupWallet] = []
    @Published var selectedWallet: GroupWallet?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showPrivacySheet = false

    private let cloudKitManager = CloudKitSyncManager.shared
    private let nearbyManager = NearbyPaymentManager.shared

    func createWallet(name: String, members: [Contact], privacy: GroupWallet.PrivacyLevel) async {
        isLoading = true
        defer { isLoading = false }

        let walletMembers = members.map { contact in
            WalletMember(
                id: UUID(),
                contact: contact,
                role: .member,
                joinedAt: Date(),
                permissions: [.viewBalance, .addTransactions]
            )
        }

        let newWallet = GroupWallet(
            id: UUID(),
            name: name,
            members: walletMembers,
            balance: 0.0,
            transactions: [],
            createdAt: Date(),
            privacyLevel: privacy,
            icon: "person.3.fill",
            color: .blue
        )

        do {
            try await cloudKitManager.saveGroupWallet(newWallet)
            wallets.append(newWallet)
        } catch {
            errorMessage = "Не удалось создать кошелек: \(error.localizedDescription)"
        }
    }

    func inviteMember(to walletID: UUID, contact: Contact, permissions: WalletMember.MemberPermissions) async {
        guard let index = wallets.firstIndex(where: { $0.id == walletID }) else { return }

        let newMember = WalletMember(
            id: UUID(),
            contact: contact,
            role: .member,
            joinedAt: Date(),
            permissions: permissions
        )

        wallets[index].members.append(newMember)

        do {
            try await cloudKitManager.updateWallet(wallets[index])
            await nearbyManager.sendInvitation(to: contact, for: wallets[index])
        } catch {
            errorMessage = "Ошибка приглашения: \(error.localizedDescription)"
        }
    }

    func addTransaction(to walletID: UUID, amount: Double, description: String, splitType: GroupTransaction.SplitType, splits: [TransactionSplit]) async {
        guard let index = wallets.firstIndex(where: { $0.id == walletID }) else { return }

        let transaction = GroupTransaction(
            id: UUID(),
            amount: amount,
            description: description,
            category: .other,
            createdBy: wallets[index].members.first!,
            timestamp: Date(),
            splitType: splitType,
            splits: splits,
            receiptImage: nil,
            comments: []
        )

        wallets[index].transactions.append(transaction)
        wallets[index].balance += amount

        do {
            try await cloudKitManager.saveTransaction(transaction, to: walletID)
            await notifyMembers(of: transaction, in: wallets[index])
        } catch {
            errorMessage = "Ошибка сохранения транзакции"
        }
    }

    private func notifyMembers(of transaction: GroupTransaction, in wallet: GroupWallet) async {
        for member in wallet.members where member.id != transaction.createdBy.id {
            await nearbyManager.sendTransactionNotification(to: member.contact, transaction: transaction, walletName: wallet.name)
        }
    }

    func updatePrivacy(for walletID: UUID, level: GroupWallet.PrivacyLevel) {
        guard let index = wallets.firstIndex(where: { $0.id == walletID }) else { return }
        wallets[index].privacyLevel = level
        Task {
            try? await cloudKitManager.updateWallet(wallets[index])
        }
    }

    func deleteWallet(_ wallet: GroupWallet) async {
        wallets.removeAll { $0.id == wallet.id }
        try? await cloudKitManager.deleteWallet(wallet)
    }
}

// MARK: - Views
struct GroupWalletView: View {
    @StateObject private var viewModel = GroupWalletViewModel()
    @State private var showCreateSheet = false
    @State private var showInviteSheet = false
    @State private var selectedWalletForInvite: GroupWallet?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection

                        // Wallets Grid
                        walletsGrid

                        // Recent Activity
                        recentActivitySection
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Групповые кошельки")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showCreateSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateGroupWalletSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showInviteSheet) {
                if let wallet = selectedWalletForInvite {
                    InviteMemberSheet(wallet: wallet, viewModel: viewModel)
                }
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Управляйте деньгами вместе")
                .font(.title2.bold())

            Text("Создавайте совместные кошельки для поездок, подарков и общих расходов")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var walletsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(viewModel.wallets) { wallet in
                WalletCard(wallet: wallet, viewModel: viewModel)
            }

            // Add New Card
            Button(action: { showCreateSheet = true }) {
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.opacity(0.6))

                    Text("Новый кошелек")
                        .font(.callout.bold())
                        .foregroundStyle(.blue)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 2)
                )
            }
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Недавняя активность")
                .font(.headline)

            if viewModel.wallets.flatMap(\.transactions).isEmpty {
                emptyActivityView
            } else {
                ForEach(viewModel.wallets.flatMap(\.transactions).sorted(by: { $0.timestamp > $1.timestamp }).prefix(5)) { transaction in
                    TransactionRow(transaction: transaction)
                }
            }
        }
        .padding(.top, 8)
    }

    private var emptyActivityView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Пока нет активности")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct WalletCard: View {
    let wallet: GroupWallet
    @ObservedObject var viewModel: GroupWalletViewModel
    @State private var showDetail = false
    @State private var showPrivacy = false

    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: wallet.icon)
                        .font(.title2)
                        .foregroundStyle(walletColor)

                    Spacer()

                    privacyBadge
                }

                Text(wallet.name)
                    .font(.headline)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Баланс")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if wallet.privacyLevel == .closed && !isCurrentUserMember {
                        Text("••••")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(wallet.balance, format: .currency(code: "RUB"))
                            .font(.title2.bold())
                            .foregroundStyle(walletColor)
                    }
                }

                HStack(spacing: -8) {
                    ForEach(wallet.members.prefix(3)) { member in
                        MemberAvatar(member: member)
                    }

                    if wallet.members.count > 3 {
                        Text("+\(wallet.members.count - 3)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.gray))
                    }
                }

                Spacer()
            }
            .padding()
            .frame(height: 180)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(walletColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(walletColor.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            WalletDetailView(wallet: wallet, viewModel: viewModel)
        }
    }

    private var walletColor: Color {
        switch wallet.color {
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        }
    }

    private var privacyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: privacyIcon)
                .font(.caption2)
            Text(wallet.privacyLevel.rawValue)
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

    private var privacyIcon: String {
        switch wallet.privacyLevel {
        case .open: return "lock.open.fill"
        case .balancedOnly: return "lock.shield.fill"
        case .closed: return "lock.fill"
        }
    }

    private var isCurrentUserMember: Bool {
        // In real app, check against current user ID
        true
    }
}

struct MemberAvatar: View {
    let member: WalletMember

    var body: some View {
        Circle()
            .fill(Color.random)
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(member.contact.name.prefix(1)))
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            )
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 2)
            )
    }
}

struct WalletDetailView: View {
    let wallet: GroupWallet
    @ObservedObject var viewModel: GroupWalletViewModel
    @State private var showAddTransaction = false
    @State private var showInvite = false
    @State private var showPrivacySettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Balance Card
                    balanceCard

                    // Quick Actions
                    quickActions

                    // Members
                    membersSection

                    // Transactions
                    transactionsSection
                }
                .padding()
            }
            .navigationTitle(wallet.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showPrivacySettings = true }) {
                            Label("Приватность", systemImage: "lock.shield")
                        }

                        Button(action: { showInvite = true }) {
                            Label("Пригласить", systemImage: "person.badge.plus")
                        }

                        Divider()

                        Button(role: .destructive, action: {
                            Task { await viewModel.deleteWallet(wallet) }
                        }) {
                            Label("Удалить кошелек", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionSheet(wallet: wallet, viewModel: viewModel)
            }
            .sheet(isPresented: $showInvite) {
                InviteMemberSheet(wallet: wallet, viewModel: viewModel)
            }
            .sheet(isPresented: $showPrivacySettings) {
                PrivacySettingsSheet(wallet: wallet, viewModel: viewModel)
            }
        }
    }

    private var balanceCard: some View {
        VStack(spacing: 16) {
            Text("Общий баланс")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(wallet.balance, format: .currency(code: "RUB"))
                .font(.system(size: 48, weight: .bold, design: .rounded))

            HStack(spacing: 20) {
                StatBadge(title: "Входящие", value: "+\(wallet.transactions.filter { $0.amount > 0 }.count)", color: .green)
                StatBadge(title: "Исходящие", value: "\(wallet.transactions.filter { $0.amount < 0 }.count)", color: .red)
                StatBadge(title: "Участников", value: "\(wallet.members.count)", color: .blue)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            QuickActionButton(icon: "plus.circle.fill", title: "Добавить", color: .green) {
                showAddTransaction = true
            }

            QuickActionButton(icon: "qrcode", title: "QR-код", color: .blue) {
                // Show QR for wallet
            }

            QuickActionButton(icon: "arrow.left.arrow.right", title: "Перевод", color: .purple) {
                // Transfer between wallets
            }

            QuickActionButton(icon: "chart.pie.fill", title: "Аналитика", color: .orange) {
                // Show analytics
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Участники")
                    .font(.headline)

                Spacer()

                Button(action: { showInvite = true }) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(.blue)
                }
            }

            ForEach(wallet.members) { member in
                MemberRow(member: member)
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
            Text("Транзакции")
                .font(.headline)

            if wallet.transactions.isEmpty {
                emptyTransactionsView
            } else {
                ForEach(wallet.transactions.sorted(by: { $0.timestamp > $1.timestamp })) { transaction in
                    NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                        TransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private var emptyTransactionsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Нет транзакций")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MemberRow: View {
    let member: WalletMember

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.contact.name)
                    .font(.subheadline.bold())

                Text(member.role.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if member.role == .owner {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TransactionRow: View {
    let transaction: GroupTransaction

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(transaction.amount > 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: transaction.amount > 0 ? "arrow.down.left" : "arrow.up.right")
                    .foregroundStyle(transaction.amount > 0 ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                Text(transaction.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.amount, format: .currency(code: "RUB"))
                .font(.subheadline.bold())
                .foregroundStyle(transaction.amount > 0 ? .green : .primary)
        }
        .padding(.vertical, 6)
    }
}

struct TransactionDetailView: View {
    let transaction: GroupTransaction

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Amount Header
                VStack(spacing: 8) {
                    Text(transaction.amount, format: .currency(code: "RUB"))
                        .font(.system(size: 56, weight: .bold, design: .rounded))

                    Text(transaction.description)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Split Details
                VStack(alignment: .leading, spacing: 12) {
                    Text("Разделение")
                        .font(.headline)

                    ForEach(transaction.splits) { split in
                        HStack {
                            Text(split.member.contact.name)
                            Spacer()
                            Text(split.amount, format: .currency(code: "RUB"))

                            if split.isPaid {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )

                // Comments
                NavigationLink(destination: TransactionCommentsView(transaction: transaction)) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Комментарии")
                        Spacer()
                        Text("\(transaction.comments.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle("Детали")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sheets
struct CreateGroupWalletSheet: View {
    @ObservedObject var viewModel: GroupWalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedPrivacy: GroupWallet.PrivacyLevel = .balancedOnly
    @State private var selectedMembers: [Contact] = []
    @State private var selectedColor: GroupWallet.WalletColor = .blue

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: Поездка в Париж", text: $name)
                }

                Section("Цвет") {
                    HStack(spacing: 12) {
                        ForEach(GroupWallet.WalletColor.allCases, id: \.self) { color in
                            ColorCircle(color: color, isSelected: selectedColor == color) {
                                selectedColor = color
                            }
                        }
                    }
                }

                Section("Приватность") {
                    Picker("Уровень", selection: $selectedPrivacy) {
                        ForEach(GroupWallet.PrivacyLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    privacyDescription
                }

                Section("Участники") {
                    ContactPicker(selectedContacts: $selectedMembers)
                }
            }
            .navigationTitle("Новый кошелек")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        Task {
                            await viewModel.createWallet(
                                name: name,
                                members: selectedMembers,
                                privacy: selectedPrivacy
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private var privacyDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch selectedPrivacy {
            case .open:
                Text("Все участники видят все транзакции и баланс")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .balancedOnly:
                Text("Участники видят только общий баланс, детали — только свои")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .closed:
                Text("Только владелец видит полную информацию")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

struct ColorCircle: View {
    let color: GroupWallet.WalletColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(swiftColor.opacity(0.3))
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(isSelected ? swiftColor : Color.clear, lineWidth: 3)
                )
                .overlay(
                    Circle()
                        .fill(swiftColor)
                        .frame(width: 20, height: 20)
                )
        }
        .buttonStyle(.plain)
    }

    private var swiftColor: Color {
        switch color {
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}

struct InviteMemberSheet: View {
    let wallet: GroupWallet
    @ObservedObject var viewModel: GroupWalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedContact: Contact?
    @State private var permissions: WalletMember.MemberPermissions = [.viewBalance, .addTransactions]

    var body: some View {
        NavigationStack {
            Form {
                Section("Контакт") {
                    ContactPickerSingle(selectedContact: $selectedContact)
                }

                Section("Разрешения") {
                    Toggle("Просмотр баланса", isOn: binding(for: .viewBalance))
                    Toggle("Добавление транзакций", isOn: binding(for: .addTransactions))
                    Toggle("Приглашение участников", isOn: binding(for: .inviteMembers))
                    Toggle("Управление настройками", isOn: binding(for: .manageSettings))
                    Toggle("Вывод средств", isOn: binding(for: .withdraw))
                }
            }
            .navigationTitle("Пригласить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Пригласить") {
                        if let contact = selectedContact {
                            Task {
                                await viewModel.inviteMember(to: wallet.id, contact: contact, permissions: permissions)
                                dismiss()
                            }
                        }
                    }
                    .disabled(selectedContact == nil)
                }
            }
        }
    }

    private func binding(for permission: WalletMember.MemberPermissions) -> Binding<Bool> {
        Binding(
            get: { permissions.contains(permission) },
            set: { isOn in
                if isOn {
                    permissions.insert(permission)
                } else {
                    permissions.remove(permission)
                }
            }
        )
    }
}

struct PrivacySettingsSheet: View {
    let wallet: GroupWallet
    @ObservedObject var viewModel: GroupWalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: GroupWallet.PrivacyLevel

    init(wallet: GroupWallet, viewModel: GroupWalletViewModel) {
        self.wallet = wallet
        self.viewModel = viewModel
        _selectedLevel = State(initialValue: wallet.privacyLevel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Уровень приватности") {
                    Picker("Уровень", selection: $selectedLevel) {
                        ForEach(GroupWallet.PrivacyLevel.allCases, id: \.self) { level in
                            HStack {
                                Image(systemName: privacyIcon(for: level))
                                Text(level.rawValue)
                            }
                            .tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Описание") {
                    privacyDetailDescription
                }

                Section("Индивидуальные настройки") {
                    ForEach(wallet.members) { member in
                        NavigationLink(destination: MemberPrivacyView(member: member)) {
                            HStack {
                                Text(member.contact.name)
                                Spacer()
                                Text(member.role.rawValue)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Приватность")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        viewModel.updatePrivacy(for: wallet.id, level: selectedLevel)
                        dismiss()
                    }
                }
            }
        }
    }

    private func privacyIcon(for level: GroupWallet.PrivacyLevel) -> String {
        switch level {
        case .open: return "lock.open.fill"
        case .balancedOnly: return "lock.shield.fill"
        case .closed: return "lock.fill"
        }
    }

    private var privacyDetailDescription: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch selectedLevel {
            case .open:
                PrivacyFeatureRow(icon: "eye.fill", text: "Все видят все транзакции")
                PrivacyFeatureRow(icon: "dollarsign.circle.fill", text: "Все видят общий баланс")
                PrivacyFeatureRow(icon: "person.2.fill", text: "Все видят список участников")
            case .balancedOnly:
                PrivacyFeatureRow(icon: "eye.slash.fill", text: "Только свои транзакции")
                PrivacyFeatureRow(icon: "dollarsign.circle.fill", text: "Общий баланс виден всем")
                PrivacyFeatureRow(icon: "person.2.fill", text: "Участники видны всем")
            case .closed:
                PrivacyFeatureRow(icon: "lock.fill", text: "Только владелец видит детали")
                PrivacyFeatureRow(icon: "dollarsign.circle.fill", text: "Баланс скрыт от участников")
                PrivacyFeatureRow(icon: "person.2.fill", text: "Список участников ограничен")
            }
        }
    }
}

struct PrivacyFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct MemberPrivacyView: View {
    let member: WalletMember
    @State private var canViewTransactions = true
    @State private var canViewBalance = true
    @State private var canViewMembers = true

    var body: some View {
        Form {
            Section("Разрешения просмотра") {
                Toggle("Транзакции", isOn: $canViewTransactions)
                Toggle("Баланс", isOn: $canViewBalance)
                Toggle("Участники", isOn: $canViewMembers)
            }

            Section {
                Button(role: .destructive, action: {}) {
                    Text("Исключить из кошелька")
                }
            }
        }
        .navigationTitle(member.contact.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddTransactionSheet: View {
    let wallet: GroupWallet
    @ObservedObject var viewModel: GroupWalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var description = ""
    @State private var splitType: GroupTransaction.SplitType = .equal
    @State private var customSplits: [TransactionSplit] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Сумма") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }

                Section("Описание") {
                    TextField("За что платим?", text: $description)
                }

                Section("Разделение") {
                    Picker("Тип", selection: $splitType) {
                        ForEach(GroupTransaction.SplitType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    SplitConfigurationView(
                        members: wallet.members,
                        totalAmount: Double(amount) ?? 0,
                        splitType: splitType,
                        splits: $customSplits
                    )
                }
            }
            .navigationTitle("Новая транзакция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            let total = Double(amount) ?? 0
                            let splits = customSplits.isEmpty ? createEqualSplits(total: total) : customSplits
                            await viewModel.addTransaction(
                                to: wallet.id,
                                amount: total,
                                description: description,
                                splitType: splitType,
                                splits: splits
                            )
                            dismiss()
                        }
                    }
                    .disabled(amount.isEmpty || description.isEmpty)
                }
            }
        }
    }

    private func createEqualSplits(total: Double) -> [TransactionSplit] {
        let perPerson = total / Double(wallet.members.count)
        return wallet.members.map { member in
            TransactionSplit(
                id: UUID(),
                member: member,
                amount: perPerson,
                percentage: nil,
                isPaid: false
            )
        }
    }
}

struct SplitConfigurationView: View {
    let members: [WalletMember]
    let totalAmount: Double
    let splitType: GroupTransaction.SplitType
    @Binding var splits: [TransactionSplit]

    var body: some View {
        VStack(spacing: 8) {
            switch splitType {
            case .equal:
                EqualSplitView(members: members, totalAmount: totalAmount)
            case .percentage:
                PercentageSplitView(members: members, totalAmount: totalAmount, splits: $splits)
            case .exact:
                ExactSplitView(members: members, totalAmount: totalAmount, splits: $splits)
            case .custom:
                CustomSplitView(members: members, totalAmount: totalAmount, splits: $splits)
            }
        }
    }
}

struct EqualSplitView: View {
    let members: [WalletMember]
    let totalAmount: Double

    var perPerson: Double {
        members.isEmpty ? 0 : totalAmount / Double(members.count)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(members) { member in
                HStack {
                    Text(member.contact.name)
                    Spacer()
                    Text(perPerson, format: .currency(code: "RUB"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PercentageSplitView: View {
    let members: [WalletMember]
    let totalAmount: Double
    @Binding var splits: [TransactionSplit]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(members) { member in
                HStack {
                    Text(member.contact.name)
                    Spacer()

                    HStack(spacing: 4) {
                        TextField("0", value: binding(for: member), format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 50)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            let totalPercentage = splits.reduce(0) { $0 + ($1.percentage ?? 0) }
            if totalPercentage != 100 {
                Text("Сумма процентов должна быть 100% (сейчас \(Int(totalPercentage))%)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func binding(for member: WalletMember) -> Binding<Double> {
        Binding(
            get: {
                splits.first(where: { $0.member.id == member.id })?.percentage ?? 0
            },
            set: { newValue in
                if let index = splits.firstIndex(where: { $0.member.id == member.id }) {
                    splits[index].percentage = newValue
                    splits[index].amount = totalAmount * (newValue / 100)
                } else {
                    var newSplit = TransactionSplit(
                        id: UUID(),
                        member: member,
                        amount: totalAmount * (newValue / 100),
                        percentage: newValue,
                        isPaid: false
                    )
                    splits.append(newSplit)
                }
            }
        )
    }
}

struct ExactSplitView: View {
    let members: [WalletMember]
    let totalAmount: Double
    @Binding var splits: [TransactionSplit]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(members) { member in
                HStack {
                    Text(member.contact.name)
                    Spacer()

                    TextField("0.00", value: binding(for: member), format: .currency(code: "RUB"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            let totalSplit = splits.reduce(0) { $0 + $1.amount }
            if abs(totalSplit - totalAmount) > 0.01 {
                Text("Сумма: \(totalSplit, format: .currency(code: "RUB")) из \(totalAmount, format: .currency(code: "RUB"))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func binding(for member: WalletMember) -> Binding<Double> {
        Binding(
            get: {
                splits.first(where: { $0.member.id == member.id })?.amount ?? 0
            },
            set: { newValue in
                if let index = splits.firstIndex(where: { $0.member.id == member.id }) {
                    splits[index].amount = newValue
                } else {
                    let newSplit = TransactionSplit(
                        id: UUID(),
                        member: member,
                        amount: newValue,
                        percentage: nil,
                        isPaid: false
                    )
                    splits.append(newSplit)
                }
            }
        )
    }
}

struct CustomSplitView: View {
    let members: [WalletMember]
    let totalAmount: Double
    @Binding var splits: [TransactionSplit]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(members) { member in
                HStack {
                    Text(member.contact.name)
                    Spacer()

                    Menu {
                        Button("Оплатил полностью") {
                            updateSplit(member: member, amount: totalAmount)
                        }
                        Button("Не платил") {
                            updateSplit(member: member, amount: 0)
                        }
                        Button("Половина") {
                            updateSplit(member: member, amount: totalAmount / 2)
                        }
                    } label: {
                        Text(splitAmount(for: member), format: .currency(code: "RUB"))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    private func splitAmount(for member: WalletMember) -> Double {
        splits.first(where: { $0.member.id == member.id })?.amount ?? 0
    }

    private func updateSplit(member: WalletMember, amount: Double) {
        if let index = splits.firstIndex(where: { $0.member.id == member.id }) {
            splits[index].amount = amount
        } else {
            let newSplit = TransactionSplit(
                id: UUID(),
                member: member,
                amount: amount,
                percentage: nil,
                isPaid: false
            )
            splits.append(newSplit)
        }
    }
}

// MARK: - Supporting Types
struct Contact: Identifiable, Hashable {
    let id: UUID
    var name: String
    var phone: String?
    var email: String?
    var avatar: Data?
}

enum TransactionCategory: String, CaseIterable {
    case food = "Еда"
    case transport = "Транспорт"
    case entertainment = "Развлечения"
    case shopping = "Покупки"
    case bills = "Счета"
    case travel = "Путешествия"
    case other = "Другое"
}

struct StatBadge: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ContactPicker: View {
    @Binding var selectedContacts: [Contact]
    @State private var searchText = ""

    var body: some View {
        // Simplified contact picker
        VStack {
            TextField("Поиск контактов", text: $searchText)
                .textFieldStyle(.roundedBorder)

            // Mock contacts
            ForEach(mockContacts.filter { searchText.isEmpty || $0.name.contains(searchText) }) { contact in
                ContactRow(contact: contact, isSelected: selectedContacts.contains(contact)) {
                    if selectedContacts.contains(contact) {
                        selectedContacts.removeAll { $0.id == contact.id }
                    } else {
                        selectedContacts.append(contact)
                    }
                }
            }
        }
    }
}

struct ContactPickerSingle: View {
    @Binding var selectedContact: Contact?
    @State private var searchText = ""

    var body: some View {
        VStack {
            TextField("Поиск контактов", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ForEach(mockContacts.filter { searchText.isEmpty || $0.name.contains(searchText) }) { contact in
                ContactRow(contact: contact, isSelected: selectedContact?.id == contact.id) {
                    selectedContact = contact
                }
            }
        }
    }
}

struct ContactRow: View {
    let contact: Contact
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Circle()
                    .fill(Color.random)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(contact.name.prefix(1)))
                            .font(.callout.bold())
                            .foregroundStyle(.white)
                    )

                Text(contact.name)
                    .font(.subheadline)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

let mockContacts = [
    Contact(id: UUID(), name: "Анна", phone: "+7...", email: nil),
    Contact(id: UUID(), name: "Михаил", phone: "+7...", email: nil),
    Contact(id: UUID(), name: "Елена", phone: "+7...", email: nil),
    Contact(id: UUID(), name: "Дмитрий", phone: "+7...", email: nil),
    Contact(id: UUID(), name: "София", phone: "+7...", email: nil)
]

extension Color {
    static var random: Color {
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .red, .teal, .indigo]
        return colors.randomElement() ?? .blue
    }
}

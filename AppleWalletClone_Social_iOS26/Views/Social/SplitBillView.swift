import SwiftUI

// MARK: - Models
struct BillItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var amount: Double
    var assignedTo: [Contact]
    var quantity: Int
    var category: BillCategory
    var image: Data?

    enum BillCategory: String, CaseIterable {
        case food = "Еда"
        case drinks = "Напитки"
        case dessert = "Десерт"
        case service = "Обслуживание"
        case other = "Другое"

        var icon: String {
            switch self {
            case .food: return "fork.knife"
            case .drinks: return "wineglass.fill"
            case .dessert: return "birthday.cake.fill"
            case .service: return "person.fill.checkmark"
            case .other: return "tag.fill"
            }
        }

        var color: Color {
            switch self {
            case .food: return .orange
            case .drinks: return .blue
            case .dessert: return .pink
            case .service: return .green
            case .other: return .gray
            }
        }
    }
}

struct BillSplit: Identifiable {
    let id: UUID
    var contact: Contact
    var items: [BillItem]
    var percentage: Double
    var tipAmount: Double
    var totalOwed: Double
    var isPaid: Bool
    var paymentMethod: PaymentMethod?

    enum PaymentMethod: String {
        case card = "Карта"
        case cash = "Наличные"
        case transfer = "Перевод"
        case applePay = "Apple Pay"
    }
}

struct SplitBillSession: Identifiable {
    let id: UUID
    var restaurantName: String
    var date: Date
    var items: [BillItem]
    var participants: [Contact]
    var splits: [BillSplit]
    var taxRate: Double
    var tipPercentage: Double
    var isCompleted: Bool
    var receiptImage: Data?
}

// MARK: - ViewModel
@MainActor
class SplitBillViewModel: ObservableObject {
    @Published var sessions: [SplitBillSession] = []
    @Published var currentSession: SplitBillSession?
    @Published var draggedContact: Contact?
    @Published var isScanningReceipt = false
    @Published var showPaymentConfirmation = false
    @Published var pendingPayment: BillSplit?

    private let cloudKitManager = CloudKitSyncManager.shared

    func createSession(restaurantName: String, participants: [Contact]) {
        let session = SplitBillSession(
            id: UUID(),
            restaurantName: restaurantName,
            date: Date(),
            items: [],
            participants: participants,
            splits: [],
            taxRate: 0.20,
            tipPercentage: 0.10,
            isCompleted: false,
            receiptImage: nil
        )
        currentSession = session
        sessions.append(session)
    }

    func addItem(name: String, amount: Double, quantity: Int = 1, category: BillItem.BillCategory = .food) {
        guard var session = currentSession else { return }

        let item = BillItem(
            id: UUID(),
            name: name,
            amount: amount,
            assignedTo: [],
            quantity: quantity,
            category: category,
            image: nil
        )

        session.items.append(item)
        currentSession = session
        updateSplits()
    }

    func assignItem(_ item: BillItem, to contact: Contact) {
        guard var session = currentSession else { return }

        if let index = session.items.firstIndex(where: { $0.id == item.id }) {
            if session.items[index].assignedTo.contains(contact) {
                session.items[index].assignedTo.removeAll { $0.id == contact.id }
            } else {
                session.items[index].assignedTo.append(contact)
            }
        }

        currentSession = session
        updateSplits()
    }

    func assignItemViaDrag(_ item: BillItem, to contact: Contact) {
        guard var session = currentSession else { return }

        if let index = session.items.firstIndex(where: { $0.id == item.id }) {
            if !session.items[index].assignedTo.contains(contact) {
                session.items[index].assignedTo.append(contact)
            }
        }

        currentSession = session
        updateSplits()
    }

    func updateSplits() {
        guard var session = currentSession else { return }

        var newSplits: [BillSplit] = []

        for participant in session.participants {
            let assignedItems = session.items.filter { $0.assignedTo.contains(participant) }
            let subtotal = assignedItems.reduce(0) { $0 + ($1.amount * Double($1.quantity)) }
            let tax = subtotal * session.taxRate
            let tip = subtotal * session.tipPercentage
            let total = subtotal + tax + tip

            let split = BillSplit(
                id: UUID(),
                contact: participant,
                items: assignedItems,
                percentage: session.items.isEmpty ? 0 : (Double(assignedItems.count) / Double(session.items.count)),
                tipAmount: tip,
                totalOwed: total,
                isPaid: false,
                paymentMethod: nil
            )

            newSplits.append(split)
        }

        session.splits = newSplits
        currentSession = session
    }

    func markAsPaid(split: BillSplit, method: BillSplit.PaymentMethod) {
        guard var session = currentSession else { return }

        if let index = session.splits.firstIndex(where: { $0.id == split.id }) {
            session.splits[index].isPaid = true
            session.splits[index].paymentMethod = method
        }

        currentSession = session

        Task {
            try? await cloudKitManager.updateSplitBillSession(session)
        }
    }

    func sendReminder(to split: BillSplit) {
        // Send push notification / iMessage
        Task {
            await NearbyPaymentManager.shared.sendPaymentReminder(to: split.contact, amount: split.totalOwed)
        }
    }

    func completeSession() {
        guard var session = currentSession else { return }
        session.isCompleted = true
        currentSession = session

        Task {
            try? await cloudKitManager.saveSplitBillSession(session)
        }
    }

    func scanReceipt(image: UIImage) async {
        isScanningReceipt = true
        defer { isScanningReceipt = false }

        // VisionKit / ML receipt scanning simulation
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Mock parsed items
        let parsedItems = [
            BillItem(id: UUID(), name: "Паста Карбонара", amount: 890, assignedTo: [], quantity: 1, category: .food),
            BillItem(id: UUID(), name: "Капучино", amount: 350, assignedTo: [], quantity: 2, category: .drinks),
            BillItem(id: UUID(), name: "Тирамису", amount: 450, assignedTo: [], quantity: 1, category: .dessert)
        ]

        guard var session = currentSession else { return }
        session.items.append(contentsOf: parsedItems)
        currentSession = session
        updateSplits()
    }

    var totalBill: Double {
        guard let session = currentSession else { return 0 }
        let subtotal = session.items.reduce(0) { $0 + ($1.amount * Double($1.quantity)) }
        let tax = subtotal * session.taxRate
        let tip = subtotal * session.tipPercentage
        return subtotal + tax + tip
    }

    var remainingAmount: Double {
        guard let session = currentSession else { return 0 }
        let paid = session.splits.filter(\.isPaid).reduce(0) { $0 + $1.totalOwed }
        return totalBill - paid
    }
}

// MARK: - Main View
struct SplitBillView: View {
    @StateObject private var viewModel = SplitBillViewModel()
    @State private var showNewSession = false
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if let session = viewModel.currentSession {
                    ActiveSplitSessionView(viewModel: viewModel, session: session)
                } else {
                    EmptySplitView(showNewSession: $showNewSession)
                }
            }
            .navigationTitle("Разделить чек")
            .toolbar {
                if viewModel.currentSession != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { viewModel.currentSession = nil }) {
                            Text("Завершить")
                                .font(.subheadline.bold())
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewSession) {
                NewSessionSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showScanner) {
                ReceiptScannerSheet(viewModel: viewModel)
            }
        }
    }
}

struct EmptySplitView: View {
    @Binding var showNewSession: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 8) {
                Text("Разделите чек")
                    .font(.title2.bold())

                Text("Сканируйте чек, перетаскивайте позиции на контакты и мгновенно рассчитывайтесь")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button(action: { showNewSession = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Новое разделение")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue)
                    )
                }

                Button(action: {}) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("История")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

struct ActiveSplitSessionView: View {
    @ObservedObject var viewModel: SplitBillViewModel
    let session: SplitBillSession
    @State private var showAddItem = false
    @State private var showPayment = false
    @State private var selectedSplit: BillSplit?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header Card
                sessionHeader

                // Participants Strip
                participantsStrip

                // Bill Items with Drag-Drop
                billItemsSection

                // Split Summary
                splitSummary
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .sheet(isPresented: $showAddItem) {
            AddBillItemSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showPayment) {
            if let split = selectedSplit {
                PaymentSheet(split: split, viewModel: viewModel)
            }
        }
    }

    private var sessionHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.restaurantName)
                        .font(.title2.bold())
                    Text(session.date, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Scan Button
                Button(action: {}) {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.title3)
                        Text("Скан")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(viewModel.totalBill, format: .currency(code: "RUB"))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Общий счет")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text(viewModel.remainingAmount, format: .currency(code: "RUB"))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.remainingAmount > 0 ? .orange : .green)
                    Text("Осталось")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .padding()
    }

    private var participantsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(session.participants) { contact in
                    DraggableContactAvatar(
                        contact: contact,
                        totalOwed: session.splits.first(where: { $0.contact.id == contact.id })?.totalOwed ?? 0,
                        isPaid: session.splits.first(where: { $0.contact.id == contact.id })?.isPaid ?? false
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var billItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Позиции")
                    .font(.headline)

                Spacer()

                Button(action: { showAddItem = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            if session.items.isEmpty {
                emptyItemsView
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(session.items) { item in
                        DraggableBillItemRow(
                            item: item,
                            viewModel: viewModel,
                            participants: session.participants
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var emptyItemsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Добавьте позиции из чека")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(action: { showAddItem = true }) {
                Text("Добавить вручную")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var splitSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Кто сколько")
                .font(.headline)
                .padding(.horizontal)

            ForEach(session.splits) { split in
                SplitRow(split: split) {
                    selectedSplit = split
                    showPayment = true
                } onReminder: {
                    viewModel.sendReminder(to: split)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button(action: { showAddItem = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Позиция")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue)
                )
            }

            Button(action: { viewModel.completeSession() }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Готово")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(viewModel.remainingAmount <= 0.01 ? Color.green : Color.gray)
                )
            }
            .disabled(viewModel.remainingAmount > 0.01)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Drag-Drop Components
struct DraggableContactAvatar: View {
    let contact: Contact
    let totalOwed: Double
    let isPaid: Bool
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isPaid ? Color.green.opacity(0.2) : Color.random.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(isPaid ? Color.green : Color.clear, lineWidth: 2)
                    )

                Text(String(contact.name.prefix(1)))
                    .font(.title3.bold())
                    .foregroundStyle(isPaid ? .green : .primary)

                if isPaid {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .background(Circle().fill(.white))
                        .offset(x: 18, y: 18)
                }
            }

            Text(contact.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 60)

            Text(totalOwed, format: .currency(code: "RUB"))
                .font(.caption2.bold())
                .foregroundStyle(isPaid ? .green : .primary)
        }
        .offset(dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation
                }
                .onEnded { _ in
                    withAnimation(.spring()) {
                        isDragging = false
                        dragOffset = .zero
                    }
                }
        )
        .scaleEffect(isDragging ? 1.2 : 1.0)
        .zIndex(isDragging ? 100 : 1)
    }
}

struct DraggableBillItemRow: View {
    let item: BillItem
    @ObservedObject var viewModel: SplitBillViewModel
    let participants: [Contact]
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            // Category Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.category.color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: item.category.icon)
                    .foregroundStyle(item.category.color)
            }

            // Item Info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.bold())

                HStack(spacing: 4) {
                    Text("\(item.quantity) x")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !item.assignedTo.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)

                        HStack(spacing: -4) {
                            ForEach(item.assignedTo.prefix(3)) { contact in
                                Circle()
                                    .fill(Color.random)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Text(String(contact.name.prefix(1)))
                                            .font(.system(size: 8))
                                            .foregroundStyle(.white)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 1)
                                    )
                            }

                            if item.assignedTo.count > 3 {
                                Text("+\(item.assignedTo.count - 3)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.amount * Double(item.quantity), format: .currency(code: "RUB"))
                    .font(.subheadline.bold())

                if item.assignedTo.isEmpty {
                    Text("Перетащите контакт")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    let perPerson = (item.amount * Double(item.quantity)) / Double(item.assignedTo.count)
                    Text("\(perPerson, format: .currency(code: "RUB")) / чел")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isTargeted ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
        .dropDestination(for: Contact.self) { contacts, location in
            guard let contact = contacts.first else { return false }
            viewModel.assignItemViaDrag(item, to: contact)
            isTargeted = false
            return true
        } isTargeted: { isTargeted in
            withAnimation {
                self.isTargeted = isTargeted
            }
        }
    }
}

struct SplitRow: View {
    let split: BillSplit
    let onPay: () -> Void
    let onReminder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(split.isPaid ? Color.green.opacity(0.2) : Color.random.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(String(split.contact.name.prefix(1)))
                    .font(.callout.bold())
                    .foregroundStyle(split.isPaid ? .green : .primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(split.contact.name)
                    .font(.subheadline.bold())

                if split.isPaid, let method = split.paymentMethod {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(method.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("\(split.items.count) позиций")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(split.totalOwed, format: .currency(code: "RUB"))
                    .font(.subheadline.bold())
                    .foregroundStyle(split.isPaid ? .green : .primary)

                if !split.isPaid {
                    HStack(spacing: 8) {
                        Button(action: onReminder) {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        Button(action: onPay) {
                            Text("Оплатить")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.blue)
                                )
                        }
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

// MARK: - Sheets
struct NewSessionSheet: View {
    @ObservedObject var viewModel: SplitBillViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var restaurantName = ""
    @State private var selectedParticipants: [Contact] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Ресторан") {
                    TextField("Название заведения", text: $restaurantName)
                }

                Section("Участники") {
                    ContactPicker(selectedContacts: $selectedParticipants)
                }

                Section("Настройки") {
                    HStack {
                        Text("Налог")
                        Spacer()
                        Text("20%")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Чаевые")
                        Spacer()
                        Text("10%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Новое разделение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Начать") {
                        viewModel.createSession(restaurantName: restaurantName, participants: selectedParticipants)
                        dismiss()
                    }
                    .disabled(restaurantName.isEmpty || selectedParticipants.isEmpty)
                }
            }
        }
    }
}

struct AddBillItemSheet: View {
    @ObservedObject var viewModel: SplitBillViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var quantity = 1
    @State private var category: BillItem.BillCategory = .food

    var body: some View {
        NavigationStack {
            Form {
                Section("Позиция") {
                    TextField("Название", text: $name)

                    TextField("Сумма", text: $amount)
                        .keyboardType(.decimalPad)
                }

                Section("Количество") {
                    Stepper("\(quantity)", value: $quantity, in: 1...99)
                }

                Section("Категория") {
                    Picker("Категория", selection: $category) {
                        ForEach(BillItem.BillCategory.allCases, id: \.self) { cat in
                            HStack {
                                Image(systemName: cat.icon)
                                Text(cat.rawValue)
                            }
                            .tag(cat)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("Добавить позицию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        if let amountValue = Double(amount) {
                            viewModel.addItem(name: name, amount: amountValue, quantity: quantity, category: category)
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || amount.isEmpty)
                }
            }
        }
    }
}

struct PaymentSheet: View {
    let split: BillSplit
    @ObservedObject var viewModel: SplitBillViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethod: BillSplit.PaymentMethod = .applePay

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Amount
                VStack(spacing: 8) {
                    Text("К оплате")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(split.totalOwed, format: .currency(code: "RUB"))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                }
                .padding(.top, 20)

                // Payment Methods
                VStack(spacing: 12) {
                    PaymentMethodButton(
                        method: .applePay,
                        icon: "apple.logo",
                        title: "Apple Pay",
                        isSelected: selectedMethod == .applePay
                    ) {
                        selectedMethod = .applePay
                    }

                    PaymentMethodButton(
                        method: .card,
                        icon: "creditcard.fill",
                        title: "Банковская карта",
                        isSelected: selectedMethod == .card
                    ) {
                        selectedMethod = .card
                    }

                    PaymentMethodButton(
                        method: .transfer,
                        icon: "arrow.left.arrow.right",
                        title: "Перевод SBP",
                        isSelected: selectedMethod == .transfer
                    ) {
                        selectedMethod = .transfer
                    }

                    PaymentMethodButton(
                        method: .cash,
                        icon: "banknote.fill",
                        title: "Наличные",
                        isSelected: selectedMethod == .cash
                    ) {
                        selectedMethod = .cash
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Pay Button
                Button(action: {
                    viewModel.markAsPaid(split: split, method: selectedMethod)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Оплатить \(split.totalOwed, format: .currency(code: "RUB"))")
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

struct PaymentMethodButton: View {
    let method: BillSplit.PaymentMethod
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 32)

                Text(title)
                    .font(.subheadline.bold())

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct ReceiptScannerSheet: View {
    @ObservedObject var viewModel: SplitBillViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Отсканируйте чек")
                    .font(.title2.bold())

                Text("Наведите камеру на чек, и мы автоматически распознаем все позиции")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: { showCamera = true }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Сканировать")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue)
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Сканер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

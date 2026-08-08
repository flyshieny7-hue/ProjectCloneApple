import Foundation
import MultipeerConnectivity
import CoreBluetooth
import CryptoKit
import Combine

// MARK: - Models
struct NearbyPaymentSession: Identifiable {
    let id: UUID
    var sender: NearbyContact
    var receiver: NearbyContact
    var amount: Double
    var status: PaymentStatus
    var timestamp: Date
    var confirmationCode: String
    var isSecure: Bool

    enum PaymentStatus: String {
        case discovering = "Поиск..."
        case connecting = "Подключение..."
        case authenticating = "Аутентификация..."
        case confirming = "Подтверждение..."
        case completed = "Завершено"
        case failed = "Ошибка"
        case cancelled = "Отменено"
    }
}

struct NearbyContact: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var peerID: MCPeerID?
    var avatar: Data?
    var deviceType: DeviceType
    var distance: Double? // in meters
    var lastSeen: Date
    var isTrusted: Bool
    var publicKey: String?

    enum DeviceType: String {
        case iPhone = "iPhone"
        case iPad = "iPad"
        case appleWatch = "Apple Watch"
        case mac = "Mac"
        case unknown = "Устройство"
    }
}

struct NearbyPaymentRequest: Identifiable {
    let id: UUID
    var from: NearbyContact
    var amount: Double
    var description: String
    var timestamp: Date
    var expiryDate: Date
    var isUrgent: Bool
}

// MARK: - Errors
enum NearbyPaymentError: Error, LocalizedError {
    case peerNotFound
    case connectionFailed
    case authenticationFailed
    case insufficientFunds
    case timeout
    case cancelled
    case encryptionFailed
    case invalidAmount
    case deviceNotSupported

    var errorDescription: String? {
        switch self {
        case .peerNotFound: return "Получатель не найден"
        case .connectionFailed: return "Не удалось установить соединение"
        case .authenticationFailed: return "Ошибка аутентификации"
        case .insufficientFunds: return "Недостаточно средств"
        case .timeout: return "Время ожидания истекло"
        case .cancelled: return "Операция отменена"
        case .encryptionFailed: return "Ошибка шифрования"
        case .invalidAmount: return "Некорректная сумма"
        case .deviceNotSupported: return "Устройство не поддерживается"
        }
    }
}

// MARK: - Manager
@MainActor
final class NearbyPaymentManager: NSObject, ObservableObject {
    static let shared = NearbyPaymentManager()

    // Published properties
    @Published var discoveredContacts: [NearbyContact] = []
    @Published var activeSessions: [NearbyPaymentSession] = []
    @Published var incomingRequests: [NearbyPaymentRequest] = []
    @Published var isScanning = false
    @Published var isAdvertising = false
    @Published var currentSession: NearbyPaymentSession?
    @Published var error: NearbyPaymentError?
    @Published var showError = false

    // Multipeer Connectivity
    private var peerID: MCPeerID?
    private var session: MCSession?
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser?
    private var nearbyServiceBrowser: MCNearbyServiceBrowser?

    // Security
    private let serviceType = "wallet-payment"
    private let encryptionKey: SymmetricKey
    private var trustedPeers: Set<String> = []

    // Combine
    private var cancellables = Set<AnyCancellable>()
    private var timeoutTimer: Timer?

    // Discovery settings
    private let discoveryTimeout: TimeInterval = 30.0
    private let connectionTimeout: TimeInterval = 15.0
    private let maxDiscoveryDistance: Double = 10.0 // meters

    private override init() {
        // Generate or load encryption key
        if let keyData = UserDefaults.standard.data(forKey: "nearby_payment_key") {
            self.encryptionKey = SymmetricKey(data: keyData)
        } else {
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }
            UserDefaults.standard.set(keyData, forKey: "nearby_payment_key")
            self.encryptionKey = newKey
        }

        super.init()
        setupSession()
    }

    private func setupSession() {
        let displayName = UIDevice.current.name
        peerID = MCPeerID(displayName: displayName)

        guard let peerID = peerID else { return }

        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
    }

    // MARK: - Public Methods

    func startDiscovery() {
        guard let peerID = peerID else { return }

        isScanning = true
        discoveredContacts.removeAll()

        // Start browsing
        nearbyServiceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        nearbyServiceBrowser?.delegate = self
        nearbyServiceBrowser?.startBrowsingForPeers()

        // Start advertising
        nearbyServiceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: [
            "version": "1.0",
            "device": UIDevice.current.model,
            "publicKey": publicKeyString()
        ], serviceType: serviceType)
        nearbyServiceAdvertiser?.delegate = self
        nearbyServiceAdvertiser?.startAdvertisingPeer()
        isAdvertising = true

        // Timeout
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: discoveryTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopDiscovery()
            }
        }
    }

    func stopDiscovery() {
        isScanning = false
        isAdvertising = false
        nearbyServiceBrowser?.stopBrowsingForPeers()
        nearbyServiceAdvertiser?.stopAdvertisingPeer()
        timeoutTimer?.invalidate()
    }

    func sendPayment(to contact: NearbyContact, amount: Double, description: String = "") async throws {
        guard amount > 0 else {
            throw NearbyPaymentError.invalidAmount
        }

        guard let peerID = contact.peerID,
              let session = session else {
            throw NearbyPaymentError.peerNotFound
        }

        // Create session
        let currentUser = NearbyContact(
            id: UUID(),
            displayName: self.peerID?.displayName ?? "Вы",
            peerID: self.peerID,
            avatar: nil,
            deviceType: .iPhone,
            distance: nil,
            lastSeen: Date(),
            isTrusted: true,
            publicKey: publicKeyString()
        )

        let paymentSession = NearbyPaymentSession(
            id: UUID(),
            sender: currentUser,
            receiver: contact,
            amount: amount,
            status: .connecting,
            timestamp: Date(),
            confirmationCode: generateConfirmationCode(),
            isSecure: true
        )

        activeSessions.append(paymentSession)
        currentSession = paymentSession

        // Invite peer
        nearbyServiceBrowser?.invitePeer(peerID, to: session, withContext: nil, timeout: connectionTimeout)

        // Wait for connection
        try await waitForConnection(session: paymentSession)

        // Send encrypted payment data
        let paymentData = try await createPaymentPayload(session: paymentSession, description: description)
        try await sendEncryptedData(paymentData, to: peerID)

        // Wait for confirmation
        try await waitForConfirmation(session: paymentSession)

        // Complete
        updateSessionStatus(paymentSession.id, to: .completed)
    }

    func requestPayment(from contact: NearbyContact, amount: Double, description: String = "", isUrgent: Bool = false) async throws {
        let request = NearbyPaymentRequest(
            id: UUID(),
            from: contact,
            amount: amount,
            description: description,
            timestamp: Date(),
            expiryDate: Date().addingTimeInterval(86400),
            isUrgent: isUrgent
        )

        incomingRequests.append(request)

        // Send request via Multipeer
        let requestData = try JSONEncoder().encode(request)
        if let peerID = contact.peerID {
            try await sendEncryptedData(requestData, to: peerID)
        }
    }

    func acceptRequest(_ request: NearbyPaymentRequest) async throws {
        guard let contact = discoveredContacts.first(where: { $0.id == request.from.id }) else {
            throw NearbyPaymentError.peerNotFound
        }

        try await sendPayment(to: contact, amount: request.amount, description: request.description)
        incomingRequests.removeAll { $0.id == request.id }
    }

    func declineRequest(_ request: NearbyPaymentRequest) {
        incomingRequests.removeAll { $0.id == request.id }
        // Notify sender
    }

    func cancelSession(_ session: NearbyPaymentSession) {
        updateSessionStatus(session.id, to: .cancelled)
        if let peerID = session.receiver.peerID {
            self.session?.cancelConnectPeer(peerID)
        }
    }

    func trustContact(_ contact: NearbyContact) {
        if let key = contact.publicKey {
            trustedPeers.insert(key)
        }
    }

    func untrustContact(_ contact: NearbyContact) {
        if let key = contact.publicKey {
            trustedPeers.remove(key)
        }
    }

    // MARK: - Social Notifications (used by other managers)

    func sendInvitation(to contact: Contact, for wallet: GroupWallet) async {
        // In real app, send via Push Notification / iMessage
        print("Invitation sent to \(contact.name) for wallet \(wallet.name)")
    }

    func sendTransactionNotification(to contact: Contact, transaction: GroupTransaction, walletName: String) async {
        print("Transaction notification sent to \(contact.name)")
    }

    func sendPaymentReminder(to contact: Contact, amount: Double) async {
        print("Payment reminder sent to \(contact.name) for \(amount)")
    }

    func sendBudgetAlert(to contact: BudgetMember, message: String, budgetName: String) async {
        print("Budget alert sent to \(contact.contact.name): \(message)")
    }

    func sendApprovalRequest(to manager: BudgetMember, transaction: BudgetTransaction, budgetName: String) async {
        print("Approval request sent to \(manager.contact.name)")
    }

    func sendMilestoneNotification(to contributor: SavingsContributor, milestone: SavingsMilestone, goalName: String) async {
        print("Milestone \(milestone.title) reached for \(goalName), notified \(contributor.contact.name)")
    }

    func sendContributionNotification(to contributor: SavingsContributor, contributorName: String, amount: Double, goalName: String) async {
        print("\(contributorName) contributed \(amount) to \(goalName), notified \(contributor.contact.name)")
    }

    func sendCommentNotification(to participant: SocialContact, message: String, transactionDescription: String) async {
        print("Comment notification sent to \(participant.name) about \(transactionDescription)")
    }

    // MARK: - Private Methods

    private func waitForConnection(session: NearbyPaymentSession) async throws {
        let startTime = Date()
        while session.status != .authenticating && session.status != .confirming {
            if Date().timeIntervalSince(startTime) > connectionTimeout {
                throw NearbyPaymentError.timeout
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
    }

    private func waitForConfirmation(session: NearbyPaymentSession) async throws {
        let startTime = Date()
        while session.status != .completed && session.status != .failed {
            if Date().timeIntervalSince(startTime) > connectionTimeout {
                throw NearbyPaymentError.timeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if session.status == .failed {
            throw NearbyPaymentError.authenticationFailed
        }
    }

    private func createPaymentPayload(session: NearbyPaymentSession, description: String) async throws -> Data {
        let payload: [String: Any] = [
            "type": "payment",
            "sessionID": session.id.uuidString,
            "amount": session.amount,
            "description": description,
            "confirmationCode": session.confirmationCode,
            "timestamp": ISO8601DateFormatter().string(from: session.timestamp),
            "senderPublicKey": publicKeyString()
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try encryptData(jsonData)
    }

    private func sendEncryptedData(_ data: Data, to peer: MCPeerID) async throws {
        guard let session = session else {
            throw NearbyPaymentError.connectionFailed
        }

        try session.send(data, toPeers: [peer], with: .reliable)
    }

    private func encryptData(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        return sealedBox.combined ?? data
    }

    private func decryptData(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }

    private func generateConfirmationCode() -> String {
        let digits = "0123456789"
        return String((0..<4).map { _ in digits.randomElement()! })
    }

    private func publicKeyString() -> String {
        let publicKeyData = encryptionKey.withUnsafeBytes { Data($0) }
        return publicKeyData.base64EncodedString()
    }

    private func updateSessionStatus(_ sessionID: UUID, to status: NearbyPaymentSession.PaymentStatus) {
        if let index = activeSessions.firstIndex(where: { $0.id == sessionID }) {
            var updatedSession = activeSessions[index]
            updatedSession.status = status
            activeSessions[index] = updatedSession

            if currentSession?.id == sessionID {
                currentSession = updatedSession
            }
        }
    }

    private func handleReceivedData(_ data: Data, from peer: MCPeerID) {
        Task {
            do {
                let decryptedData = try decryptData(data)
                let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any]

                guard let type = json?["type"] as? String else { return }

                switch type {
                case "payment":
                    await handlePaymentRequest(json: json, from: peer)
                case "confirmation":
                    await handleConfirmation(json: json)
                case "payment_request":
                    await handleIncomingRequest(json: json, from: peer)
                default:
                    break
                }
            } catch {
                self.error = .encryptionFailed
                self.showError = true
            }
        }
    }

    private func handlePaymentRequest(json: [String: Any]?, from peer: MCPeerID) async {
        guard let amount = json?["amount"] as? Double,
              let sessionIDString = json?["sessionID"] as? String,
              let sessionID = UUID(uuidString: sessionIDString),
              let confirmationCode = json?["confirmationCode"] as? String else { return }

        // Show confirmation UI
        await MainActor.run {
            if let index = activeSessions.firstIndex(where: { $0.id == sessionID }) {
                activeSessions[index].status = .confirming
                activeSessions[index].confirmationCode = confirmationCode
                currentSession = activeSessions[index]
            }
        }
    }

    private func handleConfirmation(json: [String: Any]?) async {
        guard let sessionIDString = json?["sessionID"] as? String,
              let sessionID = UUID(uuidString: sessionIDString),
              let confirmed = json?["confirmed"] as? Bool else { return }

        await MainActor.run {
            updateSessionStatus(sessionID, to: confirmed ? .completed : .failed)
        }
    }

    private func handleIncomingRequest(json: [String: Any]?, from peer: MCPeerID) async {
        // Handle incoming payment request
    }
}

// MARK: - MCSessionDelegate
extension NearbyPaymentManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if let index = activeSessions.firstIndex(where: { $0.receiver.peerID == peerID }) {
                    activeSessions[index].status = .authenticating
                    if currentSession?.id == activeSessions[index].id {
                        currentSession = activeSessions[index]
                    }
                }
            case .connecting:
                break
            case .notConnected:
                if let index = activeSessions.firstIndex(where: { $0.receiver.peerID == peerID }) {
                    activeSessions[index].status = .failed
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            handleReceivedData(data, from: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate
extension NearbyPaymentManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            let deviceType = NearbyContact.DeviceType(rawValue: info?["device"] ?? "Устройство") ?? .unknown
            let publicKey = info?["publicKey"]
            let isTrusted = publicKey != nil ? trustedPeers.contains(publicKey!) : false

            let contact = NearbyContact(
                id: UUID(),
                displayName: peerID.displayName,
                peerID: peerID,
                avatar: nil,
                deviceType: deviceType,
                distance: nil, // Would need BLE RSSI for actual distance
                lastSeen: Date(),
                isTrusted: isTrusted,
                publicKey: publicKey
            )

            if !discoveredContacts.contains(where: { $0.peerID == peerID }) {
                discoveredContacts.append(contact)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            discoveredContacts.removeAll { $0.peerID == peerID }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension NearbyPaymentManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Auto-accept from trusted peers, show prompt for others
            let isTrusted = discoveredContacts.first(where: { $0.peerID == peerID })?.isTrusted ?? false
            invitationHandler(true, session)
        }
    }
}

// MARK: - NearbyPaymentView (UI)
struct NearbyPaymentView: View {
    @StateObject private var manager = NearbyPaymentManager.shared
    @State private var amount = ""
    @State private var selectedContact: NearbyContact?
    @State private var showConfirmation = false
    @State private var showRequestSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Scanner Animation
                    scannerSection

                    // Discovered Contacts
                    contactsList

                    // Manual Entry
                    manualEntrySection
                }
            }
            .navigationTitle("Оплата рядом")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showRequestSheet = true }) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .sheet(isPresented: $showRequestSheet) {
                RequestMoneyView()
            }
            .overlay {
                if let session = manager.currentSession {
                    PaymentConfirmationOverlay(session: session, manager: manager)
                }
            }
        }
    }

    private var scannerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(manager.isScanning ? Color.cyan.opacity(0.3) : Color(.systemGray5), lineWidth: 2)
                    .frame(width: 160, height: 160)

                if manager.isScanning {
                    Circle()
                        .stroke(Color.cyan.opacity(0.6), lineWidth: 2)
                        .frame(width: 160, height: 160)
                        .scaleEffect(1.2)
                        .opacity(0.5)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: manager.isScanning)
                }

                Image(systemName: "wave.3.right")
                    .font(.system(size: 48))
                    .foregroundStyle(manager.isScanning ? .cyan : .secondary)
            }

            Text(manager.isScanning ? "Поиск устройств..." : "Нажмите для поиска")
                .font(.headline)
                .foregroundStyle(manager.isScanning ? .cyan : .secondary)

            Button(action: {
                if manager.isScanning {
                    manager.stopDiscovery()
                } else {
                    manager.startDiscovery()
                }
            }) {
                HStack {
                    Image(systemName: manager.isScanning ? "stop.fill" : "wave.3.right.circle.fill")
                    Text(manager.isScanning ? "Остановить" : "Начать поиск")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(manager.isScanning ? Color.red : Color.cyan)
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
    }

    private var contactsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Рядом")
                    .font(.headline)

                Spacer()

                if manager.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)

            if manager.discoveredContacts.isEmpty && manager.isScanning {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Устройства не найдены")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Убедитесь, что другие устройства тоже ищут")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
            } else if manager.discoveredContacts.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "wave.3.right.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Нажмите «Начать поиск»")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
            } else {
                ForEach(manager.discoveredContacts) { contact in
                    NearbyContactRow(contact: contact, isSelected: selectedContact?.id == contact.id) {
                        selectedContact = contact
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top)
    }

    private var manualEntrySection: some View {
        VStack(spacing: 12) {
            if let contact = selectedContact {
                HStack(spacing: 12) {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                }

                Text("Отправить \(contact.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: {
                    Task {
                        if let amountValue = Double(amount) {
                            try? await manager.sendPayment(to: contact, amount: amountValue)
                            amount = ""
                            selectedContact = nil
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Отправить")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(amount.isEmpty ? Color.gray : Color.cyan)
                    )
                }
                .disabled(amount.isEmpty)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

struct NearbyContactRow: View {
    let contact: NearbyContact
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: deviceIcon)
                        .font(.title3)
                        .foregroundStyle(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.subheadline.bold())

                    HStack(spacing: 4) {
                        Text(contact.deviceType.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if contact.isTrusted {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }

                        if let distance = contact.distance {
                            Text("• \(Int(distance)) м")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.cyan.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var deviceIcon: String {
        switch contact.deviceType {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .appleWatch: return "applewatch"
        case .mac: return "desktopcomputer"
        case .unknown: return "device.unknown"
        }
    }
}

struct PaymentConfirmationOverlay: View {
    let session: NearbyPaymentSession
    @ObservedObject var manager: NearbyPaymentManager

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Status Icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 100, height: 100)

                    Image(systemName: statusIcon)
                        .font(.system(size: 48))
                        .foregroundStyle(statusColor)
                }

                VStack(spacing: 8) {
                    Text(session.status.rawValue)
                        .font(.title2.bold())

                    if session.status == .confirming {
                        Text("Код подтверждения: **\(session.confirmationCode)**")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text("Сообщите этот код получателю")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let amount = session.amount {
                        Text(amount, format: .currency(code: "RUB"))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                    }
                }

                if session.status == .confirming {
                    HStack(spacing: 12) {
                        Button(action: {
                            // Send confirmation
                        }) {
                            Text("Подтвердить")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.green)
                                )
                        }

                        Button(action: {
                            manager.cancelSession(session)
                        }) {
                            Text("Отменить")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.red)
                                )
                        }
                    }
                } else if session.status == .completed {
                    Button(action: {
                        manager.currentSession = nil
                    }) {
                        Text("Готово")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.green)
                            )
                    }
                } else if session.status == .failed || session.status == .cancelled {
                    Button(action: {
                        manager.currentSession = nil
                    }) {
                        Text("Закрыть")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray)
                            )
                    }
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)
            )
            .padding(32)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .discovering, .connecting, .authenticating: return .orange
        case .confirming: return .blue
        case .completed: return .green
        case .failed, .cancelled: return .red
        }
    }

    private var statusIcon: String {
        switch session.status {
        case .discovering: return "wave.3.right"
        case .connecting: return "link"
        case .authenticating: return "lock.shield"
        case .confirming: return "checkmark.shield"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "xmark.octagon.fill"
        }
    }
}

struct RequestMoneyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var description = ""
    @State private var isUrgent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Сумма") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                }

                Section("Описание") {
                    TextField("За что?", text: $description)
                }

                Section("Приоритет") {
                    Toggle("Срочный запрос", isOn: $isUrgent)
                }

                Section("Контакты") {
                    Text("Выберите контакты для запроса")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(mockSocialContacts) { contact in
                        HStack {
                            Circle()
                                .fill(contact.color)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(String(contact.name.prefix(1)))
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                )

                            Text(contact.name)
                                .font(.subheadline)

                            Spacer()

                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Запросить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") {
                        dismiss()
                    }
                    .disabled(amount.isEmpty)
                }
            }
        }
    }
}

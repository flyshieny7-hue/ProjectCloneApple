import SwiftUI

// MARK: - Models
struct TransactionComment: Identifiable, Equatable {
    let id: UUID
    var author: SocialContact
    var text: String
    var timestamp: Date
    var reactions: [CommentReaction]
    var replies: [TransactionComment]
    var isEdited: Bool
    var editTimestamp: Date?
    var attachments: [CommentAttachment]
    var isPinned: Bool

    static func == (lhs: TransactionComment, rhs: TransactionComment) -> Bool {
        lhs.id == rhs.id
    }
}

struct CommentReaction: Identifiable, Equatable {
    let id: UUID
    var emoji: String
    var authors: [SocialContact]

    var count: Int { authors.count }
    var isEmpty: Bool { authors.isEmpty }
}

struct CommentAttachment: Identifiable {
    let id: UUID
    var type: AttachmentType
    var url: URL?
    var data: Data?
    var thumbnail: Data?

    enum AttachmentType: String {
        case image = "Фото"
        case receipt = "Чек"
        case location = "Локация"
        case link = "Ссылка"
        case voice = "Голосовое"
    }
}

struct SocialContact: Identifiable, Hashable {
    let id: UUID
    var name: String
    var avatar: Data?
    var color: Color
    var isCurrentUser: Bool
}

struct CommentThread: Identifiable {
    let id: UUID
    var transactionID: UUID
    var transactionDescription: String
    var transactionAmount: Double
    var comments: [TransactionComment]
    var participants: [SocialContact]
    var lastActivity: Date
    var isMuted: Bool
}

// MARK: - ViewModel
@MainActor
class TransactionCommentsViewModel: ObservableObject {
    @Published var threads: [CommentThread] = []
    @Published var currentThread: CommentThread?
    @Published var newCommentText = ""
    @Published var selectedReaction: String?
    @Published var isLoading = false
    @Published var showEmojiPicker = false
    @Published var replyingTo: TransactionComment?

    private let cloudKitManager = CloudKitSyncManager.shared

    let availableReactions = ["👍", "❤️", "😂", "😮", "😢", "🔥", "👏", "💰", "📉", "📈"]

    func loadThreads() {
        Task {
            isLoading = true
            defer { isLoading = false }

            // Mock data for demonstration
            threads = createMockThreads()
        }
    }

    func addComment(to threadID: UUID, text: String, replyTo: TransactionComment? = nil, attachments: [CommentAttachment] = []) async {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else { return }

        let currentUser = SocialContact(
            id: UUID(),
            name: "Вы",
            avatar: nil,
            color: .blue,
            isCurrentUser: true
        )

        let newComment = TransactionComment(
            id: UUID(),
            author: currentUser,
            text: text,
            timestamp: Date(),
            reactions: [],
            replies: [],
            isEdited: false,
            editTimestamp: nil,
            attachments: attachments,
            isPinned: false
        )

        if let replyTo = replyTo,
           let commentIndex = threads[threadIndex].comments.firstIndex(where: { $0.id == replyTo.id }) {
            threads[threadIndex].comments[commentIndex].replies.append(newComment)
        } else {
            threads[threadIndex].comments.append(newComment)
        }

        threads[threadIndex].lastActivity = Date()

        do {
            try await cloudKitManager.saveComment(newComment, to: threadID)
            await notifyParticipants(in: threads[threadIndex], about: newComment)
        } catch {
            print("Failed to save comment: \(error)")
        }

        newCommentText = ""
        replyingTo = nil
    }

    func addReaction(_ emoji: String, to commentID: UUID, in threadID: UUID) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
              let commentIndex = threads[threadIndex].comments.firstIndex(where: { $0.id == commentID }) else { return }

        let currentUser = SocialContact(
            id: UUID(),
            name: "Вы",
            avatar: nil,
            color: .blue,
            isCurrentUser: true
        )

        if let reactionIndex = threads[threadIndex].comments[commentIndex].reactions.firstIndex(where: { $0.emoji == emoji }) {
            if threads[threadIndex].comments[commentIndex].reactions[reactionIndex].authors.contains(currentUser) {
                threads[threadIndex].comments[commentIndex].reactions[reactionIndex].authors.removeAll { $0.id == currentUser.id }
                if threads[threadIndex].comments[commentIndex].reactions[reactionIndex].isEmpty {
                    threads[threadIndex].comments[commentIndex].reactions.remove(at: reactionIndex)
                }
            } else {
                threads[threadIndex].comments[commentIndex].reactions[reactionIndex].authors.append(currentUser)
            }
        } else {
            let newReaction = CommentReaction(
                id: UUID(),
                emoji: emoji,
                authors: [currentUser]
            )
            threads[threadIndex].comments[commentIndex].reactions.append(newReaction)
        }

        Task {
            try? await cloudKitManager.updateComment(threads[threadIndex].comments[commentIndex])
        }
    }

    func editComment(_ comment: TransactionComment, newText: String, in threadID: UUID) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
              let commentIndex = threads[threadIndex].comments.firstIndex(where: { $0.id == comment.id }) else { return }

        threads[threadIndex].comments[commentIndex].text = newText
        threads[threadIndex].comments[commentIndex].isEdited = true
        threads[threadIndex].comments[commentIndex].editTimestamp = Date()

        Task {
            try? await cloudKitManager.updateComment(threads[threadIndex].comments[commentIndex])
        }
    }

    func deleteComment(_ comment: TransactionComment, in threadID: UUID) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[threadIndex].comments.removeAll { $0.id == comment.id }

        Task {
            try? await cloudKitManager.deleteComment(comment)
        }
    }

    func pinComment(_ comment: TransactionComment, in threadID: UUID) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
              let commentIndex = threads[threadIndex].comments.firstIndex(where: { $0.id == comment.id }) else { return }

        // Unpin all others
        for i in threads[threadIndex].comments.indices {
            threads[threadIndex].comments[i].isPinned = false
        }

        threads[threadIndex].comments[commentIndex].isPinned.toggle()

        Task {
            try? await cloudKitManager.updateComment(threads[threadIndex].comments[commentIndex])
        }
    }

    private func notifyParticipants(in thread: CommentThread, about comment: TransactionComment) async {
        for participant in thread.participants where !participant.isCurrentUser {
            await NearbyPaymentManager.shared.sendCommentNotification(
                to: participant,
                message: "\(comment.author.name): \(comment.text)",
                transactionDescription: thread.transactionDescription
            )
        }
    }

    private func createMockThreads() -> [CommentThread] {
        let contacts = [
            SocialContact(id: UUID(), name: "Анна", avatar: nil, color: .pink, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Михаил", avatar: nil, color: .blue, isCurrentUser: false),
            SocialContact(id: UUID(), name: "Елена", avatar: nil, color: .purple, isCurrentUser: false)
        ]

        let currentUser = SocialContact(id: UUID(), name: "Вы", avatar: nil, color: .green, isCurrentUser: true)

        let comment1 = TransactionComment(
            id: UUID(),
            author: contacts[0],
            text: "Кажется, мы переплатили за такси. Давайте проверим чек?",
            timestamp: Date().addingTimeInterval(-3600),
            reactions: [
                CommentReaction(id: UUID(), emoji: "👍", authors: [contacts[1], currentUser]),
                CommentReaction(id: UUID(), emoji: "❓", authors: [contacts[2]])
            ],
            replies: [
                TransactionComment(
                    id: UUID(),
                    author: contacts[1],
                    text: "Да, точно! Должно быть 450₽, а не 650₽",
                    timestamp: Date().addingTimeInterval(-3000),
                    reactions: [CommentReaction(id: UUID(), emoji: "🔥", authors: [currentUser])],
                    replies: [],
                    isEdited: false,
                    editTimestamp: nil,
                    attachments: [],
                    isPinned: false
                )
            ],
            isEdited: false,
            editTimestamp: nil,
            attachments: [],
            isPinned: true
        )

        let comment2 = TransactionComment(
            id: UUID(),
            author: contacts[2],
            text: "Я нашла чек, прикрепляю фото",
            timestamp: Date().addingTimeInterval(-1800),
            reactions: [CommentReaction(id: UUID(), emoji: "📸", authors: [contacts[0], currentUser])],
            replies: [],
            isEdited: false,
            editTimestamp: nil,
            attachments: [CommentAttachment(id: UUID(), type: .image, url: nil, data: nil, thumbnail: nil)],
            isPinned: false
        )

        let comment3 = TransactionComment(
            id: UUID(),
            author: currentUser,
            text: "Отлично, тогда пересчитаем завтра за завтраком ☕️",
            timestamp: Date().addingTimeInterval(-900),
            reactions: [
                CommentReaction(id: UUID(), emoji: "☕️", authors: [contacts[0], contacts[1], contacts[2]])
            ],
            replies: [],
            isEdited: false,
            editTimestamp: nil,
            attachments: [],
            isPinned: false
        )

        return [
            CommentThread(
                id: UUID(),
                transactionID: UUID(),
                transactionDescription: "Такси до аэропорта",
                transactionAmount: 650,
                comments: [comment1, comment2, comment3],
                participants: contacts + [currentUser],
                lastActivity: Date(),
                isMuted: false
            ),
            CommentThread(
                id: UUID(),
                transactionID: UUID(),
                transactionDescription: "Ужин в ресторане",
                transactionAmount: 12400,
                comments: [],
                participants: contacts + [currentUser],
                lastActivity: Date().addingTimeInterval(-86400),
                isMuted: false
            )
        ]
    }
}

// MARK: - Views
struct TransactionCommentsView: View {
    @StateObject private var viewModel = TransactionCommentsViewModel()
    @State private var selectedThread: CommentThread?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                List {
                    ForEach(viewModel.threads.sorted(by: { $0.lastActivity > $1.lastActivity })) { thread in
                        ThreadRow(thread: thread) {
                            selectedThread = thread
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Обсуждения")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.loadThreads() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .navigationDestination(item: $selectedThread) { thread in
                CommentThreadView(thread: thread, viewModel: viewModel)
            }
            .onAppear {
                viewModel.loadThreads()
            }
        }
    }
}

struct ThreadRow: View {
    let thread: CommentThread
    let action: () -> Void

    var lastComment: TransactionComment? {
        thread.comments.sorted(by: { $0.timestamp > $1.timestamp }).first
    }

    var unreadCount: Int {
        // In real app, track read timestamps
        max(0, thread.comments.count - 2)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Transaction Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 52, height: 52)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(thread.transactionDescription)
                            .font(.subheadline.bold())

                        Spacer()

                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Circle().fill(.blue))
                        }
                    }

                    Text(thread.transactionAmount, format: .currency(code: "RUB"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastComment = lastComment {
                        HStack(spacing: 4) {
                            Text("\(lastComment.author.name):")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(lastComment.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack {
                        HStack(spacing: -4) {
                            ForEach(thread.participants.prefix(3)) { participant in
                                Circle()
                                    .fill(participant.color)
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Text(String(participant.name.prefix(1)))
                                            .font(.system(size: 8))
                                            .foregroundStyle(.white)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 1)
                                    )
                            }
                        }

                        Spacer()

                        Text(thread.lastActivity, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct CommentThreadView: View {
    let thread: CommentThread
    @ObservedObject var viewModel: TransactionCommentsViewModel
    @State private var showAttachmentPicker = false
    @State private var showEmojiPicker = false
    @FocusState private var isInputFocused: Bool

    var pinnedComment: TransactionComment? {
        thread.comments.first(where: { $0.isPinned })
    }

    var sortedComments: [TransactionComment] {
        thread.comments.filter { !$0.isPinned }.sorted(by: { $0.timestamp < $1.timestamp })
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Thread Header
                threadHeader

                // Pinned Comment
                if let pinned = pinnedComment {
                    PinnedCommentView(comment: pinned)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Comments List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(sortedComments) { comment in
                                CommentBubble(
                                    comment: comment,
                                    viewModel: viewModel,
                                    threadID: thread.id
                                )
                                .id(comment.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.threads) { _ in
                        if let lastComment = sortedComments.last {
                            withAnimation {
                                proxy.scrollTo(lastComment.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Reply Indicator
                if let replyingTo = viewModel.replyingTo {
                    HStack {
                        Text("Ответ \(replyingTo.author.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(action: { viewModel.replyingTo = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .background(Color(.systemBackground))
                }

                // Input Area
                inputArea
            }
        }
        .navigationTitle(thread.transactionDescription)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: {}) {
                        Label("Закрепить сообщение", systemImage: "pin.fill")
                    }

                    Button(action: {}) {
                        Label("Поиск", systemImage: "magnifyingglass")
                    }

                    Toggle("Без звука", isOn: .constant(thread.isMuted))

                    Divider()

                    Button(role: .destructive, action: {}) {
                        Label("Покинуть обсуждение", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAttachmentPicker) {
            AttachmentPickerSheet()
        }
    }

    private var threadHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.transactionAmount, format: .currency(code: "RUB"))
                    .font(.title3.bold())

                HStack(spacing: 6) {
                    HStack(spacing: -4) {
                        ForEach(thread.participants.prefix(3)) { participant in
                            Circle()
                                .fill(participant.color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Text(String(participant.name.prefix(1)))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(.systemBackground), lineWidth: 1)
                                )
                        }
                    }

                    Text("\(thread.participants.count) участников")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var inputArea: some View {
        HStack(spacing: 12) {
            Button(action: { showAttachmentPicker = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 8) {
                TextField(viewModel.replyingTo != nil ? "Ответить..." : "Комментарий...", text: $viewModel.newCommentText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isInputFocused)

                Button(action: { showEmojiPicker = true }) {
                    Image(systemName: "face.smiling.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
            )

            Button(action: {
                Task {
                    await viewModel.addComment(
                        to: thread.id,
                        text: viewModel.newCommentText,
                        replyTo: viewModel.replyingTo
                    )
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.newCommentText.isEmpty ? .gray : .blue)
            }
            .disabled(viewModel.newCommentText.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

struct CommentBubble: View {
    let comment: TransactionComment
    @ObservedObject var viewModel: TransactionCommentsViewModel
    let threadID: UUID
    @State private var showReactionPicker = false
    @State private var showContextMenu = false
    @State private var isEditing = false
    @State private var editText = ""

    var isCurrentUser: Bool {
        comment.author.isCurrentUser
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isCurrentUser {
                // Avatar
                Circle()
                    .fill(comment.author.color)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(comment.author.name.prefix(1)))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    )
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(comment.author.name)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }

                // Reply indicator
                if let replyTo = viewModel.replyingTo, replyTo.id == comment.id {
                    Text("Ответ...")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                }

                // Message Bubble
                VStack(alignment: .leading, spacing: 6) {
                    if isEditing {
                        TextField("Редактировать", text: $editText, axis: .vertical)
                            .lineLimit(1...5)
                            .padding(.horizontal, 4)

                        HStack {
                            Button("Отмена") {
                                isEditing = false
                            }
                            .font(.caption)

                            Spacer()

                            Button("Сохранить") {
                                viewModel.editComment(comment, newText: editText, in: threadID)
                                isEditing = false
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                        }
                    } else {
                        Text(comment.text)
                            .font(.subheadline)
                    }

                    // Attachments
                    if !comment.attachments.isEmpty {
                        AttachmentPreview(attachments: comment.attachments)
                    }

                    // Reactions
                    if !comment.reactions.isEmpty {
                        ReactionBar(
                            reactions: comment.reactions,
                            onReactionTap: { emoji in
                                viewModel.addReaction(emoji, to: comment.id, in: threadID)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isCurrentUser ? Color.blue.opacity(0.15) : Color(.secondarySystemBackground))
                )
                .contextMenu {
                    Button(action: { viewModel.replyingTo = comment }) {
                        Label("Ответить", systemImage: "arrowshape.turn.up.left.fill")
                    }

                    Button(action: {
                        showReactionPicker = true
                    }) {
                        Label("Реакция", systemImage: "face.smiling")
                    }

                    if isCurrentUser {
                        Button(action: {
                            editText = comment.text
                            isEditing = true
                        }) {
                            Label("Изменить", systemImage: "pencil")
                        }

                        Button(action: { viewModel.pinComment(comment, in: threadID) }) {
                            Label(comment.isPinned ? "Открепить" : "Закрепить", systemImage: "pin.fill")
                        }

                        Button(role: .destructive, action: {
                            viewModel.deleteComment(comment, in: threadID)
                        }) {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showReactionPicker {
                        ReactionPickerView(
                            availableReactions: viewModel.availableReactions,
                            onSelect: { emoji in
                                viewModel.addReaction(emoji, to: comment.id, in: threadID)
                                showReactionPicker = false
                            },
                            onDismiss: { showReactionPicker = false }
                        )
                        .offset(y: -40)
                    }
                }

                // Timestamp
                HStack(spacing: 4) {
                    Text(comment.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if comment.isEdited {
                        Text("(изменено)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)

                // Replies
                if !comment.replies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.turn.up.right")
                                    .font(.caption2)
                                Text("\(comment.replies.count) ответов")
                                    .font(.caption)
                            }
                            .foregroundStyle(.blue)
                        }

                        ForEach(comment.replies) { reply in
                            ReplyBubble(reply: reply, viewModel: viewModel, threadID: threadID)
                        }
                    }
                    .padding(.leading, 12)
                }
            }

            if isCurrentUser {
                Circle()
                    .fill(comment.author.color)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(comment.author.name.prefix(1)))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    )
            } else {
                Spacer(minLength: 40)
            }
        }
    }
}

struct ReplyBubble: View {
    let reply: TransactionComment
    @ObservedObject var viewModel: TransactionCommentsViewModel
    let threadID: UUID

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(reply.author.color)
                .frame(width: 24, height: 24)
                .overlay(
                    Text(String(reply.author.name.prefix(1)))
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(reply.author.name)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                Text(reply.text)
                    .font(.caption)

                if !reply.reactions.isEmpty {
                    ReactionBar(reactions: reply.reactions, onReactionTap: { emoji in
                        // Handle reply reaction
                    })
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )

            Spacer()
        }
    }
}

struct PinnedCommentView: View {
    let comment: TransactionComment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pin.fill")
                .foregroundStyle(.orange)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(comment.author.name)
                        .font(.caption2.bold())

                    Spacer()

                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Text(comment.text)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct ReactionBar: View {
    let reactions: [CommentReaction]
    let onReactionTap: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(reactions.filter { !$0.isEmpty }) { reaction in
                Button(action: { onReactionTap(reaction.emoji) }) {
                    HStack(spacing: 2) {
                        Text(reaction.emoji)
                            .font(.callout)
                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray5))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ReactionPickerView: View {
    let availableReactions: [String]
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(availableReactions, id: \.self) { emoji in
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

struct AttachmentPreview: View {
    let attachments: [CommentAttachment]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentItem(attachment: attachment)
            }
        }
    }
}

struct AttachmentItem: View {
    let attachment: CommentAttachment

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Image(systemName: iconForType)
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text(attachment.type.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconForType: String {
        switch attachment.type {
        case .image: return "photo.fill"
        case .receipt: return "doc.text.fill"
        case .location: return "location.fill"
        case .link: return "link"
        case .voice: return "waveform"
        }
    }
}

struct AttachmentPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Прикрепить")
                    .font(.headline)
                    .padding(.top)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    AttachmentOption(icon: "photo.fill", title: "Фото", color: .blue) {}
                    AttachmentOption(icon: "camera.fill", title: "Камера", color: .green) {}
                    AttachmentOption(icon: "doc.text.fill", title: "Чек", color: .orange) {}
                    AttachmentOption(icon: "location.fill", title: "Локация", color: .red) {}
                    AttachmentOption(icon: "link", title: "Ссылка", color: .purple) {}
                    AttachmentOption(icon: "waveform", title: "Голос", color: .pink) {}
                }
                .padding()

                Spacer()
            }
            .navigationTitle("Вложения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

struct AttachmentOption: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(color)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

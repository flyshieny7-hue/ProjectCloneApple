import SwiftUI

// MARK: - MasterContentView
/// Unified app router with NavigationStack + NavigationPath + deep links
struct MasterContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var restorationManager: StateRestorationManager
    @EnvironmentObject var urlHandler: URLSchemeHandler
    @EnvironmentObject var tutorialManager: TutorialManager
    @EnvironmentObject var settings: AppSettings

    @State private var navigationPath = NavigationPath()
    @State private var showOnboarding: Bool = false
    @State private var showTutorial: Bool = false
    @State private var showDebugMenu: Bool = false

    var body: some View {
        ZStack {
            mainContent

            // Performance Monitor Overlay
            if settings.showPerformanceOverlay || appState.showPerformanceOverlay {
                PerformanceOverlay()
                    .environmentObject(PerformanceMonitor())
            }

            // Tutorial Overlay
            if tutorialManager.isShowingTutorial {
                TutorialOverlay()
                    .environmentObject(tutorialManager)
                    .transition(.opacity)
            }

            // Debug Menu
            if showDebugMenu {
                DebugMenu(isPresented: $showDebugMenu)
                    .transition(.move(edge: .bottom))
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingFlow(isPresented: $showOnboarding)
        }
        .onAppear {
            checkOnboarding()
            setupDeepLinkHandling()
            setupShakeDetection()
            setupUniversalLinks()
        }
        .onChange(of: urlHandler.lastHandledURL) { _, newURL in
            if let url = newURL {
                handleDeepLink(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stateShouldRestore)) { _ in
            restoreNavigationState()
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: $appState.selectedTab) {
                WalletView()
                    .tabItem {
                        Label(AppState.Tab.wallet.title, systemImage: AppState.Tab.wallet.icon)
                    }
                    .tag(AppState.Tab.wallet)

                TransactionsView()
                    .tabItem {
                        Label(AppState.Tab.transactions.title, systemImage: AppState.Tab.transactions.icon)
                    }
                    .tag(AppState.Tab.transactions)

                BudgetView()
                    .tabItem {
                        Label(AppState.Tab.budget.title, systemImage: AppState.Tab.budget.icon)
                    }
                    .tag(AppState.Tab.budget)

                SettingsMasterView()
                    .tabItem {
                        Label(AppState.Tab.settings.title, systemImage: AppState.Tab.settings.icon)
                    }
                    .tag(AppState.Tab.settings)
            }
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
        }
    }

    // MARK: - Navigation Destinations
    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .cardDetail(let id):
            CardDetailView(cardID: id)
        case .transactionDetail(let id):
            TransactionDetailView(transactionID: id)
        case .budgetCategory(let category):
            BudgetCategoryView(category: category)
        case .pay:
            PayView()
        case .addCard:
            AddCardView()
        case .settingsDetail(let section):
            SettingsDetailView(section: section)
        case .debugConsole:
            DebugConsoleView()
        }
    }

    // MARK: - Onboarding
    private func checkOnboarding() {
        let hasCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        if !hasCompleted {
            showOnboarding = true
        } else {
            appState.isOnboardingComplete = true
        }
    }

    // MARK: - Deep Link Handling
    private func setupDeepLinkHandling() {
        // Handled via onOpenURL and URLSchemeHandler
    }

    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }

        switch url.scheme {
        case "wallet":
            handleWalletScheme(components: components)
        case "https":
            handleUniversalLink(components: components)
        default:
            break
        }
    }

    private func handleWalletScheme(components: URLComponents) {
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = path.split(separator: "/").map(String.init)

        guard let action = segments.first else { return }

        switch action {
        case "pay":
            navigate(to: .pay)
        case "card":
            if let cardID = segments.dropFirst().first {
                navigate(to: .cardDetail(id: cardID))
            }
        case "budget":
            appState.selectedTab = .budget
        case "settings":
            appState.selectedTab = .settings
        default:
            break
        }
    }

    private func handleUniversalLink(components: URLComponents) {
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = path.split(separator: "/").map(String.init)

        guard let action = segments.first else { return }

        switch action {
        case "pay":
            navigate(to: .pay)
        case "card":
            if let cardID = segments.dropFirst().first {
                navigate(to: .cardDetail(id: cardID))
            }
        case "budget":
            appState.selectedTab = .budget
        default:
            break
        }
    }

    // MARK: - Navigation
    private func navigate(to route: Route) {
        navigationPath.append(route)
    }

    // MARK: - State Restoration
    private func restoreNavigationState() {
        if let savedPath = restorationManager.restoredPath {
            for route in savedPath {
                navigationPath.append(route)
            }
        }
        if let savedTab = restorationManager.restoredTab {
            appState.selectedTab = savedTab
        }
    }

    // MARK: - Shake Detection
    private func setupShakeDetection() {
        NotificationCenter.default.addObserver(
            forName: .shakeDetected,
            object: nil,
            queue: .main
        ) { _ in
            if settings.debugMode || appState.showDebugMenu {
                withAnimation(.spring()) {
                    showDebugMenu.toggle()
                }
            }
        }
    }

    // MARK: - Universal Links
    private func setupUniversalLinks() {
        NotificationCenter.default.addObserver(
            forName: .universalLinkReceived,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                handleDeepLink(url)
            }
        }
    }
}

// MARK: - Route
enum Route: Hashable, Codable {
    case cardDetail(id: String)
    case transactionDetail(id: String)
    case budgetCategory(category: String)
    case pay
    case addCard
    case settingsDetail(section: SettingsSection)
    case debugConsole

    enum SettingsSection: String, Codable, Hashable {
        case general, security, notifications, privacy, about, advanced
    }
}

// MARK: - Placeholder Views
struct WalletView: View {
    var body: some View {
        VStack {
            Text("Wallet")
                .font(.largeTitle)
                .padding()
            Spacer()
        }
    }
}

struct TransactionsView: View {
    var body: some View {
        VStack {
            Text("Transactions")
                .font(.largeTitle)
                .padding()
            Spacer()
        }
    }
}

struct BudgetView: View {
    var body: some View {
        VStack {
            Text("Budget")
                .font(.largeTitle)
                .padding()
            Spacer()
        }
    }
}

struct CardDetailView: View {
    let cardID: String
    var body: some View {
        VStack {
            Text("Card: " + cardID)
                .font(.largeTitle)
            Spacer()
        }
        .navigationTitle("Card Details")
    }
}

struct TransactionDetailView: View {
    let transactionID: String
    var body: some View {
        VStack {
            Text("Transaction: " + transactionID)
                .font(.largeTitle)
            Spacer()
        }
        .navigationTitle("Transaction")
    }
}

struct BudgetCategoryView: View {
    let category: String
    var body: some View {
        VStack {
            Text("Category: " + category)
                .font(.largeTitle)
            Spacer()
        }
        .navigationTitle("Budget Category")
    }
}

struct PayView: View {
    var body: some View {
        VStack {
            Text("Pay")
                .font(.largeTitle)
            Spacer()
        }
        .navigationTitle("Quick Pay")
    }
}

struct AddCardView: View {
    var body: some View {
        VStack {
            Text("Add Card")
                .font(.largeTitle)
            Spacer()
        }
        .navigationTitle("Add Card")
    }
}

struct SettingsDetailView: View {
    let section: Route.SettingsSection
    var body: some View {
        VStack {
            Text(section.rawValue.capitalized)
                .font(.largeTitle)
            Spacer()
        }
        .navigationTitle(section.rawValue.capitalized)
    }
}

struct DebugConsoleView: View {
    var body: some View {
        VStack {
            Text("Debug Console")
                .font(.largeTitle)
            Spacer()
        }
        .navigationTitle("Debug")
    }
}

// MARK: - Shake Gesture Modifier
struct ShakeGestureViewModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .shakeDetected)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeGestureViewModifier(action: action))
    }
}

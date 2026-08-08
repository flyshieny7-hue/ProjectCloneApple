import SwiftUI
import Combine

// MARK: - URLSchemeHandler
/// Handles custom URL schemes and Universal Links
@MainActor
final class URLSchemeHandler: ObservableObject {

    // MARK: - Published Properties
    @Published var lastHandledURL: URL?
    @Published var lastHandledRoute: DeepLinkRoute?
    @Published var handlingError: URLError?
    @Published var isHandling: Bool = false

    // MARK: - Types
    enum DeepLinkRoute: Equatable {
        case pay(amount: Double?, recipient: String?)
        case cardDetail(id: String)
        case budget
        case budgetCategory(name: String)
        case transactionDetail(id: String)
        case settings(section: String?)
        case onboarding(step: Int?)
        case unknown

        var description: String {
            switch self {
            case .pay: return "Pay"
            case .cardDetail(let id): return "Card: " + id
            case .budget: return "Budget"
            case .budgetCategory(let name): return "Budget Category: " + name
            case .transactionDetail(let id): return "Transaction: " + id
            case .settings: return "Settings"
            case .onboarding: return "Onboarding"
            case .unknown: return "Unknown"
            }
        }
    }

    enum URLError: Error, Equatable {
        case invalidURL
        case unsupportedScheme
        case missingParameter(String)
        case invalidParameter(String, String)
        case routeNotFound
        case appNotReady

        var localizedDescription: String {
            switch self {
            case .invalidURL: return "Invalid URL format"
            case .unsupportedScheme: return "Unsupported URL scheme"
            case .missingParameter(let param): return "Missing required parameter: " + param
            case .invalidParameter(let param, let value): return "Invalid value for parameter: " + param
            case .routeNotFound: return "Route not found"
            case .appNotReady: return "App is not ready to handle this link"
            }
        }
    }

    // MARK: - Properties
    private var cancellables = Set<AnyCancellable>()
    private let urlHistoryKey = "url_handling_history"
    private let maxHistoryItems = 50

    // MARK: - URL Handling
    func handle(url: URL) {
        isHandling = true
        handlingError = nil

        print("[URLScheme] Handling URL: " + url.absoluteString)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            handlingError = .invalidURL
            isHandling = false
            return
        }

        let route: DeepLinkRoute

        switch url.scheme {
        case "wallet":
            route = parseWalletScheme(components: components)
        case "https":
            route = parseUniversalLink(components: components)
        default:
            handlingError = .unsupportedScheme
            isHandling = false
            return
        }

        lastHandledURL = url
        lastHandledRoute = route

        logURLHandling(url: url, route: route)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isHandling = false
        }
    }

    // MARK: - Wallet Scheme Parsing
    private func parseWalletScheme(components: URLComponents) -> DeepLinkRoute {
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = path.split(separator: "/").map(String.init)
        let queryItems = components.queryItems ?? []

        guard let action = segments.first else {
            return .unknown
        }

        switch action {
        case "pay":
            let amount = queryItems.first(where: { $0.name == "amount" })?.value.flatMap(Double.init)
            let recipient = queryItems.first(where: { $0.name == "to" })?.value
            return .pay(amount: amount, recipient: recipient)

        case "card":
            guard let cardID = segments.dropFirst().first else {
                return .unknown
            }
            return .cardDetail(id: cardID)

        case "budget":
            if let category = queryItems.first(where: { $0.name == "category" })?.value {
                return .budgetCategory(name: category)
            }
            return .budget

        case "transaction":
            guard let txID = segments.dropFirst().first else {
                return .unknown
            }
            return .transactionDetail(id: txID)

        case "settings":
            let section = queryItems.first(where: { $0.name == "section" })?.value
            return .settings(section: section)

        case "onboarding":
            let step = queryItems.first(where: { $0.name == "step" })?.value.flatMap(Int.init)
            return .onboarding(step: step)

        default:
            return .unknown
        }
    }

    // MARK: - Universal Link Parsing
    private func parseUniversalLink(components: URLComponents) -> DeepLinkRoute {
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = path.split(separator: "/").map(String.init)
        let queryItems = components.queryItems ?? []

        guard let host = components.host,
              host == "wallet.app" || host == "www.wallet.app" else {
            return .unknown
        }

        guard let action = segments.first else {
            return .unknown
        }

        switch action {
        case "pay":
            let amount = queryItems.first(where: { $0.name == "amount" })?.value.flatMap(Double.init)
            let recipient = queryItems.first(where: { $0.name == "to" })?.value
            return .pay(amount: amount, recipient: recipient)

        case "card":
            guard let cardID = segments.dropFirst().first else {
                return .unknown
            }
            return .cardDetail(id: cardID)

        case "budget":
            if let category = queryItems.first(where: { $0.name == "category" })?.value {
                return .budgetCategory(name: category)
            }
            return .budget

        case "transaction":
            guard let txID = segments.dropFirst().first else {
                return .unknown
            }
            return .transactionDetail(id: txID)

        default:
            return .unknown
        }
    }

    // MARK: - URL Generation
    func generateWalletURL(route: DeepLinkRoute) -> URL? {
        var components = URLComponents()
        components.scheme = "wallet"

        switch route {
        case .pay(let amount, let recipient):
            components.path = "/pay"
            var items: [URLQueryItem] = []
            if let amount = amount {
                items.append(URLQueryItem(name: "amount", value: String(amount)))
            }
            if let recipient = recipient {
                items.append(URLQueryItem(name: "to", value: recipient))
            }
            components.queryItems = items.isEmpty ? nil : items

        case .cardDetail(let id):
            components.path = "/card/" + id

        case .budget:
            components.path = "/budget"

        case .budgetCategory(let name):
            components.path = "/budget"
            components.queryItems = [URLQueryItem(name: "category", value: name)]

        case .transactionDetail(let id):
            components.path = "/transaction/" + id

        case .settings(let section):
            components.path = "/settings"
            if let section = section {
                components.queryItems = [URLQueryItem(name: "section", value: section)]
            }

        default:
            return nil
        }

        return components.url
    }

    func generateUniversalURL(route: DeepLinkRoute) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wallet.app"

        switch route {
        case .pay(let amount, let recipient):
            components.path = "/pay"
            var items: [URLQueryItem] = []
            if let amount = amount {
                items.append(URLQueryItem(name: "amount", value: String(amount)))
            }
            if let recipient = recipient {
                items.append(URLQueryItem(name: "to", value: recipient))
            }
            components.queryItems = items.isEmpty ? nil : items

        case .cardDetail(let id):
            components.path = "/card/" + id

        case .budget:
            components.path = "/budget"

        case .budgetCategory(let name):
            components.path = "/budget"
            components.queryItems = [URLQueryItem(name: "category", value: name)]

        case .transactionDetail(let id):
            components.path = "/transaction/" + id

        default:
            return nil
        }

        return components.url
    }

    // MARK: - History
    private func logURLHandling(url: URL, route: DeepLinkRoute) {
        let entry = URLHistoryEntry(
            url: url.absoluteString,
            route: route.description,
            timestamp: Date()
        )

        var history = getURLHistory()
        history.insert(entry, at: 0)
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }

        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: urlHistoryKey)
        }
    }

    func getURLHistory() -> [URLHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: urlHistoryKey),
              let history = try? JSONDecoder().decode([URLHistoryEntry].self, from: data) else {
            return []
        }
        return history
    }

    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: urlHistoryKey)
    }
}

// MARK: - Supporting Types
struct URLHistoryEntry: Codable {
    let url: String
    let route: String
    let timestamp: Date
}

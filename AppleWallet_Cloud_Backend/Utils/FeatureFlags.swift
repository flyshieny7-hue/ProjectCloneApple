import Foundation
import Combine
import CloudKit

/// Remote config manager для A/B тестирования и feature flags
/// iOS 26, использует CloudKit для remote config, local caching, gradual rollout
@MainActor
final class FeatureFlags: ObservableObject {

    // MARK: - Singleton
    static let shared = FeatureFlags()

    // MARK: - Published Properties
    @Published var flags: [String: FeatureFlag] = [:]
    @Published var experiments: [String: ABExperiment] = [:]
    @Published var isLoading: Bool = false
    @Published var lastUpdate: Date?
    @Published var configVersion: String = "1.0.0"

    // MARK: - Types
    struct FeatureFlag: Codable, Identifiable {
        let id: String
        let key: String
        let value: FlagValue
        let description: String
        let rolloutPercentage: Double
        let targetGroups: [TargetGroup]
        let minOSVersion: String?
        let expirationDate: Date?
        let isEnabled: Bool
        let metadata: [String: String]

        enum FlagValue: Codable {
            case bool(Bool)
            case string(String)
            case int(Int)
            case double(Double)
            case json(Data)

            enum CodingKeys: String, CodingKey {
                case type, value
            }

            enum ValueType: String, Codable {
                case bool, string, int, double, json
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .bool(let v):
                    try container.encode(ValueType.bool, forKey: .type)
                    try container.encode(v, forKey: .value)
                case .string(let v):
                    try container.encode(ValueType.string, forKey: .type)
                    try container.encode(v, forKey: .value)
                case .int(let v):
                    try container.encode(ValueType.int, forKey: .type)
                    try container.encode(v, forKey: .value)
                case .double(let v):
                    try container.encode(ValueType.double, forKey: .type)
                    try container.encode(v, forKey: .value)
                case .json(let v):
                    try container.encode(ValueType.json, forKey: .type)
                    try container.encode(v, forKey: .value)
                }
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(ValueType.self, forKey: .type)
                switch type {
                case .bool:
                    self = .bool(try container.decode(Bool.self, forKey: .value))
                case .string:
                    self = .string(try container.decode(String.self, forKey: .value))
                case .int:
                    self = .int(try container.decode(Int.self, forKey: .value))
                case .double:
                    self = .double(try container.decode(Double.self, forKey: .value))
                case .json:
                    self = .json(try container.decode(Data.self, forKey: .value))
                }
            }
        }

        enum TargetGroup: String, Codable {
            case all = "all"
            case beta = "beta"
            case premium = "premium"
            case newUsers = "new_users"
            case existingUsers = "existing_users"
            case specificRegion = "specific_region"
        }
    }

    struct ABExperiment: Codable, Identifiable {
        let id: String
        let name: String
        let description: String
        let variants: [Variant]
        let startDate: Date
        let endDate: Date?
        let targetAudience: FeatureFlag.TargetGroup
        let isActive: Bool
        let metrics: [String]

        struct Variant: Codable, Identifiable {
            let id: String
            let name: String
            let weight: Double
            let configOverrides: [String: FeatureFlag.FlagValue]
            let metrics: [String: Double]?
        }
    }

    enum FeatureFlagError: LocalizedError {
        case fetchFailed
        case invalidConfig
        case rolloutCalculationFailed
        case experimentNotFound
        case variantAssignmentFailed
        case configExpired
        case networkUnavailable

        var errorDescription: String? {
            switch self {
            case .fetchFailed: return "Failed to fetch feature flags"
            case .invalidConfig: return "Invalid feature flag configuration"
            case .rolloutCalculationFailed: return "Failed to calculate rollout"
            case .experimentNotFound: return "A/B experiment not found"
            case .variantAssignmentFailed: return "Failed to assign experiment variant"
            case .configExpired: return "Feature flag configuration has expired"
            case .networkUnavailable: return "Network unavailable for config fetch"
            }
        }
    }

    // MARK: - Constants
    private enum Constants {
        static let flagsRecordType = "FeatureFlags"
        static let experimentsRecordType = "ABExperiments"
        static let configCacheKey = "com.wallet.featureflags.cache"
        static let configVersionKey = "com.wallet.featureflags.version"
        static let userVariantKey = "com.wallet.featureflags.variants"
        static let fetchInterval: TimeInterval = 3600 // 1 hour
        static let maxCacheAge: TimeInterval = 86400 // 24 hours
        static let retryAttempts = 3
        static let retryBackoffBase: TimeInterval = 5.0
    }

    // MARK: - Properties
    private var cancellables = Set<AnyCancellable>()
    private let configQueue = DispatchQueue(label: "com.wallet.featureflags", qos: .utility)
    private var fetchTimer: Timer?
    private var userVariants: [String: String] = [:] // experimentID -> variantID

    // MARK: - Initialization
    private init() {
        loadCachedConfig()
        loadUserVariants()
        setupPeriodicFetch()
        observeNetworkChanges()
    }

    // MARK: - Fetch Configuration

    /// Загружает конфигурацию feature flags из CloudKit
    func fetchConfiguration() async throws {
        guard !isLoading else { return }
        isLoading = true

        defer { isLoading = false }

        do {
            // Пробуем загрузить из CloudKit
            try await fetchFromCloudKit()

            // Если не удалось, используем кэш
        } catch {
            AnalyticsCollector.shared.logError(error, context: "FeatureFlagsFetch")

            // Проверяем кэш
            if let cached = loadCachedConfig(), !isCacheExpired() {
                applyConfiguration(cached)
            } else {
                throw FeatureFlagError.fetchFailed
            }
        }
    }

    private func fetchFromCloudKit() async throws {
        // Fetch feature flags
        let flagsPredicate = NSPredicate(format: "isEnabled == YES")
        let flagsQuery = CKQuery(recordType: Constants.flagsRecordType, predicate: flagsPredicate)

        let (flagsResults, _) = try await CloudKitManager.shared.privateDatabase.records(
            matching: flagsQuery,
            resultsLimit: 100
        )

        var fetchedFlags: [String: FeatureFlag] = [:]
        for result in flagsResults {
            if case .success(let record) = result.1,
               let flag = FeatureFlag(from: record) {
                fetchedFlags[flag.key] = flag
            }
        }

        // Fetch A/B experiments
        let experimentsPredicate = NSPredicate(format: "isActive == YES")
        let experimentsQuery = CKQuery(recordType: Constants.experimentsRecordType, predicate: experimentsPredicate)

        let (experimentsResults, _) = try await CloudKitManager.shared.privateDatabase.records(
            matching: experimentsQuery,
            resultsLimit: 50
        )

        var fetchedExperiments: [String: ABExperiment] = [:]
        for result in experimentsResults {
            if case .success(let record) = result.1,
               let experiment = ABExperiment(from: record) {
                fetchedExperiments[experiment.id] = experiment
            }
        }

        // Применяем и кэшируем
        flags = fetchedFlags
        experiments = fetchedExperiments
        lastUpdate = Date()

        try cacheConfiguration()

        AnalyticsCollector.shared.logEvent("feature_flags_fetched", parameters: [
            "flags_count": fetchedFlags.count,
            "experiments_count": fetchedExperiments.count
        ])
    }

    // MARK: - Flag Evaluation

    /// Проверяет, включен ли feature flag
    func isEnabled(_ key: String) -> Bool {
        guard let flag = flags[key] else { return false }
        guard flag.isEnabled else { return false }
        guard !isExpired(flag) else { return false }
        guard isTargetGroupEligible(flag) else { return false }
        guard isOSVersionEligible(flag) else { return false }

        // Rollout percentage
        return isInRollout(flag)
    }

    /// Получает значение feature flag
    func value<T>(for key: String, defaultValue: T) -> T {
        guard let flag = flags[key],
              flag.isEnabled,
              isInRollout(flag) else {
            return defaultValue
        }

        switch flag.value {
        case .bool(let value) where T.self == Bool.self:
            return value as! T
        case .string(let value) where T.self == String.self:
            return value as! T
        case .int(let value) where T.self == Int.self:
            return value as! T
        case .double(let value) where T.self == Double.self:
            return value as! T
        default:
            return defaultValue
        }
    }

    /// Получает JSON конфигурацию
    func jsonConfig(for key: String) -> [String: Any]? {
        guard let flag = flags[key],
              case .json(let data) = flag.value else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - A/B Testing

    /// Получает вариант для пользователя в эксперименте
    func getVariant(for experimentId: String) -> ABExperiment.Variant? {
        guard let experiment = experiments[experimentId],
              experiment.isActive,
              Date() >= experiment.startDate else {
            return nil
        }

        if let endDate = experiment.endDate, Date() > endDate {
            return nil
        }

        // Проверяем target audience
        guard isTargetGroupEligible(experiment.targetAudience) else { return nil }

        // Если вариант уже назначен, возвращаем его
        if let assignedVariantId = userVariants[experimentId],
           let variant = experiment.variants.first(where: { $0.id == assignedVariantId }) {
            return variant
        }

        // Назначаем новый вариант
        let variant = assignVariant(for: experiment)
        if let variant = variant {
            userVariants[experimentId] = variant.id
            saveUserVariants()

            AnalyticsCollector.shared.logEvent("ab_variant_assigned", parameters: [
                "experiment": experimentId,
                "variant": variant.name
            ])
        }

        return variant
    }

    /// Проверяет, находится ли пользователь в контрольной группе
    func isControlGroup(for experimentId: String) -> Bool {
        guard let variant = getVariant(for: experimentId) else { return true }
        return variant.name.lowercased() == "control" || variant.name.lowercased() == "baseline"
    }

    /// Получает override конфигурации для варианта
    func variantConfig(for experimentId: String) -> [String: FeatureFlag.FlagValue] {
        return getVariant(for: experimentId)?.configOverrides ?? [:]
    }

    private func assignVariant(for experiment: ABExperiment) -> ABExperiment.Variant? {
        let totalWeight = experiment.variants.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        // Детерминированное назначение на основе user ID
        let userHash = abs(userIdentifier().hashValue)
        let randomValue = Double(userHash % 10000) / 100.0

        var cumulativeWeight = 0.0
        for variant in experiment.variants {
            cumulativeWeight += (variant.weight / totalWeight) * 100.0
            if randomValue <= cumulativeWeight {
                return variant
            }
        }

        return experiment.variants.last
    }

    // MARK: - Eligibility Checks

    private func isInRollout(_ flag: FeatureFlag) -> Bool {
        guard flag.rolloutPercentage < 100.0 else { return true }
        guard flag.rolloutPercentage > 0.0 else { return false }

        // Детерминированный rollout на основе user ID
        let userHash = abs(userIdentifier().hashValue)
        let userPercentage = Double(userHash % 10000) / 100.0

        return userPercentage <= flag.rolloutPercentage
    }

    private func isTargetGroupEligible(_ flag: FeatureFlag) -> Bool {
        return isTargetGroupEligible(flag.targetGroups)
    }

    private func isTargetGroupEligible(_ group: FeatureFlag.TargetGroup) -> Bool {
        return isTargetGroupEligible([group])
    }

    private func isTargetGroupEligible(_ groups: [FeatureFlag.TargetGroup]) -> Bool {
        guard !groups.contains(.all) else { return true }

        // Проверяем группы пользователя
        let isBeta = UserDefaults.standard.bool(forKey: "isBetaUser")
        let isPremium = UserDefaults.standard.bool(forKey: "isPremiumUser")
        let isNewUser = isNewUser()

        for group in groups {
            switch group {
            case .all:
                return true
            case .beta where isBeta:
                return true
            case .premium where isPremium:
                return true
            case .newUsers where isNewUser:
                return true
            case .existingUsers where !isNewUser:
                return true
            default:
                continue
            }
        }

        return false
    }

    private func isOSVersionEligible(_ flag: FeatureFlag) -> Bool {
        guard let minVersion = flag.minOSVersion else { return true }

        let currentVersion = UIDevice.current.systemVersion
        return currentVersion.compare(minVersion, options: .numeric) != .orderedAscending
    }

    private func isExpired(_ flag: FeatureFlag) -> Bool {
        guard let expiration = flag.expirationDate else { return false }
        return Date() > expiration
    }

    private func isNewUser() -> Bool {
        guard let firstLaunch = UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date else {
            return true
        }
        return Date().timeIntervalSince(firstLaunch) < 7 * 86400 // 7 days
    }

    private func userIdentifier() -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "anonymous"
    }

    // MARK: - Caching

    private func cacheConfiguration() throws {
        let config = FeatureFlagsConfig(
            flags: flags,
            experiments: experiments,
            version: configVersion,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: Constants.configCacheKey)
        UserDefaults.standard.set(configVersion, forKey: Constants.configVersionKey)
    }

    private func loadCachedConfig() -> FeatureFlagsConfig? {
        guard let data = UserDefaults.standard.data(forKey: Constants.configCacheKey) else { return nil }
        return try? JSONDecoder().decode(FeatureFlagsConfig.self, from: data)
    }

    private func applyConfiguration(_ config: FeatureFlagsConfig) {
        flags = config.flags
        experiments = config.experiments
        configVersion = config.version
        lastUpdate = config.timestamp
    }

    private func isCacheExpired() -> Bool {
        guard let timestamp = lastUpdate else { return true }
        return Date().timeIntervalSince(timestamp) > Constants.maxCacheAge
    }

    // MARK: - User Variants Persistence

    private func saveUserVariants() {
        if let data = try? JSONEncoder().encode(userVariants) {
            UserDefaults.standard.set(data, forKey: Constants.userVariantKey)
        }
    }

    private func loadUserVariants() {
        guard let data = UserDefaults.standard.data(forKey: Constants.userVariantKey) else { return }
        userVariants = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    // MARK: - Periodic Fetch

    private func setupPeriodicFetch() {
        fetchTimer = Timer.scheduledTimer(withTimeInterval: Constants.fetchInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                try? await self?.fetchConfiguration()
            }
        }
    }

    private func observeNetworkChanges() {
        NotificationCenter.default.publisher(for: .NWPathUpdate)
            .sink { [weak self] notification in
                guard let path = notification.object as? NWPath else { return }
                if path.status == .satisfied && (self?.isCacheExpired() ?? true) {
                    Task { @MainActor in
                        try? await self?.fetchConfiguration()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Debug

    #if DEBUG
    func overrideFlag(_ key: String, value: FeatureFlag.FlagValue) {
        var flag = flags[key] ?? FeatureFlag(
            id: UUID().uuidString,
            key: key,
            value: value,
            description: "Debug override",
            rolloutPercentage: 100.0,
            targetGroups: [.all],
            minOSVersion: nil,
            expirationDate: nil,
            isEnabled: true,
            metadata: [:]
        )
        flags[key] = flag
    }

    func resetOverrides() {
        if let cached = loadCachedConfig() {
            applyConfiguration(cached)
        }
    }

    func allFlags() -> [String: FeatureFlag] {
        return flags
    }

    func allExperiments() -> [String: ABExperiment] {
        return experiments
    }
    #endif
}

// MARK: - Configuration Model
struct FeatureFlagsConfig: Codable {
    let flags: [String: FeatureFlags.FeatureFlag]
    let experiments: [String: FeatureFlags.ABExperiment]
    let version: String
    let timestamp: Date
}

// MARK: - CKRecord Extensions
extension FeatureFlags.FeatureFlag {
    init?(from record: CKRecord) {
        guard let key = record["key"] as? String,
              let description = record["description"] as? String else {
            return nil
        }

        self.id = record.recordID.recordName
        self.key = key
        self.description = description
        self.isEnabled = record["isEnabled"] as? Bool ?? false
        self.rolloutPercentage = record["rolloutPercentage"] as? Double ?? 0.0
        self.targetGroups = (record["targetGroups"] as? [String])?.compactMap {
            FeatureFlags.FeatureFlag.TargetGroup(rawValue: $0)
        } ?? [.all]
        self.minOSVersion = record["minOSVersion"] as? String
        self.expirationDate = record["expirationDate"] as? Date
        self.metadata = record["metadata"] as? [String: String] ?? [:]

        // Parse value
        if let boolValue = record["boolValue"] as? Bool {
            self.value = .bool(boolValue)
        } else if let stringValue = record["stringValue"] as? String {
            self.value = .string(stringValue)
        } else if let intValue = record["intValue"] as? Int {
            self.value = .int(intValue)
        } else if let doubleValue = record["doubleValue"] as? Double {
            self.value = .double(doubleValue)
        } else if let jsonData = record["jsonValue"] as? Data {
            self.value = .json(jsonData)
        } else {
            self.value = .bool(false)
        }
    }
}

extension FeatureFlags.ABExperiment {
    init?(from record: CKRecord) {
        guard let name = record["name"] as? String,
              let description = record["description"] as? String,
              let startDate = record["startDate"] as? Date else {
            return nil
        }

        self.id = record.recordID.recordName
        self.name = name
        self.description = description
        self.startDate = startDate
        self.endDate = record["endDate"] as? Date
        self.isActive = record["isActive"] as? Bool ?? false
        self.targetAudience = FeatureFlags.FeatureFlag.TargetGroup(rawValue: record["targetAudience"] as? String ?? "all") ?? .all
        self.metrics = record["metrics"] as? [String] ?? []

        // Parse variants from JSON
        if let variantsData = record["variants"] as? Data,
           let variants = try? JSONDecoder().decode([Variant].self, from: variantsData) {
            self.variants = variants
        } else {
            self.variants = []
        }
    }
}

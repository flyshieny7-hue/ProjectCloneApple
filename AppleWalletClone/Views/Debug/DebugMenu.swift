import SwiftUI

// MARK: - DebugMenu
/// Hidden developer menu (shake to open)
struct DebugMenu: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var performanceMonitor: PerformanceMonitor
    @EnvironmentObject var urlHandler: URLSchemeHandler
    @State private var selectedTab: DebugTab = .general

    enum DebugTab: String, CaseIterable {
        case general = "General"
        case network = "Network"
        case logs = "Logs"
        case state = "State"
        case tools = "Tools"

        var icon: String {
            switch self {
            case .general: return "gearshape.2"
            case .network: return "network"
            case .logs: return "doc.text"
            case .state: return "memorychip"
            case .tools: return "wrench"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Tab", selection: $selectedTab) {
                    ForEach(DebugTab.allCases, id: \.self) { tab in
                        Image(systemName: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                ScrollView {
                    switch selectedTab {
                    case .general:
                        GeneralDebugView()
                    case .network:
                        NetworkDebugView()
                    case .logs:
                        LogsDebugView()
                    case .state:
                        StateDebugView()
                    case .tools:
                        ToolsDebugView()
                    }
                }
            }
            .navigationTitle("Debug Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        withAnimation {
                            isPresented = false
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - General Debug View
struct GeneralDebugView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DebugSection(title: "App Info") {
                DebugInfoRow(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "N/A")
                DebugInfoRow(label: "Version", value: "1.0.0")
                DebugInfoRow(label: "Build", value: "100")
                DebugInfoRow(label: "iOS Version", value: UIDevice.current.systemVersion)
                DebugInfoRow(label: "Device", value: UIDevice.current.model)
            }

            DebugSection(title: "Feature Flags") {
                Toggle("Onboarding Complete", isOn: .constant(appState.isOnboardingComplete))
                Toggle("Authenticated", isOn: $appState.isAuthenticated)
                Toggle("Performance Overlay", isOn: $appState.showPerformanceOverlay)
            }

            DebugSection(title: "Actions") {
                DebugButton(title: "Reset Onboarding", color: .orange) {
                    UserDefaults.standard.set(false, forKey: "onboardingCompleted")
                }
                DebugButton(title: "Clear UserDefaults", color: .red) {
                    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
                }
                DebugButton(title: "Trigger Crash", color: .red) {
                    fatalError("Debug crash triggered")
                }
            }
        }
        .padding()
    }
}

// MARK: - Network Debug View
struct NetworkDebugView: View {
    @State private var requests: [DebugNetworkRequest] = []
    @State private var isRecording: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("Record Requests", isOn: $isRecording)
                Spacer()
                Button("Clear") {
                    requests.removeAll()
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)

            ForEach(requests) { request in
                NetworkRequestRow(request: request)
            }

            if requests.isEmpty {
                Text("No network requests recorded")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding(.vertical)
    }
}

struct DebugNetworkRequest: Identifiable {
    let id = UUID()
    let url: String
    let method: String
    let statusCode: Int
    let duration: TimeInterval
    let timestamp: Date
}

struct NetworkRequestRow: View {
    let request: DebugNetworkRequest

    var statusColor: Color {
        switch request.statusCode {
        case 200...299: return .green
        case 400...499: return .orange
        case 500...599: return .red
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(request.method)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)

                Text(String(request.statusCode))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(statusColor)

                Spacer()

                Text(String(format: "%.0fms", request.duration * 1000))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Text(request.url)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Logs Debug View
struct LogsDebugView: View {
    @State private var logs: [DebugLogEntry] = []
    @State private var filter: String = ""

    var filteredLogs: [DebugLogEntry] {
        if filter.isEmpty { return logs }
        return logs.filter { $0.message.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter logs...", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredLogs) { log in
                        LogEntryRow(entry: log)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let level: LogLevel
    let message: String
    let timestamp: Date
    let file: String
    let line: Int

    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var color: Color {
            switch self {
            case .debug: return .gray
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: DebugLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(entry.level.color)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(size: 12))

                Text(entry.file + ":" + String(entry.line))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - State Debug View
struct StateDebugView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DebugSection(title: "App State") {
                DebugInfoRow(label: "Selected Tab", value: appState.selectedTab.rawValue)
                DebugInfoRow(label: "Onboarding", value: appState.isOnboardingComplete ? "Complete" : "Incomplete")
                DebugInfoRow(label: "Authenticated", value: appState.isAuthenticated ? "Yes" : "No")
            }

            DebugSection(title: "Settings") {
                DebugInfoRow(label: "Currency", value: settings.currencyCode)
                DebugInfoRow(label: "Language", value: settings.language)
                DebugInfoRow(label: "Auto-Lock", value: String(settings.autoLockTimeout))
                DebugInfoRow(label: "Dark Mode", value: settings.darkMode ? "On" : "Off")
                DebugInfoRow(label: "Biometric", value: settings.biometricAuth ? "On" : "Off")
            }

            DebugSection(title: "UserDefaults") {
                let allKeys = UserDefaults.standard.dictionaryRepresentation().keys.sorted()
                ForEach(allKeys.prefix(20), id: \.self) { key in
                    if let value = UserDefaults.standard.object(forKey: key) {
                        DebugInfoRow(label: key, value: String(describing: value))
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Tools Debug View
struct ToolsDebugView: View {
    @EnvironmentObject var performanceMonitor: PerformanceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DebugSection(title: "Performance") {
                DebugInfoRow(label: "FPS", value: String(format: "%.1f", performanceMonitor.currentFPS))
                DebugInfoRow(label: "Memory", value: performanceMonitor.formattedMemoryUsage)
                DebugInfoRow(label: "CPU", value: String(format: "%.1f%%", performanceMonitor.cpuUsage))
            }

            DebugSection(title: "Testing") {
                DebugButton(title: "Simulate Low Memory", color: .orange) {
                    // Simulate memory pressure
                }
                DebugButton(title: "Simulate Slow Network", color: .orange) {
                    // Enable network throttling
                }
                DebugButton(title: "Generate Test Data", color: .blue) {
                    // Generate mock data
                }
                DebugButton(title: "Run UI Tests", color: .green) {
                    // Trigger UI test suite
                }
            }

            DebugSection(title: "Diagnostics") {
                DebugButton(title: "Export Logs", color: .blue) {
                    // Export logs to file
                }
                DebugButton(title: "Share Diagnostics", color: .blue) {
                    // Share diagnostic data
                }
            }
        }
        .padding()
    }
}

// MARK: - Debug UI Components
struct DebugSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct DebugInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}

struct DebugButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
            .foregroundColor(color)
            .padding(.vertical, 8)
        }
    }
}

import SwiftUI

// MARK: - SettingsMasterView
/// Unified settings with ALL options
struct SettingsMasterView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @State private var navigationPath = NavigationPath()
    @State private var showResetConfirmation: Bool = false
    @State private var showLogoutConfirmation: Bool = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                // Profile Section
                profileSection

                // General Section
                generalSection

                // Security Section
                securitySection

                // Notifications Section
                notificationsSection

                // Privacy Section
                privacySection

                // Appearance Section
                appearanceSection

                // Advanced Section
                advancedSection

                // About Section
                aboutSection

                // Danger Zone
                dangerZoneSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDetail(for: route)
            }
            .alert("Reset All Data?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetAllData()
                }
            } message: {
                Text("This will erase all your cards, transactions, and settings. This action cannot be undone.")
            }
            .alert("Log Out?", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Log Out", role: .destructive) {
                    logout()
                }
            } message: {
                Text("You will need to sign in again to access your wallet.")
            }
        }
    }

    // MARK: - Profile Section
    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)

                    Text("JD")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("John Doe")
                        .font(.system(size: 18, weight: .semibold))
                    Text("john.doe@email.com")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - General Section
    private var generalSection: some View {
        Section("General") {
            NavigationLink(value: SettingsRoute.currency) {
                SettingsRow(
                    icon: "dollarsign.circle.fill",
                    iconColor: .green,
                    title: "Currency",
                    subtitle: settings.currencyCode
                )
            }

            NavigationLink(value: SettingsRoute.language) {
                SettingsRow(
                    icon: "globe",
                    iconColor: .blue,
                    title: "Language",
                    subtitle: languageName(for: settings.language)
                )
            }

            Toggle(isOn: $settings.hapticEnabled) {
                SettingsRow(
                    icon: "hand.tap.fill",
                    iconColor: .orange,
                    title: "Haptic Feedback",
                    subtitle: nil
                )
            }
        }
    }

    // MARK: - Security Section
    private var securitySection: some View {
        Section("Security") {
            Toggle(isOn: $settings.biometricAuth) {
                SettingsRow(
                    icon: "faceid",
                    iconColor: .blue,
                    title: "Face ID / Touch ID",
                    subtitle: nil
                )
            }

            NavigationLink(value: SettingsRoute.passcode) {
                SettingsRow(
                    icon: "lock.fill",
                    iconColor: .red,
                    title: "Passcode",
                    subtitle: "Change"
                )
            }

            NavigationLink(value: SettingsRoute.autoLock) {
                SettingsRow(
                    icon: "timer",
                    iconColor: .purple,
                    title: "Auto-Lock",
                    subtitle: String(Int(settings.autoLockTimeout)) + "s"
                )
            }
        }
    }

    // MARK: - Notifications Section
    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle(isOn: $settings.notificationsEnabled) {
                SettingsRow(
                    icon: "bell.badge.fill",
                    iconColor: .red,
                    title: "Enable Notifications",
                    subtitle: nil
                )
            }

            NavigationLink(value: SettingsRoute.notificationSettings) {
                SettingsRow(
                    icon: "bell.and.waves.left.and.right.fill",
                    iconColor: .orange,
                    title: "Notification Preferences",
                    subtitle: nil
                )
            }
        }
    }

    // MARK: - Privacy Section
    private var privacySection: some View {
        Section("Privacy") {
            Toggle(isOn: $settings.analyticsEnabled) {
                SettingsRow(
                    icon: "chart.bar.fill",
                    iconColor: .blue,
                    title: "Analytics",
                    subtitle: "Help improve the app"
                )
            }

            Toggle(isOn: $settings.crashReporting) {
                SettingsRow(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange,
                    title: "Crash Reporting",
                    subtitle: "Send anonymous crash logs"
                )
            }

            NavigationLink(value: SettingsRoute.privacyPolicy) {
                SettingsRow(
                    icon: "doc.text.fill",
                    iconColor: .gray,
                    title: "Privacy Policy",
                    subtitle: nil
                )
            }

            NavigationLink(value: SettingsRoute.dataExport) {
                SettingsRow(
                    icon: "square.and.arrow.up.fill",
                    iconColor: .green,
                    title: "Export Data",
                    subtitle: nil
                )
            }
        }
    }

    // MARK: - Appearance Section
    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle(isOn: $settings.darkMode) {
                SettingsRow(
                    icon: "moon.fill",
                    iconColor: .indigo,
                    title: "Dark Mode",
                    subtitle: nil
                )
            }

            NavigationLink(value: SettingsRoute.appIcon) {
                SettingsRow(
                    icon: "app.fill",
                    iconColor: .pink,
                    title: "App Icon",
                    subtitle: nil
                )
            }
        }
    }

    // MARK: - Advanced Section
    private var advancedSection: some View {
        Section("Advanced") {
            Toggle(isOn: $settings.debugMode) {
                SettingsRow(
                    icon: "ladybug.fill",
                    iconColor: .red,
                    title: "Debug Mode",
                    subtitle: "Shake to open debug menu"
                )
            }

            NavigationLink(value: SettingsRoute.debugConsole) {
                SettingsRow(
                    icon: "terminal.fill",
                    iconColor: .green,
                    title: "Debug Console",
                    subtitle: nil
                )
            }

            NavigationLink(value: SettingsRoute.networkSettings) {
                SettingsRow(
                    icon: "network",
                    iconColor: .blue,
                    title: "Network",
                    subtitle: nil
                )
            }

            NavigationLink(value: SettingsRoute.cache) {
                SettingsRow(
                    icon: "externaldrive.fill",
                    iconColor: .gray,
                    title: "Cache & Storage",
                    subtitle: nil
                )
            }
        }
    }

    // MARK: - About Section
    private var aboutSection: some View {
        Section("About") {
            SettingsRow(
                icon: "info.circle.fill",
                iconColor: .blue,
                title: "Version",
                subtitle: "1.0.0 (Build 100)"
            )

            NavigationLink(value: SettingsRoute.termsOfService) {
                SettingsRow(
                    icon: "doc.text.fill",
                    iconColor: .gray,
                    title: "Terms of Service",
                    subtitle: nil
                )
            }

            NavigationLink(value: SettingsRoute.acknowledgments) {
                SettingsRow(
                    icon: "hands.sparkles.fill",
                    iconColor: .yellow,
                    title: "Acknowledgments",
                    subtitle: nil
                )
            }

            Button {
                // Rate app
            } label: {
                SettingsRow(
                    icon: "star.fill",
                    iconColor: .yellow,
                    title: "Rate App",
                    subtitle: nil
                )
            }

            Button {
                // Share app
            } label: {
                SettingsRow(
                    icon: "square.and.arrow.up",
                    iconColor: .blue,
                    title: "Share App",
                    subtitle: nil
                )
            }
        }
    }

    // MARK: - Danger Zone
    private var dangerZoneSection: some View {
        Section {
            Button {
                showLogoutConfirmation = true
            } label: {
                HStack {
                    Text("Log Out")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.red)
                    Spacer()
                }
            }

            Button {
                showResetConfirmation = true
            } label: {
                HStack {
                    Text("Reset All Data")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Settings Detail Views
    @ViewBuilder
    private func settingsDetail(for route: SettingsRoute) -> some View {
        switch route {
        case .currency:
            CurrencySettingsView()
        case .language:
            LanguageSettingsView()
        case .passcode:
            PasscodeSettingsView()
        case .autoLock:
            AutoLockSettingsView()
        case .notificationSettings:
            NotificationSettingsView()
        case .privacyPolicy:
            PrivacyPolicyView()
        case .dataExport:
            DataExportView()
        case .appIcon:
            AppIconSettingsView()
        case .debugConsole:
            DebugConsoleView()
        case .networkSettings:
            NetworkSettingsView()
        case .cache:
            CacheSettingsView()
        case .termsOfService:
            TermsOfServiceView()
        case .acknowledgments:
            AcknowledgmentsView()
        }
    }

    // MARK: - Helpers
    private func languageName(for code: String) -> String {
        let languages = [
            "en": "English",
            "ru": "Russian",
            "es": "Spanish",
            "de": "German",
            "fr": "French",
            "ja": "Japanese",
            "zh": "Chinese"
        ]
        return languages[code] ?? code.uppercased()
    }

    private func resetAllData() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        UserDefaults.standard.synchronize()
    }

    private func logout() {
        appState.isAuthenticated = false
    }
}

// MARK: - SettingsRoute
enum SettingsRoute: Hashable {
    case currency
    case language
    case passcode
    case autoLock
    case notificationSettings
    case privacyPolicy
    case dataExport
    case appIcon
    case debugConsole
    case networkSettings
    case cache
    case termsOfService
    case acknowledgments
}

// MARK: - SettingsRow
struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(iconColor)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .regular))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Settings Detail Views (Placeholders)
struct CurrencySettingsView: View {
    var body: some View {
        List {
            ForEach(["USD", "EUR", "GBP", "JPY", "RUB", "CNY"], id: \.self) { currency in
                HStack {
                    Text(currency)
                    Spacer()
                    if currency == "USD" {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .navigationTitle("Currency")
    }
}

struct LanguageSettingsView: View {
    var body: some View {
        List {
            ForEach(["en", "ru", "es", "de", "fr", "ja", "zh"], id: \.self) { code in
                HStack {
                    Text(code.uppercased())
                    Spacer()
                    if code == "en" {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .navigationTitle("Language")
    }
}

struct PasscodeSettingsView: View {
    var body: some View {
        Text("Passcode Settings")
            .navigationTitle("Passcode")
    }
}

struct AutoLockSettingsView: View {
    var body: some View {
        List {
            ForEach([30, 60, 120, 300, 600], id: \.self) { seconds in
                HStack {
                    Text(String(seconds) + " seconds")
                    Spacer()
                    if seconds == 60 {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .navigationTitle("Auto-Lock")
    }
}

struct NotificationSettingsView: View {
    var body: some View {
        Text("Notification Preferences")
            .navigationTitle("Notifications")
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text("Privacy Policy content...")
                .padding()
        }
        .navigationTitle("Privacy Policy")
    }
}

struct DataExportView: View {
    var body: some View {
        VStack {
            Text("Export your data")
            Button("Export to JSON") {}
            Button("Export to CSV") {}
        }
        .navigationTitle("Export Data")
    }
}

struct AppIconSettingsView: View {
    var body: some View {
        Text("App Icon Settings")
            .navigationTitle("App Icon")
    }
}

struct NetworkSettingsView: View {
    var body: some View {
        Text("Network Settings")
            .navigationTitle("Network")
    }
}

struct CacheSettingsView: View {
    var body: some View {
        List {
            HStack {
                Text("Cache Size")
                Spacer()
                Text("24.5 MB")
                    .foregroundColor(.secondary)
            }
            Button("Clear Cache") {}
        }
        .navigationTitle("Cache & Storage")
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            Text("Terms of Service content...")
                .padding()
        }
        .navigationTitle("Terms of Service")
    }
}

struct AcknowledgmentsView: View {
    var body: some View {
        List {
            Text("SwiftUI")
            Text("Combine")
            Text("CoreNFC")
        }
        .navigationTitle("Acknowledgments")
    }
}

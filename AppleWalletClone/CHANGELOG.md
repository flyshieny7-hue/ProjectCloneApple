# Changelog

All notable changes to the Apple Wallet Clone project.

## [1.0.0] - 2026-08-08

### Added
- **MasterContentView**: Unified app router with NavigationStack + NavigationPath
- **StateRestorationManager**: Full state restoration after app kill/background
  - Automatic save on background/terminate
  - Age validation (1 hour max)
  - Manual checkpoint support
  - Onboarding completion check
- **URLSchemeHandler**: Complete deep link and universal link system
  - Custom scheme: `wallet://`
  - Universal links: `https://wallet.app/`
  - 7 route types with query parameters
  - URL generation helpers
  - Handling history with 50-item limit
- **OnboardingFlow**: 5-step animated onboarding
  - Gradient backgrounds with glow effects
  - Spring physics animations
  - Progress bar with page indicators
  - Skip and completion tracking
- **TutorialOverlay**: Contextual CoachMarks system
  - 5 position options (top/bottom/center/left/right)
  - Highlight cutout with pulse animation
  - Persistent completion tracking
  - CoachMark view modifier
- **SettingsMasterView**: Comprehensive settings interface
  - 9 sections with 25+ options
  - Profile, General, Security, Notifications
  - Privacy, Appearance, Advanced, About
  - Danger Zone with confirmation dialogs
- **DebugMenu**: Shake-to-open developer menu
  - 5 tabs: General, Network, Logs, State, Tools
  - Feature flag toggles
  - Network request recording
  - Filterable log viewer
  - Live state inspection
  - Performance diagnostics
  - Test data generation
- **PerformanceMonitor**: Real-time performance tracking
  - FPS monitoring via CADisplayLink
  - Memory usage (resident size)
  - CPU usage (thread times)
  - Battery level and low power mode
  - Thermal state monitoring
  - Expandable overlay HUD
- **AppStoreAssets**: Complete App Store metadata
  - Screenshot specs for all device sizes
  - 30-second preview video script
  - Keywords and promotional text
  - In-app purchase definitions

### Technical
- SwiftUI NavigationStack with typed destinations
- EnvironmentObject pattern for global state
- Combine framework for reactive programming
- UserDefaults with Codable persistence
- NotificationCenter for cross-module communication
- @MainActor for thread safety
- Custom PreferenceKey for layout measurements

## [0.9.0] - 2026-07-15

### Added
- Initial project structure
- Basic tab navigation
- Card wallet view placeholder
- Transaction list placeholder
- Budget view placeholder

## [0.8.0] - 2026-06-20

### Added
- Project initialization
- SwiftUI app lifecycle setup
- Basic theming and appearance configuration

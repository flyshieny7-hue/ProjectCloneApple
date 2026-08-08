# Apple Wallet Clone

A full-featured Apple Wallet clone built with SwiftUI for iOS 26. This project demonstrates modern iOS development patterns including NavigationStack routing, deep linking, state restoration, contextual tutorials, and comprehensive settings management.

## Architecture Overview

```
AppleWalletClone/
├── AppleWalletCloneApp.swift      # App entry point with all environment objects
├── ContentView.swift              # MasterContentView - unified router
├── Managers/
│   ├── StateRestorationManager.swift   # State persistence after kill
│   └── URLSchemeHandler.swift          # Deep links & universal links
├── Views/
│   ├── Onboarding/
│   │   ├── OnboardingFlow.swift        # 5-step animated onboarding
│   │   └── TutorialOverlay.swift       # Contextual hints (CoachMarks)
│   ├── Settings/
│   │   └── SettingsMasterView.swift    # All settings in one place
│   └── Debug/
│       └── DebugMenu.swift             # Shake-to-open dev menu
├── Utils/
│   └── PerformanceMonitor.swift        # FPS, memory, battery overlay
└── Resources/
    └── AppStoreAssets/                 # Screenshots, metadata, preview script
```

## Features

### MasterContentView
- **NavigationStack** with typed `NavigationPath`
- **Deep Link Routing**: `wallet://pay`, `wallet://card/{id}`, `wallet://budget`
- **Universal Links**: `https://wallet.app/pay`
- **State Restoration**: Automatic recovery after app kill
- **Shake Detection**: Opens debug menu when enabled
- **Tab-based navigation** with 4 tabs: Wallet, Activity, Budget, Settings

### StateRestorationManager
- Saves navigation path and selected tab on background/terminate
- Validates restoration age (max 1 hour)
- Supports manual checkpoints
- Checks onboarding completion before restoring

### URLSchemeHandler
- Custom URL scheme: `wallet://`
- Universal Links: `https://wallet.app/`
- Routes: pay, card detail, budget, transactions, settings, onboarding
- URL generation helpers
- Full handling history with logging

### OnboardingFlow
- 5 animated steps with spring physics
- Gradient backgrounds and glowing icons
- Progress indicator with animated bar
- Skip and Next/Get Started buttons
- Stores completion state in UserDefaults

### TutorialOverlay
- Contextual CoachMarks system
- Dimmed background with highlight cutouts
- Position-aware hint placement (top/bottom/center/left/right)
- Pulse animation on target elements
- Skip and "Got it" actions
- Persistent completion tracking

### SettingsMasterView
- **Profile**: User avatar and info
- **General**: Currency, Language, Haptic Feedback
- **Security**: Face ID, Passcode, Auto-Lock
- **Notifications**: Enable/Disable, Preferences
- **Privacy**: Analytics, Crash Reporting, Privacy Policy, Data Export
- **Appearance**: Dark Mode, App Icon
- **Advanced**: Debug Mode, Debug Console, Network, Cache
- **About**: Version, Terms, Acknowledgments, Rate, Share
- **Danger Zone**: Log Out, Reset All Data

### DebugMenu
- **General**: App info, feature flags, actions (reset, clear, crash)
- **Network**: Request recording and inspection
- **Logs**: Filterable log viewer with levels
- **State**: Live app state and UserDefaults inspection
- **Tools**: Performance metrics, testing utilities, diagnostics export

### PerformanceMonitor
- **FPS**: Real-time frame rate with 60-sample averaging
- **Memory**: Resident size tracking in MB
- **CPU**: Thread time-based usage percentage
- **Battery**: Level and low power mode detection
- **Thermal**: State monitoring
- **Overlay**: Compact HUD with expandable details
- Color-coded indicators (green/orange/red)

### AppStoreAssets
- Screenshot metadata for all iPhone sizes (6.7, 6.5, 5.5)
- iPad Pro 12.9 metadata
- 30-second app preview script with 5 scenes
- Keywords list
- Promotional text
- In-app purchase definitions

## Deep Link Examples

```
wallet://pay
wallet://pay?amount=50.00&to=John+Doe
wallet://card/card-123
wallet://budget
wallet://budget?category=food
wallet://settings?section=security

https://wallet.app/pay
https://wallet.app/card/card-123
https://wallet.app/budget
```

## Requirements

- iOS 26.0+
- Xcode 26.0+
- Swift 6.0+

## Installation

1. Clone the repository
2. Open `AppleWalletClone.xcodeproj` in Xcode 26
3. Build and run on iOS 26 simulator or device

## Info.plist Configuration

Add to your `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.example.walletclone</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>wallet</string>
        </array>
    </dict>
</array>

<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:wallet.app</string>
</array>
```

## License

MIT License - see LICENSE file for details.

## Changelog

See CHANGELOG.md for version history.

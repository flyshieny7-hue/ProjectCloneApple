# Apple Wallet Spatial — iOS 26 + visionOS 2

## Spatial UI Layer для Apple Wallet Clone

### Структура проекта

```
AppleWalletSpatial/
├── Views/
│   └── Spatial/
│       ├── SpatialCardView.swift      # 3D карта с depth, glass material, volumetric glow
│       ├── SpatialWalletSpace.swift   # Immersive space для Vision Pro
│       └── SpatialTransactionFlow.swift # 3D анимация перевода денег
├── Managers/
│   ├── HandGestureManager.swift       # Жесты pinch-to-pay, grab-to-move-card
│   ├── EyeTrackingManager.swift       # Фокусировка взглядом на карте
│   └── SpatialAudioManager.swift      # 3D звуки при взаимодействии
├── Resources/
│   └── SpatialAudio/
│       ├── tap.wav                    # Звук тапа
│       ├── swipe.wav                  # Звук свайпа
│       ├── success.wav                # Звук успеха
│       ├── error.wav                  # Звук ошибки
│       ├── focus.wav                  # Звук фокуса
│       ├── flip.wav                   # Звук переворота карты
│       ├── pay.wav                    # Звук оплаты
│       ├── card_slide.wav             # Звук скольжения карты
│       ├── notification.wav           # Звук уведомления
│       └── ambient.wav                # Фоновый звук
└── Models/
    └── (RealityKit card models)
```

### Особенности

#### SpatialCardView
- **3D карта** с физически корректными материалами (PBR)
- **Glass material** с преломлением и отражением
- **Volumetric glow** — свечение вокруг карты
- **Depth layers** — слои для чипа и текста
- **4 типа карт**: Titanium Elite, Platinum, Gold, Standard
- **Металлические текстуры** для elite карт

#### SpatialWalletSpace
- **Immersive space** для Vision Pro
- **Парящие карты** с физикой и анимацией
- **Ambient particles** — плавающие частицы света
- **Spatial lighting** — направленный и точечный свет
- **Ornament controls** — панель управления

#### SpatialTransactionFlow
- **3D анимация** перевода денег между картами
- **Money orb** — светящаяся сфера с траекторией
- **Transaction beam** — луч соединения карт
- **Progress ring** — индикатор прогресса

#### HandGestureManager
- **Pinch-to-pay** — щипок для подтверждения оплаты
- **Grab-to-move** — захват для перемещения карты
- **Tap-to-select** — тап для выбора
- **Rotate-to-flip** — вращение для переворота
- **Haptic feedback** — тактильная обратная связь

#### EyeTrackingManager
- **Gaze focus** — фокусировка взглядом
- **Dwell select** — выбор задержкой взгляда
- **Progressive scale** — плавное увеличение
- **Focus ring indicator** — визуальный индикатор

#### SpatialAudioManager
- **3D spatial audio** для Vision Pro
- **10 типов звуков** для разных действий
- **Reverb и occlusion** — реверберация и окклюзия
- **Ambient sound** — фоновое звучание
- **Haptic-audio sync** — синхронизация с тактильной обратной связью

### Поддержка платформ

| Функция | iPhone (2D fallback) | Vision Pro (Full spatial) |
|---------|---------------------|---------------------------|
| 3D карты | ✅ (UIKit + SwiftUI) | ✅ (RealityKit) |
| Glass material | ✅ (VisualEffectView) | ✅ (Shader Graph) |
| Volumetric glow | ✅ (Shadow + blur) | ✅ (Emissive + bloom) |
| Парящие карты | ❌ | ✅ |
| Hand gestures | ❌ | ✅ |
| Eye tracking | ❌ | ✅ |
| Spatial audio | ❌ (Stereo) | ✅ (3D) |
| Immersive space | ❌ | ✅ |

### Установка

1. Добавьте файлы в проект Xcode
2. Добавьте аудио файлы в `Resources/SpatialAudio/`
3. Настройте `Info.plist` для Vision Pro:
   ```xml
   <key>UIApplicationSceneManifest</key>
   <dict>
       <key>UIApplicationPreferredDefaultSceneSessionRole</key>
       <string>UIWindowSceneSessionRoleImmersiveSpaceApplication</string>
   </dict>
   ```

### Требования

- iOS 26.0+
- visionOS 2.0+
- Xcode 16.0+
- Swift 6.0+
- RealityKit
- ARKit (для hand tracking и eye tracking)

### Лицензия

MIT License

//
//  SpatialAudioManager.swift
//  AppleWalletSpatial
//
//  SpatialAudio — 3D звуки при тапе, swipe, success
//  Supports Vision Pro spatial audio and iOS fallback
//

import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation

// MARK: - Sound Types
enum SpatialSound: String, CaseIterable {
    case tap = "tap"
    case swipe = "swipe"
    case success = "success"
    case error = "error"
    case focus = "focus"
    case flip = "flip"
    case pay = "pay"
    case cardSlide = "card_slide"
    case notification = "notification"
    case ambient = "ambient"

    var fileName: String {
        return rawValue
    }

    var spatialProfile: SpatialAudioProfile {
        switch self {
        case .tap:
            return SpatialAudioProfile(
                reverbSend: 0.1,
                directivity: .omni,
                referenceDistance: 0.5,
                maxDistance: 2.0
            )
        case .swipe:
            return SpatialAudioProfile(
                reverbSend: 0.2,
                directivity: .omni,
                referenceDistance: 0.3,
                maxDistance: 1.5
            )
        case .success:
            return SpatialAudioProfile(
                reverbSend: 0.3,
                directivity: .omni,
                referenceDistance: 0.5,
                maxDistance: 3.0
            )
        case .error:
            return SpatialAudioProfile(
                reverbSend: 0.15,
                directivity: .omni,
                referenceDistance: 0.5,
                maxDistance: 2.0
            )
        case .focus:
            return SpatialAudioProfile(
                reverbSend: 0.05,
                directivity: .omni,
                referenceDistance: 0.2,
                maxDistance: 1.0
            )
        case .flip:
            return SpatialAudioProfile(
                reverbSend: 0.2,
                directivity: .omni,
                referenceDistance: 0.4,
                maxDistance: 1.5
            )
        case .pay:
            return SpatialAudioProfile(
                reverbSend: 0.4,
                directivity: .omni,
                referenceDistance: 0.5,
                maxDistance: 3.0
            )
        case .cardSlide:
            return SpatialAudioProfile(
                reverbSend: 0.15,
                directivity: .omni,
                referenceDistance: 0.3,
                maxDistance: 1.5
            )
        case .notification:
            return SpatialAudioProfile(
                reverbSend: 0.1,
                directivity: .omni,
                referenceDistance: 0.5,
                maxDistance: 2.0
            )
        case .ambient:
            return SpatialAudioProfile(
                reverbSend: 0.8,
                directivity: .omni,
                referenceDistance: 1.0,
                maxDistance: 5.0
            )
        }
    }
}

// MARK: - Spatial Audio Profile
struct SpatialAudioProfile {
    let reverbSend: Float
    let directivity: AudioResource.Directivity
    let referenceDistance: Float
    let maxDistance: Float
}

// MARK: - Spatial Audio Manager
@available(iOS 26.0, visionOS 2.0, *)
@MainActor
class SpatialAudioManager: ObservableObject {

    // MARK: - Properties
    @Published var isPlaying: Bool = false
    @Published var currentSound: SpatialSound?

    private var audioPlayers: [SpatialSound: AVAudioPlayer] = [:]
    private var spatialAudioSources: [Entity: AudioPlaybackController] = [:]
    private var ambientPlayer: AVAudioPlayer?

    // Audio engine for spatial processing
    private var audioEngine: AVAudioEngine?
    private var environmentNode: AVAudioEnvironmentNode?

    // MARK: - Initialization
    init() {
        setupAudioSession()
        setupSpatialAudio()
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .allowBluetooth]
            )
            try session.setActive(true)
        } catch {
            print("Audio session setup error: \(error)")
        }
    }

    private func setupSpatialAudio() {
        #if os(visionOS)
        // Setup spatial audio engine for Vision Pro
        audioEngine = AVAudioEngine()
        environmentNode = AVAudioEnvironmentNode()

        guard let engine = audioEngine, let environment = environmentNode else { return }

        // Configure 3D audio environment
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: 0,
            pitch: 0,
            roll: 0
        )

        // Set reverb parameters
        environment.reverbParameters.enable()
        environment.reverbParameters.level = 0.3

        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
        } catch {
            print("Audio engine start error: \(error)")
        }
        #endif
    }

    // MARK: - Sound Preloading
    func preloadSounds() {
        for sound in SpatialSound.allCases {
            loadSound(sound)
        }
    }

    private func loadSound(_ sound: SpatialSound) {
        guard let url = Bundle.main.url(
            forResource: sound.fileName,
            withExtension: "wav",
            subdirectory: "SpatialAudio"
        ) else {
            // Try mp3 fallback
            guard let mp3Url = Bundle.main.url(
                forResource: sound.fileName,
                withExtension: "mp3",
                subdirectory: "SpatialAudio"
            ) else {
                print("Sound file not found: \(sound.fileName)")
                return
            }

            do {
                let player = try AVAudioPlayer(contentsOf: mp3Url)
                player.prepareToPlay()
                audioPlayers[sound] = player
            } catch {
                print("Failed to load sound \(sound.fileName): \(error)")
            }
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayers[sound] = player
        } catch {
            print("Failed to load sound \(sound.fileName): \(error)")
        }
    }

    // MARK: - Play Sound
    func playSound(_ sound: SpatialSound, at position: SIMD3<Float>? = nil) {
        currentSound = sound

        #if os(visionOS)
        if let position = position {
            playSpatialSound(sound, at: position)
        } else {
            playStandardSound(sound)
        }
        #else
        playStandardSound(sound)
        #endif
    }

    // MARK: - Standard Sound Playback (iOS / Non-spatial)
    private func playStandardSound(_ sound: SpatialSound) {
        guard let player = audioPlayers[sound] else {
            // Try to load on demand
            loadSound(sound)
            audioPlayers[sound]?.play()
            return
        }

        player.currentTime = 0
        player.play()

        isPlaying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + player.duration) {
            self.isPlaying = false
        }
    }

    // MARK: - Spatial Sound Playback (Vision Pro)
    #if os(visionOS)
    private func playSpatialSound(_ sound: SpatialSound, at position: SIMD3<Float>) {
        guard let url = Bundle.main.url(
            forResource: sound.fileName,
            withExtension: "wav",
            subdirectory: "SpatialAudio"
        ) else {
            playStandardSound(sound)
            return
        }

        // Create temporary entity for spatial audio
        let audioEntity = Entity()
        audioEntity.position = position

        do {
            let audioResource = try AudioFileResource.load(
                contentsOf: url,
                withName: sound.fileName,
                inputMode: .spatial,
                loadingStrategy: .preload,
                shouldLoop: false
            )

            // Configure spatial audio properties
            var configuration = AudioPlaybackController.Configuration()
            configuration.reverbSend = sound.spatialProfile.reverbSend

            let controller = audioEntity.prepareAudio(audioResource)
            controller.configuration = configuration

            spatialAudioSources[audioEntity] = controller
            controller.play()

            // Cleanup after playback
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                controller.stop()
                self.spatialAudioSources.removeValue(forKey: audioEntity)
            }

        } catch {
            print("Spatial audio playback error: \(error)")
            playStandardSound(sound)
        }
    }
    #endif

    // MARK: - Play Sound with Entity Attachment
    func playSound(_ sound: SpatialSound, attachedTo entity: Entity) {
        #if os(visionOS)
        guard let url = Bundle.main.url(
            forResource: sound.fileName,
            withExtension: "wav",
            subdirectory: "SpatialAudio"
        ) else {
            playStandardSound(sound)
            return
        }

        do {
            let audioResource = try AudioFileResource.load(
                contentsOf: url,
                withName: sound.fileName,
                inputMode: .spatial,
                loadingStrategy: .preload,
                shouldLoop: false
            )

            let controller = entity.prepareAudio(audioResource)
            spatialAudioSources[entity] = controller
            controller.play()

        } catch {
            print("Entity audio playback error: \(error)")
            playStandardSound(sound)
        }
        #else
        playStandardSound(sound)
        #endif
    }

    // MARK: - Ambient Sound
    func startAmbientSound() {
        guard ambientPlayer == nil else { return }

        guard let url = Bundle.main.url(
            forResource: SpatialSound.ambient.fileName,
            withExtension: "wav",
            subdirectory: "SpatialAudio"
        ) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1 // Loop indefinitely
            player.volume = 0.15
            player.prepareToPlay()
            player.play()
            ambientPlayer = player
        } catch {
            print("Ambient sound error: \(error)")
        }
    }

    func stopAmbientSound() {
        ambientPlayer?.stop()
        ambientPlayer = nil
    }

    // MARK: - Transaction Sound Sequence
    func playTransactionSounds() {
        let sequence: [SpatialSound] = [.cardSlide, .swipe, .pay, .success]
        var delay: TimeInterval = 0

        for sound in sequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.playSound(sound)
            }
            delay += 0.5
        }
    }

    // MARK: - Haptic-Audio Sync
    func playSoundWithHaptic(_ sound: SpatialSound, hapticIntensity: Float = 0.5) {
        playSound(sound)

        // Trigger haptic feedback
        #if os(visionOS)
        // Vision Pro haptic via wrist or spatial audio
        #else
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: CGFloat(hapticIntensity))
        #endif
    }

    // MARK: - Volume Control
    func setVolume(_ volume: Float, for sound: SpatialSound? = nil) {
        if let sound = sound {
            audioPlayers[sound]?.volume = volume
        } else {
            audioPlayers.values.forEach { $0.volume = volume }
        }
    }

    // MARK: - Cleanup
    func stopAllSounds() {
        audioPlayers.values.forEach { $0.stop() }
        spatialAudioSources.values.forEach { $0.stop() }
        stopAmbientSound()
        isPlaying = false
    }

    deinit {
        stopAllSounds()
        audioEngine?.stop()
    }
}

// MARK: - Sound Event Protocol
protocol SoundEvent {
    var sound: SpatialSound { get }
    var position: SIMD3<Float>? { get }
}

// MARK: - View Extension for Sound
@available(iOS 26.0, visionOS 2.0, *)
extension View {
    func spatialSound(
        _ sound: SpatialSound,
        trigger: Binding<Bool>,
        position: SIMD3<Float>? = nil
    ) -> some View {
        self.onChange(of: trigger.wrappedValue) { _, isTriggered in
            if isTriggered {
                SpatialAudioManager().playSound(sound, at: position)
                trigger.wrappedValue = false
            }
        }
    }
}

// MARK: - Preview
@available(iOS 26.0, visionOS 2.0, *)
#Preview {
    SpatialAudioDebugView()
}

struct SpatialAudioDebugView: View {
    @StateObject private var audioManager = SpatialAudioManager()

    var body: some View {
        VStack(spacing: 16) {
            Text("Spatial Audio Debug")
                .font(.title)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                ForEach(SpatialSound.allCases, id: \.self) { sound in
                    Button(sound.rawValue) {
                        audioManager.playSound(sound)
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Button("Ambient: \(audioManager.ambientPlayer != nil ? "On" : "Off")") {
                    if audioManager.ambientPlayer != nil {
                        audioManager.stopAmbientSound()
                    } else {
                        audioManager.startAmbientSound()
                    }
                }

                Button("Transaction") {
                    audioManager.playTransactionSounds()
                }

                Button("Stop All") {
                    audioManager.stopAllSounds()
                }
            }

            Text("Current: \(audioManager.currentSound?.rawValue ?? "None")")
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            audioManager.preloadSounds()
        }
    }
}

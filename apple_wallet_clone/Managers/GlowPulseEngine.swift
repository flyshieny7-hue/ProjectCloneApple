import SwiftUI
import AVFoundation
import Combine
import UIKit

class GlowPulseEngine: ObservableObject {
    @Published var glowIntensity: CGFloat = 0.5
    @Published var isMusicPlaying: Bool = false

    private var audioSession: AVAudioSession?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isReducedMotion: Bool = false
    private var isLowPower: Bool = false

    init() {
        checkAccessibility()
        setupAudioMonitoring()
        startPulseAnimation()
    }

    private func checkAccessibility() {
        isReducedMotion = UIAccessibility.isReduceMotionEnabled
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.isReducedMotion = UIAccessibility.isReduceMotionEnabled
            }
            .store(in: &cancellables)
    }

    private func setupAudioMonitoring() {
        audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession?.setCategory(.ambient, mode: .default)
            try audioSession?.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkMusicPlayback()
        }
    }

    private func checkMusicPlayback() {
        let isPlaying = AVAudioSession.sharedInstance().isOtherAudioPlaying
        if isPlaying != isMusicPlaying {
            isMusicPlaying = isPlaying
        }
    }

    private func startPulseAnimation() {
        guard !isReducedMotion && !isLowPower else {
            glowIntensity = 0.3
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let baseIntensity: CGFloat = 0.3
            let pulseRange: CGFloat = 0.4
            let frequency: Double = self.isMusicPlaying ? 8.0 : 2.0

            let time = Date().timeIntervalSince1970
            let newIntensity = baseIntensity + pulseRange * CGFloat(sin(time * frequency))

            DispatchQueue.main.async {
                self.glowIntensity = newIntensity
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}

struct GlowPulseModifier: ViewModifier {
    @StateObject private var engine = GlowPulseEngine()
    let color: Color

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(engine.glowIntensity), radius: 20, x: 0, y: 0)
            .shadow(color: color.opacity(engine.glowIntensity * 0.5), radius: 40, x: 0, y: 0)
    }
}

extension View {
    func glowPulse(color: Color = .cyan) -> some View {
        modifier(GlowPulseModifier(color: color))
    }
}

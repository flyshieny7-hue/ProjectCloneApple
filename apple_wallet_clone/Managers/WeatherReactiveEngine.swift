import SwiftUI
import CoreLocation
import UIKit

class WeatherReactiveEngine: ObservableObject {
    @Published var currentWeather: WeatherType = .clear
    @Published var rainIntensity: CGFloat = 0
    @Published var isReducedMotion: Bool = false
    @Published var isLowPower: Bool = false

    private var locationManager: CLLocationManager?
    private var timer: Timer?

    enum WeatherType {
        case clear, rain, snow, fog, storm
    }

    init() {
        checkAccessibility()
        setupLocation()
        startWeatherSimulation()
    }

    private func checkAccessibility() {
        isReducedMotion = UIAccessibility.isReduceMotionEnabled
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func setupLocation() {
        locationManager = CLLocationManager()
        locationManager?.requestWhenInUseAuthorization()
    }

    private func startWeatherSimulation() {
        // In production, this would fetch real weather data
        // For demo, we cycle through weather types
        let weatherTypes: [WeatherType] = [.clear, .rain, .snow, .fog, .storm]
        var index = 0

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            index = (index + 1) % weatherTypes.count
            self.currentWeather = weatherTypes[index]

            withAnimation(.easeInOut(duration: 2)) {
                self.rainIntensity = self.currentWeather == .rain ? 1.0 : 0.0
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}

struct WeatherReactiveLayer: View {
    @StateObject private var engine = WeatherReactiveEngine()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch engine.currentWeather {
                case .rain:
                    RainEffect(intensity: engine.rainIntensity, size: geo.size)
                case .snow:
                    SnowEffect(size: geo.size)
                case .fog:
                    FogEffect(size: geo.size)
                case .storm:
                    StormEffect(size: geo.size)
                case .clear:
                    EmptyView()
                }
            }
        }
    }
}

struct RainEffect: View {
    let intensity: CGFloat
    let size: CGSize
    @State private var drops: [RainDrop] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016, paused: false)) { _ in
            Canvas { context, _ in
                for drop in drops {
                    var path = Path()
                    path.move(to: drop.start)
                    path.addLine(to: drop.end)
                    context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 1)
                }
            }
        }
        .onAppear {
            generateDrops()
        }
    }

    private func generateDrops() {
        let dropCount = Int(100 * intensity)
        drops = (0..<dropCount).map { _ in
            RainDrop(
                start: CGPoint(x: CGFloat.random(in: 0...size.width), y: -10),
                end: CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 10),
                speed: CGFloat.random(in: 5...15)
            )
        }
    }
}

struct RainDrop {
    var start: CGPoint
    var end: CGPoint
    var speed: CGFloat
}

struct SnowEffect: View {
    let size: CGSize
    @State private var flakes: [SnowFlake] = []

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, _ in
                for flake in flakes {
                    context.fill(
                        Path(ellipseIn: CGRect(x: flake.position.x, y: flake.position.y, width: flake.size, height: flake.size)),
                        with: .color(.white.opacity(0.8))
                    )
                }
            }
        }
        .onAppear {
            flakes = (0..<50).map { _ in
                SnowFlake(
                    position: CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height)),
                    size: CGFloat.random(in: 3...8),
                    speed: CGFloat.random(in: 0.5...2)
                )
            }
        }
    }
}

struct SnowFlake {
    var position: CGPoint
    var size: CGFloat
    var speed: CGFloat
}

struct FogEffect: View {
    let size: CGSize

    var body: some View {
        LinearGradient(
            colors: [.white.opacity(0.1), .white.opacity(0.3), .white.opacity(0.1)],
            startPoint: .top,
            endPoint: .bottom
        )
        .blur(radius: 50)
    }
}

struct StormEffect: View {
    let size: CGSize
    @State private var flashOpacity: Double = 0

    var body: some View {
        ZStack {
            RainEffect(intensity: 1.5, size: size)
            Color.white.opacity(flashOpacity)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: Double.random(in: 3...8), repeats: true) { _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    flashOpacity = 0.8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        flashOpacity = 0
                    }
                }
            }
        }
    }
}

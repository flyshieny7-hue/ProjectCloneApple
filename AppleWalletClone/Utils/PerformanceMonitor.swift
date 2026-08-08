import SwiftUI
import Combine
import Foundation

// MARK: - PerformanceMonitor
/// Monitors FPS, memory, battery usage
@MainActor
final class PerformanceMonitor: ObservableObject {

    // MARK: - Published Properties
    @Published var currentFPS: Double = 60.0
    @Published var averageFPS: Double = 60.0
    @Published var memoryUsage: UInt64 = 0
    @Published var cpuUsage: Double = 0.0
    @Published var batteryLevel: Float = 1.0
    @Published var isLowPowerMode: Bool = false
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var isMonitoring: Bool = false

    // MARK: - Computed Properties
    var formattedMemoryUsage: String {
        let mb = Double(memoryUsage) / 1024 / 1024
        return String(format: "%.1f MB", mb)
    }

    var formattedBatteryLevel: String {
        return String(format: "%.0f%%", batteryLevel * 100)
    }

    // MARK: - Private Properties
    private var displayLink: CADisplayLink?
    private var timer: Timer?
    private var fpsSamples: [Double] = []
    private let maxSamples = 60
    private var lastTimestamp: CFTimeInterval = 0
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle
    deinit {
        stopMonitoring()
    }

    // MARK: - Control
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        setupDisplayLink()
        setupTimer()
        setupBatteryMonitoring()
        setupThermalMonitoring()

        print("[PerformanceMonitor] Started monitoring")
    }

    func stopMonitoring() {
        isMonitoring = false
        displayLink?.invalidate()
        displayLink = nil
        timer?.invalidate()
        timer = nil

        print("[PerformanceMonitor] Stopped monitoring")
    }

    // MARK: - Display Link (FPS)
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func displayLinkTick() {
        guard let displayLink = displayLink else { return }

        let timestamp = displayLink.timestamp

        if lastTimestamp > 0 {
            let delta = timestamp - lastTimestamp
            let fps = 1.0 / delta

            fpsSamples.append(fps)
            if fpsSamples.count > maxSamples {
                fpsSamples.removeFirst()
            }

            currentFPS = fps
            averageFPS = fpsSamples.reduce(0, +) / Double(fpsSamples.count)
        }

        lastTimestamp = timestamp
    }

    // MARK: - Timer (Memory & CPU)
    private func setupTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }

    private func updateMetrics() {
        memoryUsage = getMemoryUsage()
        cpuUsage = getCPUUsage()
    }

    // MARK: - Battery Monitoring
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.batteryLevel = UIDevice.current.batteryLevel
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name.NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .store(in: &cancellables)
    }

    // MARK: - Thermal Monitoring
    private func setupThermalMonitoring() {
        thermalState = ProcessInfo.processInfo.thermalState

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.thermalState = ProcessInfo.processInfo.thermalState
            }
            .store(in: &cancellables)
    }

    // MARK: - Memory Usage
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }

    // MARK: - CPU Usage
    private func getCPUUsage() -> Double {
        var info = task_thread_times_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return 0.0 }

        let totalTime = Double(info.user_time.seconds) + Double(info.system_time.seconds)
        return min(totalTime * 100, 100.0)
    }

    // MARK: - Snapshot
    func takeSnapshot() -> PerformanceSnapshot {
        return PerformanceSnapshot(
            timestamp: Date(),
            fps: currentFPS,
            averageFPS: averageFPS,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            batteryLevel: batteryLevel,
            isLowPowerMode: isLowPowerMode,
            thermalState: thermalState
        )
    }
}

// MARK: - PerformanceSnapshot
struct PerformanceSnapshot: Codable {
    let timestamp: Date
    let fps: Double
    let averageFPS: Double
    let memoryUsage: UInt64
    let cpuUsage: Double
    let batteryLevel: Float
    let isLowPowerMode: Bool
    let thermalState: ProcessInfo.ThermalState

    var description: String {
        return """
        [Performance] FPS: \(String(format: "%.1f", fps)) |         Avg: \(String(format: "%.1f", averageFPS)) |         Memory: \(Double(memoryUsage) / 1024 / 1024) MB |         CPU: \(String(format: "%.1f", cpuUsage))% |         Battery: \(String(format: "%.0f", batteryLevel * 100))%
        """
    }
}

// MARK: - PerformanceOverlay
struct PerformanceOverlay: View {
    @EnvironmentObject var monitor: PerformanceMonitor
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 12) {
                // FPS indicator
                MetricBadge(
                    value: String(format: "%.0f", monitor.currentFPS),
                    unit: "FPS",
                    color: fpsColor
                )

                // Memory indicator
                MetricBadge(
                    value: monitor.formattedMemoryUsage,
                    unit: "",
                    color: .blue
                )

                // Battery indicator
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon)
                        .foregroundColor(batteryColor)
                    Text(monitor.formattedBatteryLevel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7))
                .cornerRadius(6)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg FPS: " + String(format: "%.1f", monitor.averageFPS))
                    Text("CPU: " + String(format: "%.1f%%", monitor.cpuUsage))
                    Text("Thermal: " + String(describing: monitor.thermalState))
                    if monitor.isLowPowerMode {
                        Text("Low Power Mode")
                            .foregroundColor(.yellow)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
                .padding(8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 8)
        .padding(.trailing, 8)
        .allowsHitTesting(true)
    }

    private var fpsColor: Color {
        if monitor.currentFPS >= 55 { return .green }
        if monitor.currentFPS >= 30 { return .orange }
        return .red
    }

    private var batteryIcon: String {
        let level = monitor.batteryLevel
        if level <= 0.1 { return "battery.0" }
        if level <= 0.25 { return "battery.25" }
        if level <= 0.5 { return "battery.50" }
        if level <= 0.75 { return "battery.75" }
        return "battery.100"
    }

    private var batteryColor: Color {
        if monitor.batteryLevel <= 0.2 { return .red }
        if monitor.isLowPowerMode { return .yellow }
        return .green
    }
}

struct MetricBadge: View {
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold))
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 9))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.8))
        .cornerRadius(6)
    }
}

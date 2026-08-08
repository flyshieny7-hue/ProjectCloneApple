import SwiftUI
import MetalKit

struct LiquidCardView: View {
    let card: WalletCard
    @State private var distortion: Float = 0.0
    @State private var time: Float = 0.0
    @State private var isReducedMotion: Bool = false
    @State private var isLowPower: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base card
                RoundedRectangle(cornerRadius: 20)
                    .fill(card.color)
                    .overlay(
                        LiquidGlassLayer(
                            size: geo.size,
                            distortion: isReducedMotion || isLowPower ? 0 : distortion,
                            time: time
                        )
                    )

                // Card content
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: card.icon)
                            .font(.title)
                            .foregroundColor(.white)
                        Spacer()
                        Text(card.type.uppercased())
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    Text(card.number)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.white)
                    Text(card.holder)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding()
            }
        }
        .onAppear {
            isReducedMotion = reduceMotion
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            if !isReducedMotion && !isLowPower {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    distortion = 0.15
                }
                Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
                    time += 0.016
                }
            }
        }
        .onChange(of: reduceMotion) { newValue in
            isReducedMotion = newValue
        }
    }
}

struct LiquidGlassLayer: UIViewRepresentable {
    let size: CGSize
    let distortion: Float
    let time: Float

    func makeUIView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()!
        let mtkView = MTKView(frame: CGRect(origin: .zero, size: size), device: device)
        mtkView.delegate = context.coordinator
        mtkView.backgroundColor = .clear
        mtkView.isOpaque = false
        mtkView.enableSetNeedsDisplay = true
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.distortion = distortion
        context.coordinator.time = time
        uiView.setNeedsDisplay()
    }

    func makeCoordinator() -> LiquidGlassCoordinator {
        LiquidGlassCoordinator()
    }
}

class LiquidGlassCoordinator: NSObject, MTKViewDelegate {
    var distortion: Float = 0.0
    var time: Float = 0.0
    private var pipelineState: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?

    override init() {
        super.init()
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        commandQueue = device.makeCommandQueue()

        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "liquidVertex")
        let fragmentFunction = library?.makeFunction(name: "liquidFragment")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let commandQueue = commandQueue else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentBytes(&distortion, length: MemoryLayout<Float>.size, index: 0)
        renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 1)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct WalletCard: Identifiable {
    let id = UUID()
    let color: Color
    let icon: String
    let type: String
    let number: String
    let holder: String
    let isElite: Bool
}

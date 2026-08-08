import SwiftUI
import MetalKit

struct HologramEffect: View {
    let isActive: Bool
    @State private var time: Float = 0
    @State private var isReducedMotion: Bool = false
    @State private var isLowPower: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isActive && !isReducedMotion && !isLowPower {
                    HologramMetalLayer(size: geo.size, time: time)
                        .blendMode(.screen)
                        .opacity(0.7)
                }
            }
        }
        .onAppear {
            isReducedMotion = reduceMotion
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            if !isReducedMotion && !isLowPower {
                Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
                    time += 0.016
                }
            }
        }
    }
}

struct HologramMetalLayer: UIViewRepresentable {
    let size: CGSize
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
        context.coordinator.time = time
        uiView.setNeedsDisplay()
    }

    func makeCoordinator() -> HologramCoordinator {
        HologramCoordinator()
    }
}

class HologramCoordinator: NSObject, MTKViewDelegate {
    var time: Float = 0
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
        let vertexFunction = library?.makeFunction(name: "hologramVertex")
        let fragmentFunction = library?.makeFunction(name: "hologramFragment")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create hologram pipeline: \(error)")
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
        renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

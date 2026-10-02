#if os(iOS) && canImport(WebRTC) && !SWIFT_PACKAGE
import SwiftUI
import MetalKit
import CoreImage
import simd
@preconcurrency import WebRTC

struct SpatialMetalView: UIViewRepresentable {
    @ObservedObject var session: SpatialSession
    func makeCoordinator() -> Renderer { Renderer(session: session) }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColorMake(0.01, 0.01, 0.025, 1)
        view.framebufferOnly = true
        context.coordinator.configure(view)
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {}
    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true; view.delegate = nil; coordinator.detach()
    }

    @MainActor
    final class Renderer: NSObject, @preconcurrency MTKViewDelegate {
        struct Uniforms {
            var eyeToWorld: simd_float4x4
            var inverseProjection: simd_float4x4
            var reticle: SIMD4<Float>
            var state: SIMD4<Float>
        }
        struct SurfaceGPU {
            var center: SIMD4<Float>
            var size: SIMD4<Float>
            var atlas: SIMD4<Float>
        }
        let session: SpatialSession
        private let mailbox = SpatialVideoMailbox()
        private var track: RTCVideoTrack?
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var context: CIContext?
        private var video: MTLTexture?
        private var atlas: MTLTexture?
        private var stereo: MTLTexture?
        private var previousSurfaces: [SpatialSurface] = []
        private var lastFrameTimestamp: Int64 = -1
        private var calibrated = false
        private var lastProfileState = false
        private var lastVideoAt = 0.0
        private let inFlight = DispatchSemaphore(value: 2)
        

        init(session: SpatialSession) { self.session = session }
        func configure(_ view: MTKView) {
            guard let device = view.device else { session.reportRenderError("Metal is unavailable."); return }
            do {
                guard let library = device.makeDefaultLibrary(),
                      let vertex = library.makeFunction(name: "spatialVertex"),
                      let fragment = library.makeFunction(name: "spatialFragment") else {
                    session.reportRenderError("Spatial shaders are missing from the app build."); return
                }
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertex; descriptor.fragmentFunction = fragment
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                queue = device.makeCommandQueue()
                context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
                video = texture(device, width: 1, height: 1, usage: [.shaderRead, .shaderWrite])
            } catch { session.reportRenderError(error.localizedDescription) }
        }
        func detach() { track?.remove(mailbox); track = nil; mailbox.clear(); session.stop() }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            stereo = nil; session.recenter(); session.pause()
        }
        func draw(in view: MTKView) {
            guard let device = view.device, let queue, let pipeline,
                  view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }
            guard inFlight.wait(timeout: .now()) == .success else { return }
            var submitted = false
            defer { if !submitted { inFlight.signal() } }
            let newTrack = session.workspace.mediaState.webRTCClient.remoteVideoTrack
            if track !== newTrack {
                track?.remove(mailbox); mailbox.clear(); track = newTrack; track?.add(mailbox)
                lastFrameTimestamp = -1; lastVideoAt = 0; session.pause()
            }
            guard let command = queue.makeCommandBuffer(), let drawable = view.currentDrawable,
                  let output = view.currentRenderPassDescriptor else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let (frame, received) = mailbox.latest()
            if let frame, frame.timeStampNs != lastFrameTimestamp,
               let pixel = SpatialVideoMailbox.pixelBuffer(frame), let context {
                var image = CIImage(cvPixelBuffer: pixel)
                let exif: Int32 = switch frame.rotation.rawValue {
                case 90: 6
                case 180: 3
                case 270: 8
                default: 1
                }
                image = image.oriented(forExifOrientation: exif)
                image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                let width = Int(image.extent.width), height = Int(image.extent.height)
                if video?.width != width || video?.height != height {
                    video = texture(device, width: width, height: height, usage: [.shaderRead, .shaderWrite, .renderTarget])
                }
                if let video {
                    let destination = CIRenderDestination(mtlTexture: video, commandBuffer: command)
                    destination.isFlipped = true
                    destination.colorSpace = CGColorSpaceCreateDeviceRGB()
                    do {
                        _ = try context.startTask(toRender: image, to: destination)
                        lastFrameTimestamp = frame.timeStampNs; lastVideoAt = received
                    } catch { session.reportRenderError("Video conversion failed: " + error.localizedDescription) }
                }
            }
            let orientation = view.window?.windowScene?.interfaceOrientation ?? .landscapeLeft
            // A static desktop may legitimately stop producing changed frames.
            // ICE/media health, not frame age alone, determines input availability.
            let videoFresh = lastVideoAt > 0 && session.workspace.mediaState.webRTCClient.connectionState == .connected
            session.update(time: now, orientation: orientation, videoFresh: videoFresh)
            let width = Int(view.drawableSize.width), height = Int(view.drawableSize.height)
            let profile = stereo == nil ? session.optics.hasProfile : lastProfileState
            if stereo == nil || stereo?.width != width || stereo?.height != height || profile != lastProfileState {
                stereo = texture(device, width: width, height: height, usage: [.renderTarget, .shaderRead])
                calibrated = session.optics.configure(with: device, width: Int32(width), height: Int32(height))
                lastProfileState = profile
            }
            if previousSurfaces != session.surfaces || atlas == nil {
                atlas = makeAtlas(device: device, surfaces: session.surfaces)
                previousSurfaces = session.surfaces
            }
            guard let video, let atlas else { return }
            let pass: MTLRenderPassDescriptor
            if calibrated, let stereo {
                pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = stereo
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = view.clearColor
            } else { pass = output }
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(video, index: 0)
            encoder.setFragmentTexture(atlas, index: 1)
            let count = session.surfaces.count
            let gpu = session.surfaces.enumerated().map { index, surface in
                SurfaceGPU(center: SIMD4(surface.center, 0), size: SIMD4(surface.size.x, surface.size.y, surface.isDisplay ? 1 : 0, surface.curvatureRadius),
                           atlas: SIMD4(0, Float(index) / Float(count), 1, 1 / Float(count)))
            }
            gpu.withUnsafeBufferPointer { buffer in
                if let address = buffer.baseAddress {
                    encoder.setFragmentBytes(address, length: MemoryLayout<SurfaceGPU>.stride * count, index: 1)
                }
            }
            for eye in 0..<2 {
                var eyeFromHead = matrix_identity_float4x4
                let projection: simd_float4x4
                if calibrated {
                    eyeFromHead = session.optics.eyeFromHead(Int32(eye))
                    projection = session.optics.projection(eye: Int32(eye))
                } else {
                    eyeFromHead.columns.3.x = eye == 0 ? 0.032 : -0.032
                    projection = Self.projection(aspect: Float(width) / 2 / Float(height))
                }
                var uniforms = Uniforms(eyeToWorld: session.head * eyeFromHead.inverse,
                    inverseProjection: projection.inverse,
                    reticle: SIMD4(session.reticle, session.progress),
                    state: SIMD4(Float(count), Float(session.surfaces.firstIndex { $0.id == session.activeID } ?? -1),
                                 videoFresh ? 1 : 0, session.armed ? 1 : 0))
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.setViewport(MTLViewport(originX: Double(eye * width) / 2, originY: 0,
                                               width: Double(width)/2, height: Double(height), znear: 0, zfar: 1))
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            encoder.endEncoding()
            if calibrated, let stereo, let distortion = command.makeRenderCommandEncoder(descriptor: output) {
                session.optics.distort(with: distortion, texture: stereo, width: Int32(width), height: Int32(height))
                distortion.endEncoding()
            }
            let semaphore = inFlight
            command.addCompletedHandler { buffer in
                semaphore.signal()
                // No main-actor work or new frame queue is created here.
            }
            command.present(drawable); command.commit(); submitted = true
        }

        private func texture(_ device: MTLDevice, width: Int, height: Int, usage: MTLTextureUsage) -> MTLTexture? {
            guard width > 0, height > 0 else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                      width: width, height: height, mipmapped: false)
            descriptor.usage = usage; descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)
        }
        private static func projection(aspect: Float) -> simd_float4x4 {
            let y: Float = 1 / tan(.pi / 6), x = y / aspect
            let near: Float = 0.05, far: Float = 100
            return simd_float4x4(columns: (SIMD4(x,0,0,0), SIMD4(0,y,0,0),
                SIMD4(0,0,-(far+near)/(far-near),-1), SIMD4(0,0,-2*far*near/(far-near),0)))
        }
        private static func appSymbol(_ id: String) -> String {
            let name = id.lowercased()
            if name.contains("safari") || name.contains("chrome") { return "safari.fill" }
            if name.contains("mail") { return "envelope.fill" }
            if name.contains("notes") { return "note.text" }
            if name.contains("photo") { return "photo.on.rectangle" }
            if name.contains("calendar") { return "calendar" }
            if name.contains("music") { return "music.note" }
            if name.contains("message") { return "message.fill" }
            if name.contains("finder") { return "folder.fill" }
            if name.contains("terminal") { return "terminal.fill" }
            if name.contains("code") { return "chevron.left.forwardslash.chevron.right" }
            if name.contains("settings") || name.contains("preferences") { return "gearshape" }
            return "app.fill"
        }
        private func makeAtlas(device: MTLDevice, surfaces: [SpatialSurface]) -> MTLTexture? {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: CGFloat(512 * surfaces.count)), format: format)
            let image = renderer.image { context in
                for (index, surface) in surfaces.enumerated() {
                    let height = CGFloat(512 * surface.size.y / max(0.001, surface.size.x))
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: 0, y: CGFloat(index * 512))
                    context.cgContext.scaleBy(x: 1, y: 512 / height)
                    let rect = CGRect(x: 0, y: 0, width: 512, height: height)
                    let backing = surface.id.hasSuffix("background") || surface.id == "status" || surface.isDisplay
                    if backing {
                        let shape = UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: surface.id == "dock-background" ? height / 2 : 22)
                        context.cgContext.saveGState()
                        shape.addClip()
                        let colors = [UIColor(red: 0.20, green: 0.29, blue: 0.42, alpha: 0.92).cgColor,
                                      UIColor(red: 0.08, green: 0.15, blue: 0.25, alpha: 0.92).cgColor]
                        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 512, y: height), options: [])
                        }
                        context.cgContext.restoreGState()
                        UIColor.white.withAlphaComponent(0.28).setStroke(); shape.lineWidth = 2; shape.stroke()
                    }
                    let app = surface.id.hasPrefix("app:")
                    let control = !backing && !app
                    if app || control {
                        let diameter = min(height * 0.57, app ? 240 : 160)
                        let iconRect = CGRect(x: (512 - diameter) / 2, y: height * 0.12, width: diameter, height: diameter)
                        let shape = UIBezierPath(roundedRect: iconRect, cornerRadius: app ? diameter * 0.22 : diameter / 2)
                        let palette: [UIColor] = [.systemBlue, .systemCyan, .systemOrange, .systemGreen, .systemPink, .systemIndigo]
                        let stableIndex = surface.id.utf8.reduce(0) { ($0 + Int($1)) % palette.count }
                        (app ? palette[stableIndex] : surface.id == "exit" ? UIColor.systemRed.withAlphaComponent(0.48) : surface.id == "apps" ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.16)).setFill()
                        shape.fill()
                    }
                    let symbol = app ? Self.appSymbol(surface.id) : surface.symbol
                    let icon = UIImage(systemName: symbol,
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 42, weight: .regular))?
                        .withTintColor(.white, renderingMode: .alwaysOriginal)
                    let symbolSize = min(height * 0.27, backing ? 48 : 85)
                    icon?.draw(in: CGRect(x: (512 - symbolSize) / 2, y: height * 0.12 + (min(height * 0.57, app ? 240 : 160) - symbolSize) / 2, width: symbolSize, height: symbolSize))
                    let style = NSMutableParagraphStyle(); style.alignment = surface.id == "picker-background" ? .left : .center; style.lineBreakMode = .byTruncatingTail
                    (surface.title as NSString).draw(in: CGRect(x: 24, y: surface.id == "picker-background" ? 20 : surface.symbol.isEmpty ? max(0, (height - 34) / 2) : height * 0.77, width: 464, height: 60),
                        withAttributes: [.font: UIFont.systemFont(ofSize: app ? 34 : backing ? 24 : 30, weight: .medium), .foregroundColor: UIColor.white,
                                         .paragraphStyle: style])
                    context.cgContext.restoreGState()
                }
            }
            guard let cgImage = image.cgImage else { return nil }
            do {
                return try MTKTextureLoader(device: device).newTexture(cgImage: cgImage,
                    options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
            } catch {
                session.reportRenderError("Could not create workspace controls: " + error.localizedDescription)
                return nil
            }
        }
    }
}
#endif

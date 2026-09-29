#if os(iOS) && canImport(WebRTC) && !SWIFT_PACKAGE
import Foundation
import CoreVideo
@preconcurrency import WebRTC

/// Only the newest frame is retained. WebRTC's callback never queues UI work.
final class SpatialVideoMailbox: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var frame: RTCVideoFrame?
    private var receivedAt = 0.0
    func setSize(_ size: CGSize) {}
    func renderFrame(_ frame: RTCVideoFrame?) {
        lock.lock(); defer { lock.unlock() }
        self.frame = frame
        receivedAt = ProcessInfo.processInfo.systemUptime
    }
    func latest() -> (RTCVideoFrame?, Double) {
        lock.lock(); defer { lock.unlock() }
        return (frame, receivedAt)
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        frame = nil; receivedAt = 0
    }

    static func pixelBuffer(_ frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let native = frame.buffer as? RTCCVPixelBuffer { return native.pixelBuffer }
        // Software decoder fallback: pack I420 into NV12 for Core Image.
        let source = frame.buffer.toI420()
        var output: CVPixelBuffer?
        let attributes = [kCVPixelBufferMetalCompatibilityKey: true,
                          kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(source.width), Int(source.height),
                                  kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                  attributes, &output) == kCVReturnSuccess, let output else { return nil }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(output, 0),
              let uv = CVPixelBufferGetBaseAddressOfPlane(output, 1) else { return nil }
        for row in 0..<Int(source.height) {
            memcpy(y.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(output, 0)),
                   source.dataY.advanced(by: row * Int(source.strideY)), Int(source.width))
        }
        for row in 0..<Int(source.chromaHeight) {
            let dest = uv.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(output, 1)).assumingMemoryBound(to: UInt8.self)
            for col in 0..<Int(source.chromaWidth) {
                dest[col * 2] = source.dataU[row * Int(source.strideU) + col]
                dest[col * 2 + 1] = source.dataV[row * Int(source.strideV) + col]
            }
        }
        return output
    }
}
#endif

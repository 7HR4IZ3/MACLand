// MACLand derivative of selected VoidDisplay capture concepts.
// Upstream: iamsyc/VoidDisplay @ 1169fcd2e51103746976b2b2cd27c112f3e13082.
// This file is a reduced MACLand-owned interface; it is not copied wholesale.
import CoreMedia
import Foundation

enum VoidDisplayCaptureOutputKind: String, Sendable {
    case video
    case audio
}

struct VoidDisplayCaptureDimensions: Codable, Equatable, Sendable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

enum VoidDisplayCaptureGeometryError: LocalizedError, Equatable {
    case invalidLogicalSize
    case invalidScaleFactor

    var errorDescription: String? {
        switch self {
        case .invalidLogicalSize:
            return "Capture dimensions must be greater than zero."
        case .invalidScaleFactor:
            return "Capture scale factor must be greater than zero."
        }
    }
}

enum VoidDisplayCaptureGeometry {
    static func pixelDimensions(
        logicalSize: VoidDisplayCaptureDimensions,
        scaleFactor: Double,
        orientation: DisplayOrientation
    ) throws -> VoidDisplayCaptureDimensions {
        guard logicalSize.width > 0, logicalSize.height > 0 else {
            throw VoidDisplayCaptureGeometryError.invalidLogicalSize
        }
        guard scaleFactor > 0, scaleFactor.isFinite else {
            throw VoidDisplayCaptureGeometryError.invalidScaleFactor
        }

        let orientedWidth: Double
        let orientedHeight: Double
        switch orientation {
        case .portrait:
            orientedWidth = Double(logicalSize.width)
            orientedHeight = Double(logicalSize.height)
        case .landscape:
            orientedWidth = Double(logicalSize.height)
            orientedHeight = Double(logicalSize.width)
        }

        return VoidDisplayCaptureDimensions(
            width: max(1, Int((orientedWidth * scaleFactor).rounded())),
            height: max(1, Int((orientedHeight * scaleFactor).rounded()))
        )
    }
}

struct VoidDisplayVideoFrame: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer

    init(sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}

struct VoidDisplayAudioFrame: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer

    init(sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}

enum VoidDisplayCaptureOutput: @unchecked Sendable {
    case video(VoidDisplayVideoFrame)
    case audio(VoidDisplayAudioFrame)

    var kind: VoidDisplayCaptureOutputKind {
        switch self {
        case .video:
            return .video
        case .audio:
            return .audio
        }
    }
}

struct VoidDisplayCaptureConfiguration: Equatable, Sendable {
    let displayID: UInt32
    let logicalSize: VoidDisplayCaptureDimensions
    let scaleFactor: Double
    let orientation: DisplayOrientation
    let framesPerSecond: Int
    let capturesAudio: Bool
    let queueDepth: Int

    init(
        displayID: UInt32,
        logicalSize: VoidDisplayCaptureDimensions,
        scaleFactor: Double = 1,
        orientation: DisplayOrientation,
        framesPerSecond: Int = 60,
        capturesAudio: Bool = true,
        queueDepth: Int = 3
    ) {
        self.displayID = displayID
        self.logicalSize = logicalSize
        self.scaleFactor = scaleFactor
        self.orientation = orientation
        self.framesPerSecond = max(1, framesPerSecond)
        self.capturesAudio = capturesAudio
        self.queueDepth = max(1, queueDepth)
    }

    func pixelDimensions() throws -> VoidDisplayCaptureDimensions {
        try VoidDisplayCaptureGeometry.pixelDimensions(
            logicalSize: logicalSize,
            scaleFactor: scaleFactor,
            orientation: orientation
        )
    }
}

enum VoidDisplayCaptureFailure: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case displayNotFound(UInt32)
    case streamStartFailed(String)
    case streamStopped(String)

    var code: String {
        switch self {
        case .permissionDenied:
            return "permission_denied"
        case .displayNotFound:
            return "display_not_found"
        case .streamStartFailed:
            return "stream_start_failed"
        case .streamStopped:
            return "stream_stopped"
        }
    }

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required to capture a display."
        case let .displayNotFound(displayID):
            return "Screen Capture Kit could not find display \(displayID)."
        case let .streamStartFailed(reason):
            return "Screen capture could not start: \(reason)"
        case let .streamStopped(reason):
            return "Screen capture stopped unexpectedly: \(reason)"
        }
    }
}

enum VoidDisplayCaptureState: Equatable, Sendable {
    case idle
    case requestingPermission
    case starting
    case capturing
    case stopping
    case failed(VoidDisplayCaptureFailure)
}

enum VoidDisplayCaptureStateMachine {
    static func startState(
        permissionGranted: Bool
    ) -> VoidDisplayCaptureState {
        permissionGranted ? .starting : .failed(.permissionDenied)
    }

    static func stopState(
        from state: VoidDisplayCaptureState
    ) -> VoidDisplayCaptureState {
        switch state {
        case .capturing, .starting, .requestingPermission:
            return .stopping
        case .idle, .stopping, .failed:
            return .idle
        }
    }
}

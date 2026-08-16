// MACLand derivative of selected VoidDisplay ScreenCaptureKit concepts.
// Upstream: iamsyc/VoidDisplay @ 1169fcd2e51103746976b2b2cd27c112f3e13082.
// Adapted for MACLand's display-ID boundary and native WebRTC session.
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
protocol VoidDisplayCaptureSession: AnyObject {
    var state: VoidDisplayCaptureState { get }

    func start() async throws
    func stop() async
}

@MainActor
final class VoidDisplayScreenCaptureSession: NSObject, VoidDisplayCaptureSession {
    private final class StreamCallback: NSObject, SCStreamOutput, SCStreamDelegate {
        weak var owner: VoidDisplayScreenCaptureSession?

        func stream(
            _ stream: SCStream,
            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
            of type: SCStreamOutputType
        ) {
            let output: VoidDisplayCaptureOutput?
            switch type {
            case .screen:
                output = .video(VoidDisplayVideoFrame(sampleBuffer: sampleBuffer))
            case .audio, .microphone:
                output = .audio(VoidDisplayAudioFrame(sampleBuffer: sampleBuffer))
            @unknown default:
                output = nil
            }
            guard let output else { return }
            Task { @MainActor [weak owner] in
                owner?.receive(output: output)
            }
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            let reason = error.localizedDescription
            Task { @MainActor [weak owner] in
                owner?.streamDidStop(reason: reason)
            }
        }
    }

    private let configuration: VoidDisplayCaptureConfiguration
    private let permissionProvider: any VoidDisplayCapturePermissionProviding
    private let output: @Sendable (VoidDisplayCaptureOutput) -> Void
    private let sampleHandlerQueue = DispatchQueue(
        label: "com.thraize.macland.void-display-capture",
        qos: .userInitiated
    )
    private var stream: SCStream?
    private var callback: StreamCallback?
    private(set) var state: VoidDisplayCaptureState = .idle

    init(
        configuration: VoidDisplayCaptureConfiguration,
        permissionProvider: any VoidDisplayCapturePermissionProviding = SystemVoidDisplayCapturePermissionProvider(),
        output: @escaping @Sendable (VoidDisplayCaptureOutput) -> Void
    ) {
        self.configuration = configuration
        self.permissionProvider = permissionProvider
        self.output = output
        super.init()
    }

    func start() async throws {
        guard stream == nil else { return }

        state = .requestingPermission
        guard permissionProvider.request() == .granted else {
            state = VoidDisplayCaptureStateMachine.startState(permissionGranted: false)
            throw VoidDisplayCaptureFailure.permissionDenied
        }

        state = .starting
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                $0.displayID == configuration.displayID
            }) else {
                throw VoidDisplayCaptureFailure.displayNotFound(configuration.displayID)
            }

            let pixelDimensions = try configuration.pixelDimensions()
            let streamConfiguration = SCStreamConfiguration()
            streamConfiguration.width = pixelDimensions.width
            streamConfiguration.height = pixelDimensions.height
            streamConfiguration.minimumFrameInterval = CMTime(
                value: 1,
                timescale: CMTimeScale(configuration.framesPerSecond)
            )
            streamConfiguration.queueDepth = configuration.queueDepth
            streamConfiguration.capturesAudio = configuration.capturesAudio
            streamConfiguration.showsCursor = false

            let callback = StreamCallback()
            callback.owner = self
            let stream = SCStream(
                filter: SCContentFilter(display: display, excludingWindows: []),
                configuration: streamConfiguration,
                delegate: callback
            )
            try stream.addStreamOutput(
                callback,
                type: .screen,
                sampleHandlerQueue: sampleHandlerQueue
            )
            if configuration.capturesAudio {
                try stream.addStreamOutput(
                    callback,
                    type: .audio,
                    sampleHandlerQueue: sampleHandlerQueue
                )
            }
            try await stream.startCapture()

            self.stream = stream
            self.callback = callback
            state = .capturing
        } catch let failure as VoidDisplayCaptureFailure {
            state = .failed(failure)
            throw failure
        } catch {
            let failure = VoidDisplayCaptureFailure.streamStartFailed(error.localizedDescription)
            state = .failed(failure)
            throw failure
        }
    }

    func stop() async {
        guard let stream else {
            state = .idle
            return
        }

        state = VoidDisplayCaptureStateMachine.stopState(from: state)
        do {
            try await stream.stopCapture()
        } catch {
            state = .failed(.streamStopped(error.localizedDescription))
            self.stream = nil
            callback = nil
            return
        }

        self.stream = nil
        callback = nil
        state = .idle
    }

    private func receive(output: VoidDisplayCaptureOutput) {
        self.output(output)
    }

    private func streamDidStop(reason: String) {
        guard stream != nil else { return }
        stream = nil
        callback = nil
        state = .failed(.streamStopped(reason))
    }
}

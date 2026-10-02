// MACLand-owned coordinator around the extracted VoidDisplay capture and
// WebRTC layers. The upstream browser/server lifecycle is intentionally not
// used here.
import CoreGraphics
import Combine
import Foundation

@MainActor
enum VoidDisplayMediaCoordinatorState: Equatable, Sendable {
    case idle
    case starting
    case waitingForAnswer
    case streaming
    case reconnecting
    case failed(String)
    case stopped

    var label: String {
        switch self {
        case .idle: "Media idle"
        case .starting: "Starting media"
        case .waitingForAnswer: "Waiting for WebRTC answer"
        case .streaming: "Streaming display"
        case .reconnecting: "Reconnecting media"
        case let .failed(reason): "Media failed: " + reason
        case .stopped: "Media stopped"
        }
    }
}

@MainActor
final class VoidDisplayMediaCoordinator: ObservableObject {
    @Published private(set) var state: VoidDisplayMediaCoordinatorState = .idle
    @Published private(set) var latestOffer: VoidDisplayWebRTCSessionDescription?
    @Published private(set) var audioStatus = "System audio capture is not published yet."

    let configuration: VoidDisplayCaptureConfiguration
    let codecMetadata: VoidDisplayCodecNegotiationMetadata

    /// The host transport subscribes to this callback and sends the offer in
    /// a typed `media.offer` envelope. Keeping this callback outside the media
    /// layer prevents WebRTC from depending on MACLand's WebSocket transport.
    var onOffer: ((VoidDisplayWebRTCSessionDescription) -> Void)?
    var onICECandidate: ((VoidDisplayWebRTCICECandidate) -> Void)?

    private var captureSession: VoidDisplayScreenCaptureSession?
    private var pendingRemoteICE: [VoidDisplayWebRTCICECandidate] = []
    private var remoteAnswerApplied = false
    private var senderSession: (any VoidDisplayWebRTCSession)?

    init(
        configuration: VoidDisplayCaptureConfiguration,
        codecMetadata: VoidDisplayCodecNegotiationMetadata = .h264First
    ) {
        self.configuration = configuration
        self.codecMetadata = codecMetadata
    }

    func start() async {
        guard state == .idle || state == .stopped || state.isFailure else { return }
        state = .starting

        do {
            let sender = try makeSender()
            senderSession = sender
            sender.onLocalICECandidate = { [weak self] candidate in
                self?.onICECandidate?(candidate)
            }
            try await sender.start()

            let capture = VoidDisplayScreenCaptureSession(
                configuration: configuration,
                output: { [weak self] output in
                    Task { @MainActor [weak self] in
                        self?.consume(output)
                    }
                }
            )
            captureSession = capture
            try await capture.start()

            let offer = try await sender.makeOffer()
            latestOffer = offer
            state = .waitingForAnswer
            onOffer?(offer)
        } catch {
            await stopCaptureAndSender()
            state = .failed(error.localizedDescription)
        }
    }

    func applyRemoteAnswer(_ answer: VoidDisplayWebRTCSessionDescription) async {
        guard let senderSession else {
            state = .failed("A WebRTC sender session is not available.")
            return
        }

        do {
            try await senderSession.applyRemoteAnswer(answer)
            remoteAnswerApplied = true
            let candidates = pendingRemoteICE
            pendingRemoteICE.removeAll()
            for candidate in candidates { try await senderSession.addRemoteICECandidate(candidate) }
            state = .streaming
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func addRemoteICECandidate(_ candidate: VoidDisplayWebRTCICECandidate) async {
        guard remoteAnswerApplied, let senderSession else {
            pendingRemoteICE.append(candidate)
            return
        }
        do { try await senderSession.addRemoteICECandidate(candidate) }
        catch { state = .failed(error.localizedDescription) }
    }

    func markReconnecting() {
        guard state != .idle, state != .stopped else { return }
        state = .reconnecting
    }

    func stop() async {
        await stopCaptureAndSender()
        latestOffer = nil
        state = .stopped
    }

    private func makeSender() throws -> any VoidDisplayWebRTCSession {
#if canImport(WebRTC)
        return try WebRTCVoidDisplaySenderSession(metadata: codecMetadata)
#else
        return try UnavailableVoidDisplayWebRTCSessionAdapter().makeSession(metadata: codecMetadata)
#endif
    }

    private func consume(_ output: VoidDisplayCaptureOutput) {
        guard let senderSession else { return }

        do {
            try senderSession.send(output)
        } catch VoidDisplayWebRTCError.audioPublishingUnavailable {
            // The capture stream is still useful for video. Surface the
            // boundary once instead of failing the whole display session for
            // each audio sample.
            audioStatus = "System audio captured; WebRTC audio publishing is pending."
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func stopCaptureAndSender() async {
        if let captureSession {
            await captureSession.stop()
        }
        captureSession = nil
        senderSession?.close()
        senderSession = nil
        pendingRemoteICE.removeAll()
        remoteAnswerApplied = false
    }
}

private extension VoidDisplayMediaCoordinatorState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

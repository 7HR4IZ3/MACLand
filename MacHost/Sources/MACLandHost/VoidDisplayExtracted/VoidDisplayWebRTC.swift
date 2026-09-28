// MACLand derivative of selected VoidDisplay WebRTC media concepts.
// Upstream: iamsyc/VoidDisplay @ 1169fcd2e51103746976b2b2cd27c112f3e13082.
// Adapted for MACLand signaling; VoidDisplay's browser server is excluded.
import CoreMedia
import CoreVideo
import Foundation

#if canImport(WebRTC)
@preconcurrency import WebRTC
#endif

enum VoidDisplayVideoCodec: String, CaseIterable, Codable, Sendable {
    case h264 = "H264"
    case vp8 = "VP8"
    case vp9 = "VP9"
    case av1 = "AV1"
}

struct VoidDisplayCodecCapability: Codable, Equatable, Sendable {
    let codec: VoidDisplayVideoCodec
    let payloadType: Int
    let clockRate: Int
    let channels: Int?
    let parameters: [String: String]

    init(
        codec: VoidDisplayVideoCodec,
        payloadType: Int,
        clockRate: Int = 90_000,
        channels: Int? = nil,
        parameters: [String: String] = [:]
    ) {
        self.codec = codec
        self.payloadType = payloadType
        self.clockRate = clockRate
        self.channels = channels
        self.parameters = parameters
    }
}

struct VoidDisplayCodecNegotiationMetadata: Codable, Equatable, Sendable {
    let preferredVideoCodecs: [VoidDisplayVideoCodec]
    let offeredVideoCodecs: [VoidDisplayCodecCapability]

    init(
        preferredVideoCodecs: [VoidDisplayVideoCodec] = [.h264, .vp8, .vp9, .av1],
        offeredVideoCodecs: [VoidDisplayCodecCapability] = []
    ) {
        self.preferredVideoCodecs = preferredVideoCodecs
        self.offeredVideoCodecs = offeredVideoCodecs
    }

    static let h264First = VoidDisplayCodecNegotiationMetadata()

    func selectingCommonCodec(
        from remoteCapabilities: [VoidDisplayCodecCapability]
    ) -> VoidDisplayCodecCapability? {
        for preferredCodec in preferredVideoCodecs {
            if !offeredVideoCodecs.isEmpty,
               !offeredVideoCodecs.contains(where: { $0.codec == preferredCodec }) {
                continue
            }
            if let remoteCodec = remoteCapabilities.first(where: {
                $0.codec == preferredCodec
            }) {
                return remoteCodec
            }
        }
        return nil
    }
}

enum VoidDisplayWebRTCSessionState: String, Sendable {
    case idle
    case ready
    case offering
    case waitingForAnswer = "waiting_for_answer"
    case starting
    case connected
    case closed
}

enum VoidDisplayWebRTCAudioPublishingState: String, Codable, Sendable {
    case captureAvailablePublishingUnavailable = "capture_available_publishing_unavailable"
}

struct VoidDisplayWebRTCMediaCapabilities: Codable, Equatable, Sendable {
    let videoPublishing: Bool
    let audioCapture: Bool
    let audioPublishing: Bool
    let audioPublishingState: VoidDisplayWebRTCAudioPublishingState

    static let screenSender = VoidDisplayWebRTCMediaCapabilities(
        videoPublishing: true,
        audioCapture: true,
        audioPublishing: false,
        audioPublishingState: .captureAvailablePublishingUnavailable
    )
}

enum VoidDisplayWebRTCSignalingType: String, Codable, Sendable {
    case offer
    case answer
}

struct VoidDisplayWebRTCSessionDescription: Codable, Equatable, Sendable {
    let type: VoidDisplayWebRTCSignalingType
    let sdp: String

    init(type: VoidDisplayWebRTCSignalingType, sdp: String) {
        self.type = type
        self.sdp = sdp
    }
}

struct VoidDisplayWebRTCICECandidate: Sendable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
}

enum VoidDisplayWebRTCError: LocalizedError, Equatable, Sendable {
    case packageUnavailable
    case noCommonVideoCodec
    case noVideoCodecCapability
    case peerConnectionUnavailable
    case videoFrameMissingPixelBuffer
    case audioPublishingUnavailable
    case invalidRemoteDescriptionType(expected: VoidDisplayWebRTCSignalingType)
    case signalingOperationFailed(String)
    case sessionClosed

    var errorDescription: String? {
        switch self {
        case .packageUnavailable:
            return "WebRTC media transport is not configured for MACLand host capture."
        case .noCommonVideoCodec:
            return "The capture session and remote peer have no common video codec."
        case .noVideoCodecCapability:
            return "The WebRTC factory did not expose a usable video codec capability."
        case .peerConnectionUnavailable:
            return "The WebRTC factory could not create a peer connection."
        case .videoFrameMissingPixelBuffer:
            return "The captured video sample did not contain a pixel buffer."
        case .audioPublishingUnavailable:
            return "System audio capture is available, but audio publishing is not wired safely."
        case let .invalidRemoteDescriptionType(expected):
            return "The remote description must be an \(expected.rawValue)."
        case let .signalingOperationFailed(reason):
            return "WebRTC signaling failed: \(reason)"
        case .sessionClosed:
            return "The WebRTC capture session is closed."
        }
    }
}

@MainActor
protocol VoidDisplayWebRTCSession: AnyObject {
    var state: VoidDisplayWebRTCSessionState { get }
    var mediaCapabilities: VoidDisplayWebRTCMediaCapabilities { get }
    var onLocalICECandidate: ((VoidDisplayWebRTCICECandidate) -> Void)? { get set }

    func start() async throws
    func send(_ output: VoidDisplayCaptureOutput) throws
    func send(pixelBuffer: CVPixelBuffer, timestampNs: Int64) throws
    func makeOffer() async throws -> VoidDisplayWebRTCSessionDescription
    func applyRemoteAnswer(_ answer: VoidDisplayWebRTCSessionDescription) async throws
    func addRemoteICECandidate(_ candidate: VoidDisplayWebRTCICECandidate) async throws
    func close()
}

@MainActor
protocol VoidDisplayWebRTCSessionAdapter {
    func makeSession(
        metadata: VoidDisplayCodecNegotiationMetadata
    ) throws -> any VoidDisplayWebRTCSession
}

/// The capture layer is usable without pretending that frames are streamed.
/// A concrete adapter can be added when the WebRTC package and its runtime
/// transport are wired into the host target.
@MainActor
struct UnavailableVoidDisplayWebRTCSessionAdapter: VoidDisplayWebRTCSessionAdapter {
    func makeSession(
        metadata: VoidDisplayCodecNegotiationMetadata
    ) throws -> any VoidDisplayWebRTCSession {
        _ = metadata
        throw VoidDisplayWebRTCError.packageUnavailable
    }
}

#if canImport(WebRTC)
@MainActor
final class WebRTCVoidDisplaySenderSession: NSObject, VoidDisplayWebRTCSession, RTCPeerConnectionDelegate {
    private static let sslInitialized: Void = {
        _ = RTCInitializeSSL()
    }()

    let factory: RTCPeerConnectionFactory
    let videoSource: RTCVideoSource
    let videoTrack: RTCVideoTrack
    let peerConnection: RTCPeerConnection
    let codecMetadata: VoidDisplayCodecNegotiationMetadata

    private let videoCapturer: RTCVideoCapturer
    private let videoTransceiver: RTCRtpTransceiver
    private(set) var state: VoidDisplayWebRTCSessionState = .idle
    let mediaCapabilities = VoidDisplayWebRTCMediaCapabilities.screenSender
    var onLocalICECandidate: ((VoidDisplayWebRTCICECandidate) -> Void)?

    init(
        metadata: VoidDisplayCodecNegotiationMetadata = .h264First,
        iceServers: [RTCIceServer] = []
    ) throws {
        _ = Self.sslInitialized

        let factory = RTCPeerConnectionFactory()
        let videoSource = factory.videoSource(forScreenCast: true)
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "void-display-video")
        let videoCapturer = RTCVideoCapturer(delegate: videoSource)

        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        guard let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: nil
        ) else {
            throw VoidDisplayWebRTCError.peerConnectionUnavailable
        }

        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendOnly
        transceiverInit.streamIds = ["void-display"]
        guard let videoTransceiver = peerConnection.addTransceiver(
            with: videoTrack,
            init: transceiverInit
        ) else {
            throw VoidDisplayWebRTCError.signalingOperationFailed(
                "Could not create the video transceiver."
            )
        }

        let availableCodecs = factory.rtpSenderCapabilities(
            forKind: kRTCMediaStreamTrackKindVideo
        ).codecs
        let preferredCodecs = Self.h264FirstCodecPreferences(
            from: availableCodecs,
            preferredOrder: metadata.preferredVideoCodecs
        )
        guard !preferredCodecs.isEmpty else {
            throw VoidDisplayWebRTCError.noVideoCodecCapability
        }
        do {
            try videoTransceiver.setCodecPreferences(preferredCodecs, error: ())
        } catch {
            throw VoidDisplayWebRTCError.signalingOperationFailed(
                error.localizedDescription
            )
        }

        self.factory = factory
        self.videoSource = videoSource
        self.videoTrack = videoTrack
        self.peerConnection = peerConnection
        self.videoCapturer = videoCapturer
        self.videoTransceiver = videoTransceiver
        self.codecMetadata = Self.makeCodecMetadata(
            from: availableCodecs,
            preferredOrder: metadata.preferredVideoCodecs
        )
        super.init()
        peerConnection.delegate = self
    }

    func start() async throws {
        guard state != .closed else {
            throw VoidDisplayWebRTCError.sessionClosed
        }
        if state == .idle {
            state = .ready
        }
    }

    func send(_ output: VoidDisplayCaptureOutput) throws {
        switch output {
        case let .video(frame):
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else {
                throw VoidDisplayWebRTCError.videoFrameMissingPixelBuffer
            }
            try send(
                pixelBuffer: pixelBuffer,
                timestampNs: Self.timestampNanoseconds(for: frame.sampleBuffer)
            )
        case .audio:
            throw VoidDisplayWebRTCError.audioPublishingUnavailable
        }
    }

    func send(pixelBuffer: CVPixelBuffer, timestampNs: Int64) throws {
        guard state != .closed else {
            throw VoidDisplayWebRTCError.sessionClosed
        }

        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(
            buffer: rtcBuffer,
            rotation: ._0,
            timeStampNs: max(0, timestampNs)
        )
        videoSource.capturer(videoCapturer, didCapture: frame)
    }

    func makeOffer() async throws -> VoidDisplayWebRTCSessionDescription {
        guard state != .closed else {
            throw VoidDisplayWebRTCError.sessionClosed
        }
        if state == .idle {
            state = .ready
        }
        state = .offering

        do {
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            )
            let offer = try await createOffer(constraints: constraints)
            try await setLocalDescription(offer)
            state = .waitingForAnswer
            return VoidDisplayWebRTCSessionDescription(
                type: .offer,
                sdp: offer.sdp
            )
        } catch let error as VoidDisplayWebRTCError {
            state = .ready
            throw error
        } catch {
            state = .ready
            throw VoidDisplayWebRTCError.signalingOperationFailed(
                error.localizedDescription
            )
        }
    }

    func applyRemoteAnswer(
        _ answer: VoidDisplayWebRTCSessionDescription
    ) async throws {
        guard state != .closed else {
            throw VoidDisplayWebRTCError.sessionClosed
        }
        guard answer.type == .answer else {
            throw VoidDisplayWebRTCError.invalidRemoteDescriptionType(expected: .answer)
        }

        do {
            try await setRemoteDescription(
                RTCSessionDescription(type: .answer, sdp: answer.sdp)
            )
            state = .connected
        } catch {
            throw VoidDisplayWebRTCError.signalingOperationFailed(
                error.localizedDescription
            )
        }
    }

    func addRemoteICECandidate(_ candidate: VoidDisplayWebRTCICECandidate) async throws {
        guard state != .closed else { throw VoidDisplayWebRTCError.sessionClosed }
        let iceCandidate = RTCIceCandidate(
            sdp: candidate.candidate,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdpMid: candidate.sdpMid
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(iceCandidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func close() {
        guard state != .closed else { return }
        state = .closed
        peerConnection.close()
    }

    private func createOffer(
        constraints: RTCMediaConstraints
    ) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peerConnection.offer(for: constraints) { offer, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let offer else {
                    continuation.resume(
                        throwing: VoidDisplayWebRTCError.signalingOperationFailed(
                            "The peer connection returned no offer."
                        )
                    )
                    return
                }
                continuation.resume(returning: offer)
            }
        }
    }

    private func setLocalDescription(
        _ description: RTCSessionDescription
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func setRemoteDescription(
        _ description: RTCSessionDescription
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func timestampNanoseconds(for sampleBuffer: CMSampleBuffer) -> Int64 {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, presentationTime.timescale != 0 else {
            return 0
        }
        return max(
            0,
            Int64(
                (Double(presentationTime.value) / Double(presentationTime.timescale))
                    * 1_000_000_000
            )
        )
    }

    private static func h264FirstCodecPreferences(
        from capabilities: [RTCRtpCodecCapability],
        preferredOrder: [VoidDisplayVideoCodec]
    ) -> [RTCRtpCodecCapability] {
        var result: [RTCRtpCodecCapability] = []
        var selectedPayloadTypes = Set<Int>()

        for codec in preferredOrder {
            let matching = capabilities.filter {
                $0.name.caseInsensitiveCompare(codec.rawValue) == .orderedSame
            }
            result.append(contentsOf: matching)
            selectedPayloadTypes.formUnion(
                matching.compactMap { $0.preferredPayloadType?.intValue }
            )
        }

        let retransmissionCodecs = capabilities.filter { capability in
            guard capability.name.caseInsensitiveCompare("rtx") == .orderedSame,
                  let apt = capability.parameters["apt"].flatMap(Int.init)
            else {
                return false
            }
            return selectedPayloadTypes.contains(apt)
        }
        result.append(contentsOf: retransmissionCodecs)
        return result
    }

    private static func makeCodecMetadata(
        from capabilities: [RTCRtpCodecCapability],
        preferredOrder: [VoidDisplayVideoCodec]
    ) -> VoidDisplayCodecNegotiationMetadata {
        let offered = capabilities.compactMap { capability -> VoidDisplayCodecCapability? in
            guard let codec = VoidDisplayVideoCodec(rawValue: capability.name.uppercased()),
                  let payloadType = capability.preferredPayloadType?.intValue
            else {
                return nil
            }
            return VoidDisplayCodecCapability(
                codec: codec,
                payloadType: payloadType,
                clockRate: capability.clockRate?.intValue ?? 90_000,
                channels: capability.numChannels?.intValue,
                parameters: capability.parameters
            )
        }
        return VoidDisplayCodecNegotiationMetadata(
            preferredVideoCodecs: preferredOrder,
            offeredVideoCodecs: offered
        )
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor [weak self] in
            self?.onLocalICECandidate?(
                VoidDisplayWebRTCICECandidate(
                    candidate: candidate.sdp,
                    sdpMid: candidate.sdpMid,
                    sdpMLineIndex: candidate.sdpMLineIndex
                )
            )
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {}
}
#endif

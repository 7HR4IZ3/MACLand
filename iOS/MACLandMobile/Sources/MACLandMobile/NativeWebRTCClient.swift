import Foundation

#if canImport(WebRTC) && !SWIFT_PACKAGE
@preconcurrency import WebRTC

/// Native iOS WebRTC viewer. The control WebSocket owns signaling; this type
/// only owns peer-connection negotiation, ICE, and the received media tracks.
@MainActor
public final class NativeWebRTCClient: NSObject, ObservableObject {
    @Published public private(set) var remoteVideoTrack: RTCVideoTrack?
    @Published public private(set) var connectionState: RemoteMediaConnectionState = .idle

    public var onLocalICECandidate: ((RTCIceCandidate) -> Void)?
    public var onConnectionFailure: ((String) -> Void)?

    private static let sslInitialized: Void = {
        _ = RTCInitializeSSL()
    }()

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?

    public override init() {
        _ = Self.sslInitialized
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
    }

    public func start(iceServerURLs: [String] = []) throws {
        guard peerConnection == nil else { return }

        let configuration = RTCConfiguration()
        configuration.iceServers = iceServerURLs.isEmpty
            ? []
            : [RTCIceServer(urlStrings: iceServerURLs)]
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )
        guard let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw NativeWebRTCClientError.peerConnectionUnavailable
        }

        self.peerConnection = peerConnection
        connectionState = .negotiating
    }

    public func applyRemoteOffer(sdp: String) async throws -> String {
        try start()
        guard let peerConnection else {
            throw NativeWebRTCClientError.peerConnectionUnavailable
        }

        try await setRemoteDescription(
            RTCSessionDescription(type: .offer, sdp: sdp),
            on: peerConnection
        )
        let answer = try await createAnswer(on: peerConnection)
        try await setLocalDescription(answer, on: peerConnection)
        connectionState = .negotiating
        return peerConnection.localDescription?.sdp ?? answer.sdp
    }

    public func addRemoteICECandidate(
        sdp: String,
        sdpMLineIndex: Int32,
        sdpMid: String?
    )
    async throws {
        guard let peerConnection else {
            throw NativeWebRTCClientError.peerConnectionUnavailable
        }
        let candidate = RTCIceCandidate(
            sdp: sdp,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(candidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    public func stop() {
        peerConnection?.close()
        peerConnection = nil
        remoteVideoTrack = nil
        connectionState = .idle
    }

    private func createAnswer(on peerConnection: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            )
            peerConnection.answer(for: constraints) { answer, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let answer {
                    continuation.resume(returning: answer)
                } else {
                    continuation.resume(throwing: NativeWebRTCClientError.missingSessionDescription)
                }
            }
        }
    }

    private func setRemoteDescription(
        _ description: RTCSessionDescription,
        on peerConnection: RTCPeerConnection
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

    private func setLocalDescription(
        _ description: RTCSessionDescription,
        on peerConnection: RTCPeerConnection
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
}

public enum NativeWebRTCClientError: LocalizedError, Equatable {
    case peerConnectionUnavailable
    case missingSessionDescription

    public var errorDescription: String? {
        switch self {
        case .peerConnectionUnavailable:
            "The iOS WebRTC peer connection could not be created."
        case .missingSessionDescription:
            "WebRTC returned no session description."
        }
    }
}

extension NativeWebRTCClient: RTCPeerConnectionDelegate {
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor [weak self] in
            self?.onLocalICECandidate?(candidate)
        }
    }

    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch newState {
            case .connected:
                connectionState = .connected
            case .failed:
                connectionState = .failed
                onConnectionFailure?("The iOS WebRTC peer connection failed.")
            case .disconnected:
                connectionState = .reconnecting
            case .closed:
                connectionState = .idle
            default:
                break
            }
        }
    }

    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard let videoTrack = rtpReceiver.track as? RTCVideoTrack else { return }
        Task { @MainActor [weak self] in
            self?.remoteVideoTrack = videoTrack
        }
    }

    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        Task { @MainActor [weak self] in
            if self?.remoteVideoTrack?.trackId == rtpReceiver.track?.trackId {
                self?.remoteVideoTrack = nil
            }
        }
    }

}
#else
@MainActor
public final class NativeWebRTCClient: ObservableObject {
    @Published public private(set) var remoteVideoTrack: NativeRemoteVideoTrack? = nil

    public init() {}

    public func stop() {
        remoteVideoTrack = nil
    }
}

public enum NativeWebRTCClientError: LocalizedError, Equatable {
    case peerConnectionUnavailable
    case missingSessionDescription

    public var errorDescription: String? { "Native WebRTC is only available in the iOS application target." }
}
#endif

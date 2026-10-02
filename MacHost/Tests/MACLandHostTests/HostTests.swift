import Foundation
import CoreGraphics
import CoreVideo
@preconcurrency import WebRTC
import Network
import XCTest
@testable import MACLandHost

final class HostTests: XCTestCase {
    @MainActor
    func testNetworkQueueFetchesApplicationsOnMainActor() async throws {
        let material = try KeychainTLSIdentityStore().load()
        let listener = try LocalControlListener(
            hostName: "Application catalog regression",
            port: .any,
            tlsIdentityFactory: { material.identity },
            appsListProvider: {
                MainActor.assertIsolated()
                return AppsListPayload(applications: [ApplicationDescriptor(bundleIdentifier: "com.example.app", name: "Test app")])
            }
        )
        let payload = await Task.detached {
            await listener.fetchApplications()
        }.value
        XCTAssertEqual(payload?.applications.first?.name, "Test app")
    }

    @MainActor
    func testViewerICEReachesMediaCallback() throws {
        let material = try KeychainTLSIdentityStore().load()
        var received: MediaICEPayload?
        let listener = try LocalControlListener(hostName: "ICE regression", port: .any,
            tlsIdentityFactory: { material.identity }, onMediaICE: { received = $0 })
        let candidate = MediaICEPayload(sessionID: UUID(), candidate: "candidate:1 1 UDP 1 127.0.0.1 12345 typ host", sdpMid: "0", sdpMLineIndex: 0)
        listener.forwardMediaICE(candidate)
        XCTAssertEqual(received?.candidate, candidate.candidate)
        XCTAssertEqual(received?.sessionID, candidate.sessionID)
    }

    @MainActor
    func testWebRTCViewerReceivesDecodedFrame() async throws {
        let sender = try WebRTCVoidDisplaySenderSession()
        let firstFrame = expectation(description: "Viewer decodes a frame from the host sender")
        let receiverDelegate = LoopbackVideoReceiver(firstFrame: firstFrame)
        let factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        let receiver = try XCTUnwrap(factory.peerConnection(with: configuration,
            constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: receiverDelegate))
        defer { sender.close(); receiver.close() }
        var viewerCandidates: [VoidDisplayWebRTCICECandidate] = []
        var hostCandidates: [RTCIceCandidate] = []
        var viewerReady = false
        var hostReady = false
        sender.onLocalICECandidate = { candidate in
            let ice = RTCIceCandidate(sdp: candidate.candidate, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
            if viewerReady { receiver.add(ice) { _ in } }
            else { hostCandidates.append(ice) }
        }
        receiverDelegate.onCandidate = { candidate in
            let ice = VoidDisplayWebRTCICECandidate(candidate: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)
            if hostReady { Task { try await sender.addRemoteICECandidate(ice) } }
            else { viewerCandidates.append(ice) }
        }
        try await sender.start()
        let offer = try await sender.makeOffer()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            receiver.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: offer.sdp)) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        viewerReady = true
        for candidate in hostCandidates { receiver.add(candidate) { _ in } }
        let answer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            receiver.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { answer, error in
                if let error { continuation.resume(throwing: error) }
                else if let answer { continuation.resume(returning: answer) }
                else { continuation.resume(throwing: VoidDisplayWebRTCError.peerConnectionUnavailable) }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            receiver.setLocalDescription(answer) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        try await sender.applyRemoteAnswer(VoidDisplayWebRTCSessionDescription(type: .answer, sdp: answer.sdp))
        hostReady = true
        for candidate in viewerCandidates { try await sender.addRemoteICECandidate(candidate) }
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), 255, CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let frames = Task { @MainActor in
            for index in 0..<150 {
                try Task.checkCancellation()
                try sender.send(pixelBuffer: pixels, timestampNs: Int64(index) * 33_333_333)
                try await Task.sleep(for: .milliseconds(33))
            }
        }
        defer { frames.cancel() }
        await fulfillment(of: [firstFrame], timeout: 8)
    }

    func testVirtualDisplayGateIdentifiesTheExperimentalVoidDisplayPath() {
        let status = VirtualDisplayGate.evaluate()
        XCTAssertTrue(
            status == .experimentalPrivateAPI("VoidDisplay") ||
                status == .unavailable(reason: "VoidDisplay private runtime is unavailable")
        )
    }

    func testApplicationCatalogErrorIncludesBundleIdentifier() {
        let error = ApplicationCatalogError.notFound("com.example.missing")
        XCTAssertEqual(error.errorDescription, "Application not found: com.example.missing")
    }

    func testTouchDragCreatesDraggedEventAndTapPreservesClickCount() throws {
        let injector = InputInjector()
        let point = InputPoint(x: 200, y: 150)
        let move = try injector.makePointerEvent(InputEvent(kind: .pointerMove, timestamp: 1, location: point))
        XCTAssertEqual(move.type, .mouseMoved)
        let drag = try injector.makePointerEvent(InputEvent(kind: .pointerMove, timestamp: 1, location: point, button: .left, pressed: true))
        XCTAssertEqual(drag.type, .leftMouseDragged)
        XCTAssertEqual(drag.location, CGPoint(x: 200, y: 150))
        let click = try injector.makePointerEvent(InputEvent(kind: .pointerButton, timestamp: 1, location: point, button: .left, pressed: false, clickCount: 2))
        XCTAssertEqual(click.type, .leftMouseUp)
        XCTAssertEqual(click.getIntegerValueField(.mouseEventClickState), 2)
        let right = try injector.makePointerEvent(InputEvent(kind: .pointerButton, timestamp: 1, location: point, button: .right, pressed: true))
        XCTAssertEqual(right.type, .rightMouseDown)
    }

    func testTwoFingerScrollCreatesWheelEventWithBothAxes() throws {
        let event = InputEvent(kind: .scroll, timestamp: 1, location: InputPoint(x: 200, y: 150),
                               scrollDelta: InputPoint(x: -12, y: 35))
        let wheel = try InputInjector().makePointerEvent(event)
        XCTAssertEqual(wheel.type, .scrollWheel)
        XCTAssertEqual(wheel.location, CGPoint(x: 200, y: 150))
        XCTAssertEqual(wheel.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 35)
        XCTAssertEqual(wheel.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -12)
        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(InputEvent.self, from: data), event)
        XCTAssertThrowsError(try InputInjector().makePointerEvent(InputEvent(kind: .scroll, timestamp: 1, location: event.location)))
    }

    func testInputInjectorRejectsTextEventsUntilTextChannelExists() {
        let event = InputEvent(kind: .text, timestamp: 1, text: "hello")
        XCTAssertThrowsError(try InputInjector().inject(event)) { error in
            XCTAssertTrue(error is InputInjectorError)
        }
    }

    func testControlListenerFailsClosedWithoutProvisionedTLSIdentity() {
        XCTAssertThrowsError(try LocalControlListener(hostName: "Test Mac")) { error in
            XCTAssertEqual(
                error as? LocalControlListenerError,
                .tlsIdentity(.notConfigured)
            )
        }
    }

    func testControlListenerSurfacesTLSPermissionErrors() {
        XCTAssertThrowsError(
            try LocalControlListener(hostName: "Test Mac", tlsIdentityFactory: {
                throw ControlTLSIdentityError.permissionDenied
            })
        ) { error in
            XCTAssertEqual(
                error as? LocalControlListenerError,
                .tlsIdentity(.permissionDenied)
            )
        }
    }

    func testControlListenerRejectsBlankHostNamesBeforeTouchingTLS() {
        XCTAssertThrowsError(try LocalControlListener(hostName: "   ")) { error in
            XCTAssertEqual(error as? LocalControlListenerError, .invalidHostName)
        }
    }

    func testWebSocketSessionCannotSendCommandsBeforePairing() throws {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: 9)!, using: .tcp)
        let session = ControlWebSocketSession(
            connection: connection,
            queue: DispatchQueue(label: "macland-host-test")
        )
        let envelope = try ControlEnvelope(
            kind: .heartbeat,
            sequence: 1,
            payload: HeartbeatPayload(kind: .ping, heartbeatID: UUID())
        )

        XCTAssertThrowsError(try session.send(envelope)) { error in
            XCTAssertEqual(error as? ControlTransportError, .pairingRequired)
        }
        session.close()
    }
}

@MainActor
private final class LoopbackVideoReceiver: NSObject, RTCPeerConnectionDelegate {
    var onCandidate: ((RTCIceCandidate) -> Void)?
    private let renderer: LoopbackFrameRenderer
    private var videoTrack: RTCVideoTrack?
    init(firstFrame: XCTestExpectation) { renderer = LoopbackFrameRenderer(firstFrame: firstFrame) }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in self.onCandidate?(candidate) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        Task { @MainActor in
            self.videoTrack = rtpReceiver.track as? RTCVideoTrack
            self.videoTrack?.add(self.renderer)
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
}
private final class LoopbackFrameRenderer: NSObject, RTCVideoRenderer {
    private let firstFrame: XCTestExpectation
    private let lock = NSLock()
    private var received = false
    init(firstFrame: XCTestExpectation) { self.firstFrame = firstFrame }
    func setSize(_ size: CGSize) {}
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard frame != nil else { return }
        lock.lock()
        let first = !received
        received = true
        lock.unlock()
        if first { firstFrame.fulfill() }
    }
}

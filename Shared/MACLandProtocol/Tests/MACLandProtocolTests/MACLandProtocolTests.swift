import Foundation
import XCTest
@testable import MACLandProtocol

final class MACLandProtocolTests: XCTestCase {
    func testHostHelloEnvelopeRoundTripsWithIDsAndSequence() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let requestID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let payload = HostHelloPayload(
            hostID: id,
            hostName: "Studio Mac",
            hostVersion: "2.4.0",
            supportedVersions: [.current],
            capabilities: Capabilities(values: [.displayEnumeration, .screenCapture]),
            permissionState: PermissionState(screenRecording: .granted, accessibility: .denied)
        )
        let original = try ControlEnvelope(
            kind: .hostHello,
            id: id,
            sequence: 42,
            requestID: requestID,
            payload: payload
        )

        let data = try MACLandJSON.makeEncoder().encode(original)
        let decoded = try ControlEnvelope<HostHelloPayload>.decode(from: data, expectedKind: .hostHello)

        XCTAssertEqual(decoded.version, .current)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.sequence, 42)
        XCTAssertEqual(decoded.requestID, requestID)
        XCTAssertEqual(decoded.payload, payload)
    }

    func testPayloadWithDataRoundTrips() throws {
        let payload = ClipboardPayload(
            operation: .changed,
            content: "hello",
            uniformTypeIdentifier: "public.utf8-plain-text",
            data: Data([0, 1, 2, 255])
        )
        let envelope = try ControlEnvelope(kind: .clipboard, sequence: 7, payload: payload)

        let data = try MACLandJSON.makeEncoder().encode(envelope)
        let decoded = try ControlEnvelope<ClipboardPayload>.decode(from: data, expectedKind: .clipboard)

        XCTAssertEqual(decoded.payload, payload)
    }

    func testStableWireEnumValues() {
        XCTAssertEqual(ControlMessageKind.hostHello.rawValue, "host.hello")
        XCTAssertEqual(ControlMessageKind.pairingQRCode.rawValue, "pair.qr")
        XCTAssertEqual(ControlMessageKind.pairingRequest.rawValue, "pair.request")
        XCTAssertEqual(ControlMessageKind.pairingResponse.rawValue, "pair.accept")
        XCTAssertEqual(ControlMessageKind.displayCreate.rawValue, "display.create")
        XCTAssertEqual(ControlMessageKind.appsList.rawValue, "apps.list")
        XCTAssertEqual(ControlMessageKind.windowsList.rawValue, "windows.list")
        XCTAssertEqual(ControlMessageKind.windowCommand.rawValue, "window.command")
        XCTAssertEqual(ControlMessageKind.appLaunch.rawValue, "app.launch")
        XCTAssertEqual(ControlMessageKind.appFocus.rawValue, "app.focus")
        XCTAssertEqual(ControlMessageKind.appClose.rawValue, "app.close")
        XCTAssertEqual(ControlMessageKind.inputBatch.rawValue, "input.batch")
        XCTAssertEqual(ControlMessageKind.mediaOffer.rawValue, "media.offer")
        XCTAssertEqual(ControlMessageKind.mediaAnswer.rawValue, "media.answer")
        XCTAssertEqual(ControlMessageKind.mediaICE.rawValue, "media.ice")
        XCTAssertEqual(ControlMessageKind.sessionResume.rawValue, "session.resume")
        XCTAssertEqual(ControlMessageKind.sessionResumeResponse.rawValue, "session.resume.accept")
        XCTAssertEqual(ControlMessageKind.permissionState.rawValue, "permission.state")
        XCTAssertEqual(PermissionStatus.notDetermined.rawValue, "not_determined")
        XCTAssertEqual(MediaNegotiationKind.renegotiate.rawValue, "renegotiate")
        XCTAssertEqual(ControlErrorCode.unsupportedVersion.rawValue, "unsupported_version")
        XCTAssertEqual(ControlErrorCode.tlsIdentityNotConfigured.rawValue, "tls_identity_not_configured")
    }

    func testRemoteWindowInventoryRoundTrips() throws {
        let payload = WindowsListPayload(windows: [
            RemoteWindowDescriptor(
                id: "840:0",
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                title: "MACLand",
                frame: RemoteWindowFrame(x: 18, y: 32, width: 920, height: 680)
            )
        ])
        let envelope = try ControlEnvelope(kind: .windowsList, sequence: 20, payload: payload)
        let data = try MACLandJSON.makeEncoder().encode(envelope)
        let decoded = try ControlEnvelope<WindowsListPayload>.decode(
            from: data,
            expectedKind: .windowsList
        )

        XCTAssertEqual(decoded.payload, payload)
    }

    func testVersionHelpersAcceptCompatibleMinorAndRejectFutureMajor() throws {
        XCTAssertTrue(ProtocolVersion(major: 1, minor: 0).isCompatible(with: .current))
        XCTAssertThrowsError(try ProtocolVersion(major: 2, minor: 0).validate()) { error in
            XCTAssertEqual(
                error as? ProtocolVersionError,
                .unsupported(version: ProtocolVersion(major: 2, minor: 0), supportedVersions: [.current])
            )
        }
    }

    func testEnvelopeDecodingRejectsUnsupportedVersion() throws {
        let json = #"{"version":"2.0","kind":"heartbeat","id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","sequence":1,"payload":{"kind":"ping","heartbeatID":"11111111-2222-3333-4444-555555555555"}}"#.data(using: .utf8)!

        XCTAssertThrowsError(try ControlEnvelope<HeartbeatPayload>.decode(from: json, expectedKind: .heartbeat)) { error in
            XCTAssertEqual(
                error as? ProtocolVersionError,
                .unsupported(version: ProtocolVersion(major: 2, minor: 0), supportedVersions: [.current])
            )
        }
    }

    func testExpectedKindHelperRejectsMismatchedEnvelope() throws {
        let envelope = try ControlEnvelope(
            kind: .heartbeat,
            sequence: 9,
            payload: HeartbeatPayload(kind: .ping, heartbeatID: UUID())
        )
        let data = try MACLandJSON.makeEncoder().encode(envelope)

        XCTAssertThrowsError(try ControlEnvelope<HeartbeatPayload>.decode(from: data, expectedKind: .error)) { error in
            XCTAssertEqual(
                error as? ControlEnvelopeError,
                .unexpectedKind(expected: .error, actual: .heartbeat)
            )
        }
    }

    func testPairingQRCodeAndResumePayloadsRoundTrip() throws {
        let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let clientID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let certificate = CertificatePinningMetadata(certificateSHA256: "certificate-digest")
        let host = DeviceIdentityMetadata(
            deviceID: hostID,
            deviceName: "Studio Mac",
            platform: .macOS,
            appVersion: "0.1.0"
        )
        let qr = PairingQRCodePayload(
            hostIdentity: host,
            endpoint: "wss://mac.local:443/control",
            pairingCode: "123456",
            certificatePinning: certificate,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            nonce: "nonce"
        )
        let qrData = try MACLandJSON.makeEncoder().encode(qr)
        let decodedQR = try MACLandJSON.makeDecoder().decode(PairingQRCodePayload.self, from: qrData)

        XCTAssertEqual(decodedQR, qr)

        let resume = SessionResumePayload(
            sessionID: hostID,
            clientID: clientID,
            resumeToken: "opaque-resume-token",
            lastReceivedSequence: 12,
            lastSentSequence: 18
        )
        let envelope = try ControlEnvelope(kind: .sessionResume, sequence: 19, payload: resume)
        let decoded = try ControlFrameCodec().decode(
            try ControlFrameCodec().encode(envelope),
            as: SessionResumePayload.self,
            expectedKind: .sessionResume
        )

        XCTAssertEqual(decoded.payload, resume)

        let offer = MediaOfferPayload(sessionID: hostID, sdp: "v=0")
        let offerEnvelope = try ControlEnvelope(kind: .mediaOffer, sequence: 20, payload: offer)
        let decodedOffer = try ControlFrameCodec().decode(
            try ControlFrameCodec().encode(offerEnvelope),
            as: MediaOfferPayload.self,
            expectedKind: .mediaOffer
        )
        XCTAssertEqual(decodedOffer.payload, offer)
    }

    func testControlFrameCodecRejectsOversizedMessages() throws {
        let codec = ControlFrameCodec(maximumFrameSize: 32)
        let envelope = try ControlEnvelope(
            kind: .error,
            sequence: 1,
            payload: ErrorPayload(code: .malformedFrame, message: String(repeating: "x", count: 100))
        )

        XCTAssertThrowsError(try codec.encode(envelope)) { error in
            guard case let ControlFrameError.tooLarge(actual, maximum) = error else {
                return XCTFail("Expected an oversized frame error, got \(error)")
            }
            XCTAssertGreaterThan(actual, maximum)
            XCTAssertEqual(maximum, 32)
        }
    }

    func testTransportStateMachineRequiresPairingAndSupportsResume() throws {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var machine = ControlTransportStateMachine()

        try machine.apply(.start)
        try machine.apply(.transportReady)
        XCTAssertEqual(machine.state, .awaitingPairing)

        try machine.apply(.pairingAccepted(sessionID: sessionID))
        try machine.apply(.transportInterrupted)
        try machine.apply(.transportReady)
        XCTAssertEqual(machine.state, .resuming(sessionID: sessionID))

        try machine.apply(.resumeAccepted(sessionID: sessionID))
        XCTAssertEqual(machine.state, .established(sessionID: sessionID))
    }

    func testRejectedPairingCannotBecomeEstablished() throws {
        var machine = ControlTransportStateMachine()
        try machine.apply(.start)
        try machine.apply(.transportReady)
        try machine.apply(.pairingRejected)

        XCTAssertEqual(machine.state, .failed(.pairingRejected))
        XCTAssertThrowsError(try machine.apply(.pairingAccepted(sessionID: UUID()))) { error in
            XCTAssertEqual(error as? ControlTransportError, .invalidState)
        }
    }
}

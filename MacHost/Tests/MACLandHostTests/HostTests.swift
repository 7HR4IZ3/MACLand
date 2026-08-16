import Foundation
import Network
import XCTest
@testable import MACLandHost

final class HostTests: XCTestCase {
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

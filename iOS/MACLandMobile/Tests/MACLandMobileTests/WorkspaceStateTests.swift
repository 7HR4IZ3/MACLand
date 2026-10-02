import XCTest
@testable import MACLandMobile

@MainActor
final class WorkspaceStateTests: XCTestCase {
    func testMissingInputPermissionShowsNoticeWithoutFailingControlConnection() throws {
        let client = MACLandControlClient()
        var notice: String?
        client.onInputError = { notice = $0 }
        let payload = ErrorPayload(code: .unauthorized, message: "Enable Accessibility on the Mac", retryable: true,
                                   details: ["capability": "input"])
        let envelope = try ControlEnvelope(kind: .error, sequence: 1, payload: payload)
        client.handle(data: try ControlFrameCodec().encode(envelope))
        XCTAssertEqual(notice, payload.message)
        XCTAssertEqual(client.state, .idle)
        XCTAssertNil(client.lastError)
    }

    func testCodePairingUsesResolvedSecureEndpointAndPreservesLeadingZeros() throws {
        let hostID = UUID()
        let pin = String(repeating: "a", count: 64)
        let host = MACLandDiscoveredHost(id: "Mac", name: "Mac", endpointDescription: "wss://mac.local.:58943",
            hostID: hostID, certificateSHA256: pin)
        let payload = try host.pairingPayload(code: " 001234 ")
        XCTAssertEqual(payload.pairingCode, "001234")
        XCTAssertEqual(payload.endpoint, host.endpointDescription)
        XCTAssertEqual(payload.hostIdentity.deviceID, hostID)
        XCTAssertEqual(payload.certificatePinning.certificateSHA256, pin)
        for code in ["", "12345", "1234567", "abcdef", "１２３４５６"] {
            XCTAssertThrowsError(try host.pairingPayload(code: code))
        }
    }

    func testCodePairingRejectsHostsWithoutCertificateMetadata() {
        let oldHost = MACLandDiscoveredHost(id: "Mac", name: "Mac", endpointDescription: "wss://mac.local:58943")
        XCTAssertThrowsError(try oldHost.pairingPayload(code: "123456"))
    }

    func testReturningHostCannotReplaceItsRememberedCertificate() {
        let host = MACLandDiscoveredHost(id: UUID().uuidString, name: "Mac", endpointDescription: "wss://mac.local:58943",
            hostID: UUID(), certificateSHA256: String(repeating: "b", count: 64))
        let key = "macland.trusted-host-pin." + host.id
        UserDefaults.standard.set(String(repeating: "a", count: 64), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let client = MACLandControlClient()
        XCTAssertThrowsError(try client.connect(to: host, code: "123456")) { error in
            XCTAssertEqual(error as? MACLandControlClientError, .certificateChanged)
        }
        XCTAssertEqual(client.state, .idle)
    }

    func testOpeningAWindowFocusesItAndOpeningItAgainDoesNotDuplicateIt() {
        let state = WorkspaceState(initialWindows: [])

        state.openWindow(.settings)
        let settingsID = state.activeWindowID
        state.openWindow(.settings)

        XCTAssertEqual(state.windows.count, 1)
        XCTAssertEqual(state.activeWindowID, settingsID)
        XCTAssertFalse(state.windows[0].isMinimized)
    }

    func testMinimizingAndRestoringWindowUpdatesActiveWindow() throws {
        let remote = WorkspaceWindow(kind: .remoteDisplay)
        let settings = WorkspaceWindow(kind: .settings)
        let state = WorkspaceState(initialWindows: [remote, settings])

        state.focusWindow(remote.id)
        state.minimizeWindow(remote.id)
        XCTAssertEqual(state.activeWindowID, settings.id)
        XCTAssertTrue(try XCTUnwrap(state.windows.first { $0.id == remote.id }).isMinimized)

        state.focusWindow(remote.id)
        XCTAssertEqual(state.activeWindowID, remote.id)
        XCTAssertFalse(try XCTUnwrap(state.windows.first { $0.id == remote.id }).isMinimized)
    }

    func testClosingTheActiveWindowSelectsAnotherVisibleWindow() {
        let remote = WorkspaceWindow(kind: .remoteDisplay)
        let settings = WorkspaceWindow(kind: .settings)
        let state = WorkspaceState(initialWindows: [remote, settings])

        state.focusWindow(settings.id)
        state.closeWindow(settings.id)

        XCTAssertEqual(state.activeWindowID, remote.id)
        XCTAssertEqual(state.windows.map(\.kind), [.remoteDisplay])
    }

    func testLauncherAndTaskSwitcherAreMutuallyExclusive() {
        let state = WorkspaceState()

        state.presentLauncher()
        XCTAssertTrue(state.isLauncherPresented)
        XCTAssertFalse(state.isTaskSwitcherPresented)

        state.toggleTaskSwitcher()
        XCTAssertFalse(state.isLauncherPresented)
        XCTAssertTrue(state.isTaskSwitcherPresented)
    }

    func testPairingConnectionAndDisconnectTransitions() {
        let state = WorkspaceState()

        state.beginPairing()
        XCTAssertEqual(state.connectionState, .pairing(code: ""))
        state.beginConnection()
        XCTAssertEqual(state.connectionState, .connecting)
        state.connect(deviceName: "Test Mac")
        XCTAssertEqual(state.connectionState, .connected(deviceName: "Test Mac"))
        state.disconnect()
        XCTAssertEqual(state.connectionState, .disconnected)
    }
}

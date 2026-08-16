import XCTest
@testable import MACLandMobile

@MainActor
final class WorkspaceStateTests: XCTestCase {
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

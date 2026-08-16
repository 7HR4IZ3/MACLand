import CoreGraphics
import XCTest
@testable import MACLandHost

@MainActor
final class ApplicationWindowControllerTests: XCTestCase {
    func testPlacementClampsWindowToConfiguredDisplayBounds() throws {
        let controller = try WindowPlacementController(
            displayBounds: CGRect(x: 1200, y: 40, width: 1080, height: 1920)
        )

        let frame = controller.targetFrame(
            for: CGRect(x: 900, y: -200, width: 1400, height: 2200)
        )

        XCTAssertEqual(frame, CGRect(x: 1200, y: 40, width: 1080, height: 1920))
    }

    func testLocatingWindowsReturnsTypedSnapshotsForRunningApplication() throws {
        let provider = StubApplicationProvider()
        let client = StubWindowAccessibilityClient()
        client.windowsToReturn = [
            ApplicationWindow(
                id: ApplicationWindowID(processIdentifier: 42, ordinal: 0),
                title: "Editor",
                role: "AXWindow",
                frame: CGRect(x: 30, y: 40, width: 800, height: 600)
            )
        ]
        let controller = try ApplicationWindowController(
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            applicationProvider: provider,
            accessibilityClient: client
        )

        let windows = try controller.locateWindows(for: "com.example.editor")

        XCTAssertEqual(windows.map(\.title), ["Editor"])
        XCTAssertEqual(client.requestedApplications.map(\.bundleIdentifier), ["com.example.editor"])
    }

    func testLifecycleOperationsTargetSelectedWindow() throws {
        let provider = StubApplicationProvider()
        let client = StubWindowAccessibilityClient()
        let controller = try ApplicationWindowController(
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            applicationProvider: provider,
            accessibilityClient: client
        )
        let window = ApplicationWindow(
            id: ApplicationWindowID(processIdentifier: 42, ordinal: 1),
            title: "Selected",
            frame: CGRect(x: 10, y: 20, width: 400, height: 300)
        )

        _ = try controller.place(window: window, in: "com.example.editor")
        try controller.focus(window: window, in: "com.example.editor")
        try controller.minimize(window: window, in: "com.example.editor")
        try controller.restore(window: window, in: "com.example.editor")
        try controller.close(window: window, in: "com.example.editor")

        XCTAssertEqual(client.raisedWindows, [window.id])
        XCTAssertEqual(client.minimizedWindows.map(\.0), [window.id, window.id])
        XCTAssertEqual(client.minimizedWindows.map(\.1), [true, false])
        XCTAssertEqual(client.closedWindows, [window.id])
        XCTAssertEqual(client.placedWindows.first?.id, window.id)
        XCTAssertEqual(provider.activatedApplications, ["com.example.editor"])
    }

    func testAccessibilityPermissionErrorExplainsHowToRecover() throws {
        let provider = StubApplicationProvider()
        let client = StubWindowAccessibilityClient()
        client.isTrusted = false
        let controller = try ApplicationWindowController(
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            applicationProvider: provider,
            accessibilityClient: client
        )

        XCTAssertThrowsError(try controller.locateWindows(for: "com.example.editor")) { error in
            guard case let ApplicationWindowError.accessibility(accessibilityError) = error else {
                return XCTFail("Expected an actionable Accessibility error")
            }
            XCTAssertTrue(accessibilityError.errorDescription?.contains("Privacy & Security > Accessibility") == true)
            XCTAssertTrue(accessibilityError.recoverySuggestion?.contains("enable MACLand Host") == true)
        }
    }

    func testTerminalWindowControlIsDisabledByDefault() throws {
        let controller = try ApplicationWindowController(
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            applicationProvider: StubApplicationProvider(),
            accessibilityClient: StubWindowAccessibilityClient()
        )

        XCTAssertThrowsError(try controller.locateWindows(for: "com.apple.Terminal")) { error in
            guard case let ApplicationWindowError.terminalControlDisabled(bundleIdentifier) = error else {
                return XCTFail("Expected terminal control to remain gated")
            }
            XCTAssertEqual(bundleIdentifier, "com.apple.Terminal")
        }
    }
}

@MainActor
private final class StubApplicationProvider: RunningApplicationProviding {
    let runningApplication = RunningApplicationDescriptor(
        processIdentifier: 42,
        bundleIdentifier: "com.example.editor",
        name: "Editor"
    )
    var activatedApplications: [String] = []

    func application(bundleIdentifier: String) -> RunningApplicationDescriptor? {
        bundleIdentifier == runningApplication.bundleIdentifier ? runningApplication : nil
    }

    func activate(_ application: RunningApplicationDescriptor) -> Bool {
        activatedApplications.append(application.bundleIdentifier)
        return true
    }
}

@MainActor
private final class StubWindowAccessibilityClient: WindowAccessibilityClient {
    var isTrusted = true
    var windowsToReturn: [ApplicationWindow] = []
    var requestedApplications: [RunningApplicationDescriptor] = []
    var placedWindows: [(id: ApplicationWindowID, frame: CGRect)] = []
    var raisedWindows: [ApplicationWindowID] = []
    var minimizedWindows: [(ApplicationWindowID, Bool)] = []
    var closedWindows: [ApplicationWindowID] = []

    func windows(for application: RunningApplicationDescriptor) throws -> [ApplicationWindow] {
        requestedApplications.append(application)
        guard isTrusted else {
            throw AccessibilityError.permissionRequired(
                operation: "locate windows for " + application.bundleIdentifier
            )
        }
        return windowsToReturn
    }

    func setFrame(_ frame: CGRect, for window: ApplicationWindowID) throws {
        placedWindows.append((window, frame))
    }

    func raise(window: ApplicationWindowID) throws {
        raisedWindows.append(window)
    }

    func setMinimized(_ minimized: Bool, for window: ApplicationWindowID) throws {
        minimizedWindows.append((window, minimized))
    }

    func close(window: ApplicationWindowID) throws {
        closedWindows.append(window)
    }
}

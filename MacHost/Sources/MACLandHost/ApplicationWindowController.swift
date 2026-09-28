import AppKit
import ApplicationServices
import Foundation

struct RunningApplicationDescriptor: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let name: String
}

struct ApplicationWindowID: Hashable, Sendable, CustomStringConvertible {
    let processIdentifier: pid_t
    let ordinal: Int

    var description: String {
        "\(processIdentifier):\(ordinal)"
    }
}

struct ApplicationWindow: Identifiable, Equatable {
    let id: ApplicationWindowID
    let title: String
    let role: String?
    let subrole: String?
    let frame: CGRect?
    let isMinimized: Bool

    init(
        id: ApplicationWindowID,
        title: String,
        role: String? = nil,
        subrole: String? = nil,
        frame: CGRect? = nil,
        isMinimized: Bool = false
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.isMinimized = isMinimized
    }
}

enum ApplicationWindowError: LocalizedError, Equatable {
    case applicationNotRunning(bundleIdentifier: String)
    case noWindows(bundleIdentifier: String)
    case windowNotFound(ApplicationWindowID)
    case focusFailed(bundleIdentifier: String)
    case invalidDisplayBounds(CGRect)
    case terminalControlDisabled(bundleIdentifier: String)
    case accessibility(AccessibilityError)

    var errorDescription: String? {
        switch self {
        case let .applicationNotRunning(bundleIdentifier):
            return "Application is not running: " + bundleIdentifier + ". Launch it and try again."
        case let .noWindows(bundleIdentifier):
            return "No accessible windows were found for " + bundleIdentifier + ". Open a window and try again."
        case let .windowNotFound(id):
            return "The selected window is no longer available (\(id.description)). Refresh the application’s windows and try again."
        case let .focusFailed(bundleIdentifier):
            return "macOS could not focus " + bundleIdentifier + ". Confirm the app is running and retry."
        case let .invalidDisplayBounds(bounds):
            return "The configured virtual display bounds are invalid: \(bounds.debugDescription). Set a positive width and height."
        case let .terminalControlDisabled(bundleIdentifier):
            return "Window control for terminal applications is disabled by default: \(bundleIdentifier). Enable it explicitly before controlling terminal windows."
        case let .accessibility(error):
            return error.errorDescription
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .accessibility(error):
            return error.recoverySuggestion
        case .applicationNotRunning, .noWindows, .windowNotFound, .focusFailed,
                .invalidDisplayBounds, .terminalControlDisabled:
            return nil
        }
    }
}

enum AccessibilityError: LocalizedError, Equatable {
    case permissionRequired(operation: String)
    case attributeReadFailed(attribute: String, code: Int32)
    case attributeWriteFailed(attribute: String, code: Int32)
    case actionFailed(action: String, code: Int32)
    case unsupportedAttribute(attribute: String)
    case unavailableWindow(ApplicationWindowID)

    var errorDescription: String? {
        switch self {
        case let .permissionRequired(operation):
            return "Accessibility permission is required to " + operation + ". Enable MACLand Host in System Settings > Privacy & Security > Accessibility, then retry."
        case let .attributeReadFailed(attribute, code):
            return "Accessibility could not read " + attribute + " (AXError " + String(code) + "). Verify the target app is responsive and that MACLand Host is enabled in System Settings > Privacy & Security > Accessibility."
        case let .attributeWriteFailed(attribute, code):
            return "Accessibility could not update " + attribute + " (AXError " + String(code) + "). Verify the target app allows window control and that MACLand Host is enabled in System Settings > Privacy & Security > Accessibility."
        case let .actionFailed(action, code):
            return "Accessibility could not perform " + action + " (AXError " + String(code) + "). Verify the target app is responsive and retry."
        case let .unsupportedAttribute(attribute):
            return "The selected window does not support the Accessibility attribute " + attribute + "."
        case let .unavailableWindow(id):
            return "The selected Accessibility window is no longer available (\(id.description)). Refresh the application’s windows and try again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionRequired:
            return "Open System Settings > Privacy & Security > Accessibility, enable MACLand Host, then refresh the window list."
        case .attributeReadFailed, .attributeWriteFailed, .actionFailed, .unsupportedAttribute, .unavailableWindow:
            return nil
        }
    }
}

struct ApplicationWindowPolicy: Equatable, Sendable {
    var allowsTerminalApplications: Bool

    static let `default` = ApplicationWindowPolicy(allowsTerminalApplications: false)

    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.github.wez.wezterm"
    ]

    func allows(bundleIdentifier: String) -> Bool {
        allowsTerminalApplications || !Self.terminalBundleIdentifiers.contains(bundleIdentifier)
    }
}

@MainActor
protocol RunningApplicationProviding {
    func application(bundleIdentifier: String) -> RunningApplicationDescriptor?
    func activate(_ application: RunningApplicationDescriptor) -> Bool
}

@MainActor
final class WorkspaceRunningApplicationProvider: RunningApplicationProviding {
    func application(bundleIdentifier: String) -> RunningApplicationDescriptor? {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) else {
            return nil
        }

        return RunningApplicationDescriptor(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            name: application.localizedName ?? bundleIdentifier
        )
    }

    func activate(_ application: RunningApplicationDescriptor) -> Bool {
        guard let runningApplication = NSRunningApplication(processIdentifier: application.processIdentifier) else {
            return false
        }

        return runningApplication.activate(options: [.activateAllWindows])
    }
}

@MainActor
protocol WindowAccessibilityClient {
    var isTrusted: Bool { get }

    func windows(for application: RunningApplicationDescriptor) throws -> [ApplicationWindow]
    func setFrame(_ frame: CGRect, for window: ApplicationWindowID) throws
    func raise(window: ApplicationWindowID) throws
    func setMinimized(_ minimized: Bool, for window: ApplicationWindowID) throws
    func close(window: ApplicationWindowID) throws
}

@MainActor
final class AXWindowAccessibilityClient: WindowAccessibilityClient {
    private var elements: [ApplicationWindowID: AXUIElement] = [:]

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func windows(for application: RunningApplicationDescriptor) throws -> [ApplicationWindow] {
        try requireTrust(operation: "locate windows for \(application.bundleIdentifier)")

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let value = try copyAttribute(kAXWindowsAttribute, from: applicationElement)
        guard let windowElements = value as? [AXUIElement] else {
            throw AccessibilityError.attributeReadFailed(
                attribute: kAXWindowsAttribute,
                code: AXError.failure.rawValue
            )
        }

        elements = elements.filter { $0.key.processIdentifier != application.processIdentifier }

        return windowElements.enumerated().map { ordinal, element in
            let id = ApplicationWindowID(
                processIdentifier: application.processIdentifier,
                ordinal: ordinal
            )
            elements[id] = element

            return ApplicationWindow(
                id: id,
                title: (try? stringAttribute(kAXTitleAttribute, from: element)) ?? "Untitled window",
                role: try? stringAttribute(kAXRoleAttribute, from: element),
                subrole: try? stringAttribute(kAXSubroleAttribute, from: element),
                frame: try? frameAttribute(from: element),
                isMinimized: (try? boolAttribute(kAXMinimizedAttribute, from: element)) ?? false
            )
        }
    }

    func setFrame(_ frame: CGRect, for window: ApplicationWindowID) throws {
        try requireTrust(operation: "move and resize a window")
        let element = try element(for: window)

        var position = frame.origin
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw AccessibilityError.attributeWriteFailed(
                attribute: kAXPositionAttribute,
                code: AXError.failure.rawValue
            )
        }
        try setAttribute(kAXPositionAttribute, value: positionValue, on: element)

        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw AccessibilityError.attributeWriteFailed(
                attribute: kAXSizeAttribute,
                code: AXError.failure.rawValue
            )
        }
        try setAttribute(kAXSizeAttribute, value: sizeValue, on: element)
    }

    func raise(window: ApplicationWindowID) throws {
        try requireTrust(operation: "focus a window")
        try perform(kAXRaiseAction, on: try element(for: window))
    }

    func setMinimized(_ minimized: Bool, for window: ApplicationWindowID) throws {
        try requireTrust(operation: minimized ? "minimize a window" : "restore a window")
        try setAttribute(
            kAXMinimizedAttribute,
            value: NSNumber(value: minimized),
            on: try element(for: window)
        )
    }

    func close(window: ApplicationWindowID) throws {
        try requireTrust(operation: "close a window")
        let closeButton = try copyAttribute(kAXCloseButtonAttribute, from: try element(for: window))
        guard CFGetTypeID(closeButton) == AXUIElementGetTypeID() else {
            throw AccessibilityError.unsupportedAttribute(attribute: kAXCloseButtonAttribute)
        }
        try perform(kAXPressAction, on: closeButton as! AXUIElement)
    }

    private func requireTrust(operation: String) throws {
        guard isTrusted else {
            throw AccessibilityError.permissionRequired(operation: operation)
        }
    }

    private func element(for window: ApplicationWindowID) throws -> AXUIElement {
        guard let element = elements[window] else {
            throw AccessibilityError.unavailableWindow(window)
        }
        return element
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) throws -> CFTypeRef {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else {
            throw AccessibilityError.attributeReadFailed(attribute: attribute, code: error.rawValue)
        }
        return value
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) throws -> String {
        let value = try copyAttribute(attribute, from: element)
        guard let string = value as? String else {
            throw AccessibilityError.attributeReadFailed(attribute: attribute, code: AXError.failure.rawValue)
        }
        return string
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) throws -> Bool {
        let value = try copyAttribute(attribute, from: element)
        guard let number = value as? NSNumber else {
            throw AccessibilityError.attributeReadFailed(attribute: attribute, code: AXError.failure.rawValue)
        }
        return number.boolValue
    }

    private func frameAttribute(from element: AXUIElement) throws -> CGRect {
        let positionValue = try copyAttribute(kAXPositionAttribute, from: element)
        let sizeValue = try copyAttribute(kAXSizeAttribute, from: element)
        guard let position = cgPoint(from: positionValue),
              let size = cgSize(from: sizeValue) else {
            throw AccessibilityError.attributeReadFailed(
                attribute: "\(kAXPositionAttribute) + \(kAXSizeAttribute)",
                code: AXError.failure.rawValue
            )
        }
        return CGRect(origin: position, size: size)
    }

    private func cgPoint(from value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func cgSize(from value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func setAttribute(_ attribute: String, value: CFTypeRef, on element: AXUIElement) throws {
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard error == .success else {
            throw AccessibilityError.attributeWriteFailed(attribute: attribute, code: error.rawValue)
        }
    }

    private func perform(_ action: String, on element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, action as CFString)
        guard error == .success else {
            throw AccessibilityError.actionFailed(action: action, code: error.rawValue)
        }
    }
}

@MainActor
final class ApplicationWindowController {
    let policy: ApplicationWindowPolicy

    private let applicationProvider: any RunningApplicationProviding
    private let accessibilityClient: any WindowAccessibilityClient
    private let placementController: WindowPlacementController

    init(
        displayBounds: CGRect,
        policy: ApplicationWindowPolicy = .default,
        applicationProvider: (any RunningApplicationProviding)? = nil,
        accessibilityClient: (any WindowAccessibilityClient)? = nil
    ) throws {
        self.policy = policy
        self.applicationProvider = applicationProvider ?? WorkspaceRunningApplicationProvider()
        self.accessibilityClient = accessibilityClient ?? AXWindowAccessibilityClient()
        placementController = try WindowPlacementController(displayBounds: displayBounds)
    }

    func locateWindows(for bundleIdentifier: String) throws -> [ApplicationWindow] {
        try validate(bundleIdentifier: bundleIdentifier)
        let application = try runningApplication(bundleIdentifier: bundleIdentifier)
        let windows = try withAccessibility {
            try accessibilityClient.windows(for: application)
        }
        guard !windows.isEmpty else {
            throw ApplicationWindowError.noWindows(bundleIdentifier: bundleIdentifier)
        }
        return windows
    }

    @discardableResult
    func place(window: ApplicationWindow, in bundleIdentifier: String) throws -> CGRect {
        let application = try applicationAndValidate(window: window, bundleIdentifier: bundleIdentifier)
        let frame = placementController.targetFrame(for: window.frame)
        try withAccessibility {
            try accessibilityClient.setFrame(
                frame,
                for: validatedWindowID(window.id, application: application)
            )
        }
        return frame
    }

    func focus(window: ApplicationWindow, in bundleIdentifier: String) throws {
        let application = try applicationAndValidate(window: window, bundleIdentifier: bundleIdentifier)
        guard applicationProvider.activate(application) else {
            throw ApplicationWindowError.focusFailed(bundleIdentifier: bundleIdentifier)
        }
        try withAccessibility {
            try accessibilityClient.raise(window: validatedWindowID(window.id, application: application))
        }
    }

    func minimize(window: ApplicationWindow, in bundleIdentifier: String) throws {
        let application = try applicationAndValidate(window: window, bundleIdentifier: bundleIdentifier)
        try withAccessibility {
            try accessibilityClient.setMinimized(
                true,
                for: validatedWindowID(window.id, application: application)
            )
        }
    }

    func restore(window: ApplicationWindow, in bundleIdentifier: String) throws {
        let application = try applicationAndValidate(window: window, bundleIdentifier: bundleIdentifier)
        try withAccessibility {
            try accessibilityClient.setMinimized(
                false,
                for: validatedWindowID(window.id, application: application)
            )
        }
    }

    func close(window: ApplicationWindow, in bundleIdentifier: String) throws {
        let application = try applicationAndValidate(window: window, bundleIdentifier: bundleIdentifier)
        try withAccessibility {
            try accessibilityClient.close(window: validatedWindowID(window.id, application: application))
        }
    }

    private func validate(bundleIdentifier: String) throws {
        guard policy.allows(bundleIdentifier: bundleIdentifier) else {
            throw ApplicationWindowError.terminalControlDisabled(bundleIdentifier: bundleIdentifier)
        }
    }

    private func runningApplication(bundleIdentifier: String) throws -> RunningApplicationDescriptor {
        guard let application = applicationProvider.application(bundleIdentifier: bundleIdentifier) else {
            throw ApplicationWindowError.applicationNotRunning(bundleIdentifier: bundleIdentifier)
        }
        return application
    }

    private func applicationAndValidate(
        window: ApplicationWindow,
        bundleIdentifier: String
    ) throws -> RunningApplicationDescriptor {
        try validate(bundleIdentifier: bundleIdentifier)
        let application = try runningApplication(bundleIdentifier: bundleIdentifier)
        _ = try validatedWindowID(window.id, application: application)
        return application
    }

    private func validatedWindowID(
        _ id: ApplicationWindowID,
        application: RunningApplicationDescriptor
    ) throws -> ApplicationWindowID {
        guard id.processIdentifier == application.processIdentifier else {
            throw ApplicationWindowError.windowNotFound(id)
        }
        return id
    }

    private func withAccessibility<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as ApplicationWindowError {
            throw error
        } catch let error as AccessibilityError {
            throw ApplicationWindowError.accessibility(error)
        }
    }
}

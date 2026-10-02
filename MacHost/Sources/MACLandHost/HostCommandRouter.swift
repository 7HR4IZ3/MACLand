import AppKit
import CoreGraphics
import Foundation

@MainActor
final class HostCommandRouter {
    func hello(hostID: UUID, hostName: String, permissionState: PermissionState) throws -> ControlEnvelope<HostHelloPayload> {
        let payload = HostHelloPayload(
            hostID: hostID,
            hostName: hostName,
            hostVersion: "0.1.0",
            capabilities: Capabilities(),
            permissionState: permissionState
        )
        return try ControlEnvelope(
            kind: .hostHello,
            sequence: 0,
            payload: payload
        )
    }

    func rejectDisplayCommand() -> ErrorPayload {
        ErrorPayload(
            code: .unavailable,
            message: "MACLand cannot create a remote display until the configured third-party driver is installed, approved, and responding.",
            retryable: false,
            details: [
                "capability": "display.create",
                "provider": "voiddisplay-private-api"
            ]
        )
    }
}

struct InputInjector {
    func inject(_ event: InputEvent) throws {
        switch event.kind {
        case .pointerMove, .pointerButton, .scroll:
            try injectPointer(event)
        case .key:
            try injectKey(event)
        case .text:
            throw InputInjectorError.textInjectionUnavailable
        }
    }

    private func injectPointer(_ event: InputEvent) throws {
        try makePointerEvent(event).post(tap: .cghidEventTap)
    }

    // Kept separate so event semantics can be tested without controlling the Mac.
    func makePointerEvent(_ event: InputEvent) throws -> CGEvent {
        guard let location = event.location else { throw InputInjectorError.missingLocation }
        let button = event.button.map(Self.cgButton(for:)) ?? .left
        let type: CGEventType

        switch event.kind {
        case .pointerMove:
            switch event.pressed == true ? event.button : nil {
            case .left: type = .leftMouseDragged
            case .right: type = .rightMouseDragged
            case .middle: type = .otherMouseDragged
            case nil: type = .mouseMoved
            }
        case .pointerButton:
            switch event.button ?? .left {
            case .left: type = event.pressed == true ? .leftMouseDown : .leftMouseUp
            case .right: type = event.pressed == true ? .rightMouseDown : .rightMouseUp
            case .middle: type = event.pressed == true ? .otherMouseDown : .otherMouseUp
            }
        case .scroll:
            type = .scrollWheel
        case .key, .text:
            throw InputInjectorError.unsupportedEvent
        }

        if event.kind == .scroll {
            guard let delta = event.scrollDelta, delta.x.isFinite, delta.y.isFinite else {
                throw InputInjectorError.unsupportedEvent
            }
            guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                      wheel1: Int32(max(-4096, min(4096, delta.y))),
                                      wheel2: Int32(max(-4096, min(4096, delta.x))), wheel3: 0) else {
                throw InputInjectorError.eventCreationFailed
            }
            wheel.location = CGPoint(x: location.x, y: location.y)
            return wheel
        }

        guard let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: location.x, y: location.y),
            mouseButton: button
        ) else { throw InputInjectorError.eventCreationFailed }

        if event.kind == .pointerButton {
            cgEvent.setIntegerValueField(.mouseEventClickState, value: Int64(min(2, max(1, event.clickCount ?? 1))))
        }
        return cgEvent
    }

    private func injectKey(_ event: InputEvent) throws {
        guard let keyCode = event.keyCode,
              let cgEvent = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: event.pressed == true
              ) else { throw InputInjectorError.eventCreationFailed }

        cgEvent.flags = CGEventFlags(rawValue: event.modifiers.reduce(into: UInt64(0)) { result, modifier in
            result |= Self.cgFlags(for: modifier).rawValue
        })
        cgEvent.post(tap: .cghidEventTap)
    }

    private static func cgButton(for button: MouseButton) -> CGMouseButton {
        switch button {
        case .left: .left
        case .right: .right
        case .middle: .center
        }
    }

    private static func cgFlags(for modifier: InputModifier) -> CGEventFlags {
        switch modifier {
        case .shift: .maskShift
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        case .capsLock: .maskAlphaShift
        }
    }
}

enum InputInjectorError: LocalizedError {
    case missingLocation
    case eventCreationFailed
    case textInjectionUnavailable
    case unsupportedEvent

    var errorDescription: String? {
        switch self {
        case .missingLocation: "The input event has no location."
        case .eventCreationFailed: "macOS could not create the input event."
        case .textInjectionUnavailable: "Text input requires a dedicated keyboard/text channel."
        case .unsupportedEvent: "The input event is not supported by this injector."
        }
    }
}

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var state = PermissionState()

    var summary: String {
        "Screen Recording: \(state.screenRecording.rawValue) · Accessibility: \(state.accessibility.rawValue)"
    }

    func refresh() {
        state = PermissionState(
            screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .notDetermined,
            accessibility: AXIsProcessTrusted() ? .granted : .notDetermined,
            inputMonitoring: .unknown,
            notifications: .unknown
        )
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

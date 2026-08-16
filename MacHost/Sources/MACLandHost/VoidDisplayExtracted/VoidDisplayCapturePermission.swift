// MACLand derivative of selected VoidDisplay capture permission concepts.
// Upstream: iamsyc/VoidDisplay @ 1169fcd2e51103746976b2b2cd27c112f3e13082.
import CoreGraphics
import Foundation

enum VoidDisplayCapturePermissionStatus: String, Sendable {
    case notDetermined = "not_determined"
    case granted
}

protocol VoidDisplayCapturePermissionProviding: Sendable {
    func status() -> VoidDisplayCapturePermissionStatus
    func request() -> VoidDisplayCapturePermissionStatus
}

struct SystemVoidDisplayCapturePermissionProvider: VoidDisplayCapturePermissionProviding {
    func status() -> VoidDisplayCapturePermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    func request() -> VoidDisplayCapturePermissionStatus {
        _ = CGRequestScreenCaptureAccess()
        return status()
    }
}

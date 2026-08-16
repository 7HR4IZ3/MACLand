import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = "Not configured"

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = "Enabled"
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Requires approval in System Settings"
        case .notRegistered:
            isEnabled = false
            statusMessage = "Disabled"
        case .notFound:
            isEnabled = false
            statusMessage = "Unavailable for this build"
        @unknown default:
            isEnabled = false
            statusMessage = "Unknown"
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
        refresh()
    }
}

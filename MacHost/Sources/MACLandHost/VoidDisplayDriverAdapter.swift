import Foundation

/// Experimental VoidDisplay-backed provider.
///
/// VoidDisplay currently creates displays through macOS's private
/// CGVirtualDisplay runtime. This adapter is deliberately isolated so the
/// host can be moved to a supported display-driver API later.
@MainActor
final class VoidDisplayDriverAdapter: ThirdPartyDisplayDriverAdapter {
    let identifier = "voiddisplay-private-api"
    let isConfigured = true

    private var activeDisplayID: UInt32?

    var isAvailable: Bool {
        MACLandVoidDisplayRuntimeAvailable()
    }

    func createDisplay(configuration: ThirdPartyDisplayConfiguration) async throws -> UInt32 {
        guard isAvailable else {
            throw RemoteDisplayProviderError.driverUnavailable(identifier)
        }

        guard activeDisplayID == nil else {
            throw RemoteDisplayProviderError.driverCreationFailed
        }

        let serialNumber = UInt32.random(in: 1...UInt32.max)
        let displayName = "MACLand Remote Display (" + configuration.orientation.rawValue.capitalized + ")"
        var displayID: UInt32 = 0
        let created = displayName.withCString { name in
            MACLandVoidDisplayCreate(
                UInt32(max(1, configuration.pixelWidth)),
                UInt32(max(1, configuration.pixelHeight)),
                serialNumber,
                configuration.scaleFactor > 1,
                name,
                &displayID
            )
        }

        guard created, displayID != 0 else {
            throw RemoteDisplayProviderError.driverCreationFailed
        }

        activeDisplayID = displayID
        return displayID
    }

    func reconfigureDisplay(configuration: ThirdPartyDisplayConfiguration) async throws {
        guard isAvailable, activeDisplayID != nil else {
            throw RemoteDisplayProviderError.displayModeControlUnavailable
        }

        let applied = MACLandVoidDisplayReconfigure(
            UInt32(max(1, configuration.pixelWidth)),
            UInt32(max(1, configuration.pixelHeight)),
            configuration.scaleFactor > 1
        )
        guard applied else {
            throw RemoteDisplayProviderError.driverReconfigurationFailed
        }
    }

    func destroyDisplay() async throws {
        guard activeDisplayID != nil else { return }
        MACLandVoidDisplayDestroy()
        activeDisplayID = nil
    }
}

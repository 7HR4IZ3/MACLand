import CoreGraphics
import Foundation

struct ThirdPartyDisplayConfiguration: Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let scaleFactor: Double
    let orientation: DisplayOrientation

    init(
        pixelWidth: Int,
        pixelHeight: Int,
        scaleFactor: Double = 1,
        orientation: DisplayOrientation
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scaleFactor = scaleFactor
        self.orientation = orientation
    }
}

struct DisplayCandidate: Equatable, Sendable {
    let displayID: UInt32
    let pixelWidth: Int
    let pixelHeight: Int
    let isBuiltIn: Bool
}

enum RemoteDisplayProviderStatus: Equatable, Sendable {
    case driverIntegrationRequired
    case candidatesAvailable([DisplayCandidate])
    case ready(DisplayDescriptor)
    case unavailable(String)

    var label: String {
        switch self {
        case .driverIntegrationRequired:
            return "Driver adapter required"
        case let .candidatesAvailable(candidates):
            return String(candidates.count) + " display candidate(s) found"
        case let .ready(display):
            return "Ready: " + display.name
        case let .unavailable(reason):
            return "Unavailable: " + reason
        }
    }
}

enum RemoteDisplayProviderError: LocalizedError, Equatable {
    case vendorAdapterRequired
    case driverUnavailable(String)
    case displayNotFound(UInt32)
    case displayModeControlUnavailable
    case driverCreationFailed
    case driverResponseInvalid
    case driverRequestTimedOut
    case driverReconfigurationFailed

    var errorDescription: String? {
        switch self {
        case .vendorAdapterRequired:
            return "A verified third-party driver adapter is required before MACLand can create or configure a display."
        case let .driverUnavailable(identifier):
            return "The configured display driver is unavailable: " + identifier + "."
        case let .displayNotFound(displayID):
            return "The configured display is not active: " + String(displayID) + "."
        case .displayModeControlUnavailable:
            return "The installed driver does not expose supported display-mode control."
        case .driverCreationFailed:
            return "VoidDisplay could not create or configure the virtual display."
        case .driverResponseInvalid:
            return "The display driver returned an invalid or incomplete response."
        case .driverRequestTimedOut:
            return "The display driver did not respond before the request timed out."
        case .driverReconfigurationFailed:
            return "The display driver could not apply the requested display mode."
        }
    }
}

protocol ActiveDisplayInventory {
    func activeDisplays() -> [DisplayCandidate]
}

@MainActor
protocol ThirdPartyDisplayDriverAdapter: AnyObject {
    var identifier: String { get }
    var isConfigured: Bool { get }
    var isAvailable: Bool { get }

    func createDisplay(configuration: ThirdPartyDisplayConfiguration) async throws -> UInt32
    func reconfigureDisplay(configuration: ThirdPartyDisplayConfiguration) async throws
    func destroyDisplay() async throws
}

extension ThirdPartyDisplayDriverAdapter {
    func reconfigureDisplay(configuration: ThirdPartyDisplayConfiguration) async throws {
        _ = configuration
        throw RemoteDisplayProviderError.displayModeControlUnavailable
    }
}

@MainActor
final class UnconfiguredThirdPartyDisplayDriverAdapter: ThirdPartyDisplayDriverAdapter {
    let identifier = "unconfigured-third-party-driver"
    let isConfigured = false
    let isAvailable = false

    func createDisplay(configuration: ThirdPartyDisplayConfiguration) async throws -> UInt32 {
        _ = configuration
        throw RemoteDisplayProviderError.vendorAdapterRequired
    }

    func destroyDisplay() async throws {
        throw RemoteDisplayProviderError.vendorAdapterRequired
    }
}

struct CoreGraphicsDisplayInventory: ActiveDisplayInventory {
    func activeDisplays() -> [DisplayCandidate] {
        let maximumDisplayCount: UInt32 = 32
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maximumDisplayCount))
        var displayCount: UInt32 = 0

        let result = CGGetActiveDisplayList(
            maximumDisplayCount,
            &displayIDs,
            &displayCount
        )

        guard result == .success else { return [] }

        return displayIDs.prefix(Int(displayCount)).map { displayID in
            DisplayCandidate(
                displayID: displayID,
                pixelWidth: CGDisplayPixelsWide(displayID),
                pixelHeight: CGDisplayPixelsHigh(displayID),
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
            )
        }
    }
}

@MainActor
protocol RemoteDisplayProvider: AnyObject {
    var identifier: String { get }
    var status: RemoteDisplayProviderStatus { get }

    func refresh()
    func create(configuration: ThirdPartyDisplayConfiguration) async throws
    func reconfigure(configuration: ThirdPartyDisplayConfiguration) async throws
    func destroy() async throws
}

@MainActor
final class ThirdPartyDisplayProvider: RemoteDisplayProvider {
    let identifier: String
    private let inventory: ActiveDisplayInventory
    private let driver: ThirdPartyDisplayDriverAdapter
    private(set) var status: RemoteDisplayProviderStatus = .driverIntegrationRequired
    private var selectedDisplayID: UInt32?

    var activeDisplayID: UInt32? { selectedDisplayID }

    var activeDisplayBounds: CGRect? {
        guard let selectedDisplayID else { return nil }
        return CGDisplayBounds(selectedDisplayID)
    }

    var activeDisplayDescriptor: DisplayDescriptor? {
        if case let .ready(display) = status { return display }
        return nil
    }

    init(
        driver: ThirdPartyDisplayDriverAdapter = UnconfiguredThirdPartyDisplayDriverAdapter(),
        inventory: ActiveDisplayInventory = CoreGraphicsDisplayInventory()
    ) {
        self.identifier = driver.identifier
        self.driver = driver
        self.inventory = inventory
    }

    func refresh() {
        guard driver.isConfigured else {
            status = .driverIntegrationRequired
            return
        }

        guard driver.isAvailable else {
            status = .unavailable("Configured display driver is unavailable: " + identifier)
            return
        }

        guard let selectedDisplayID else {
            let candidates = inventory.activeDisplays().filter { !$0.isBuiltIn }
            status = candidates.isEmpty ? .driverIntegrationRequired : .candidatesAvailable(candidates)
            return
        }

        guard let candidate = inventory.activeDisplays().first(where: { $0.displayID == selectedDisplayID }) else {
            status = .unavailable("Configured display is not active")
            return
        }

        status = .ready(Self.makeDescriptor(candidate))
    }

    func create(configuration: ThirdPartyDisplayConfiguration) async throws {
        guard driver.isConfigured else {
            throw RemoteDisplayProviderError.vendorAdapterRequired
        }
        guard driver.isAvailable else {
            throw RemoteDisplayProviderError.driverUnavailable(identifier)
        }

        let displayID = try await driver.createDisplay(configuration: configuration)
        try await waitForDisplayRegistration(displayID)
        selectedDisplayID = displayID
        refresh()
    }

    func reconfigure(configuration: ThirdPartyDisplayConfiguration) async throws {
        guard selectedDisplayID != nil else {
            throw RemoteDisplayProviderError.displayNotFound(0)
        }
        try await driver.reconfigureDisplay(configuration: configuration)
        if let displayID = selectedDisplayID {
            try await waitForDisplayRegistration(displayID)
        }
        refresh()
    }

    func destroy() async throws {
        try await driver.destroyDisplay()
        selectedDisplayID = nil
        refresh()
    }

    private static func makeDescriptor(_ candidate: DisplayCandidate) -> DisplayDescriptor {
        return DisplayDescriptor(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", candidate.displayID)) ?? UUID(),
            name: "Driver display " + String(candidate.displayID),
            pixelWidth: candidate.pixelWidth,
            pixelHeight: candidate.pixelHeight,
            scaleFactor: 1,
            refreshRate: nil
        )
    }

    private func waitForDisplayRegistration(_ displayID: UInt32) async throws {
        // CGVirtualDisplay can return before WindowServer has published the
        // display in CGGetActiveDisplayList. Poll briefly so callers only see
        // success after ScreenCaptureKit and AppKit can discover it too.
        let attempts = 20
        for attempt in 0..<attempts {
            if inventory.activeDisplays().contains(where: {
                $0.displayID == displayID && !$0.isBuiltIn
            }) {
                return
            }
            if attempt < attempts - 1 {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw RemoteDisplayProviderError.displayNotFound(displayID)
    }
}

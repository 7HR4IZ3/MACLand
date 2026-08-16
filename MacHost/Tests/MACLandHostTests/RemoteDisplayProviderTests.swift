import XCTest
@testable import MACLandHost

private struct FakeDisplayInventory: ActiveDisplayInventory {
    var displays: [DisplayCandidate]

    func activeDisplays() -> [DisplayCandidate] {
        displays
    }
}

@MainActor
private final class FakeDisplayDriver: ThirdPartyDisplayDriverAdapter {
    let identifier = "test-driver"
    let isConfigured = true
    let isAvailable: Bool
    let displayID: UInt32
    private(set) var createdConfiguration: ThirdPartyDisplayConfiguration?
    private(set) var destroyCallCount = 0

    init(displayID: UInt32, isAvailable: Bool = true) {
        self.displayID = displayID
        self.isAvailable = isAvailable
    }

    func createDisplay(configuration: ThirdPartyDisplayConfiguration) async throws -> UInt32 {
        createdConfiguration = configuration
        return displayID
    }

    func destroyDisplay() async throws {
        destroyCallCount += 1
    }
}

@MainActor
final class RemoteDisplayProviderTests: XCTestCase {
    func testProviderDoesNotPretendToCreateADisplayWithoutVendorAdapter() async {
        let provider = ThirdPartyDisplayProvider(inventory: FakeDisplayInventory(displays: []))

        provider.refresh()

        XCTAssertEqual(provider.status, .driverIntegrationRequired)
        do {
            try await provider.create(
                configuration: ThirdPartyDisplayConfiguration(
                    pixelWidth: 1080,
                    pixelHeight: 1920,
                    orientation: .portrait
                )
            )
            XCTFail("Expected the unconfigured provider to reject display creation")
        } catch {
            XCTAssertEqual(error as? RemoteDisplayProviderError, .vendorAdapterRequired)
        }
    }

    func testProviderReportsOnlyNonBuiltInDisplaysAsCandidates() {
        let provider = ThirdPartyDisplayProvider(
            driver: FakeDisplayDriver(displayID: 2),
            inventory: FakeDisplayInventory(displays: [
                DisplayCandidate(displayID: 1, pixelWidth: 2560, pixelHeight: 1440, isBuiltIn: true),
                DisplayCandidate(displayID: 2, pixelWidth: 1080, pixelHeight: 1920, isBuiltIn: false)
            ])
        )

        provider.refresh()

        XCTAssertEqual(
            provider.status,
            .candidatesAvailable([
                DisplayCandidate(displayID: 2, pixelWidth: 1080, pixelHeight: 1920, isBuiltIn: false)
            ])
        )
    }

    func testUnavailableConfiguredDriverDoesNotExposeExternalDisplaysAsReady() {
        let provider = ThirdPartyDisplayProvider(
            driver: FakeDisplayDriver(displayID: 42, isAvailable: false),
            inventory: FakeDisplayInventory(displays: [
                DisplayCandidate(displayID: 42, pixelWidth: 1080, pixelHeight: 1920, isBuiltIn: false)
            ])
        )

        provider.refresh()

        XCTAssertEqual(
            provider.status,
            .unavailable("Configured display driver is unavailable: test-driver")
        )
    }

    func testConfiguredAdapterCreatesAndDestroysTheSelectedDisplay() async throws {
        let driver = FakeDisplayDriver(displayID: 42)
        let provider = ThirdPartyDisplayProvider(
            driver: driver,
            inventory: FakeDisplayInventory(displays: [
                DisplayCandidate(displayID: 42, pixelWidth: 1920, pixelHeight: 1080, isBuiltIn: false)
            ])
        )
        let configuration = ThirdPartyDisplayConfiguration(
            pixelWidth: 1920,
            pixelHeight: 1080,
            orientation: .landscape
        )

        try await provider.create(configuration: configuration)

        XCTAssertEqual(driver.createdConfiguration, configuration)
        guard case let .ready(display) = provider.status else {
            return XCTFail("Expected the adapter-created display to be ready")
        }
        XCTAssertEqual(display.pixelWidth, 1920)
        XCTAssertEqual(display.pixelHeight, 1080)

        try await provider.destroy()

        XCTAssertEqual(driver.destroyCallCount, 1)
        XCTAssertEqual(
            provider.status,
            .candidatesAvailable([
                DisplayCandidate(displayID: 42, pixelWidth: 1920, pixelHeight: 1080, isBuiltIn: false)
            ])
        )
    }
}

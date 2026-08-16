import CoreGraphics
import XCTest
@testable import MACLandMobile

final class CoordinateMappingTests: XCTestCase {
    func testAspectFitMappingAccountsForLetterboxing() throws {
        let mapper = RemoteDisplayCoordinateMapper(
            remoteSize: CGSize(width: 1920, height: 1080),
            surfaceSize: CGSize(width: 400, height: 400)
        )

        let touch = try XCTUnwrap(mapper.map(CGPoint(x: 200, y: 200)))

        XCTAssertEqual(touch.remote.x, 960, accuracy: 0.001)
        XCTAssertEqual(touch.remote.y, 540, accuracy: 0.001)
        XCTAssertEqual(touch.normalized.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(touch.normalized.y, 0.5, accuracy: 0.001)
    }

    func testTouchesOutsideRenderedRemoteDisplayAreIgnored() {
        let mapper = RemoteDisplayCoordinateMapper(
            remoteSize: CGSize(width: 1920, height: 1080),
            surfaceSize: CGSize(width: 400, height: 400)
        )

        XCTAssertNil(mapper.map(CGPoint(x: 200, y: 20)))
        XCTAssertNil(mapper.map(CGPoint(x: 20, y: 20)))
        XCTAssertNil(mapper.map(CGPoint(x: 20, y: 380)))
    }

    func testMappingPreservesRemoteCorners() throws {
        let mapper = RemoteDisplayCoordinateMapper(
            remoteSize: CGSize(width: 1000, height: 500),
            surfaceSize: CGSize(width: 500, height: 500)
        )

        let topLeft = try XCTUnwrap(mapper.map(mapper.renderedRect.origin))
        let bottomRight = try XCTUnwrap(mapper.map(CGPoint(x: mapper.renderedRect.maxX, y: mapper.renderedRect.maxY)))

        XCTAssertEqual(topLeft.remote, CGPoint(x: 0, y: 0))
        XCTAssertEqual(bottomRight.remote, CGPoint(x: 1000, y: 500))
    }
}

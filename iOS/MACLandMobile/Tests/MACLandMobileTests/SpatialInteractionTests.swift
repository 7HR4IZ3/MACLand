import XCTest
@testable import MACLandMobile

final class SpatialInteractionTests: XCTestCase {
    private let display = SpatialSurface(id: "display", center: SIMD3(0,0,-2),
        size: SIMD2(2,1), title: "Mac", symbol: "display", isDisplay: true)

    func testCenterAndCornersMapToTopLeftPixelCoordinates() {
        let center = SpatialGeometry.hit(direction: SIMD3(0,0,-1), surfaces: [display])
        XCTAssertEqual(center?.uv, SIMD2(0.5,0.5))
        let topLeft = SpatialGeometry.hit(direction: SIMD3(-1,0.5,-2), surfaces: [display])
        XCTAssertEqual(topLeft?.uv, SIMD2(0,0))
        let bottomRight = SpatialGeometry.hit(direction: SIMD3(1,-0.5,-2), surfaces: [display])
        XCTAssertEqual(bottomRight?.uv, SIMD2(1,1))
    }
    func testBehindParallelOffSurfaceAndInvalidRaysMiss() {
        for ray in [SIMD3<Float>(0,0,1), SIMD3(1,0,0), SIMD3(2,0,-2), SIMD3(.nan,0,-1)] {
            XCTAssertNil(SpatialGeometry.hit(direction: ray, surfaces: [display]))
        }
    }
    func testNearestSurfaceWinsAndEyeOffsetIsAccountedFor() {
        let near = SpatialSurface(id: "dock", center: SIMD3(0,0,-1), size: SIMD2(1,1), title: "Dock", symbol: "app")
        XCTAssertEqual(SpatialGeometry.hit(direction: SIMD3(0,0,-1), surfaces: [display,near])?.id, "dock")
        let leftEye = SpatialGeometry.hit(origin: SIMD3(-0.032,0,0), direction: SIMD3(0.032,0,-2), surfaces: [display])
        XCTAssertEqual(leftEye?.uv.x ?? -1, 0.5, accuracy: 0.0001)
    }
    func testCurvedDisplayUsesArcCoordinatesAndTrueDepth() {
        let radius: Float = 3.2
        let curved = SpatialSurface(id: "curved", center: SIMD3(0,0,-2.5), size: SIMD2(2.4,1.2),
            title: "App", symbol: "app", isDisplay: true, curvatureRadius: radius)
        let angle: Float = 0.3
        let point = SIMD3<Float>(radius * sin(angle), 0.3, -2.5 + radius * (1 - cos(angle)))
        let hit = SpatialGeometry.hit(direction: point, surfaces: [curved])
        XCTAssertEqual(hit?.uv.x ?? -1, 0.5 + radius * angle / 2.4, accuracy: 0.0001)
        XCTAssertEqual(hit?.uv.y ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(hit?.point.z ?? 0, point.z, accuracy: 0.0001)
        XCTAssertNil(SpatialGeometry.hit(direction: SIMD3(3,0,-1), surfaces: [curved]))
    }
    func testDwellFiresOnceAndMovementRearms() {
        var dwell = SpatialDwell()
        XCTAssertFalse(dwell.update(target: "display", point: .zero, time: 0, duration: 1))
        XCTAssertFalse(dwell.update(target: "display", point: .zero, time: 0.8, duration: 1))
        XCTAssertTrue(dwell.update(target: "display", point: .zero, time: 1.01, duration: 1))
        XCTAssertFalse(dwell.update(target: "display", point: .zero, time: 10, duration: 1))
        XCTAssertFalse(dwell.update(target: "display", point: SIMD2(0.04,0), time: 11, duration: 1))
        XCTAssertTrue(dwell.update(target: "display", point: SIMD2(0.04,0), time: 12.01, duration: 1))
    }
    func testChangingTargetOrLeavingCancelsProgress() {
        var dwell = SpatialDwell()
        _ = dwell.update(target: "apps", point: .zero, time: 0, duration: 1)
        XCTAssertFalse(dwell.update(target: "exit", point: .zero, time: 1, duration: 1))
        XCTAssertEqual(dwell.progress, 0)
        _ = dwell.update(target: nil, point: .zero, time: 1.5, duration: 1)
        XCTAssertFalse(dwell.update(target: "exit", point: .zero, time: 2, duration: 1))
    }
    func testSmallJitterDoesNotPreventSelectionAndResetClearsLatch() {
        var dwell = SpatialDwell()
        _ = dwell.update(target: "display", point: .zero, time: 0, duration: 1)
        XCTAssertTrue(dwell.update(target: "display", point: SIMD2(0.005,0.005), time: 1.1, duration: 1))
        dwell.reset()
        XCTAssertFalse(dwell.update(target: "display", point: .zero, time: 20, duration: 1))
        XCTAssertEqual(dwell.progress, 0)
    }
}

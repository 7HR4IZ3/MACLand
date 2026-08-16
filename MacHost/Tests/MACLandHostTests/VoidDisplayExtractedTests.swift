import XCTest
@testable import MACLandHost

final class VoidDisplayExtractedTests: XCTestCase {
    func testCaptureGeometrySwapsOrientationBeforeApplyingScale() throws {
        let logicalSize = VoidDisplayCaptureDimensions(width: 1080, height: 1920)

        XCTAssertEqual(
            try VoidDisplayCaptureGeometry.pixelDimensions(
                logicalSize: logicalSize,
                scaleFactor: 2,
                orientation: .portrait
            ),
            VoidDisplayCaptureDimensions(width: 2160, height: 3840)
        )
        XCTAssertEqual(
            try VoidDisplayCaptureGeometry.pixelDimensions(
                logicalSize: logicalSize,
                scaleFactor: 2,
                orientation: .landscape
            ),
            VoidDisplayCaptureDimensions(width: 3840, height: 2160)
        )
    }

    func testCodecNegotiationMetadataPrefersH264() {
        XCTAssertEqual(
            VoidDisplayCodecNegotiationMetadata.h264First.preferredVideoCodecs.first,
            .h264
        )

        let selected = VoidDisplayCodecNegotiationMetadata.h264First.selectingCommonCodec(
            from: [
                VoidDisplayCodecCapability(codec: .vp8, payloadType: 98),
                VoidDisplayCodecCapability(codec: .h264, payloadType: 102)
            ]
        )

        XCTAssertEqual(selected?.codec, .h264)
        XCTAssertEqual(selected?.payloadType, 102)
    }

    func testCaptureStateReportsPermissionFailureWithoutStartingStream() {
        XCTAssertEqual(
            VoidDisplayCaptureStateMachine.startState(permissionGranted: false),
            .failed(.permissionDenied)
        )
        XCTAssertEqual(
            VoidDisplayCaptureStateMachine.startState(permissionGranted: true),
            .starting
        )
    }

    func testCaptureFailureReportsStableCodeAndDescription() {
        let failure = VoidDisplayCaptureFailure.streamStartFailed("display unavailable")

        XCTAssertEqual(failure.code, "stream_start_failed")
        XCTAssertEqual(
            failure.errorDescription,
            "Screen capture could not start: display unavailable"
        )
    }
}

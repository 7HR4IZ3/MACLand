import CoreGraphics
import Foundation

struct WindowPlacementController {
    let displayBounds: CGRect

    init(displayBounds: CGRect) throws {
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            throw ApplicationWindowError.invalidDisplayBounds(displayBounds)
        }

        self.displayBounds = displayBounds
    }

    /// Returns a frame that keeps the existing window size where possible while
    /// ensuring the whole window is inside the configured display bounds.
    func targetFrame(for currentFrame: CGRect?) -> CGRect {
        guard let currentFrame, currentFrame.width > 0, currentFrame.height > 0 else {
            return displayBounds
        }

        let size = CGSize(
            width: min(currentFrame.width, displayBounds.width),
            height: min(currentFrame.height, displayBounds.height)
        )
        let maximumOrigin = CGPoint(
            x: displayBounds.maxX - size.width,
            y: displayBounds.maxY - size.height
        )
        let origin = CGPoint(
            x: min(max(currentFrame.minX, displayBounds.minX), maximumOrigin.x),
            y: min(max(currentFrame.minY, displayBounds.minY), maximumOrigin.y)
        )

        return CGRect(origin: origin, size: size)
    }
}

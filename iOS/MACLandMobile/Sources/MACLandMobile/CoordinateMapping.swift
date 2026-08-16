import CoreGraphics
import Foundation

public struct RemoteTouchPoint: Equatable, Sendable {
    public let remote: CGPoint
    public let normalized: CGPoint

    public init(remote: CGPoint, normalized: CGPoint) {
        self.remote = remote
        self.normalized = normalized
    }
}

/// Maps a touch in an aspect-fit remote display surface to the remote display's pixels.
public struct RemoteDisplayCoordinateMapper: Equatable, Sendable {
    public let remoteSize: CGSize
    public let surfaceSize: CGSize

    public init(remoteSize: CGSize, surfaceSize: CGSize) {
        self.remoteSize = remoteSize
        self.surfaceSize = surfaceSize
    }

    public var scale: CGFloat {
        guard remoteSize.width > 0, remoteSize.height > 0 else { return 0 }
        return min(
            surfaceSize.width / remoteSize.width,
            surfaceSize.height / remoteSize.height
        )
    }

    public var renderedRect: CGRect {
        let renderedSize = CGSize(
            width: remoteSize.width * scale,
            height: remoteSize.height * scale
        )
        return CGRect(
            x: (surfaceSize.width - renderedSize.width) / 2,
            y: (surfaceSize.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }

    public func map(_ surfacePoint: CGPoint) -> RemoteTouchPoint? {
        guard scale > 0,
              surfacePoint.x >= renderedRect.minX,
              surfacePoint.x <= renderedRect.maxX,
              surfacePoint.y >= renderedRect.minY,
              surfacePoint.y <= renderedRect.maxY
        else { return nil }

        let remotePoint = CGPoint(
            x: min(max((surfacePoint.x - renderedRect.minX) / scale, 0), remoteSize.width),
            y: min(max((surfacePoint.y - renderedRect.minY) / scale, 0), remoteSize.height)
        )
        let normalizedPoint = CGPoint(
            x: remotePoint.x / remoteSize.width,
            y: remotePoint.y / remoteSize.height
        )
        return RemoteTouchPoint(remote: remotePoint, normalized: normalizedPoint)
    }
}

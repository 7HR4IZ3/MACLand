import Foundation

/// A rectangular world-space surface; rendering and input share these bounds.
struct SpatialSurface: Equatable {
    let id: String
    var center: SIMD3<Float>
    var size: SIMD2<Float>
    var title: String
    var symbol: String
    var isDisplay = false
}

struct SpatialHit: Equatable {
    let id: String
    let point: SIMD3<Float>
    let uv: SIMD2<Float>
    let distance: Float
}

enum SpatialGeometry {
    static func hit(origin: SIMD3<Float> = .zero, direction: SIMD3<Float>,
                    surfaces: [SpatialSurface]) -> SpatialHit? {
        guard direction.x.isFinite, direction.y.isFinite, direction.z.isFinite,
              abs(direction.z) > 0.00001 else { return nil }
        return surfaces.compactMap { surface -> SpatialHit? in
            guard surface.size.x > 0, surface.size.y > 0 else { return nil }
            let t = (surface.center.z - origin.z) / direction.z
            guard t > 0 else { return nil }
            let point = origin + t * direction
            let uv = SIMD2<Float>(0.5 + (point.x - surface.center.x) / surface.size.x,
                                  0.5 - (point.y - surface.center.y) / surface.size.y)
            guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { return nil }
            return SpatialHit(id: surface.id, point: point, uv: uv, distance: t)
        }.min { $0.distance < $1.distance }
    }
}

/// Target identity and world hit position both participate in dwell stability.
/// A completed dwell stays latched until the user leaves or moves deliberately.
struct SpatialDwell {
    private var target: String?
    private var anchor = SIMD2<Float>.zero
    private var began = 0.0
    private var fired = false
    private(set) var progress = 0.0

    mutating func reset() { target = nil; progress = 0; fired = false }
    mutating func update(target: String?, point: SIMD2<Float>, time: Double,
                         duration: Double, tolerance: Float = 0.015) -> Bool {
        guard let target, time.isFinite, point.x.isFinite, point.y.isFinite else {
            reset(); return false
        }
        let delta = point - anchor
        if target != self.target || delta.x * delta.x + delta.y * delta.y > tolerance * tolerance || time < began {
            self.target = target; anchor = point; began = time; progress = 0; fired = false
            return false
        }
        guard !fired else { return false }
        progress = min(1, max(0, (time - began) / max(0.4, duration)))
        if progress >= 1 { fired = true; return true }
        return false
    }
}

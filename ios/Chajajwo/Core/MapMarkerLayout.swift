import Foundation
import CoreGraphics

/// Screen-space geometry is independent of the map SDK and never changes a
/// place's geographic coordinate. Only its label receives the returned offset.
struct MapMarkerFootprint {
    let id: String
    let anchor: CGPoint
    let size: CGSize
    let anchorY: CGFloat
    var priority = 0

    var frame: CGRect {
        CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height * anchorY,
               width: size.width, height: size.height)
    }
}

struct MapMarkerPlacement {
    let offset: CGPoint
    let frame: CGRect
}

enum MapMarkerLayout {
    static let gap: CGFloat = 8

    static func place(_ markers: [MapMarkerFootprint], avoiding obstacles: [CGRect],
                      in viewport: CGRect) -> [String: MapMarkerPlacement] {
        var occupied = obstacles.filter { $0.intersects(viewport) }
            .map { $0.insetBy(dx: -gap, dy: -gap) }
        var result: [String: MapMarkerPlacement] = [:]
        for marker in markers.sorted(by: { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }) {
            let base = marker.frame
            if !base.intersects(viewport) || !occupied.contains(where: { $0.intersects(base) }) {
                result[marker.id] = .init(offset: .zero, frame: base)
                if base.intersects(viewport) { occupied.append(base.insetBy(dx: -gap, dy: -gap)) }
                continue
            }
            // Candidate edges sit just outside occupied rectangles, rather than
            // using a fixed geographic displacement that breaks at another zoom.
            var xs: Set<CGFloat> = [0, viewport.minX + 4 - base.minX, viewport.maxX - 4 - base.maxX]
            var ys: Set<CGFloat> = [0, viewport.minY + 4 - base.minY, viewport.maxY - 4 - base.maxY]
            for rect in occupied {
                xs.insert(rect.minX - base.maxX - 1); xs.insert(rect.maxX - base.minX + 1)
                ys.insert(rect.minY - base.maxY - 1); ys.insert(rect.maxY - base.minY + 1)
            }
            let offsets = xs.flatMap { x in ys.map { y in CGPoint(x: x.rounded(), y: y.rounded()) } }
                .sorted {
                    let a = $0.x * $0.x + $0.y * $0.y, b = $1.x * $1.x + $1.y * $1.y
                    if a != b { return a < b }
                    return $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
                }
            let candidates = offsets.filter { viewport.insetBy(dx: 3, dy: 3).contains(base.offsetBy(dx: $0.x, dy: $0.y)) }
            let clear = candidates.first { offset in
                !occupied.contains { $0.intersects(base.offsetBy(dx: offset.x, dy: offset.y)) }
            }
            // Even in an overfull viewport retain every marker; prefer the least
            // obstructed location instead of silently dropping a quest or a cafe.
            let offset = clear ?? candidates.min { a, b in
                overlap(base.offsetBy(dx: a.x, dy: a.y), occupied) < overlap(base.offsetBy(dx: b.x, dy: b.y), occupied)
            } ?? .zero
            let frame = base.offsetBy(dx: offset.x, dy: offset.y)
            result[marker.id] = .init(offset: offset, frame: frame)
            occupied.append(frame.insetBy(dx: -gap, dy: -gap))
        }
        return result
    }

    private static func overlap(_ frame: CGRect, _ occupied: [CGRect]) -> CGFloat {
        occupied.reduce(0) { sum, rect in
            let intersection = frame.intersection(rect)
            return sum + (intersection.isNull ? 0 : intersection.width * intersection.height)
        }
    }
}

/// Calibrate against the SDK's inverse projection so zoom and camera rotation
/// use the same screen units as native marker images and tap coordinates.
struct CampusScreenProjection {
    let center: CGPoint
    let origin: CampusCoordinate
    private let horizontal: (Double, Double)
    private let vertical: (Double, Double)
    private let span: Double
    private let determinant: Double

    init?(center: CGPoint, origin: CampusCoordinate, horizontal: CampusCoordinate,
          vertical: CampusCoordinate, span: Double) {
        let x = (horizontal.longitude - origin.longitude, horizontal.latitude - origin.latitude)
        let y = (vertical.longitude - origin.longitude, vertical.latitude - origin.latitude)
        let determinant = x.0 * y.1 - x.1 * y.0
        guard origin.isValid, horizontal.isValid, vertical.isValid, span > 0,
              determinant.isFinite, abs(determinant) > 1e-20 else { return nil }
        self.center = center; self.origin = origin; self.horizontal = x; self.vertical = y
        self.span = span; self.determinant = determinant
    }

    func point(for coordinate: CampusCoordinate) -> CGPoint {
        let x = coordinate.longitude - origin.longitude, y = coordinate.latitude - origin.latitude
        return CGPoint(x: Double(center.x) + (x * vertical.1 - y * vertical.0) / determinant * span,
                       y: Double(center.y) + (y * horizontal.0 - x * horizontal.1) / determinant * span)
    }
}

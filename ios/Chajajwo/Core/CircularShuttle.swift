import Foundation

struct CampusCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    func distance(to other: Self) -> Double {
        hypot((other.latitude - latitude) * 111195,
              (other.longitude - longitude) * 111195 * cos(latitude * .pi / 180))
    }
    func bearing(to other: Self) -> Double {
        let angle = atan2((other.longitude - longitude) * cos(latitude * .pi / 180), other.latitude - latitude)
        return (angle + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
    }
}

struct CircularRoute: Decodable {
    struct Stop: Decodable {
        let name: String
        let diagram: [Double]
        let geo: [Double]
        var coordinate: CampusCoordinate { .init(latitude: geo[0], longitude: geo[1]) }
    }
    let routeId: String
    let stops: [Stop]
    let segments: [[[Double]]]
    static func load() -> Self? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "circular_route", withExtension: "json"),
              let data = try? Data(contentsOf: url), let route = try? JSONDecoder().decode(Self.self, from: data),
              route.isValid else { return nil }
        return route
    }
    var isValid: Bool {
        routeId == "41946" && stops.count >= 2 && segments.count == stops.count &&
        stops.allSatisfy { $0.diagram.count == 2 && $0.diagram.allSatisfy(\.isFinite) && $0.geo.count == 2 && $0.coordinate.isValid } &&
        segments.allSatisfy { $0.count >= 2 && $0.allSatisfy { $0.count == 2 && CampusCoordinate(latitude: $0[0], longitude: $0[1]).isValid } }
    }
}

struct CircularFeed: Decodable {
    struct Vehicle: Decodable {
        let id: String
        let x: Double
        let y: Double
        var isValid: Bool {
            id.range(of: "^[A-Za-z0-9_.:-]{1,64}$", options: .regularExpression) != nil &&
            x.isFinite && y.isFinite && (90...220).contains(x) && (20...420).contains(y)
        }
    }
    let routeId: String
    let checkedAt: String
    let vehicles: [Vehicle]
    var queryDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: checkedAt) ?? ISO8601DateFormatter().date(from: checkedAt)
    }
    func validated(at now: Date) -> Bool {
        guard routeId == "41946", let date = queryDate else { return false }
        let age = now.timeIntervalSince(date)
        return (-5...20).contains(age) && vehicles.allSatisfy(\.isValid)
    }
}

struct ShuttlePosition: Identifiable {
    let id: String
    let coordinate: CampusCoordinate
    let bearingRadians: Double
    let nextStop: String
    let movementAge: TimeInterval?
    let changes: Int
}

/// Port of the reviewed Android/TypeScript tracker. Pixel matching is separate
/// from road metres. Query times never imply an operator GPS measurement time.
final class CircularShuttleTracker {
    static let interpolation = 1.2
    static let checkpointInterpolation = 8.0
    static let staleAfter = 20.0
    private struct Bus {
        var id: String, x: Double, y: Double, diagram: Double, road: Double, fromRoad: Double
        var animationAt: Double, movedAt: Double, seenAt: Double
        var animationDuration = CircularShuttleTracker.interpolation
        var changes = 0
        var visible = true
        func display(at now: Double) -> Double {
            let t = min(1, max(0, (now - animationAt) / animationDuration))
            return fromRoad + (road - fromRoad) * t * t * (3 - 2 * t)
        }
    }
    let route: CircularRoute
    private var buses: [String: Bus] = [:]
    private var diagramDistances = [0.0]
    private var roadStarts: [Double] = []
    private var roadLengths: [Double] = []
    private var roadPoints: [CampusCoordinate] = []
    private var roadDistances = [0.0]
    private(set) var heldCount = 0
    var totalRoadDistance: Double { roadDistances.last ?? 0 }
    var totalDiagramDistance: Double { diagramDistances.last ?? 0 }
    init(route: CircularRoute) throws {
        guard route.isValid else { throw CocoaError(.coderInvalidValue) }
        self.route = route
        var start = 0.0
        for i in route.stops.indices {
            let a = route.stops[i].diagram, b = route.stops[(i + 1) % route.stops.count].diagram
            diagramDistances.append(diagramDistances.last! + hypot(b[0] - a[0], b[1] - a[1]))
            let points = route.segments[i].map { CampusCoordinate(latitude: $0[0], longitude: $0[1]) }
            let length = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
            roadStarts.append(start); roadLengths.append(length); start += length
            if i + 1 < route.segments.count {
                let p = route.segments[i + 1][0]
                start += points.last!.distance(to: .init(latitude: p[0], longitude: p[1]))
            }
            roadPoints += points
        }
        for i in 1..<roadPoints.count { roadDistances.append(roadDistances.last! + roadPoints[i - 1].distance(to: roadPoints[i])) }
        guard totalRoadDistance > 0, totalDiagramDistance > 0 else { throw CocoaError(.coderInvalidValue) }
    }
    func clear() { buses.removeAll(); heldCount = 0 }
    private func modulo(_ value: Double, _ total: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: total)
        return r < 0 ? r + total : r
    }
    private func segment(_ distance: Double) -> (Int, Double) {
        let d = modulo(distance, totalDiagramDistance)
        let index = max(0, (diagramDistances.indices.dropFirst().first { d <= diagramDistances[$0] } ?? 1) - 1)
        return (index, (d - diagramDistances[index]) / max(0.001, diagramDistances[index + 1] - diagramDistances[index]))
    }
    func roadDistance(atDiagram distance: Double) -> Double {
        let (i, t) = segment(distance)
        return floor(distance / totalDiagramDistance) * totalRoadDistance + roadStarts[i] + roadLengths[i] * t
    }
    func coordinate(at distance: Double) -> CampusCoordinate {
        let d = modulo(distance, totalRoadDistance)
        let i = max(1, roadDistances.indices.dropFirst().first { d <= roadDistances[$0] } ?? 1)
        let a = roadPoints[i - 1], b = roadPoints[i]
        let t = (d - roadDistances[i - 1]) / max(.leastNonzeroMagnitude, roadDistances[i] - roadDistances[i - 1])
        return .init(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
    private func project(_ row: CircularFeed.Vehicle, previous: Double?) -> (distance: Double, error: Double)? {
        var best: (Double, Double, Double)?
        for i in route.stops.indices {
            let a = route.stops[i].diagram, b = route.stops[(i + 1) % route.stops.count].diagram
            let dx = b[0] - a[0], dy = b[1] - a[1], length = dx * dx + dy * dy
            guard length > 0.01 else { continue }
            let t = max(0, min(1, ((row.x - a[0]) * dx + (row.y - a[1]) * dy) / length))
            let error = hypot(row.x - a[0] - t * dx, row.y - a[1] - t * dy)
            var distance = diagramDistances[i] + t * sqrt(length), score = error
            if let previous {
                distance += ((previous - distance) / totalDiagramDistance).rounded() * totalDiagramDistance
                if distance < previous - totalDiagramDistance * 0.5 { distance += totalDiagramDistance }
                if distance > previous + totalDiagramDistance * 0.5 { distance -= totalDiagramDistance }
                let delta = distance - previous
                score += delta < -5 ? 25 + abs(delta) * 0.3 : max(0, delta - 75) * 0.15
            }
            if best == nil || score < best!.2 { best = (distance, error, score) }
        }
        return best.map { ($0.0, $0.1) }
    }
    func update(_ rows: [CircularFeed.Vehicle], at now: Double) {
        var next: [String: Bus] = [:]; heldCount = 0
        for row in rows where row.isValid && next[row.id] == nil {
            var old = buses[row.id]
            if let bus = old, now - bus.seenAt >= Self.staleAfter { old = nil }
            guard let match = project(row, previous: old?.diagram), match.error <= 24 else {
                if var bus = old { bus.visible = false; next[row.id] = bus }
                heldCount += 1; continue
            }
            guard var bus = old else {
                let road = roadDistance(atDiagram: match.distance)
                next[row.id] = Bus(id: row.id, x: row.x, y: row.y, diagram: match.distance, road: road, fromRoad: road, animationAt: now, movedAt: now, seenAt: now)
                continue
            }
            bus.visible = true
            if hypot(row.x - bus.x, row.y - bus.y) >= 0.7 {
                let delta = match.distance - bus.diagram
                let road = roadDistance(atDiagram: max(bus.diagram, match.distance))
                let seconds = max(1, (now - bus.movedAt))
                guard delta >= -5, delta <= max(28, seconds * 7 + 16), road - bus.road <= seconds * 15 + 35 else {
                    bus.visible = false; heldCount += 1; next[row.id] = bus; continue
                }
                if road - bus.road > 0.01 {
                    // Coarse stop-to-stop checkpoints are normal operator updates.
                    // Animate the confirmed road leg instead of teleporting at >38px.
                    bus.fromRoad = bus.display(at: now)
                    bus.animationDuration = delta > 38
                        ? min(Self.checkpointInterpolation, max(Self.interpolation, seconds))
                        : max(Self.interpolation, bus.animationAt + bus.animationDuration - now)
                    bus.diagram = max(bus.diagram, match.distance); bus.road = road
                    bus.animationAt = now; bus.movedAt = now; bus.changes += 1
                    bus.x = row.x; bus.y = row.y
                }
            }
            bus.seenAt = now; next[row.id] = bus
        }
        buses = next
    }
    func isAnimating(at now: Double) -> Bool {
        buses.values.contains { $0.visible && now - $0.seenAt < Self.staleAfter &&
            $0.road - $0.fromRoad > 0.01 && now < $0.animationAt + $0.animationDuration }
    }
    func positions(at now: Double) -> [ShuttlePosition] {
        buses.values.filter { $0.visible && now - $0.seenAt < Self.staleAfter }.sorted { $0.id < $1.id }.map { bus in
            let distance = bus.display(at: now), point = coordinate(at: distance)
            let (index, t) = segment(bus.diagram)
            return ShuttlePosition(id: bus.id, coordinate: point, bearingRadians: point.bearing(to: coordinate(at: distance + 5)),
                                   nextStop: route.stops[(index + (t > 0.999 ? 2 : 1)) % route.stops.count].name,
                                   movementAge: bus.changes > 0 ? max(0, now - bus.movedAt) : nil, changes: bus.changes)
        }
    }
}

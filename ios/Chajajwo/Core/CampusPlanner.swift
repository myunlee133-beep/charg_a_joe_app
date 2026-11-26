import Foundation

struct CampusClass: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// Calendar weekday: Sunday = 1, Monday = 2.
    var weekday: Int
    var startMinute: Int
    var endMinute: Int
    var buildingNumber: String
    var room: String
    var colorIndex: Int = 0
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 80 &&
        (1...7).contains(weekday) && (0..<1440).contains(startMinute) &&
        (1...1440).contains(endMinute) && endMinute > startMinute
    }
}

struct CampusVisitTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var buildingID: String
    var location: String
    var due: Date
    var completed = false
    var reminderEnabled = false
    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 120 && due.timeIntervalSince1970.isFinite }
}

struct CampusPlannerData: Codable, Equatable {
    var classes: [CampusClass] = []
    var tasks: [CampusVisitTask] = []
    var favoriteBuildings: Set<String> = []
}

struct CampusMinuteRange: Equatable, Identifiable {
    var start: Int
    var end: Int
    var id: String { "\(start)-\(end)" }
    var duration: Int { end - start }
    var label: String { "\(CampusPlanning.time(start)) – \(CampusPlanning.time(end))" }
}

enum CampusPlanning {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
    static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    static func minute(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
    static func conflicts(_ candidate: CampusClass, with classes: [CampusClass]) -> Bool {
        classes.contains { $0.id != candidate.id && $0.weekday == candidate.weekday && $0.isValid &&
            candidate.startMinute < $0.endMinute && $0.startMinute < candidate.endMinute }
    }
    static func freeRanges(classes: [CampusClass], weekday: Int, within window: CampusMinuteRange,
                           minimumMinutes: Int = 30) -> [CampusMinuteRange] {
        guard (1...7).contains(weekday), window.start >= 0, window.end <= 1440, window.start < window.end, minimumMinutes > 0 else { return [] }
        let busy = classes.filter { $0.isValid && $0.weekday == weekday && $0.endMinute > window.start && $0.startMinute < window.end }
            .sorted { $0.startMinute < $1.startMinute }
        var cursor = window.start, result: [CampusMinuteRange] = []
        for item in busy {
            if item.startMinute - cursor >= minimumMinutes { result.append(.init(start: cursor, end: min(item.startMinute, window.end))) }
            cursor = max(cursor, item.endMinute)
        }
        if window.end - cursor >= minimumMinutes { result.append(.init(start: cursor, end: window.end)) }
        return result
    }
    static func parseHours(_ text: String) -> [CampusMinuteRange] {
        let pattern = #"(\d{1,2}):(\d{2})\s*[-–~]\s*(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let pieces = (1...4).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
            guard pieces.count == 4, pieces[1] < 60, pieces[3] < 60 else { return nil }
            let a = pieces[0] * 60 + pieces[1], b = pieces[2] * 60 + pieces[3]
            guard a >= 0, a < b, b <= 1440 else { return nil }
            return .init(start: a, end: b)
        }
    }
    static func visitRanges(classes: [CampusClass], weekday: Int, openingHours: [CampusMinuteRange], after: Int = 0) -> [CampusMinuteRange] {
        var merged: [CampusMinuteRange] = []
        for range in openingHours.filter({ $0.start >= 0 && $0.end <= 1440 && $0.start < $0.end }).sorted(by: { $0.start < $1.start }) {
            if let previous = merged.last, range.start <= previous.end { merged[merged.count - 1].end = max(previous.end, range.end) }
            else { merged.append(range) }
        }
        return merged.flatMap { hours -> [CampusMinuteRange] in
            freeRanges(classes: classes, weekday: weekday, within: .init(start: max(hours.start, after), end: hours.end))
        }.sorted { $0.start < $1.start }
    }
    static func nextClass(_ classes: [CampusClass], on date: Date, calendar: Calendar) -> CampusClass? {
        let weekday = calendar.component(.weekday, from: date), now = minute(of: date, calendar: calendar)
        return classes.filter { $0.isValid && $0.weekday == weekday && $0.startMinute > now }
            .min { $0.startMinute < $1.startMinute }
    }
}

struct CampusSpace: Identifiable {
    let id: String
    let name: String
    let building: CampusBuilding
    let floor: String
    let kind: String
    var locationLabel: String { building.buildingNumberLabel + " · " + floor }
    static let all: [CampusSpace] = CampusBuildingCatalog.all.flatMap { building in
        let venues = PlaceDirectory.venues(in: building)
        let cafes = venues.map { CampusSpace(id: $0.id, name: $0.name, building: building, floor: $0.floor, kind: "카페") }
        let facilities = (building.details?.facilities ?? []).compactMap { facility -> CampusSpace? in
            if venues.contains(where: { $0.aliases.contains { facility.name.contains($0) } }) { return nil }
            let name = facility.name
            let kind: String
            if facility.category.contains("카페") || name.contains("카페") { kind = "카페" }
            else if ["도서", "열람", "학습", "스터디"].contains(where: { name.contains($0) }) { kind = "도서·학습" }
            else if name.contains("라운지") { kind = "라운지" }
            else { return nil }
            return CampusSpace(id: facility.id, name: name, building: building, floor: PlaceDirectory.floorName(facility.floor), kind: kind)
        }
        return cafes + facilities
    }
}

struct CampusBuildingPhoto: Codable {
    let buildingID: String
    let photoURL: String
    let sourceURL: String
    let credit: String
    let checkedAt: String
    let assetName: String?
    let sha256: String?
    static let all = PlaceResources.decode("building_photos", as: [CampusBuildingPhoto].self) ?? []
    static func photo(for building: CampusBuilding) -> Self? { all.first { $0.buildingID == building.id } }
    var remoteURL: URL? {
        guard let url = URL(string: photoURL), url.scheme == "https", url.host == "map.snu.ac.kr",
              url.path.hasPrefix("/api/upload/") else { return nil }
        return url
    }
}

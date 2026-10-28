import Foundation

enum DiningMeal: String, CaseIterable {
    case breakfast = "BREAKFAST", lunch = "LUNCH", dinner = "DINNER"
    var title: String { switch self { case .breakfast: "아침"; case .lunch: "점심"; case .dinner: "저녁" } }
    var symbol: String { switch self { case .breakfast: "sunrise"; case .lunch: "sun.max"; case .dinner: "moon" } }
}

/// 웹 수집기(GitHub Actions → /api/meals)가 만든 식단 스냅샷. 날짜가 다른 메뉴로 대체하지 않는다.
struct DiningData: Codable {
    struct Restaurant: Codable {
        let unit: String
        let building: String?
        let buildingName: String?
        let weekdayHours: String
        let saturdayHours: String
        let holidayHours: String
        let latitude: Double?
        let longitude: Double?
    }
    struct Menu: Codable {
        let date: String?          // nil이면 매일 같은 고정 메뉴(푸드코트 등)
        let unit: String
        let building: String?
        let meal: String
        let name: String
        let priceWon: Int?
    }
    let schemaVersion: Int
    let generatedAt: String
    let dates: [String]
    let restaurants: [Restaurant]
    let menus: [Menu]
    private enum CodingKeys: String, CodingKey { case schemaVersion, generatedAt, dates, restaurants, menus }

    /// 건물별 메뉴. 식단 화면을 그릴 때마다 메뉴 7천여 개를 처음부터 훑지 않도록 처음 쓸 때 한 번만 묶어 둔다.
    private final class MenuIndex { var byBuilding: [String: [Menu]]? }
    private let menuIndex = MenuIndex()
    private var menusByBuilding: [String: [Menu]] {
        if let built = menuIndex.byBuilding { return built }
        let built = Dictionary(grouping: menus.filter { $0.building != nil }) { $0.building! }
        menuIndex.byBuilding = built
        return built
    }

    static let updateNeeded = "업데이트 필요"
    /// 아침·점심·저녁 구분 없이 매장별로 한 번에 보여주는 푸드코트 매장.
    private static let foodCourtPrefixes = ["4층 푸드코드 ", "220동식당 "]
    private static let nameOverrides = ["75-1동": "75-1 식당가"]
    static func isFoodCourt(_ unit: String) -> Bool {
        unit == "버거운버거" || foodCourtPrefixes.contains { unit.hasPrefix($0) }
    }
    static func stallName(_ unit: String) -> String {
        foodCourtPrefixes.first { unit.hasPrefix($0) }.map { String(unit.dropFirst($0.count)) } ?? unit
    }

    static let endpoint = URL(string: "https://raw.githubusercontent.com/myunlee133-beep/chajajwo-meals-data/main/meals.json")!
    fileprivate static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("meals.json")
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    static func decode(_ data: Data) -> DiningData? {
        guard let snapshot = try? JSONDecoder().decode(DiningData.self, from: data),
              snapshot.schemaVersion == 1, !snapshot.menus.isEmpty else { return nil }
        return snapshot
    }

    /// 앱에 포함된 스냅샷. 오프라인 첫 실행용이자 식당 위치 목록의 기준.
    static let bundled: DiningData = {
        guard let url = Bundle.main.url(forResource: "meals", withExtension: "json"),
              let data = try? Data(contentsOf: url), let snapshot = decode(data) else {
            return DiningData(schemaVersion: 1, generatedAt: "", dates: [], restaurants: [], menus: [])
        }
        return snapshot
    }()

    /// 마지막으로 받아 둔 스냅샷. 번들보다 오래됐으면 번들을 쓴다.
    static func startup() -> DiningData {
        guard let data = try? Data(contentsOf: cacheURL), let cached = decode(data),
              cached.generatedAt > bundled.generatedAt else { return bundled }
        return cached
    }

    static func fetch() async -> DiningData? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, let fresh = decode(data) else { return nil }
        return fresh
    }

    /// 새로 받은 스냅샷을 합쳐 저장한다. 전체 기간(과거 한 달~앞으로 2주)을 가진 스냅샷이면 통째로 교체하고,
    /// 며칠치만 담긴 스냅샷이면 그 날짜만 덮어써서 나머지 기간 데이터를 유지한다.
    func merged(with fresh: DiningData) -> DiningData {
        guard fresh.dates.count < dates.count else { return fresh }
        let freshDates = Set(fresh.dates)
        let kept = menus.filter { $0.date == nil || !freshDates.contains($0.date!) }
        return DiningData(schemaVersion: 1, generatedAt: fresh.generatedAt, dates: dates,
                          restaurants: fresh.restaurants, menus: kept + fresh.menus)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.cacheURL, options: .atomic) }
    }

    /// 식단 화면에서 넘겨 볼 수 있는 범위: 오늘 기준 과거 한 달, 앞으로 2주.
    static let pastDays = 30, futureDays = 14
    static func canShow(_ date: Date, offset: Int) -> Bool {
        guard let target = calendar.date(byAdding: .day, value: offset, to: date) else { return false }
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: target)).day ?? 0
        return days >= -pastDays && days <= futureDays
    }

    /// 좌표가 있는 식당을 건물 단위로 묶어 지도 핀으로 만든다. 새 건물이 생기면 앱 업데이트가 필요하다.
    // ponytail: 핀 목록은 번들 기준. 신규 식당 핀까지 즉시 반영하려면 Place.all을 동적으로 바꿔야 함.
    var foodPlaces: [Place] {
        var order: [String] = []
        var groups: [String: [Restaurant]] = [:]
        for r in restaurants where r.latitude != nil && r.longitude != nil {
            guard let building = r.building else { continue }
            if groups[building] == nil { order.append(building) }
            groups[building, default: []].append(r)
        }
        return order.map { building in
            let group = groups[building]!
            let heads = Set(group.map { $0.unit.split(separator: " ").first.map(String.init) ?? $0.unit })
            let name = group.count == 1 ? group[0].unit : heads.count == 1 ? heads.first! : (group[0].buildingName ?? building)
            return Place(id: "meal-\(building)", type: .food, name: Self.nameOverrides[building] ?? name,
                         lat: group[0].latitude!, lng: group[0].longitude!, building: building)
        }
    }

    /// foodCourt: nil이면 건물 전체, true/false면 푸드코트 매장만/일반 식당만.
    private func restaurants(in place: Place, foodCourt: Bool? = nil) -> [Restaurant] {
        restaurants.filter { $0.building == place.building && (foodCourt == nil || Self.isFoodCourt($0.unit) == foodCourt) }
    }

    func hasUnits(in place: Place, foodCourt: Bool) -> Bool { !restaurants(in: place, foodCourt: foodCourt).isEmpty }

    /// "09 :00-20:00" 같은 표기 흔들림을 바로잡고, 괄호 설명(브레이크타임 등)과 문장은 버린 운영 구간들.
    private static func ranges(in schedule: String) -> [String] {
        let text = schedule
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*:\s*"#, with: ":", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*"#, with: "-", options: .regularExpression)
        return text.split(whereSeparator: \.isWhitespace).compactMap { token in
            let times = token.split(separator: "-").map { $0.split(separator: ":").compactMap { Int($0) } }
            guard times.count == 2, times.allSatisfy({ $0.count == 2 }) else { return nil }
            return String(format: "%02d:%02d-%02d:%02d", times[0][0], times[0][1], times[1][0], times[1][1])
        }
    }

    static func dateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    private func dayMenus(for place: Place, on date: Date) -> [Menu] {
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        return (menusByBuilding[place.building] ?? []).filter { $0.date == key || $0.date == nil }
    }

    func menus(for place: Place, on date: Date, meal: DiningMeal) -> [Menu] {
        var seen = Set<String>()
        return dayMenus(for: place, on: date)
            .filter { $0.meal == meal.rawValue && !Self.isFoodCourt($0.unit) }
            .filter { seen.insert("\($0.unit)|\($0.name)|\($0.priceWon ?? 0)").inserted }
    }

    /// 푸드코트는 끼니 구분 없이 매장별 메뉴 전부. 끼니마다 중복된 메뉴는 한 번만.
    func foodCourtMenus(for place: Place, on date: Date) -> [(stall: String, menus: [Menu])] {
        var seen = Set<String>(), order: [String] = [], byUnit: [String: [Menu]] = [:]
        for menu in dayMenus(for: place, on: date) where Self.isFoodCourt(menu.unit) {
            guard seen.insert("\(menu.unit)|\(menu.name)|\(menu.priceWon ?? 0)").inserted else { continue }
            if byUnit[menu.unit] == nil { order.append(menu.unit) }
            byUnit[menu.unit, default: []].append(menu)
        }
        return order.map { (Self.stallName($0), byUnit[$0]!) }
    }

    /// 건물 안 식당들의 운영 구간을 합친 시간표. 구간이 하나도 없으면 휴관 또는 "업데이트 필요".
    func hours(for place: Place, on date: Date, foodCourt: Bool? = nil) -> String {
        let schedules = restaurants(in: place, foodCourt: foodCourt).map { r -> String in
            switch Self.calendar.component(.weekday, from: date) {
            case 1: r.holidayHours
            case 7: r.saturdayHours
            default: r.weekdayHours
            }
        }
        let ranges = Set(schedules.flatMap(Self.ranges)).sorted()
        if !ranges.isEmpty { return ranges.joined(separator: " ") }
        return schedules.contains { $0.contains("휴관") } ? "휴관" : Self.updateNeeded
    }

    func foodCourtHours(for place: Place, on date: Date) -> String {
        let schedule = hours(for: place, on: date, foodCourt: true)
        if schedule == "휴관" { return "휴무" }
        return schedule == Self.updateNeeded ? schedule : schedule.split(separator: " ").joined(separator: " · ").replacingOccurrences(of: "-", with: "–")
    }

    func hours(for place: Place, on date: Date, meal: DiningMeal) -> String {
        let schedule = hours(for: place, on: date, foodCourt: false)
        if schedule == "휴관" { return "휴무" }
        if schedule == Self.updateNeeded { return schedule }
        let ranges = schedule.split(separator: " ").filter { range in
            guard let hour = Int(range.prefix(2)) else { return false }
            switch meal {
            case .breakfast: return hour < 10
            case .lunch: return hour >= 10 && hour < 16
            case .dinner: return hour >= 16
            }
        }
        return ranges.isEmpty ? "운영 없음" : ranges.joined(separator: " · ").replacingOccurrences(of: "-", with: "–")
    }

    func status(for place: Place, at date: Date) -> (title: String, isOpen: Bool) {
        let hours = hours(for: place, on: date)
        if hours.contains("휴관") { return ("휴무", false) }
        let intervals = hours.split(separator: " ").compactMap { range -> (Int, Int)? in
            let times = range.split(separator: "-").compactMap { time -> Int? in
                let parts = time.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                return parts[0] * 60 + parts[1]
            }
            guard times.count == 2 else { return nil }
            return (times[0], times[1])
        }
        guard !intervals.isEmpty else { return (Self.updateNeeded, false) }
        let parts = Self.calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let isOpen = intervals.contains { minute >= $0.0 && minute < $0.1 }
        // 정규 시간표 기반 상태. 공휴일·임시 휴무는 별도 확인이 필요하다.
        return (isOpen ? "운영 중" : "운영 종료", isOpen)
    }
}

import SwiftUI
import UserNotifications

final class CampusPlannerStore: ObservableObject {
    @Published private(set) var data: CampusPlannerData
    @Published var message: String?
    private let defaults: UserDefaults
    private let key = "cj_campus_planner_v1"
    static let shared = CampusPlannerStore()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(CampusPlannerData.self, from: saved) {
            data = decoded
            data.classes = decoded.classes.filter(\.isValid)
            data.tasks = decoded.tasks.filter(\.isValid)
        } else { data = CampusPlannerData() }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(data) { defaults.set(encoded, forKey: key) }
    }
    func toggleFavorite(_ building: CampusBuilding) {
        if data.favoriteBuildings.contains(building.id) { data.favoriteBuildings.remove(building.id) }
        else { data.favoriteBuildings.insert(building.id) }
        save()
    }
    func upsert(_ item: CampusClass) {
        guard item.isValid else { return }
        data.classes.removeAll { $0.id == item.id }; data.classes.append(item); save()
    }
    func removeClass(_ id: UUID) { data.classes.removeAll { $0.id == id }; save() }
    func upsert(_ task: CampusVisitTask) {
        guard task.isValid else { return }
        // Changing the time never silently keeps an outdated pending alert.
        cancelReminder(task.id)
        var task = task; task.reminderEnabled = false
        data.tasks.removeAll { $0.id == task.id }; data.tasks.append(task); save()
    }
    func toggleCompleted(_ id: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[i].completed.toggle()
        if data.tasks[i].completed { cancelReminder(id); data.tasks[i].reminderEnabled = false }
        save()
    }
    func removeTask(_ id: UUID) { cancelReminder(id); data.tasks.removeAll { $0.id == id }; save() }
    private func cancelReminder(_ id: UUID) {
        let key = "campus-visit-" + id.uuidString
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [key])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [key])
    }
    @MainActor func toggleReminder(_ id: UUID) async {
        guard let task = data.tasks.first(where: { $0.id == id }), !task.completed else { return }
        if task.reminderEnabled {
            cancelReminder(id)
            if let i = data.tasks.firstIndex(where: { $0.id == id }) { data.tasks[i].reminderEnabled = false; save() }
            return
        }
        guard task.due > Date().addingTimeInterval(60) else { message = "알림은 1분 이후 시간으로 설정해 주세요."; return }
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { message = "알림이 꺼져 있어요. iPhone 설정에서 찾아줘 알림을 허용해 주세요."; return }
            let content = UNMutableNotificationContent()
            content.title = "방문할 시간이에요"
            content.body = task.title + (task.location.isEmpty ? "" : " · " + task.location)
            content.sound = .default
            let components = CampusPlanning.calendar.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: task.due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: "campus-visit-" + id.uuidString, content: content, trigger: trigger))
            guard let i = data.tasks.firstIndex(where: { $0.id == id }), !data.tasks[i].completed, data.tasks[i].due == task.due else {
                cancelReminder(id); return
            }
            data.tasks[i].reminderEnabled = true; save()
        } catch { message = "알림을 저장하지 못했어요. 잠시 후 다시 시도해 주세요." }
    }

    func tasks(in building: CampusBuilding, completed: Bool = false) -> [CampusVisitTask] {
        data.tasks.filter { $0.buildingID == building.id && $0.completed == completed }.sorted { $0.due < $1.due }
    }
}

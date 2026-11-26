import SwiftUI

struct CampusTaskRow: View {
    let task: CampusVisitTask
    @EnvironmentObject private var planner: CampusPlannerStore
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { planner.toggleCompleted(task.id) } label: {
                Image(systemName: task.completed ? "checkmark.square.fill" : "square").font(.title2).frame(width: 36, height: 44)
            }.accessibilityLabel(task.completed ? "할 일 완료 취소" : "할 일 완료")
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title).font(.subheadline.weight(.semibold)).strikethrough(task.completed).foregroundStyle(.primary)
                if !task.location.isEmpty { Text(task.location).font(.caption).foregroundStyle(.secondary) }
                Text(task.due, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
            if !task.completed {
                Button { Task { await planner.toggleReminder(task.id) } } label: {
                    Image(systemName: task.reminderEnabled ? "bell.badge.fill" : "bell").frame(width: 44, height: 44)
                        .background(BuildingDesign.mint, in: Circle())
                }.accessibilityLabel(task.reminderEnabled ? "방문 알림 해제" : "방문 알림 설정")
            }
        }
    }
}

struct CampusTaskListView: View {
    let building: CampusBuilding
    @EnvironmentObject private var planner: CampusPlannerStore
    @State private var completed = false
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("할 일 상태", selection: $completed) { Text("할 일 목록").tag(false); Text("완료한 일").tag(true) }.pickerStyle(.segmented)
                let tasks = planner.tasks(in: building, completed: completed)
                if tasks.isEmpty {
                    BuildingEmptyCard(symbol: "checklist", title: completed ? "완료한 일이 없어요" : "방문할 일을 기록해 보세요", text: completed ? "마친 일은 여기에 모아둘게요." : "식사, 서점 방문, 팀플 준비처럼 이 건물에서 할 일을 추가하세요.")
                }
                ForEach(tasks) { task in
                    BuildingSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            CampusTaskRow(task: task)
                            HStack {
                                NavigationLink("수정") { CampusTaskEditorView(building: building, task: task) }
                                Spacer()
                                Button("삭제", role: .destructive) { planner.removeTask(task.id) }
                            }.font(.caption).frame(minHeight: 36)
                        }
                    }
                }
                BuildingSurface {
                    Label("종 아이콘을 누르면 설정한 시간에 이 기기로 방문 알림을 보내드려요.", systemImage: "bell")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(18)
        }
        .background(BuildingDesign.canvas).navigationTitle("할 일 & 알림").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            NavigationLink { CampusTaskEditorView(building: building) } label: {
                Label("할 일 추가", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    .background(BuildingDesign.green, in: Capsule()).foregroundStyle(.white)
            }.padding(16).background(.regularMaterial).accessibilityIdentifier("planner.add-task")
        }
    }
}

struct CampusTaskEditorView: View {
    let building: CampusBuilding
    private let original: CampusVisitTask?
    @EnvironmentObject private var planner: CampusPlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var location: String
    @State private var due: Date
    init(building: CampusBuilding, task: CampusVisitTask? = nil, presetTitle: String = "", presetLocation: String = "") {
        self.building = building; original = task
        _title = State(initialValue: task?.title ?? presetTitle)
        _location = State(initialValue: task?.location ?? presetLocation)
        _due = State(initialValue: task?.due ?? Date().addingTimeInterval(3600))
    }
    var body: some View {
        Form {
            Section("무엇을 할까요?") {
                TextField("예: 학생회관 식당에서 점심 먹기", text: $title).accessibilityIdentifier("task.title")
                Text(building.displayTitle).font(.subheadline).foregroundStyle(.secondary)
                TextField("층·공간 이름 (선택)", text: $location).accessibilityIdentifier("task.location")
                DatePicker("방문 시간", selection: $due, displayedComponents: [.date, .hourAndMinute])
            }
            Section {} footer: { Text("할 일은 이 기기에 저장돼요. 저장 후 종 아이콘을 누르면 방문 알림을 설정할 수 있어요.") }
            Section {
                Button("저장") {
                    var task = original ?? CampusVisitTask(title: title, buildingID: building.id, location: location, due: due)
                    task.title = title.trimmingCharacters(in: .whitespacesAndNewlines); task.location = location; task.due = due
                    planner.upsert(task); dismiss()
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120)
                    .accessibilityIdentifier("task.save")
            }
        }.navigationTitle(original == nil ? "할 일 추가" : "할 일 수정").navigationBarTitleDisplayMode(.inline)
    }
}

struct CampusTimetableView: View {
    let building: CampusBuilding
    @EnvironmentObject private var planner: CampusPlannerStore
    @State private var recommendations: Bool
    init(building: CampusBuilding, initialRecommendations: Bool = false) {
        self.building = building; _recommendations = State(initialValue: initialRecommendations)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("시간표 보기", selection: $recommendations) {
                    Text("주간 시간표").tag(false); Text("방문 추천 시간").tag(true)
                }.pickerStyle(.segmented)
                if recommendations { CampusVisitRecommendations(building: building) }
                else {
                    if planner.data.classes.isEmpty {
                        BuildingEmptyCard(symbol: "calendar.badge.plus", title: "내 수업을 추가해 보세요", text: "수업 사이의 공강을 찾아 방문할 수 있는 시간을 안내해 드려요.")
                    }
                    CampusWeekGrid(classes: planner.data.classes)
                    ForEach(planner.data.classes.sorted { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }) { item in
                        NavigationLink { CampusClassEditorView(item: item) } label: {
                            BuildingSurface {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 3).fill(CampusWeekGrid.colors[max(0, item.colorIndex) % 5]).frame(width: 5)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.headline).foregroundStyle(.primary)
                                        Text("\(CampusWeekGrid.dayName(item.weekday)) · \(CampusPlanning.time(item.startMinute))–\(CampusPlanning.time(item.endMinute))")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        if !item.buildingNumber.isEmpty { Text("\(item.buildingNumber)동 \(item.room)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Text("직접 등록한 일정만 사용하며 시간표는 이 기기에 저장돼요.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.background(BuildingDesign.canvas).navigationTitle("내 시간표").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { CampusClassEditorView() } label: { Label("수업 추가", systemImage: "plus") }.accessibilityIdentifier("planner.add-class")
                }
            }
    }
}

struct CampusWeekGrid: View {
    let classes: [CampusClass]
    @Environment(\.dynamicTypeSize) private var typeSize
    static let colors: [Color] = [Color(hex: 0xdce8ff), Color(hex: 0xffedbc), Color(hex: 0xcdebe1), Color(hex: 0xe6ddfa), Color(hex: 0xffdcbf)]
    static func dayName(_ weekday: Int) -> String { ["일", "월", "화", "수", "목", "금", "토"][max(0, min(6, weekday - 1))] }
    private var days: [Int] { classes.contains { $0.weekday == 1 || $0.weekday == 7 } ? [2, 3, 4, 5, 6, 7, 1] : [2, 3, 4, 5, 6] }
    private var firstHour: Int { min(8, classes.map { $0.startMinute / 60 }.min() ?? 8) }
    private var lastHour: Int { min(24, max(21, classes.map { ($0.endMinute + 59) / 60 }.max() ?? 21)) }
    var body: some View {
        if !typeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("").frame(width: 30)
                    ForEach(days, id: \.self) { Text(Self.dayName($0)).font(.caption.weight(.semibold)).frame(maxWidth: .infinity) }
                }.frame(height: 34).background(Color(uiColor: .secondarySystemGroupedBackground))
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(firstHour..<lastHour, id: \.self) { Text("\($0)시").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 30, height: 48, alignment: .top) }
                    }
                    GeometryReader { proxy in
                        let width = proxy.size.width / CGFloat(days.count)
                        ZStack(alignment: .topLeading) {
                            Path { p in
                                for i in 0...days.count { p.move(to: .init(x: CGFloat(i) * width, y: 0)); p.addLine(to: .init(x: CGFloat(i) * width, y: proxy.size.height)) }
                                for hour in firstHour...lastHour { let y = CGFloat(hour - firstHour) * 48; p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: proxy.size.width, y: y)) }
                            }.stroke(BuildingDesign.line, lineWidth: 0.6)
                            ForEach(classes.filter(\.isValid)) { item in
                                if let day = days.firstIndex(of: item.weekday) {
                                    Text(item.title + (item.room.isEmpty ? "" : "\n" + item.room))
                                        .font(.system(size: 10, weight: .medium)).padding(4).frame(width: max(1, width - 3), height: max(4, CGFloat(item.endMinute - item.startMinute) / 60 * 48 - 2), alignment: .topLeading)
                                        .background(Self.colors[max(0, item.colorIndex) % 5], in: RoundedRectangle(cornerRadius: 4)).clipped()
                                        .offset(x: CGFloat(day) * width + 1, y: CGFloat(item.startMinute - firstHour * 60) / 60 * 48 + 1)
                                }
                            }
                        }
                    }.frame(height: CGFloat(lastHour - firstHour) * 48)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(BuildingDesign.line))
                .accessibilityHidden(true)
            Text("주간 미리보기 · 아래 수업을 선택하면 수정할 수 있어요.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CampusClassEditorView: View {
    private let original: CampusClass?
    @EnvironmentObject private var planner: CampusPlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var weekday: Int
    @State private var start: Date
    @State private var end: Date
    @State private var buildingNumber: String
    @State private var room: String
    init(item: CampusClass? = nil) {
        original = item
        _title = State(initialValue: item?.title ?? "")
        _weekday = State(initialValue: item?.weekday ?? CampusPlanning.calendar.component(.weekday, from: Date()))
        let day = CampusPlanning.calendar.startOfDay(for: Date())
        _start = State(initialValue: day.addingTimeInterval(Double(item?.startMinute ?? 540) * 60))
        _end = State(initialValue: day.addingTimeInterval(Double(item?.endMinute ?? 600) * 60))
        _buildingNumber = State(initialValue: item?.buildingNumber ?? "")
        _room = State(initialValue: item?.room ?? "")
    }
    private var candidate: CampusClass {
        var value = original ?? CampusClass(title: title, weekday: weekday, startMinute: 0, endMinute: 0, buildingNumber: buildingNumber, room: room, colorIndex: planner.data.classes.count % 5)
        value.title = title; value.weekday = weekday
        value.startMinute = CampusPlanning.minute(of: start, calendar: CampusPlanning.calendar)
        let endMinute = CampusPlanning.minute(of: end, calendar: CampusPlanning.calendar)
        value.endMinute = endMinute == 0 && value.startMinute > 0 ? 1440 : endMinute
        value.buildingNumber = buildingNumber.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "동", with: "")
        value.room = room; return value
    }
    var body: some View {
        Form {
            Section("수업 정보") {
                TextField("수업명", text: $title).accessibilityIdentifier("class.title")
                Picker("요일", selection: $weekday) { ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(CampusWeekGrid.dayName($0) + "요일").tag($0) } }
                DatePicker("시작", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("종료", selection: $end, displayedComponents: .hourAndMinute)
                TextField("건물 번호 (선택)", text: $buildingNumber).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("class.building")
                TextField("호실 (선택)", text: $room).accessibilityIdentifier("class.room")
            }
            if !title.isEmpty && !candidate.isValid { Text("수업명과 시작·종료 시간을 확인해 주세요. 자정을 넘는 수업은 요일별로 나눠 등록하세요.").font(.caption).foregroundStyle(.red) }
            if CampusPlanning.conflicts(candidate, with: planner.data.classes) { Text("등록된 수업과 시간이 겹쳐요.").font(.caption).foregroundStyle(.red) }
            Section {
                Button("저장") { planner.upsert(candidate); dismiss() }
                    .disabled(!candidate.isValid || CampusPlanning.conflicts(candidate, with: planner.data.classes)).accessibilityIdentifier("class.save")
                if let original { Button("수업 삭제", role: .destructive) { planner.removeClass(original.id); dismiss() } }
            }
        }.navigationTitle(original == nil ? "수업 추가" : "수업 수정").navigationBarTitleDisplayMode(.inline)
    }
}

struct CampusVisitRecommendations: View {
    let building: CampusBuilding
    @EnvironmentObject private var planner: CampusPlannerStore
    @EnvironmentObject private var store: Store
    @State private var weekday = CampusPlanning.calendar.component(.weekday, from: Date())
    private var hours: [CampusMinuteRange] {
        let places = Place.all.filter { $0.type == .food && $0.building == building.buildingNumberLabel }
        let next = CampusPlanning.calendar.nextDate(after: CampusPlanning.calendar.startOfDay(for: Date()).addingTimeInterval(-1), matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime) ?? Date()
        let restaurantHours = places.flatMap { CampusPlanning.parseHours(store.dining.hours(for: $0, on: next)) }
        let cafeHours = (2...6).contains(weekday) ? PlaceDirectory.venues(in: building).flatMap { CampusPlanning.parseHours($0.weekdayHours) } : []
        return restaurantHours + cafeHours
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("추천 요일", selection: $weekday) { ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(CampusWeekGrid.dayName($0) + "요일").tag($0) } }.pickerStyle(.menu)
            if planner.data.classes.isEmpty {
                BuildingEmptyCard(symbol: "calendar", title: "수업을 먼저 등록해 주세요", text: "등록한 수업의 빈 시간과 공개 운영시간을 함께 확인할게요.")
                NavigationLink("수업 추가") { CampusClassEditorView() }.accessibilityIdentifier("recommendations.add-class")
            } else {
                let sourceHours = hours.isEmpty ? [CampusMinuteRange(start: 540, end: 1080)] : hours
                let after = weekday == CampusPlanning.calendar.component(.weekday, from: Date()) ? CampusPlanning.minute(of: Date(), calendar: CampusPlanning.calendar) : 0
                let ranges = CampusPlanning.visitRanges(classes: planner.data.classes, weekday: weekday, openingHours: sourceHours, after: after)
                Text(hours.isEmpty ? "시설 운영시간 미등록 · 09–18시 공강만 표시해요" : "등록한 수업과 식당·카페의 공개 운영시간 기준이에요").font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(ranges.prefix(4).enumerated()), id: \.offset) { _, range in
                    BuildingSurface {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(range.label, systemImage: "clock").font(.headline).foregroundStyle(BuildingDesign.green)
                            Text("\(range.duration)분의 공강 · 이동시간은 길찾기에서 확인해 주세요.").font(.subheadline).foregroundStyle(.secondary)
                            NavigationLink { CampusSpaceRecommendationsView(building: building) } label: { Text("이 시간에 둘러볼 공간").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
                        }
                    }
                }
                if ranges.isEmpty { BuildingEmptyCard(symbol: "calendar.badge.clock", title: "조건에 맞는 공강이 없어요", text: "다른 요일을 선택해 보세요. 30분 이상의 빈 시간을 안내해요.") }
                Text("방문 추천은 혼잡도 예측이 아니에요. 휴일·방학·임시 휴무와 실제 좌석 상황은 매장에 확인해 주세요.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

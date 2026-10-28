import SwiftUI

struct QuestBottomSheet: View {
    @EnvironmentObject var store: Store
    let quests: [Quest]
    @State private var expanded = false
    @State private var mode: QuestMode?
    @State private var highReward = false
    @State private var creating = false

    private var rows: [Quest] {
        quests.filter { mode == nil || $0.mode == mode }.sorted {
            highReward ? $0.reward > $1.reward : $0.distance < $1.distance
        }
    }
    private var collapsed: Bool { store.questSheetCollapsed }
    /// 아래로 쓸면 한 단계씩 내려가고(펼침 → 기본 → 접힘), 위로 쓸면 올라간다.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12).onEnded { value in
            let up = value.translation.height < 0
            withAnimation(.easeInOut(duration: 0.25)) {
                if up { if collapsed { store.questSheetCollapsed = false } else { expanded = true } }
                else { if expanded { expanded = false } else { store.questSheetCollapsed = true } }
            }
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if collapsed { store.questSheetCollapsed = false } else { expanded.toggle() }
                    }
                } label: {
                    Capsule().fill(Color.cjHandle).frame(width: 40, height: 4)
                        .frame(maxWidth: .infinity).frame(height: 20).contentShape(Rectangle())
                }
                .accessibilityLabel(collapsed || !expanded ? "퀘스트 목록 펼치기" : "퀘스트 목록 접기")
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("내 주변 퀘스트 \(rows.count)").font(.title3.weight(.heavy))
                        Text("학생회관 기준 · 시연 퀘스트").font(.caption).foregroundStyle(Color.cjSub)
                    }
                    Spacer()
                    Button { creating = true } label: {
                        Label("등록", systemImage: "plus").font(.subheadline.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .foregroundStyle(.white).background(Color.cjTeal, in: Capsule())
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(swipe)
            if !collapsed {
            HStack(spacing: 8) {
                modeButton("전체", nil)
                modeButton("선착순", .firstCome)
                modeButton("결과 보상", .resultReward)
                Spacer(minLength: 0)
                Button { highReward.toggle() } label: {
                    Label(highReward ? "보상순" : "가까운순", systemImage: "arrow.up.arrow.down")
                        .font(.caption).foregroundStyle(Color.cjSub)
                }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if rows.isEmpty { Text("조건에 맞는 퀘스트가 없어요").foregroundStyle(Color.cjSub).padding(24) }
                    ForEach(rows) { quest in
                        Button { store.selectedQuest = quest } label: { QuestRow(quest: quest) }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 8)
        .frame(height: collapsed ? nil : (expanded ? min(580, UIScreen.main.bounds.height * 0.65) : 265))
        .background(Color.cjSurface, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .shadow(color: .black.opacity(0.13), radius: 10, y: -3)
        .sheet(isPresented: $creating) { CreateQuestView() }
    }
    private func modeButton(_ title: String, _ value: QuestMode?) -> some View {
        Button { mode = value } label: {
            Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 8)
                .foregroundStyle(mode == value ? Color.cjTeal : Color.cjSub)
                .background(mode == value ? Color.cjSuccessFill : Color.cjInset, in: Capsule())
        }
    }
}

struct QuestRow: View {
    let quest: Quest
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: quest.category.symbol).font(.system(size: 20))
                .foregroundStyle(quest.mode == .firstCome ? Color.cjTeal : Color.cjBlue)
                .frame(width: 45, height: 45).background(Color.cjInset, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 6) {
                Text(quest.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text("\(quest.place) · \(quest.distance)m").font(.caption).foregroundStyle(Color.cjSub)
                HStack {
                    Text(quest.mode.title).font(.caption2.weight(.bold)).foregroundStyle(quest.mode == .firstCome ? Color.cjTeal : Color.cjBlue)
                    Spacer()
                    Text(quest.rewardText).font(.subheadline.weight(.heavy)).foregroundStyle(Color.cjTeal)
                }
            }
        }.padding(.vertical, 14).contentShape(Rectangle())
    }
}

struct QuestDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let quest: Quest
    @State private var confirmAccept = false
    @State private var result = ""
    @State private var submitting = false
    private var progress: QuestProgress? { store.questSession.progress[quest.id] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Badge(text: quest.category.title, color: .cjTeal)
                        Badge(text: quest.mode.title, color: quest.mode == .firstCome ? .cjTeal : .cjBlue)
                    }
                    Text(quest.title).font(.title2.weight(.heavy))
                    Text(quest.rewardText).font(.largeTitle.weight(.heavy)).foregroundStyle(Color.cjTeal)
                    Label(quest.building, systemImage: "mappin.and.ellipse").font(.subheadline)
                    Divider()
                    Text("부탁드리는 내용").font(.headline)
                    Text(quest.details).font(.body).lineSpacing(6)
                    Divider()
                    Label(quest.requester, systemImage: "person.crop.circle").font(.subheadline)
                    Text(quest.mode == .firstCome ? "먼저 수락한 한 사람이 수행하는 퀘스트예요." : "여러 사람이 참여할 수 있어요. 요청자가 결과를 확인한 뒤 보상을 지급하는 방식이에요.")
                        .font(.subheadline).foregroundStyle(Color.cjSub)
                    if quest.mode == .resultReward { Text("참여 \(quest.participants)명").font(.caption).foregroundStyle(Color.cjSub) }
                    Text("시연 퀘스트예요. 수락과 결과 제출은 앱 실행 중에만 기록되며 실제 의뢰나 결제는 발생하지 않아요.")
                        .font(.caption).foregroundStyle(Color.cjSub).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color.cjInset, in: RoundedRectangle(cornerRadius: 12))
                }.padding(22)
            }
            .navigationTitle("퀘스트 상세").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if quest.mode == .firstCome { confirmAccept = true } else { submitting = true }
                } label: {
                    Text(progress == .accepted ? "수락한 퀘스트" : progress == .resultPending ? "결과 확인 대기 중" : quest.mode == .firstCome ? "퀘스트 수락하기" : "결과 제출하기")
                        .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(16)
                        .background(Color.cjTeal, in: RoundedRectangle(cornerRadius: 14))
                }.disabled(progress != nil).opacity(progress == nil ? 1 : 0.6).padding(16).background(Color.cjSurface)
            }
            .confirmationDialog("이 퀘스트를 수락할까요?", isPresented: $confirmAccept, titleVisibility: .visible) {
                Button("수락하기") { _ = store.questSession.accept(quest) }
                Button("취소", role: .cancel) { }
            } message: { Text("이 화면에서는 수락 상태를 시연해요.") }
            .sheet(isPresented: $submitting) {
                NavigationStack {
                    Form {
                        Section("발견 위치와 결과를 알려주세요") { TextEditor(text: $result).frame(minHeight: 140) }
                        Section { Text("10자 이상 작성해주세요. 시연용으로 제출 상태만 기록해요.").font(.caption) }
                    }
                    .navigationTitle("결과 제출")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("취소") { submitting = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("제출") { if store.questSession.submit(quest, text: result) { submitting = false } }
                                .disabled(result.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                        }
                    }
                }
            }
        }
    }
}

struct CreateQuestView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var reward = "3000"
    @State private var category = QuestCategory.errand
    @State private var mode = QuestMode.firstCome
    @State private var buildingID = ""
    private var buildings: [CampusBuilding] { CampusBuildingCatalog.all.sorted { $0.name < $1.name } }
    private var building: CampusBuilding? { buildings.first { $0.id == buildingID } }
    private var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...1_000_000).contains(Int(reward) ?? 0) && building != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section("퀘스트 내용") {
                    TextField("무엇을 부탁하고 싶으세요?", text: $title)
                    Picker("종류", selection: $category) { ForEach(QuestCategory.allCases) { Text($0.title).tag($0) } }
                    Picker("보상 방식", selection: $mode) { ForEach(QuestMode.allCases) { Text($0.title).tag($0) } }
                    TextField("보상 금액 (원)", text: $reward).keyboardType(.numberPad)
                    TextField("부탁할 내용과 전달 방법", text: $details, axis: .vertical).lineLimit(4...8)
                }
                Section("지도에 표시할 장소") {
                    Picker("건물 선택", selection: $buildingID) {
                        Text("장소를 선택해주세요").tag("")
                        ForEach(buildings) { Text($0.displayTitle).tag($0.id) }
                    }.pickerStyle(.navigationLink)
                }
                Section { Text("화면 검토를 위한 시연 등록이에요. 이 앱을 종료하면 사라지며 다른 사용자에게 공유되지 않아요.").font(.caption) }
            }
            .navigationTitle("퀘스트 등록")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("등록", action: create).disabled(!valid) }
            }
        }
    }
    private func create() {
        guard valid, let b = building, let amount = Int(reward) else { return }
        let coordinate = CampusCoordinate(latitude: b.latitude, longitude: b.longitude)
        let distance = Int(coordinate.distance(to: .init(latitude: 37.45925, longitude: 126.9506)))
        let quest = Quest(id: UUID().uuidString, title: title, category: category, mode: mode, reward: amount,
                          place: b.name, building: b.displayTitle, coordinate: coordinate, distance: distance,
                          details: details, requester: "나")
        guard quest.isValid else { return }
        store.quests.insert(quest, at: 0); store.homeFilter = .all
        store.toast("시연 퀘스트를 지도에 등록했어요"); dismiss()
    }
}

struct MyQuestsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List {
            ForEach(store.quests.filter { store.questSession.progress[$0.id] != nil || $0.requester == "나" }) { quest in
                NavigationLink { QuestDetailView(quest: quest) } label: {
                    VStack(alignment: .leading) {
                        QuestRow(quest: quest)
                        Text(store.questSession.progress[quest.id] == .accepted ? "수락 완료" : store.questSession.progress[quest.id] == .resultPending ? "결과 확인 대기" : "내가 등록한 퀘스트")
                            .font(.caption).foregroundStyle(Color.cjTeal)
                    }
                }
            }
            Text("앱 실행 중의 시연 기록이에요.").font(.caption).foregroundStyle(Color.cjSub)
        }.navigationTitle("내 퀘스트")
    }
}

struct HomePlaceCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var shuttle: CircularShuttleService
    let place: Place
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PlaceIcon(type: place.type)
                Text(place.name).font(.headline)
                Spacer()
                Button { store.closeSheet() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.cjSub).padding(6) }
                    .accessibilityLabel("장소 정보 닫기")
            }
            if place.type == .food {
                Text(place.building.isEmpty ? "교내 식당" : place.building).font(.subheadline).foregroundStyle(Color.cjSub)
                Text("식단과 운영 시간은 식당 탭에서 확인하세요.").font(.subheadline)
                Button { store.tab = .dining } label: {
                    Label("식단 보러 가기", systemImage: "fork.knife").frame(maxWidth: .infinity).padding(12)
                        .background(Color.cjSuccessFill, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                ShuttleStatusContent()
            }
            Link(destination: place.directionsURL) { Label("길찾기", systemImage: "arrow.triangle.turn.up.right.diamond") }.font(.subheadline)
        }
        .padding(18).background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 22)).shadow(radius: 6)
    }
}

struct ShuttleStatusContent: View {
    @EnvironmentObject var shuttle: CircularShuttleService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shuttle.status).font(.subheadline.weight(.semibold)).foregroundStyle(Color.cjBlue)
            if let date = shuttle.queriedAt { Text("조회 \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(Color.cjSub) }
            ForEach(shuttle.positions.prefix(3)) { bus in
                Label("교내순환 · 다음 \(bus.nextStop)", systemImage: "bus.fill").font(.subheadline)
            }
            Text("위치는 노선도 좌표를 도로 위에 보정한 추정치예요. 도착예정시간은 현재 데이터에서 제공하지 않아요.")
                .font(.caption).foregroundStyle(Color.cjSub)
            if shuttle.heldCount > 0 { Text("불확실한 위치 \(shuttle.heldCount)건 확인 중").font(.caption).foregroundStyle(Color.cjSub) }
        }
    }
}

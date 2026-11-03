import SwiftUI

extension QuestCategory {
    var accent: Color {
        switch self {
        case .printDelivery: Color.cjTeal
        case .lost: Color.cjBlue
        case .errand: Color(hex: 0xAD5B20)
        }
    }
}

struct QuestsView: View {
    @EnvironmentObject private var store: Store
    @State private var query = ""
    @State private var category: QuestCategory?
    @State private var mode: QuestMode?
    @State private var highReward = false
    @State private var creating = false
    @State private var selectedQuest: Quest?

    private var rows: [Quest] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.quests.filter {
            (category == nil || $0.category == category) && (mode == nil || $0.mode == mode) &&
            (text.isEmpty || ($0.title + " " + $0.place + " " + $0.building).localizedCaseInsensitiveContains(text))
        }.sorted {
            if highReward && $0.reward != $1.reward { return $0.reward > $1.reward }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.id < $1.id
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("오가는 길에, 작은 도움").font(.title2.weight(.bold))
                        Text("캠퍼스의 부탁을 해결하고 보상을 받아보세요")
                            .font(.subheadline).foregroundStyle(Color.cjSub)
                    }
                    .padding(.top, 8)
                    if let error = store.questError { Text(error).font(.footnote).foregroundStyle(.red) }
                    categoryFilters
                    Picker("보상 방식", selection: $mode) {
                        Text("전체").tag(QuestMode?.none)
                        Text("선착순").tag(QuestMode?.some(.firstCome))
                        Text("결과 보상").tag(QuestMode?.some(.resultReward))
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("퀘스트 \(rows.count)개").font(.headline)
                        Spacer()
                        Menu {
                            Button("가까운순") { highReward = false }
                            Button("보상 높은순") { highReward = true }
                        } label: {
                            Label(highReward ? "보상 높은순" : "가까운순", systemImage: "arrow.up.arrow.down")
                                .font(.subheadline).foregroundStyle(Color.cjSub)
                        }
                    }
                    LazyVStack(spacing: 16) {
                        if rows.isEmpty {
                            ContentUnavailableView {
                                Label("조건에 맞는 퀘스트가 없어요", systemImage: "bolt.slash")
                            } description: {
                                Text("검색어나 필터를 바꿔보세요")
                            } actions: {
                                Button("전체 퀘스트 보기") { query = ""; category = nil; mode = nil }
                            }
                        }
                        ForEach(rows) { quest in
                            Button { selectedQuest = quest } label: {
                                QuestCard(quest: quest, progress: store.progress(for: quest))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("학생회관 기준 거리 · 보상은 이용자 간 직접 송금")
                        .font(.caption).foregroundStyle(Color.cjSub).lineSpacing(4)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("퀘스트")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "퀘스트·장소 검색")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { MyQuestsView() } label: { Label("내 퀘스트", systemImage: "tray") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Label("등록", systemImage: "plus") }
                }
            }
            .refreshable { await store.refreshQuests() }
            .task { await store.refreshQuests() }
            .sheet(isPresented: $creating) { CreateQuestView() }
            .sheet(item: $selectedQuest) { QuestDetailView(quest: $0) }
        }
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton("전체", symbol: "square.grid.2x2", value: nil)
                ForEach(QuestCategory.allCases) { item in
                    categoryButton(item.title, symbol: item.symbol, value: item)
                }
            }.padding(.vertical, 2)
        }
    }

    private func categoryButton(_ title: String, symbol: String, value: QuestCategory?) -> some View {
        Button { category = value } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(category == value ? Color.white : Color.cjTealText)
                .background(category == value ? Color.cjTeal : Color.cjSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == value ? .isSelected : [])
    }
}

private struct QuestCard: View {
    let quest: Quest
    let progress: QuestProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: quest.category.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(quest.category.title).font(.subheadline.weight(.bold))
                    Text(quest.mode.title).font(.caption)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.subheadline.weight(.bold))
            }
            .foregroundStyle(quest.category.accent).padding(16)
            .background(quest.category.accent.opacity(0.09))
            VStack(alignment: .leading, spacing: 12) {
                Text(quest.title).font(.headline).foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Label("\(quest.place) · \(quest.distance)m", systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(Color.cjSub)
                HStack(alignment: .firstTextBaseline) {
                    Text(progress == .accepted ? "수락 완료" : progress == .resultPending ? "결과 확인 대기" : "완료 보상")
                        .font(.caption.weight(.medium)).foregroundStyle(Color.cjSub)
                    Spacer()
                    Text(quest.rewardText).font(.title3.weight(.heavy)).foregroundStyle(quest.category.accent)
                }
            }.padding(18)
        }
        .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(quest.category.accent.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct MapQuestPreview: View {
    @EnvironmentObject private var store: Store
    let quest: Quest
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: quest.category.symbol).font(.title3).foregroundStyle(quest.category.accent)
                    .frame(width: 40, height: 40).background(quest.category.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(quest.title).font(.subheadline.weight(.bold)).lineLimit(2)
                    Text("\(quest.place) · \(quest.distance)m").font(.caption).foregroundStyle(Color.cjSub)
                }
                Spacer(minLength: 0)
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .foregroundStyle(Color.cjSub).accessibilityLabel("퀘스트 미리보기 닫기")
            }
            HStack {
                Text(quest.rewardText).font(.title3.weight(.heavy)).foregroundStyle(quest.category.accent)
                Spacer()
                Button { store.selectedQuest = quest } label: {
                    Label("상세 보기", systemImage: "arrow.right").font(.subheadline.weight(.bold))
                        .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.cjTeal, in: Capsule())
                }
            }
        }
        .padding(16).background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

struct QuestBottomSheet: View {
    @EnvironmentObject var store: Store
    let quests: [Quest]
    @State private var mode: QuestMode?
    @State private var highReward = false
    private var rows: [Quest] {
        quests.filter { mode == nil || $0.mode == mode }.sorted {
            highReward ? $0.reward > $1.reward : $0.distance < $1.distance
        }
    }
    var body: some View {
        SwipeSheet(detent: $store.questSheet, normalHeight: 265) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("내 주변 퀘스트 \(rows.count)").font(.title3.weight(.heavy))
                    Text("학생회관 기준 · 캠퍼스 퀘스트").font(.caption).foregroundStyle(Color.cjSub)
                }
                Spacer()
                Button { store.tab = .quests } label: {
                    Label("전체 보기", systemImage: "arrow.right").font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .foregroundStyle(.white).background(Color.cjTeal, in: Capsule())
                }
            }
        } content: {
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

struct HomePlaceCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var shuttle: CircularShuttleService
    let place: Place
    @Binding var detent: SheetDetent
    var body: some View {
        SwipeSheet(detent: $detent) {
            HStack {
                PlaceIcon(type: place.type)
                Text(place.name).font(.headline)
                Spacer()
                Button { store.closeSheet() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.cjSub).padding(6) }
                    .accessibilityLabel("장소 정보 닫기")
            }
        } content: {
            ShuttleStatusContent() // 정류장 전용. 식당은 SheetView의 식단 시트로 연다.
            Link(destination: place.directionsURL) { Label("길찾기", systemImage: "arrow.triangle.turn.up.right.diamond") }.font(.subheadline)
        }
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

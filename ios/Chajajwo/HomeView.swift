import SwiftUI
import CoreLocation

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var lf: LostFoundAPI
    @EnvironmentObject var shuttle: CircularShuttleService
    @State private var selectedLostPinID: String?
    @State private var selectedMapQuest: Quest?
    @State private var selectedQuestGroup: QuestMapGroup?
    @State private var zoomRequest = 0
    @State private var query = ""
    @State private var focusedBuilding: CampusBuilding?
    @State private var focusSerial = 0
    @StateObject private var userLocation = UserLocationService()
    @Environment(\.scenePhase) private var scenePhase
    @State private var userFocusSerial = 0
    @State private var pendingUserFocus = false
    @State private var showLocationSettings = false
    @State private var placeSheet = SheetDetent.normal  // 건물·분실물 핀·정류장·식단 시트 단계
    @State private var bottomHeight: CGFloat = 0        // 하단 시트 높이. 내 위치 버튼을 그 위에 둔다
    @FocusState private var searchFocused: Bool

    private var searchResults: [CampusBuilding] { CampusBuildingCatalog.search(query) }
    private var hasSearchText: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // The three pre-existing example hubs are NOT official centers: do not render them.
    private var places: [Place] {
        if store.lostMapOnly { return [] }
        return Place.all.filter {
            switch store.homeFilter {
            case .all: $0.type != .hub
            case .quests, .hubs: false
            case .food: $0.type == .food
            case .shuttle: $0.type == .stop
            }
        }
    }
    private var lostPins: [LostFoundMapPin] {
        store.lostMapOnly || store.homeFilter == .all ? lf.pins : []
    }
    private var quests: [Quest] {
        guard !store.lostMapOnly, store.homeFilter == .all || store.homeFilter == .quests else { return [] }
        return store.quests.filter { !hasSearchText || ($0.title + $0.place + $0.building).localizedCaseInsensitiveContains(query) }
    }
    private var counts: [String: Int] {
        Dictionary(grouping: store.items, by: \.hub).mapValues(\.count)
    }

    var body: some View {
        ZStack(alignment: .top) {
            mainMap

            topBar
        }
        .overlay(alignment: .bottomTrailing) {
            myLocationButton
                .padding(.trailing, 16)
                .padding(.bottom, bottomHeight + 16) // 지금 떠 있는 하단 시트 바로 위
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) { bottomContent } // 시트가 없을 때도 높이 0으로 재도록 감싼다
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
        }
        .onChange(of: placeSheetKey) { _, _ in placeSheet = .normal }
        .sheet(item: $store.selectedQuest) { QuestDetailView(quest: $0) }
        .sheet(item: $selectedQuestGroup) { group in
            NavigationStack {
                List(group.quests) { quest in
                    NavigationLink { QuestDetailView(quest: quest) } label: { QuestRow(quest: quest) }
                }
                .navigationTitle("이 장소의 퀘스트 \(group.quests.count)개")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { selectedQuestGroup = nil } } }
            }
        }
        .onChange(of: store.homeFilter) { _, _ in selectedMapQuest = nil }
        .onChange(of: quests.map(\.id)) { _, ids in
            if let selectedMapQuest, !ids.contains(selectedMapQuest.id) { self.selectedMapQuest = nil }
        }
        .onChange(of: store.sel) { _, _ in
            if store.open { focusedBuilding = nil }
        }
        .ignoresSafeArea(.keyboard) // 키보드가 올라와도 하단 시트가 같이 밀려 올라오지 않게
        .onAppear {
            if scenePhase == .active && store.tab == .home { userLocation.start() }
            Task { await lf.prepare() }
            if let id = store.lostPinID { selectedLostPinID = id }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-map-selected") { selectedMapQuest = store.quests.first }
            #endif
        }
        .onChange(of: store.lostPinID) { _, newValue in selectedLostPinID = newValue }
        .onDisappear { userLocation.stop(); pendingUserFocus = false }
        .onChange(of: store.tab) { _, tab in
            if tab == .home && scenePhase == .active { userLocation.start() }
            else { userLocation.stop(); pendingUserFocus = false; searchFocused = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && store.tab == .home { userLocation.start() }
            else { userLocation.stop(); pendingUserFocus = false }
        }
        .onChange(of: userLocation.coordinate?.latitude) { _, _ in
            if pendingUserFocus, userLocation.coordinate != nil {
                pendingUserFocus = false
                focusedBuilding = nil
                store.closeSheet()
                userFocusSerial += 1
            }
        }
        .alert("위치 접근 권한이 필요해요", isPresented: $showLocationSettings) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("현재 위치를 지도에 표시하려면 iPhone 설정에서 찾아줘의 위치 접근을 허용해주세요.")
        }
    }


    private var mainMap: some View {
        KakaoMapView(places: places, counts: counts, selected: store.sel, sheetOpen: store.open,
                     focusedBuilding: focusedBuilding, focusSerial: focusSerial,
                     userCoordinate: userLocation.coordinate,
                     userHeadingDegrees: userLocation.headingDegrees,
                     userFocusSerial: userFocusSerial,
                     lostPins: lostPins, lostFocusID: store.lostPinID,
                     lostFocusSerial: store.lostFocusSerial,
                     quests: quests, shuttle: shuttle,
                     selectedQuestID: selectedMapQuest?.id, zoomRequest: zoomRequest,
                     onQuestSelect: { id in
                         searchFocused = false
                         focusedBuilding = nil; selectedLostPinID = nil; store.closeSheet()
                         selectedMapQuest = store.quests.first { $0.id == id }
                     }, onQuestGroupSelect: { ids in
                         selectedQuestGroup = .init(id: ids.joined(separator: "-"), quests: store.quests.filter { ids.contains($0.id) })
                     }, onQuestDeselect: {
                         selectedMapQuest = nil
                     }, onSelect: { id in
                         searchFocused = false
                         selectedMapQuest = nil
                         focusedBuilding = nil
                         selectedLostPinID = nil
                         store.select(id)
                     }, onSelectLost: { id in
                         searchFocused = false
                         selectedMapQuest = nil
                         focusedBuilding = nil
                         store.closeSheet()
                         selectedLostPinID = id
                     })
            .ignoresSafeArea(edges: .top)
    }

    // 칩(퀘스트·분실물·식당·셔틀)으로 거른 지도에는 하단 시트를 띄우지 않는다. 핀을 누르면 그 핀의 시트가 뜬다.
    @ViewBuilder private var bottomContent: some View {
        if let quest = selectedMapQuest {
            MapQuestPreview(quest: quest, onClose: { selectedMapQuest = nil }).padding(12)
        } else if let building = focusedBuilding {
            buildingCard(building)
        } else if let id = selectedLostPinID, let pin = lf.pins.first(where: { $0.id == id }) {
            lostPinCard(pin)
        } else if store.open, let place = Place.byID[store.sel], place.type == .stop {
            HomePlaceCard(place: place, detent: $placeSheet)
        } else if store.open { // 식당은 날짜별 아침·점심·저녁 식단 시트, 거점은 보관 물품 시트
            SheetView(detent: $placeSheet)
        } else if store.homeFilter == .all && !store.lostMapOnly {
            QuestBottomSheet(quests: quests)
        }
    }

    /// 지금 떠 있는 장소 시트. 다른 장소를 고르면 시트를 기본 높이로 다시 연다.
    private var placeSheetKey: String {
        "\(focusedBuilding?.id ?? "")|\(selectedLostPinID ?? "")|\(store.open ? store.sel : "")"
    }

    /// Standard map-app locate button. GPS is displayed continuously, but camera only
    /// recenters on explicit request: panning/searching a building remains user-controlled.
    private var myLocationButton: some View {
        VStack(alignment: .trailing, spacing: 5) {
            VStack(spacing: 0) {
                Button { zoomRequest += 1 } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("지도 확대")
                Divider().frame(width: 28)
                Button { zoomRequest -= 1 } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                    .accessibilityLabel("지도 축소")
            }
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.cjTealText)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .padding(.bottom, 5)
            if userLocation.approximateLocation && userLocation.coordinate != nil {
                Text("대략적인 위치")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x182A30))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.white, in: Capsule())
            }
            Button(action: focusMyLocation) {
                Image(systemName: userLocation.coordinate == nil ? "location" : "location.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x287AF0))
                    .frame(width: 52, height: 52)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(Color(hex: 0xDDE7E8), lineWidth: 1))
                    .shadow(color: .black.opacity(0.20), radius: 7, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("내 위치로 이동")
            .accessibilityHint("현재 위치가 확인되면 지도의 중심이 내 위치로 이동합니다")
        }
    }

    private func focusMyLocation() {
        searchFocused = false
        if userLocation.authorizationStatus == .denied || userLocation.authorizationStatus == .restricted {
            showLocationSettings = true
            return
        }
        userLocation.start()
        if let _ = userLocation.coordinate {
            pendingUserFocus = false
            focusedBuilding = nil
            store.closeSheet()
            userFocusSerial += 1
        } else {
            pendingUserFocus = true
            store.toast(userLocation.errorMessage ?? "현재 위치를 확인하고 있어요")
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Color.cjTeal, in: RoundedRectangle(cornerRadius: 10))
                    Text("찾아줘").font(.title3.weight(.heavy))
                }
                .padding(.vertical, 4).padding(.leading, 4).padding(.trailing, 12)
                .background(Color.cjSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.primary)
                TextField("건물·퀘스트·분실물을 검색하세요", text: $query)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit(search)
                    .onChange(of: query) { _, newValue in
                        if !newValue.isEmpty { focusedBuilding = nil }
                    }
                if hasSearchText {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.cjSub)
                    }
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 14)).shadow(radius: 4, y: 2)

            if hasSearchText {
                searchResultsPanel
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("전체", symbol: "square.grid.2x2.fill", filter: .all)
                    chip("퀘스트", symbol: "bolt.fill", filter: .quests)
                    Button {
                        store.lostMapOnly = true
                        store.homeFilter = .all
                        store.closeSheet()
                        selectedLostPinID = nil
                    } label: {
                        Label("분실물", systemImage: "shippingbox.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(store.lostMapOnly ? Color.white : Color.primary)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(store.lostMapOnly ? Color.cjTeal : Color.cjSurface, in: Capsule())
                    }
                    chip("식당", symbol: "fork.knife", filter: .food)
                    chip("셔틀", symbol: "bus.fill", filter: .shuttle)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func chip(_ title: String, symbol: String, filter: Store.HomeFilter) -> some View {
        let on = !store.lostMapOnly && store.homeFilter == filter
        return Button {
            store.lostMapOnly = false
            selectedLostPinID = nil
            store.homeFilter = filter
            store.closeSheet()
            focusedBuilding = nil
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 16).frame(height: 38)
                .background(on ? Color.cjTeal : Color.cjSurface, in: Capsule()).shadow(radius: 4, y: 2)
        }
    }

    // The Kakao map is hosted inside a UIKit view. A system-adaptive `.primary`
    // foreground can be resolved against a different appearance than this overlay's
    // background. Use an explicit high-contrast palette for the entire results panel.
    // The panel intentionally stays white in both light and dark appearance.
    private enum SearchResultColors {
        static let background = Color(hex: 0xFFFFFF)
        static let title = Color(hex: 0x182A30)
        static let secondary = Color(hex: 0x4A6067)
        static let accent = Color(hex: 0x0D7569)
        static let separator = Color(hex: 0xDDE7E8)
    }

    private var searchResultsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("건물·장소 검색 결과 \(searchResults.count)개")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SearchResultColors.secondary)
                Spacer()
                Text("결과 선택 시 지도 이동")
                    .font(.caption2)
                    .foregroundStyle(SearchResultColors.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Rectangle().fill(SearchResultColors.separator).frame(height: 1)
            if searchResults.isEmpty {
                Text(CampusBuildingCatalog.all.isEmpty ? "건물 데이터를 불러오지 못했어요" : "일치하는 건물이나 장소가 없어요")
                    .font(.subheadline)
                    .foregroundStyle(SearchResultColors.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { building in
                            Button { focus(on: building) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "building.2.fill")
                                        .foregroundStyle(SearchResultColors.accent)
                                        .frame(width: 25)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(building.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(SearchResultColors.title)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(building.buildingNumberLabel)
                                            .font(.caption)
                                            .foregroundStyle(SearchResultColors.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Image(systemName: "location.fill")
                                        .foregroundStyle(SearchResultColors.accent)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(building.displayTitle), 지도에서 보기")
                            Rectangle().fill(SearchResultColors.separator)
                                .frame(height: 1)
                                .padding(.leading, 48)
                        }
                    }
                }
                .frame(maxHeight: 320)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(SearchResultColors.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 5, y: 3)
    }

    private func focus(on building: CampusBuilding) {
        searchFocused = false
        store.filter = nil
        store.homeFilter = .all
        store.closeSheet()
        selectedLostPinID = nil
        store.lostMapOnly = false
        focusedBuilding = building
        focusSerial += 1  // Repeat taps on the same building still recenter the camera.
        query = ""        // Close results so the map location is clearly visible.
    }

    private func buildingCard(_ building: CampusBuilding) -> some View {
        SwipeSheet(detent: $placeSheet) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.title2).foregroundStyle(Color.cjTeal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(building.name).font(.headline)
                    Text(building.buildingNumberLabel).font(.subheadline).foregroundStyle(Color.cjSub)
                    if building.source == "openstreetmap" {
                        Link("지도 좌표 © OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                            .font(.caption2).foregroundStyle(Color.cjSub)
                    }
                }
                Spacer()
                Button { focusedBuilding = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.cjSub)
                }
                .accessibilityLabel("건물 위치 닫기")
            }
        } content: {
            if let url = building.directionsURL {
                Link(destination: url) {
                    Label("길찾기", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cjTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func lostPinCard(_ pin: LostFoundMapPin) -> some View {
        SwipeSheet(detent: $placeSheet) {
            HStack {
                Image(systemName: pin.kind == .center ? "cross.case.fill" : "shippingbox.fill")
                    .foregroundStyle(Color.cjTeal)
                Text(pin.title).font(.headline)
                Spacer()
                Button { selectedLostPinID = nil } label: { Image(systemName: "xmark.circle.fill") }
            }
        } content: {
            if let center = lf.center(pin.id) {
                Text("\(center.building) · \(center.room)").font(.subheadline)
                Text(center.weekdayHours ?? "운영시간 확인 필요").font(.caption).foregroundStyle(Color.cjTealText)
                Text(center.weekendHolidayNote).font(.caption).foregroundStyle(.secondary)
                if let phone = center.phone, let url = URL(string: "tel:\(phone)") { Link("전화 문의", destination: url) }
            } else {
                Text(pin.kind == .found ? "회원이 등록한 습득 위치입니다." : "회원의 분실 추정 위치입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("분실물 상세·신고 보기") { store.tab = .lostFound }
                .font(.subheadline.weight(.bold))
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchFocused = false
        guard !q.isEmpty else { return }
        let buildings = searchResults
        if buildings.count == 1, let onlyBuilding = buildings.first {
            focus(on: onlyBuilding)
        } else if !buildings.isEmpty {
            // Never arbitrarily discard other matches or jump to only the first one.
            return
        } else if let pin = lf.pins.first(where: { $0.title.localizedCaseInsensitiveContains(q) }) {
            // Search only verified center locations and server-backed user reports.
            // The old locally seeded demo items and hubs must not reappear here.
            focusedBuilding = nil
            query = ""
            store.filter = nil
            store.homeFilter = .all
            store.closeSheet()
            store.lostMapOnly = true
            store.lostPinID = pin.id
            store.lostFocusSerial += 1
            selectedLostPinID = pin.id
        } else if let p = Place.all.first(where: {
            $0.type != .hub && $0.name.localizedCaseInsensitiveContains(q)
        }) {
            focusedBuilding = nil
            query = ""
            store.filter = nil
            store.homeFilter = .all
            store.lostMapOnly = false
            store.select(p.id)
        } else if let quest = store.quests.first(where: { ($0.title + $0.place).localizedCaseInsensitiveContains(q) }) {
            store.selectedQuest = quest
        } else {
            store.toast("'\(q)' 검색 결과가 없어요")
        }
    }
}

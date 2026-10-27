import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var focusedBuilding: CampusBuilding?
    @State private var focusSerial = 0
    @FocusState private var searchFocused: Bool

    private var searchResults: [CampusBuilding] { CampusBuildingCatalog.search(query) }
    private var hasSearchText: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var places: [Place] { Place.all.filter { store.filter == nil || $0.type == store.filter } }
    private var counts: [String: Int] {
        Dictionary(grouping: store.items, by: \.hub).mapValues(\.count)
    }

    var body: some View {
        ZStack(alignment: .top) {
            KakaoMapView(places: places, counts: counts, selected: store.sel, sheetOpen: store.open,
                         focusedBuilding: focusedBuilding, focusSerial: focusSerial) { id in
                searchFocused = false
                focusedBuilding = nil
                store.select(id)
            }
                .ignoresSafeArea(edges: .top)

            topBar
        }
        .overlay(alignment: .bottom) {
            if let building = focusedBuilding {
                buildingCard(building).padding(.horizontal, 12).padding(.bottom, 12)
            } else {
                SheetView().padding(.horizontal, 12)
            }
        }
        .onChange(of: store.sel) { _, _ in
            if store.open { focusedBuilding = nil }
        }
        .ignoresSafeArea(.keyboard) // 키보드가 올라와도 하단 시트가 같이 밀려 올라오지 않게
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
                TextField("건물명·동 번호 또는 분실물을 검색하세요", text: $query)
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
                    chip("전체", symbol: "square.grid.2x2.fill", type: nil)
                    chip(PlaceType.hub.chipTitle, symbol: "mappin.circle.fill", type: .hub)
                    chip(PlaceType.food.chipTitle, symbol: "fork.knife", type: .food)
                    chip(PlaceType.stop.chipTitle, symbol: "bus.fill", type: .stop)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func chip(_ title: String, symbol: String, type: PlaceType?) -> some View {
        let on = store.filter == type
        return Button {
            if type == .food { store.showDining = true }
            else { store.filter = type }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(on ? Color.white : (type?.textColor ?? .primary))
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
        store.closeSheet()
        focusedBuilding = building
        focusSerial += 1  // Repeat taps on the same building still recenter the camera.
        query = ""        // Close results so the map location is clearly visible.
    }

    private func buildingCard(_ building: CampusBuilding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(16)
        .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8, y: 4)
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
        } else if let p = Place.all.first(where: { $0.name.localizedCaseInsensitiveContains(q) }) {
            focusedBuilding = nil
            query = ""
            store.filter = nil
            store.select(p.id)
        } else if let i = store.items.first(where: { ($0.title + $0.kind + $0.feat + $0.found).localizedCaseInsensitiveContains(q) }) {
            focusedBuilding = nil
            query = ""
            store.filter = nil
            store.select(i.hub, item: i.id)
        } else {
            store.toast("'\(q)' 검색 결과가 없어요")
        }
    }
}

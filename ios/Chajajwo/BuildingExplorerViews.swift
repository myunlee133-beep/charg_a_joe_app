import SwiftUI

/// One native sheet owns the entire hierarchy; destinations push rather than stack sheets.
struct BuildingExplorerSheet: View {
    let building: CampusBuilding
    var onRestaurant: (Place) -> Void
    var onDirections: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BuildingOverviewView(building: building, onRestaurant: onRestaurant, onDirections: onDirections)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }.accessibilityIdentifier("building-explorer.close")
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

struct BuildingOverviewView: View {
    let building: CampusBuilding
    var onRestaurant: (Place) -> Void
    var onDirections: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(building.buildingNumberLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Color.cjTealText)
                    Text(building.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    if let details = building.details { Text(details.category).font(.subheadline).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 10)
            }
            Section("무엇을 찾으세요?") {
                NavigationLink {
                    BuildingFloorView(building: building)
                } label: {
                    discoveryRow("층별 공간", subtitle: "연구실 \(PlaceDirectory.labs(in: building).count)곳 · 등록 시설 \(building.details?.facilities.count ?? 0)곳", symbol: "square.3.layers.3d")
                }
                .accessibilityIdentifier("building.floors")
                NavigationLink {
                    BuildingFoodView(building: building, onRestaurant: onRestaurant)
                } label: {
                    discoveryRow("식당·카페", subtitle: "식단과 사진으로 보는 카페 메뉴", symbol: "cup.and.saucer")
                }
                .accessibilityIdentifier("building.food")
                NavigationLink {
                    BuildingGuideView(building: building, onDirections: onDirections)
                } label: {
                    discoveryRow("이용 안내", subtitle: "연락처 · 위치 · 공식 안내", symbol: "info.circle")
                }
                .accessibilityIdentifier("building.guide")
            }
            Section {} footer: { Text("공식 자료에 등록된 공간만 안내해요. 목록에 없더라도 실제 공간이 있을 수 있어요.") }
        }
        .navigationTitle("건물 둘러보기")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func discoveryRow(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.cjTealText).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct BuildingFloorView: View {
    let building: CampusBuilding
    @State private var floor: String
    @State private var query = ""

    init(building: CampusBuilding) {
        self.building = building
        _floor = State(initialValue: PlaceDirectory.floors(in: building).first ?? "층 정보 미등록")
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var labs: [ResearchLab] {
        PlaceDirectory.labs(in: building).filter {
            (searching || $0.floor == floor) && PlaceDirectory.matches(query, fields: $0.searchFields)
        }
    }
    private var facilities: [CampusBuildingFacility] {
        (building.details?.facilities ?? []).filter {
            (searching || PlaceDirectory.floorName($0.floor) == floor)
                && PlaceDirectory.matches(query, fields: [$0.name, $0.category])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !searching {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(PlaceDirectory.floors(in: building), id: \.self) { value in
                            Button { floor = value } label: {
                                Text(value).font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .background(floor == value ? Color.cjTealText : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(floor == value ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(floor == value ? .isSelected : [])
                            .accessibilityIdentifier("floor.\(value)")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            List {
                if searching {
                    Section { Text("건물 전체에서 검색 중").font(.caption).foregroundStyle(.secondary) }
                }
                if !labs.isEmpty {
                    Section("연구실 · \(labs.count)곳") {
                        ForEach(labs) { lab in
                            NavigationLink { ResearchLabView(lab: lab) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(lab.name).font(.headline)
                                    Text("지도교수 \(lab.professor) · \(lab.field)").font(.subheadline).foregroundStyle(.secondary)
                                    if searching { Text(lab.floor).font(.caption).foregroundStyle(Color.cjTealText) }
                                }.padding(.vertical, 7)
                            }
                            .accessibilityIdentifier("lab.\(lab.id)")
                        }
                    }
                }
                if !facilities.isEmpty {
                    Section("등록 시설 · \(facilities.count)곳") {
                        ForEach(facilities) { facility in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(facility.name)
                                Text(searching ? PlaceDirectory.floorName(facility.floor) : facility.category)
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                    }
                }
                if labs.isEmpty && facilities.isEmpty {
                    ContentUnavailableView(searching ? "검색 결과가 없어요" : "등록된 공간이 없어요", systemImage: "building.2",
                                           description: Text(searching ? "연구실 이름, 지도교수 또는 연구분야로 검색해 보세요." : "다른 층을 선택해 보세요."))
                }
                Section {} footer: { Text("연구실은 컴퓨터공학부 공식 자료를 수록했어요. 일부 연구실·시설의 정보는 아직 등록되지 않았어요.") }
            }
            .listStyle(.insetGrouped)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("층별 공간")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "연구실·지도교수·연구분야")
        .accessibilityIdentifier("building-floor-directory")
    }
}

struct ResearchLabView: View {
    let lab: ResearchLab
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(lab.name).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 10) {
                    Text("지도교수").font(.subheadline).foregroundStyle(.secondary)
                    Text(lab.professor + " 교수").font(.title2.weight(.semibold))
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("주요 연구분야").font(.subheadline).foregroundStyle(.secondary)
                    TopicFlowLayout(spacing: 8) {
                        ForEach(lab.topics, id: \.self) { topic in
                            Text(topic).font(.subheadline.weight(.medium))
                                .padding(.horizontal, 13).padding(.vertical, 10)
                                .background(Color.cjTealText.opacity(0.08), in: Capsule())
                        }
                    }
                }
                Divider()
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(lab.summary).font(.body).accessibilityIdentifier("lab.description")
                        Label(lab.room, systemImage: "mappin.and.ellipse").font(.subheadline)
                        if lab.floorDerived {
                            Text("층 표시는 공식 호실 번호를 기준으로 분류했어요.").font(.caption).foregroundStyle(.secondary)
                        }
                        if let phone = PlaceDirectory.phoneURL(lab.phone) { Link(lab.phone, destination: phone) }
                        PlaceSourceLink(title: "연구실 공식 소개", value: lab.url)
                        PlaceSourceLink(title: "지도교수 소개", value: lab.professorURL)
                        Text("공식 자료 확인 · \(lab.checkedAt)").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 18).frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(expanded ? "연구실 설명 접기" : "연구실 설명 펼쳐보기").font(.subheadline.weight(.semibold)).padding(.vertical, 12)
                }
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("연구실")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Wrap real text sizes, including accessibility sizes; no fixed-height tag rows.
struct TopicFlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 320).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + result.points[index].x, y: bounds.minY + result.points[index].y),
                       proposal: ProposedViewSize(width: min(view.sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func arrange(_ views: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        let width = max(1, width)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in views {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += min(size.width, width) + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

struct BuildingGuideView: View {
    let building: CampusBuilding
    var onDirections: () -> Void
    var body: some View {
        List {
            Section("위치 정보") {
                Text(building.displayTitle)
                if let address = building.details?.address { Text(address).font(.subheadline) }
                if let url = building.directionsURL { DirectionsButton(destination: url, name: building.name) { Label("여기로 길찾기", systemImage: "arrow.triangle.turn.up.right.diamond") } }
                Button(action: onDirections) { Label("건물 간 길찾기", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                if let url = building.mapURL { Link("카카오맵에서 위치 보기", destination: url) }
            }
            if let details = building.details {
                Section("건물 소개") { Text(details.summary) }
                Section("이용 안내") {
                    Text(details.usage)
                    if let phone = details.phone, let url = details.phoneURL { Link(phone, destination: url) }
                    if let url = details.websiteURL { Link("운영기관 홈페이지", destination: url) }
                }
                if !details.accessibility.isEmpty {
                    Section("등록된 접근성 정보") { ForEach(details.accessibility, id: \.self) { Text($0) } }
                }
                if !details.notices.isEmpty {
                    Section("공식 안내") {
                        ForEach(Array(details.notices.enumerated()), id: \.offset) { _, notice in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(notice.title).font(.headline)
                                Text(notice.body).font(.subheadline)
                                Link("원문 확인", destination: notice.sourceURL)
                                Text("확인 · \(notice.checkedAt)").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }
                }
                Section("정보 출처") {
                    ForEach(Array(details.sources.enumerated()), id: \.offset) { _, source in
                        VStack(alignment: .leading, spacing: 5) {
                            Link(source.title, destination: source.url)
                            Text("확인 · \(source.checkedAt)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if building.source == "openstreetmap" {
                Section { PlaceSourceLink(title: "지도 좌표 © OpenStreetMap contributors", value: "https://www.openstreetmap.org/copyright") }
            }
        }
        .navigationTitle("이용 안내").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlaceSourceLink: View {
    let title: String
    let value: String
    var body: some View {
        if let url = PlaceDirectory.sourceURL(value) {
            Link(destination: url) { Label(title, systemImage: "arrow.up.right.square").frame(minHeight: 44, alignment: .leading) }
        }
    }
}

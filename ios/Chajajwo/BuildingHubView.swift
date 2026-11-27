import SwiftUI

struct BuildingExplorerSheet: View {
    let building: CampusBuilding
    var onRestaurant: (Place) -> Void
    var onDirections: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var showTasksOnOpen = false
    var initialKind: CampusAmenityKind? = nil
    var initialAmenity: CampusAmenity? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planner = CampusPlannerStore.shared
    @State private var detent: PresentationDetent = .fraction(0.68)
    @State private var showingTasks = false
    @State private var showingAmenity = false

    var body: some View {
        NavigationStack {
            BuildingOverviewView(building: building, onRestaurant: onRestaurant, onDirections: onDirections, initialKind: initialKind)
                .navigationDestination(isPresented: $showingTasks) { CampusTaskListView(building: building) }
                .navigationDestination(isPresented: $showingAmenity) {
                    if let initialAmenity { CampusAmenityDetailView(amenity: initialAmenity) }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.weight(.semibold)).frame(width: 44, height: 44) }
                            .accessibilityLabel("건물 정보 닫기").accessibilityIdentifier("building-explorer.close")
                    }
                }
        }
        .environmentObject(planner).tint(BuildingDesign.green)
        .environment(\.calendar, CampusPlanning.calendar)
        .environment(\.timeZone, CampusPlanning.calendar.timeZone)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .presentationDetents([.fraction(0.68), .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.68)))
        .presentationDragIndicator(.visible).presentationCornerRadius(28)
        .onAppear {
            showingTasks = showTasksOnOpen
            showingAmenity = initialAmenity != nil
            if initialAmenity != nil || initialKind != nil { detent = .large }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-place-building") { detent = .large }
            #endif
        }
        .onChange(of: showTasksOnOpen) { _, value in if value { showingTasks = true } }
        .alert("방문 알림", isPresented: Binding(get: { planner.message != nil }, set: { if !$0 { planner.message = nil } })) {
            Button("확인", role: .cancel) { planner.message = nil }
        } message: { Text(planner.message ?? "") }
    }
}

private enum BuildingHubTab: String, CaseIterable {
    case home, facilities, food, guide
    var title: String { switch self { case .home: "홈"; case .facilities: "시설정보"; case .food: "식당·카페"; case .guide: "이용안내" } }
    var identifier: String { switch self { case .home: "building.home"; case .facilities: "building.floors"; case .food: "building.food"; case .guide: "building.guide" } }
}

struct BuildingOverviewView: View {
    let building: CampusBuilding
    var onRestaurant: (Place) -> Void
    var onDirections: () -> Void
    @EnvironmentObject private var planner: CampusPlannerStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tab = BuildingHubTab.home
    @State private var amenityKind: CampusAmenityKind?

    init(building: CampusBuilding, onRestaurant: @escaping (Place) -> Void, onDirections: @escaping () -> Void, initialKind: CampusAmenityKind? = nil) {
        self.building = building; self.onRestaurant = onRestaurant; self.onDirections = onDirections
        _amenityKind = State(initialValue: initialKind)
        _tab = State(initialValue: initialKind == nil ? .home : .facilities)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                VStack(alignment: .leading, spacing: 15) {
                    header
                    BuildingHeroPhoto(building: building, height: tab == .facilities ? 120 : 168)
                    BuildingDirectionsBanner(building: building)
                }.padding(.horizontal, 18).padding(.bottom, 12).background(Color(uiColor: .systemBackground))
                Section {
                    VStack(spacing: 18) {
                        switch tab {
                        case .home: home
                        case .facilities: BuildingFacilityTab(building: building, kind: $amenityKind)
                        case .food: BuildingFoodCards(building: building, onRestaurant: onRestaurant)
                        case .guide: guide
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                } header: { tabStrip }
            }
        }
        .background(BuildingDesign.canvas)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("building.hub")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(building.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(building.buildingNumberLabel + " · " + (building.details?.category ?? "캠퍼스 공간"))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let english = building.details?.englishName { Text(english).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Button { planner.toggleFavorite(building) } label: {
                Image(systemName: planner.data.favoriteBuildings.contains(building.id) ? "star.fill" : "star")
                    .font(.system(size: 21)).frame(width: 44, height: 44)
                    .background(BuildingDesign.mint, in: Circle())
            }
            .accessibilityLabel(planner.data.favoriteBuildings.contains(building.id) ? "즐겨찾기 해제" : "즐겨찾기 추가")
            .accessibilityIdentifier("building.favorite")
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(BuildingHubTab.allCases, id: \.rawValue) { option in
                    Button { tab = option } label: {
                        VStack(spacing: 13) {
                            Text(option.title).font(.subheadline.weight(tab == option ? .bold : .medium)).fixedSize()
                            Capsule().fill(tab == option ? BuildingDesign.green : .clear).frame(height: 3)
                        }
                        .frame(minWidth: 82).padding(.top, 15).padding(.horizontal, 3)
                        .foregroundStyle(tab == option ? BuildingDesign.green : Color.secondary)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier(option.identifier)
                    .accessibilityAddTraits(tab == option ? .isSelected : [])
                }
            }.padding(.horizontal, 15)
        }
        .scrollIndicators(.hidden).background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { BuildingDesign.line.frame(height: 1) }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !CampusAmenities.inBuilding(building).isEmpty {
                BuildingSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("이 건물에서 찾을 수 있어요").font(.headline); Spacer() }
                        BuildingAmenityBadges(building: building) { kind in amenityKind = kind; tab = .facilities }
                        Button { amenityKind = nil; tab = .facilities } label: {
                            HStack { Text("층별 시설 \(CampusAmenities.inBuilding(building).count)곳 모두 보기"); Spacer(); Image(systemName: "arrow.right") }
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }.accessibilityIdentifier("building.all-facilities")
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                NavigationLink { CampusTaskListView(building: building) } label: {
                    feature("할 일 & 알림", subtitle: "일정 관리, 방문 알림", symbol: "checklist")
                }.accessibilityIdentifier("building.tasks")
                NavigationLink { CampusSpaceRecommendationsView(building: building) } label: {
                    feature("공강 공간 추천", subtitle: "내 일정에 맞는 공간", symbol: "sparkles")
                }.accessibilityIdentifier("building.spaces")
                NavigationLink { BuildingIndoorView(building: building) } label: {
                    feature("내부 공간 찾기", subtitle: "층과 호실 안내", symbol: "mappin.and.ellipse")
                }.accessibilityIdentifier("building.indoor")
                NavigationLink { BuildingFacilityStatusView(building: building) } label: {
                    feature("시설 현황", subtitle: "운영시간 · 정보 확인", symbol: "chart.bar.xaxis")
                }.accessibilityIdentifier("building.status")
            }.buttonStyle(.plain)
            upcomingTasks
            NavigationLink { CampusTimetableView(building: building) } label: {
                BuildingSurface {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").font(.title2).foregroundStyle(BuildingDesign.green)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("내 시간표").font(.headline).foregroundStyle(.primary)
                            Text(planner.data.classes.isEmpty ? "수업을 등록하고 방문 시간을 찾아보세요" : "등록한 수업 \(planner.data.classes.count)개 · 방문 추천 시간 보기")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.buttonStyle(.plain).accessibilityIdentifier("building.timetable")
        }
    }

    private func feature(_ title: String, subtitle: String, symbol: String) -> some View {
        BuildingSurface(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 23)).foregroundStyle(BuildingDesign.green).frame(width: 25)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, minHeight: 63, alignment: .leading)
        }
    }

    private var upcomingTasks: some View {
        BuildingSurface {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("다가오는 할 일", systemImage: "bell").font(.headline)
                    Spacer()
                    NavigationLink("전체 보기") { CampusTaskListView(building: building) }.font(.caption)
                }
                let tasks = Array(planner.tasks(in: building).prefix(2))
                if tasks.isEmpty {
                    Text("이 건물에서 할 일을 기록해 두세요.").font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink { CampusTaskEditorView(building: building) } label: { Label("할 일 추가", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
                } else {
                    ForEach(tasks) { task in CampusTaskRow(task: task) }
                }
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 18) {
            NavigationLink { BuildingGuideView(building: building, onDirections: onDirections) } label: {
                BuildingSurface {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("건물 이용 정보").font(.headline).foregroundStyle(.primary)
                        Label(building.details?.phone ?? "대표전화 미등록", systemImage: "phone").font(.subheadline).foregroundStyle(.secondary)
                        Label("운영기관 홈페이지·접근성·공식 안내", systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                        Text("이용 안내 자세히 보기  ›").font(.subheadline.weight(.semibold))
                    }
                }
            }.buttonStyle(.plain)
            NavigationLink { CampusTimetableView(building: building, initialRecommendations: true) } label: {
                BuildingSurface { Label("내 시간표로 방문 시간 찾기", systemImage: "calendar.badge.clock").font(.headline).frame(minHeight: 44) }
            }.buttonStyle(.plain)
            NavigationLink { CampusScheduleRouteView(building: building) } label: {
                BuildingSurface { Label("내 일정과 건물 간 동선 확인", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline).frame(minHeight: 44) }
            }.buttonStyle(.plain)
            if let photo = CampusBuildingPhoto.photo(for: building) {
                VStack(alignment: .leading, spacing: 3) {
                    PlaceSourceLink(title: photo.credit, value: photo.photoURL)
                    Text("사진 자료 확인 · \(photo.checkedAt)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BuildingFacilityTab: View {
    let building: CampusBuilding
    @Binding var kind: CampusAmenityKind?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink { BuildingFloorView(building: building) } label: {
                Label("연구실·지도교수·시설 검색", systemImage: "magnifyingglass").font(.subheadline)
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityIdentifier("building.facility-search")
            BuildingAmenityDirectory(building: building, kind: $kind)
        }
    }
}

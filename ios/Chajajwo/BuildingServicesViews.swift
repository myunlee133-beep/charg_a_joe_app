import SwiftUI
import MapKit

struct BuildingFoodCards: View {
    let building: CampusBuilding
    var onRestaurant: (Place) -> Void
    @EnvironmentObject private var store: Store
    @State private var filter = "전체"
    private var restaurants: [Place] { Place.all.filter { $0.type == .food && $0.building == building.buildingNumberLabel } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("공간 종류", selection: $filter) { ForEach(["전체", "식당", "카페"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            if filter != "카페" {
                ForEach(restaurants) { restaurant in
                    Button { onRestaurant(restaurant) } label: {
                        BuildingSurface {
                            HStack(spacing: 13) {
                                Image(systemName: "fork.knife").font(.title2).foregroundStyle(BuildingDesign.green).frame(width: 48, height: 58).background(BuildingDesign.mint, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(restaurant.name).font(.headline).foregroundStyle(.primary)
                                    Text(store.dining.hours(for: restaurant, on: Date())).font(.caption).foregroundStyle(.secondary)
                                    Text("오늘의 식단 보기").font(.caption.weight(.medium)).foregroundStyle(BuildingDesign.green)
                                }
                                Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("restaurant.\(restaurant.id)")
                }
            }
            if filter != "식당" {
                ForEach(PlaceDirectory.venues(in: building)) { venue in
                    NavigationLink { CafeMenuView(venue: venue) } label: {
                        BuildingSurface {
                            HStack(spacing: 13) {
                                if let name = PlaceDirectory.imageName(venue.featuredMenu?.photoAsset ?? venue.photoAsset) {
                                    Image(name).resizable().scaledToFit().frame(width: 65, height: 74).background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                                } else { Image(systemName: "cup.and.saucer").font(.title2).foregroundStyle(BuildingDesign.green).frame(width: 48, height: 58).background(BuildingDesign.mint, in: RoundedRectangle(cornerRadius: 12)) }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(venue.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(venue.floor) · 평일 \(venue.weekdayHours)").font(.caption).foregroundStyle(.secondary)
                                    Text("메뉴 사진·상세 보기").font(.caption.weight(.medium)).foregroundStyle(BuildingDesign.green)
                                }
                                Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("venue.\(venue.id)")
                }
            }
            if restaurants.isEmpty && PlaceDirectory.venues(in: building).isEmpty {
                BuildingEmptyCard(symbol: "cup.and.saucer", title: "등록된 매장 정보가 없어요", text: "교내 카페 전체 목록에서 다른 공간을 찾아보세요.")
            }
            NavigationLink { CafeDirectoryView() } label: { Text("교내 카페 전체 보기  ›").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
            Label("혼잡도·좌석 현황은 아직 연결되지 않았어요.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct BuildingFacilityStatusView: View {
    let building: CampusBuilding
    @EnvironmentObject private var store: Store
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BuildingSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("실시간 정보 연결 전", systemImage: "person.2.slash").font(.headline)
                        Text("좌석 수나 혼잡도를 제공하는 데이터가 아직 없어요. 아래에는 공식 등록 운영시간을 안내해요.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                let restaurants = Place.all.filter { $0.type == .food && $0.building == building.buildingNumberLabel }
                ForEach(restaurants) { restaurant in
                    BuildingSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(restaurant.name).font(.headline)
                            Label(store.dining.hours(for: restaurant, on: Date()), systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
                            Text("\(store.dining.status(for: restaurant, at: Date()).title) · 등록 시간 기준").font(.caption).foregroundStyle(BuildingDesign.green)
                        }
                    }
                }
                ForEach(PlaceDirectory.venues(in: building)) { venue in
                    BuildingSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(venue.name).font(.headline)
                            Text("\(venue.floor) · 평일 \(venue.weekdayHours)").font(.subheadline).foregroundStyle(.secondary)
                            Text("좌석·혼잡 정보 확인 불가").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if restaurants.isEmpty && PlaceDirectory.venues(in: building).isEmpty { BuildingEmptyCard(symbol: "clock.badge.questionmark", title: "운영시간 정보가 없어요", text: "건물 이용 안내의 운영기관 연락처를 확인해 주세요.") }
            }.padding(18)
        }.background(BuildingDesign.canvas).navigationTitle("시설 현황").navigationBarTitleDisplayMode(.inline)
    }
}

struct BuildingIndoorView: View {
    let building: CampusBuilding
    @State private var query = ""
    private var facilities: [CampusBuildingFacility] { (building.details?.facilities ?? []).filter { PlaceDirectory.matches(query, fields: [$0.name, $0.category]) } }
    private var labs: [ResearchLab] { PlaceDirectory.labs(in: building).filter { PlaceDirectory.matches(query, fields: $0.searchFields) } }
    var body: some View {
        List {
            Section {} footer: { Text("공식 층·호실 정보를 안내해요. 실내 보행 경로나 출입구 위치는 제공되지 않아 임의 경로를 그리지 않아요.") }
            ForEach(labs) { lab in NavigationLink { ResearchLabView(lab: lab) } label: { VStack(alignment: .leading, spacing: 6) { Text(lab.name).font(.headline); Text(lab.room).font(.subheadline).foregroundStyle(.secondary) } } }
            ForEach(facilities) { facility in
                VStack(alignment: .leading, spacing: 8) {
                    Text(facility.name).font(.headline)
                    Label(PlaceDirectory.floorName(facility.floor), systemImage: "square.3.layers.3d").font(.subheadline).foregroundStyle(BuildingDesign.green)
                }.padding(.vertical, 8)
            }
            if labs.isEmpty && facilities.isEmpty { ContentUnavailableView.search(text: query) }
        }.searchable(text: $query, prompt: "찾는 시설·연구실 검색").navigationTitle("내부 공간 찾기").navigationBarTitleDisplayMode(.inline)
    }
}

struct CampusSpaceRecommendationsView: View {
    let building: CampusBuilding
    @EnvironmentObject private var planner: CampusPlannerStore
    @State private var kind = "전체"
    private var nextClass: CampusClass? { CampusPlanning.nextClass(planner.data.classes, on: Date(), calendar: CampusPlanning.calendar) }
    private var spaces: [CampusSpace] {
        CampusSpace.all.filter { (kind == "전체" || $0.kind == kind) && $0.building.coordinate.distance(to: building.coordinate) <= 700 }
            .sorted {
                let a = $0.building.coordinate.distance(to: building.coordinate), b = $1.building.coordinate.distance(to: building.coordinate)
                return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a < b
            }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BuildingSurface {
                    VStack(alignment: .leading, spacing: 9) {
                        if let nextClass {
                            let remaining = nextClass.startMinute - CampusPlanning.minute(of: Date(), calendar: CampusPlanning.calendar)
                            Label("다음 수업까지 \(remaining)분", systemImage: "calendar.badge.clock").font(.headline)
                            Text("\(nextClass.title) · \(nextClass.buildingNumber.isEmpty ? "위치 미등록" : nextClass.buildingNumber + "동 " + nextClass.room)").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Label(planner.data.classes.isEmpty ? "시간표와 함께 공간을 찾아보세요" : "오늘 남은 수업이 없어요", systemImage: "sparkles").font(.headline)
                            Text("이 건물과 주변에 공식 등록된 공간을 모았어요.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Picker("공간 종류", selection: $kind) { ForEach(["전체", "카페", "도서·학습", "라운지"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                ForEach(Array(spaces.prefix(16))) { space in
                    BuildingSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: space.kind == "카페" ? "cup.and.saucer" : "books.vertical").font(.title2).foregroundStyle(BuildingDesign.green).frame(width: 42, height: 52)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(space.name).font(.headline)
                                    Text(space.locationLabel).font(.subheadline).foregroundStyle(.secondary)
                                    Text(space.building.id == building.id ? "이 건물 안" : "건물 간 직선거리 약 \(Int((space.building.coordinate.distance(to: building.coordinate) / 10).rounded()) * 10)m")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 16) {
                                NavigationLink { CampusTaskEditorView(building: space.building, presetTitle: space.name + " 이용하기", presetLocation: space.locationLabel) } label: { Label("할 일 추가", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
                                Spacer()
                                if let url = space.building.directionsURL { DirectionsButton(destination: url, name: space.name) { Label("길찾기", systemImage: "location").font(.subheadline.weight(.semibold)).frame(minHeight: 44) } }
                            }
                        }
                    }
                }
                if spaces.isEmpty { BuildingEmptyCard(symbol: "magnifyingglass", title: "등록된 공간이 없어요", text: "다른 종류를 선택해 보세요.") }
                Text("공식 등록 공간을 거리순으로 안내해요. 좌석·콘센트·정숙도는 확인되지 않았으며, 직선거리는 실제 보행거리와 달라요.").font(.caption).foregroundStyle(.secondary)
                if let nextClass, let destination = CampusBuildingCatalog.all.first(where: { $0.number == nextClass.buildingNumber }) {
                    NavigationLink { BuildingDirectionsView(origin: building, destination: destination) } label: {
                        BuildingSurface { Label("이용 후 다음 수업으로 길찾기", systemImage: "figure.walk").font(.headline).frame(minHeight: 44) }
                    }.buttonStyle(.plain)
                }
            }.padding(18)
        }.background(BuildingDesign.canvas).navigationTitle("공강 공간 추천").navigationBarTitleDisplayMode(.inline)
    }
}

struct CampusScheduleRouteView: View {
    let building: CampusBuilding
    @EnvironmentObject private var planner: CampusPlannerStore
    private var next: CampusClass? { CampusPlanning.nextClass(planner.data.classes, on: Date(), calendar: CampusPlanning.calendar) }
    private var destination: CampusBuilding? { next.flatMap { item in CampusBuildingCatalog.all.first { $0.number == item.buildingNumber } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BuildingSurface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("내 일정 기반 동선", systemImage: "calendar").font(.headline)
                        Label(building.displayTitle, systemImage: "mappin.circle.fill").font(.headline).foregroundStyle(BuildingDesign.green)
                        if let next {
                            Image(systemName: "arrow.down").foregroundStyle(.secondary)
                            Text("\(next.title) · \(CampusPlanning.time(next.startMinute)) 시작").font(.headline)
                            Text(next.buildingNumber.isEmpty ? "수업 위치 미등록" : next.buildingNumber + "동 " + next.room).font(.subheadline).foregroundStyle(.secondary)
                        } else { Text("오늘 남은 수업이 없거나 아직 시간표를 등록하지 않았어요.").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                Map(initialPosition: .region(MKCoordinateRegion(center: .init(latitude: building.latitude, longitude: building.longitude), span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
                    Marker(building.name, coordinate: .init(latitude: building.latitude, longitude: building.longitude)).tint(BuildingDesign.green)
                    if let destination { Marker(destination.name, coordinate: .init(latitude: destination.latitude, longitude: destination.longitude)).tint(.blue) }
                }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("선택한 건물과 다음 수업 건물 위치")
                Text("등록된 건물 위치를 표시해요. 실제 보행 경로와 시간은 길찾기에서 확인해 주세요.").font(.caption).foregroundStyle(.secondary)
                BuildingDirectionsBanner(building: building)
                if let destination {
                    NavigationLink { BuildingDirectionsView(origin: building, destination: destination) } label: {
                        Label("다음 수업까지 길찾기", systemImage: "figure.walk").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                            .background(BuildingDesign.green, in: Capsule()).foregroundStyle(.white)
                    }
                } else { NavigationLink("시간표 등록·수정") { CampusTimetableView(building: building) }.frame(minHeight: 44) }
            }.padding(18)
        }.background(BuildingDesign.canvas).navigationTitle("일정 연동 길찾기").navigationBarTitleDisplayMode(.inline)
    }
}

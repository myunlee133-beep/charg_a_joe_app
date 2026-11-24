import SwiftUI

struct BuildingFoodView: View {
    let building: CampusBuilding
    var onRestaurant: (Place) -> Void
    private var restaurants: [Place] {
        Place.all.filter { $0.type == .food && building.number != nil && $0.building == building.buildingNumberLabel }
    }
    var body: some View {
        List {
            if !restaurants.isEmpty {
                Section("식당") {
                    ForEach(restaurants) { place in
                        Button { onRestaurant(place) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(place.name).foregroundStyle(.primary)
                                    Text("기존 식단 화면에서 보기").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 8)
                            } icon: { Image(systemName: "fork.knife").foregroundStyle(Color.cjOrangeText) }
                        }
                        .accessibilityIdentifier("restaurant.\(place.id)")
                    }
                }
            }
            if !PlaceDirectory.venues(in: building).isEmpty {
                Section("카페·간식") {
                    ForEach(PlaceDirectory.venues(in: building)) { venue in
                        NavigationLink { CafeMenuView(venue: venue) } label: { CafeDirectoryRow(venue: venue) }
                            .accessibilityIdentifier("venue.\(venue.id)")
                    }
                }
            }
            if restaurants.isEmpty && PlaceDirectory.venues(in: building).isEmpty {
                ContentUnavailableView("등록된 식당·카페 정보가 없어요", systemImage: "cup.and.saucer",
                                       description: Text("교내 카페 목록에서 다른 공간을 찾아보세요."))
            }
            Section { NavigationLink("교내 카페 전체 보기") { CafeDirectoryView() } }
        }
        .navigationTitle("식당·카페").navigationBarTitleDisplayMode(.inline)
    }
}

struct CafeDirectoryView: View {
    @State private var query = ""
    private var venues: [CampusVenue] { PlaceDirectory.venues.filter { PlaceDirectory.matches(query, fields: $0.searchFields) } }
    var body: some View {
        List {
            Section {
                ForEach(venues) { venue in
                    NavigationLink { CafeMenuView(venue: venue) } label: { CafeDirectoryRow(venue: venue) }
                        .accessibilityIdentifier("venue.\(venue.id)")
                }
            } footer: { Text("공식 자료로 확인한 카페 \(PlaceDirectory.venues.count)곳을 안내해요. 매장별 메뉴 정보와 사진의 등록 범위가 달라요.") }
            if venues.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "카페·동 번호·메뉴 검색")
        .navigationTitle("교내 카페").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CafeDirectoryRow: View {
    let venue: CampusVenue
    private var photo: String? { venue.featuredMenu?.photoAsset ?? venue.menus.first(where: { $0.photoAsset != nil })?.photoAsset ?? venue.photoAsset }
    var body: some View {
        HStack(spacing: 14) {
            if let name = PlaceDirectory.imageName(photo) {
                Image(name).resizable().scaledToFit().frame(width: 72, height: 80)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "cup.and.saucer").font(.title2).foregroundStyle(.secondary)
                    .frame(width: 72, height: 80).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(venue.name).font(.headline)
                Text("\(venue.buildingNumber)동 · \(venue.floor)").font(.caption).foregroundStyle(.secondary)
                if let menu = venue.featuredMenu { Text(menu.name).font(.caption).foregroundStyle(Color.cjTealText) }
            }
        }.padding(.vertical, 8)
    }
}

struct CafeMenuView: View {
    let venue: CampusVenue
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var informationExpanded = false
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(venue.buildingNumber)동 · \(venue.floor)").font(.subheadline).foregroundStyle(.secondary)
                    Text(venue.name).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                }
                if let featured = venue.featuredMenu {
                    NavigationLink { CafeMenuDetailView(venue: venue, menu: featured) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            MenuPhoto(asset: featured.photoAsset, label: featured.name, height: 210)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("시그니처 메뉴").font(.caption.weight(.semibold)).foregroundStyle(Color.cjTealText)
                                Text(featured.name).font(.title3.bold()).foregroundStyle(.primary)
                                Text("메뉴 자세히 보기").font(.caption).foregroundStyle(.secondary)
                            }.padding([.horizontal, .bottom], 16)
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("cafe.featured")
                } else if let photo = venue.photoAsset {
                    VStack(alignment: .leading, spacing: 8) {
                        MenuPhoto(asset: photo, label: venue.photoCaption ?? venue.name, height: 210)
                        Text(venue.photoCaption ?? "카페 메뉴 사진").font(.caption).foregroundStyle(.secondary)
                        if let credit = venue.photoCredit { Text(credit).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("메뉴 둘러보기").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(venue.menus) { menu in
                            NavigationLink { CafeMenuDetailView(venue: venue, menu: menu) } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    if menu.photoAsset != nil { MenuPhoto(asset: menu.photoAsset, label: menu.name, height: 145) }
                                    Text(menu.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(menu.priceLabel).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("menu.\(menu.name)")
                        }
                    }
                }
                Text(venue.menuNote).font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup(isExpanded: $informationExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("평일 \(venue.weekdayHours)", systemImage: "clock")
                        Text("방학·휴일 운영은 매장에 확인해 주세요.").font(.caption).foregroundStyle(.secondary)
                        if let url = PlaceDirectory.phoneURL(venue.phone) { Link(venue.phone, destination: url) }
                        PlaceSourceLink(title: "매장 공식 안내", value: venue.sourceURL)
                        PlaceSourceLink(title: "공식 메뉴 원문", value: venue.menuSourceURL)
                        if let credit = venue.featuredMenu?.photoCredit { Text(credit).font(.caption).foregroundStyle(.secondary) }
                        Text("공식 자료 확인 · \(venue.checkedAt)").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 16).frame(maxWidth: .infinity, alignment: .leading)
                } label: { Text("운영시간·문의·출처").font(.subheadline.weight(.semibold)).padding(.vertical, 10) }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("카페 메뉴").navigationBarTitleDisplayMode(.inline)
    }
}

private struct MenuPhoto: View {
    let asset: String?
    let label: String
    let height: CGFloat
    var body: some View {
        if let name = PlaceDirectory.imageName(asset) {
            Image(name).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: height)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(label + " 공식 메뉴 사진")
        }
    }
}

struct CafeMenuDetailView: View {
    let venue: CampusVenue
    let menu: VenueMenu
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if menu.photoAsset != nil { MenuPhoto(asset: menu.photoAsset, label: menu.name, height: 300) }
                Text(menu.name).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(menu.priceLabel).font(.headline).foregroundStyle(.secondary)
                Text(menu.description).font(.body)
                Text(venue.menuNote).font(.footnote).foregroundStyle(.secondary)
                Divider()
                PlaceSourceLink(title: "공식 메뉴 원문", value: venue.menuSourceURL)
                if let source = menu.photoSourceURL { PlaceSourceLink(title: menu.photoCredit ?? "공식 메뉴 사진 출처", value: source) }
                Text("공식 자료 확인 · \(venue.checkedAt)").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("메뉴 상세").navigationBarTitleDisplayMode(.inline)
    }
}

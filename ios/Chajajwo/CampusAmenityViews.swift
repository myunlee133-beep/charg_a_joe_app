import SwiftUI

struct CampusAmenityMapPin: View {
    let kind: CampusAmenityKind
    let count: Int
    let name: String?
    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: kind.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(kind.ink, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                if count > 1 {
                    Text("\(count)").font(.system(size: 10, weight: .bold)).foregroundStyle(kind.ink)
                        .padding(3).background(.white, in: Circle()).offset(x: 5, y: -4)
                }
            }
            if let name { Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black).lineLimit(1).padding(.trailing, 9) }
        }.padding(3).background(.white, in: Capsule()).shadow(color: .black.opacity(0.15), radius: 3, y: 2).padding(5)
    }
}

extension CampusAmenityKind {
    var ink: Color {
        switch self {
        case .pharmacy, .health: Color(hex: 0xa43f5b)
        case .convenience: Color(hex: 0x32699c)
        case .cafe: Color(hex: 0x89613a)
        default: BuildingDesign.green
        }
    }
    var wash: Color { ink.opacity(0.09) }
}

struct CampusAmenityIcon: View {
    let kind: CampusAmenityKind
    var size: CGFloat = 42
    var body: some View {
        Image(systemName: kind.symbol).font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(kind.ink).frame(width: size, height: size)
            .background(kind.wash, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct CampusAmenityRow: View {
    let amenity: CampusAmenity
    var showBuilding = false
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CampusAmenityIcon(kind: amenity.kind)
            VStack(alignment: .leading, spacing: 5) {
                Text(amenity.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(showBuilding ? amenity.location : amenity.shortFloor + " · " + amenity.facility.category)
                    .font(.caption).foregroundStyle(.secondary)
                if let hours = amenity.weekdayHours {
                    Text("평일 " + hours).font(.caption).foregroundStyle(amenity.kind.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(12)
            .contentShape(Rectangle())
    }
}

struct BuildingAmenityBadges: View {
    let building: CampusBuilding
    var onSelect: (CampusAmenityKind) -> Void
    var body: some View {
        TopicFlowLayout(spacing: 8) {
            ForEach(CampusAmenityKind.highlights, id: \.self) { kind in
                let count = CampusAmenities.inBuilding(building, kind: kind).count
                if count > 0 {
                    Button { onSelect(kind) } label: {
                        Label { Text(kind.title + " \(count)").monospacedDigit() } icon: { Image(systemName: kind.symbol) }
                            .font(.caption.weight(.semibold)).padding(.horizontal, 11).frame(minHeight: 44)
                            .foregroundStyle(kind.ink).background(kind.wash, in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel("\(kind.title) \(count)곳 보기")
                        .accessibilityIdentifier("building.kind.\(kind.rawValue)")
                }
            }
        }
    }
}

struct BuildingAmenityDirectory: View {
    let building: CampusBuilding
    @Binding var kind: CampusAmenityKind?
    @State private var floor: String?
    private var amenities: [CampusAmenity] { CampusAmenities.inBuilding(building, kind: kind) }
    private var labs: [ResearchLab] { kind == nil ? PlaceDirectory.labs(in: building) : [] }
    private var floors: [String] {
        Set(amenities.map(\.floor) + labs.map(\.floor)).sorted {
            let a = PlaceDirectory.floorOrder($0), b = PlaceDirectory.floorOrder($1)
            return a == b ? $0.localizedStandardCompare($1) == .orderedAscending : a < b
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("층별로 둘러보기").font(.title3.bold())
                    Text("필요한 공간을 고르면 자세히 볼 수 있어요").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton(nil)
                    ForEach(CampusAmenityKind.highlights, id: \.self) { item in
                        if !CampusAmenities.inBuilding(building, kind: item).isEmpty { categoryButton(item) }
                    }
                }
            }
            if floors.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        Button("전체 층") { floor = nil }.font(.subheadline.weight(floor == nil ? .bold : .regular))
                            .foregroundStyle(floor == nil ? BuildingDesign.green : .secondary).frame(minHeight: 44)
                        ForEach(floors, id: \.self) { value in
                            Button(value.replacingOccurrences(of: "지상", with: "")) { floor = value }
                                .font(.subheadline.weight(floor == value ? .bold : .regular))
                                .foregroundStyle(floor == value ? BuildingDesign.green : .secondary).frame(minHeight: 44)
                                .accessibilityIdentifier("hub-floor.\(value)")
                        }
                    }
                }
            }
            ForEach(floors.filter { floor == nil || floor == $0 }, id: \.self) { level in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 10) {
                        Text(level.replacingOccurrences(of: "지상", with: "")).font(.subheadline.weight(.bold))
                            .foregroundStyle(BuildingDesign.green).fixedSize(horizontal: false, vertical: true)
                        Capsule().fill(BuildingDesign.line).frame(width: 2).frame(maxHeight: .infinity)
                    }.frame(width: 42)
                    VStack(spacing: 0) {
                        ForEach(amenities.filter { $0.floor == level }) { amenity in
                            NavigationLink { CampusAmenityDetailView(amenity: amenity) } label: { CampusAmenityRow(amenity: amenity) }
                                .buttonStyle(.plain).accessibilityIdentifier("amenity.\(amenity.id)")
                            if amenity.id != amenities.filter({ $0.floor == level }).last?.id || !labs.filter({ $0.floor == level }).isEmpty { Divider().padding(.leading, 66) }
                        }
                        ForEach(labs.filter { $0.floor == level }) { lab in
                            NavigationLink { ResearchLabView(lab: lab) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "flask.fill").foregroundStyle(BuildingDesign.green).frame(width: 42)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(lab.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text("지도교수 \(lab.professor) · \(lab.field)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.padding(14)
                            }.buttonStyle(.plain)
                        }
                    }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(BuildingDesign.line.opacity(0.8)))
                }.fixedSize(horizontal: false, vertical: true)
            }
            if floors.isEmpty { BuildingEmptyCard(symbol: "building.2", title: "등록된 시설이 없어요", text: "다른 종류를 선택해 보세요.") }
            Text("공식 자료에 등록된 시설이에요. 상세 정보에서 운영시간·연락처와 자료 출처를 확인할 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
        }.onChange(of: kind) { _, _ in floor = nil }
    }
    private func categoryButton(_ item: CampusAmenityKind?) -> some View {
        Button { kind = item; floor = nil } label: {
            Text(item?.title ?? "전체").font(.subheadline.weight(.semibold)).padding(.horizontal, 15).frame(minHeight: 44)
                .foregroundStyle(kind == item ? Color.white : .primary)
                .background(kind == item ? BuildingDesign.green : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(kind == item ? .isSelected : [])
            .accessibilityIdentifier("amenity-category.\(item?.rawValue ?? "all")")
    }
}

struct CampusAmenityDetailView: View {
    let amenity: CampusAmenity
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        CampusAmenityIcon(kind: amenity.kind, size: 62)
                        Spacer()
                        Text(amenity.facility.category).font(.caption.weight(.semibold))
                            .foregroundStyle(amenity.kind.ink).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(amenity.kind.wash, in: Capsule())
                    }
                    Text(amenity.name).font(.title.bold()).accessibilityAddTraits(.isHeader)
                    Label(amenity.location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { directions; phone }
                        VStack(spacing: 10) { directions; phone }
                    }
                    if let phone = amenity.phone {
                        Text(phone).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("amenity.phone")
                    }
                }.padding(20).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22))
                BuildingSurface {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("운영시간", systemImage: "clock").font(.headline)
                        if let weekday = amenity.weekdayHours {
                            hours("평일", weekday)
                            if let saturday = amenity.info?.saturdayHours { hours("토요일", saturday) }
                            if let holiday = amenity.info?.holidayHours { hours("휴일", holiday) }
                            Text("공개된 운영시간 기준이에요. 학기·방학·임시휴무에 따라 달라질 수 있어요.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("운영시간이 아직 등록되지 않았어요.").font(.subheadline).foregroundStyle(.secondary)
                            Text("방문 전 공식 안내나 운영기관에 확인해 주세요.").font(.caption).foregroundStyle(.secondary)
                        }
                        if let note = amenity.info?.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let venue = amenity.venue {
                    NavigationLink { CafeMenuView(venue: venue) } label: {
                        BuildingSurface {
                            HStack(spacing: 16) {
                                if let image = PlaceDirectory.imageName(venue.featuredMenu?.photoAsset ?? venue.photoAsset) {
                                    Image(image).resizable().scaledToFit().frame(width: 92, height: 100).accessibilityHidden(true)
                                } else { CampusAmenityIcon(kind: .cafe, size: 62) }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("메뉴 둘러보기").font(.headline).foregroundStyle(.primary)
                                    Text(venue.featuredMenu?.name ?? venue.photoCaption ?? "공식 안내에 수록된 메뉴").font(.subheadline).foregroundStyle(.secondary)
                                    Text("메뉴 사진·상세 보기  ›").font(.caption.weight(.semibold)).foregroundStyle(BuildingDesign.green)
                                }
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("amenity.menu")
                }
                if let info = amenity.info, !info.items.isEmpty {
                    BuildingSurface {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("이용할 수 있는 품목").font(.headline)
                            TopicFlowLayout(spacing: 8) {
                                ForEach(info.items, id: \.self) { item in
                                    Text(item).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 9)
                                        .background(amenity.kind.wash, in: Capsule())
                                }
                            }
                        }
                    }
                }
                BuildingSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("건물 안 위치", systemImage: "square.3.layers.3d").font(.headline)
                        Text(amenity.building.name + " " + amenity.shortFloor).font(.title3.weight(.semibold))
                        Text("지도와 길찾기는 건물 위치를 안내해요. 층과 출입구를 확인해 방문해 주세요.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("자료 출처·확인일") {
                    VStack(alignment: .leading, spacing: 12) {
                        PlaceSourceLink(title: "공식 시설 안내", value: amenity.sourceURL)
                        Text("자료 확인 · " + amenity.checkedAt).font(.caption).foregroundStyle(.secondary)
                        Text("실시간 영업 상태·재고 정보는 제공하지 않아요.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                }.font(.subheadline).padding(.horizontal, 4)
            }.padding(18)
        }.background(BuildingDesign.canvas).navigationTitle("시설 상세").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("amenity.detail")
    }
    private var directions: some View {
        Group {
            if let url = amenity.building.directionsURL {
                DirectionsButton(destination: url, name: amenity.name) {
                    Label("건물까지 길찾기", systemImage: "location.fill").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12)
                        .background(BuildingDesign.green, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(.white)
                }
            }
        }
    }
    @ViewBuilder private var phone: some View {
        if let value = amenity.phone, let url = PlaceDirectory.phoneURL(value) {
            Link(destination: url) { Label("전화", systemImage: "phone.fill").font(.subheadline.weight(.semibold)).frame(minWidth: 76, minHeight: 48).background(BuildingDesign.mint, in: RoundedRectangle(cornerRadius: 13)) }
                .accessibilityLabel("\(amenity.name) 전화 \(value)")
        }
    }
    private func hours(_ day: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(day).font(.subheadline).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
            Text(value).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import SwiftUI

struct BuildingDirectionsRequest: Identifiable {
    let id = UUID()
    var destination: CampusBuilding? = nil
}

struct BuildingDirectionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var origin: CampusBuilding?
    @State private var destination: CampusBuilding?
    @State private var transport = DirectionsTransport.walk
    @State private var selecting: EndpointField?

    private enum EndpointField: String, Identifiable {
        case origin, destination
        var id: String { rawValue }
        var title: String { self == .origin ? "출발 건물" : "도착 건물" }
    }

    init(origin: CampusBuilding? = nil, destination: CampusBuilding? = nil) {
        _origin = State(initialValue: origin)
        _destination = State(initialValue: destination)
    }

    private var routeURL: URL? {
        guard let origin, let destination, origin.id != destination.id else { return nil }
        return DirectionsURL.route(from: origin.directionsEndpoint, to: destination.directionsEndpoint, transport: transport)
    }

    private var routeName: String {
        "\(origin?.displayTitle ?? "출발 건물") → \(destination?.displayTitle ?? "도착 건물")"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    endpointButton(.origin, building: origin)
                    endpointButton(.destination, building: destination)
                    Button {
                        let previousOrigin = origin
                        origin = destination
                        destination = previousOrigin
                    } label: {
                        Label("출발·도착 바꾸기", systemImage: "arrow.up.arrow.down")
                            .frame(minHeight: 44)
                    }
                    .disabled(origin == nil && destination == nil)
                    .accessibilityIdentifier("directions.swap")
                } header: {
                    Text("어디에서 어디로 갈까요?")
                } footer: {
                    if origin != nil, destination != nil, routeURL == nil {
                        Text("출발지와 도착지가 같아요. 서로 다른 위치의 건물을 선택해주세요.")
                            .foregroundStyle(Color.cjOrangeText)
                    } else {
                        Text("건물 이름이나 동 번호로 검색할 수 있어요.")
                    }
                }

                Section("이동 수단") {
                    Picker("이동 수단", selection: $transport) {
                        ForEach(DirectionsTransport.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("건물 간 길찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                DirectionsButton(destination: routeURL, name: routeName) {
                    Label("경로 보기", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("directions.showRoute")
                .padding(16)
                .background(Color.cjSurface)
            }
            .sheet(item: $selecting) { field in
                DirectionsBuildingPicker(title: field.title,
                                         selectedID: field == .origin ? origin?.id : destination?.id) { building in
                    if field == .origin { origin = building } else { destination = building }
                }
            }
        }
    }

    private func endpointButton(_ field: EndpointField, building: CampusBuilding?) -> some View {
        Button { selecting = field } label: {
            HStack(spacing: 12) {
                Image(systemName: field == .origin ? "circle.circle.fill" : "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(field == .origin ? Color.cjTealText : Color.cjOrangeText)
                VStack(alignment: .leading, spacing: 5) {
                    Text(field.title).font(.caption).foregroundStyle(Color.cjSub)
                    Text(building?.displayTitle ?? "건물을 선택해주세요")
                        .font(.body.weight(building == nil ? .regular : .semibold))
                        .foregroundStyle(building == nil ? Color.cjSub : Color.primary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.cjSub)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("directions.\(field.rawValue)")
    }
}

private struct DirectionsBuildingPicker: View {
    let title: String
    let selectedID: String?
    let onSelect: (CampusBuilding) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var buildings: [CampusBuilding] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CampusBuildingCatalog.all.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
        return CampusBuildingCatalog.search(query)
    }

    var body: some View {
        NavigationStack {
            List(buildings) { building in
                Button {
                    onSelect(building)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(building.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(building.buildingNumberLabel).font(.subheadline).foregroundStyle(Color.cjSub)
                        }
                        Spacer()
                        if building.id == selectedID {
                            Image(systemName: "checkmark").foregroundStyle(Color.cjTealText)
                        }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(building.displayTitle)
                .accessibilityAddTraits(building.id == selectedID ? .isSelected : [])
            }
            .overlay {
                if buildings.isEmpty {
                    ContentUnavailableView {
                        Label(CampusBuildingCatalog.all.isEmpty ? "건물 목록을 불러오지 못했어요" : "검색 결과가 없어요", systemImage: "building.2")
                    } description: {
                        Text(CampusBuildingCatalog.all.isEmpty ? "앱을 다시 실행한 뒤 확인해주세요." : "다른 건물 이름이나 동 번호로 검색해주세요.")
                    }
                }
            }
            .searchable(text: $query, prompt: "건물 이름 또는 동 번호")
            .navigationTitle("\(title) 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("취소") { dismiss() } }
            }
        }
    }
}

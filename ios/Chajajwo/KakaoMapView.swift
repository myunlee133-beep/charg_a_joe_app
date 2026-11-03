import SwiftUI
import KakaoMapsSDK
import CoreLocation

/// 카카오맵 위에 거점 핀(POI)을 올리는 SwiftUI 래퍼.
struct KakaoMapView: UIViewRepresentable {
    let places: [Place]            // 지금 필터에 맞는 장소
    let counts: [String: Int]      // 거점별 보관 건수
    let selected: String
    let sheetOpen: Bool            // 하단 카드가 펼쳐졌는지
    let focusedBuilding: CampusBuilding?  // Search-selected campus building
    let focusSerial: Int                  // Increment to re-focus even for the same ID
    let userCoordinate: CLLocationCoordinate2D?
    let userHeadingDegrees: Double?
    let userFocusSerial: Int              // One-tap recenter; does not force camera following
    var shuttle: CircularShuttleService? = nil  // 셔틀 핀은 SwiftUI를 거치지 않고 위치가 바뀔 때 바로 옮긴다
    var zoomRequest = 0
    let onSelect: (String) -> Void

    static func initSDK() {
        let key = Bundle.main.object(forInfoDictionaryKey: "KAKAO_APP_KEY") as? String ?? ""
        SDKInitializer.InitSDK(appKey: key)
    }

    func makeUIView(context: Context) -> KMViewContainer {
        let container = KMViewContainer()
        context.coordinator.createController(container)
        shuttle?.onPositionsChange = { [weak coordinator = context.coordinator] in coordinator?.shuttlesChanged() }
        return container
    }

    func updateUIView(_ uiView: KMViewContainer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleUIView(_ uiView: KMViewContainer, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor final class Coordinator: NSObject, MapControllerDelegate, KakaoMapEventDelegate {
        var parent: KakaoMapView
        private var controller: KMController?
        private var pois: [String: Poi] = [:]
        private var appliedStyle: [String: String] = [:]
        private var placeTapHandlers: [String: DisposableEventHandler] = [:]
        private var foodGeometry: [String: (CGSize, CGFloat)] = [:]
        private var addedStyles: Set<String> = []
        private var lastSelected: String?
        private var lastSheetOpen = false
        private var buildingPois: [String: Poi] = [:]
        private var lastBuildingID: String?
        private var lastFocusSerial = -1
        private let layerID = "places"
        private let userLayerID = "user-location"
        private let shuttleLayerID = "circular-shuttle"
        private var shuttlePois: [String: Poi] = [:]
        private var lastZoomRequest = 0
        private var lastPlaceTapAt = -Double.infinity
        private var userDot: Poi?
        private var userDirection: Poi?
        // Zero means no locate-button request. Receiving the first GPS fix must
        // not replace the compact campus overview with an automatic zoom to 17.
        private var lastUserFocusSerial = 0
        private let viewName = "mapview"
        /// 이 지도 레벨보다 멀리서 볼 때는 핀을 모두 숨긴다(기본 화면은 레벨 14).
        private static let minPinLevel = 14
        private static let minShuttleLevel = 15
        private var pinsVisible = false

        init(_ parent: KakaoMapView) { self.parent = parent }

        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func createController(_ container: KMViewContainer) {
            let c = KMController(viewContainer: container)
            c.delegate = self
            controller = c
            c.prepareEngine()
        }

        func tearDown() {
            placeTapHandlers.values.forEach { $0.dispose() }
            placeTapHandlers.removeAll()
            // The six-tab container removes the home view when changing tabs.
            // Release this engine before a later home view creates another one.
            controller?.pauseEngine()
            controller?.delegate = nil
            (controller?.getView(viewName) as? KakaoMap)?.eventDelegate = nil
            controller?.resetEngine()
            controller = nil
            pois.removeAll(); buildingPois.removeAll(); shuttlePois.removeAll()
            userDot = nil; userDirection = nil
        }

        // MARK: MapControllerDelegate
        func authenticationSucceeded() {
            if controller?.isEngineActive == false { controller?.activateEngine() }
        }
        func authenticationFailed(_ errorCode: Int, desc: String) {
            print("카카오맵 인증 실패 \(errorCode): \(desc)") // 키 오류는 재시도해도 소용없어서 재시도 안 함
        }

        func addViews() {
            // 위쪽 검색창·아래쪽 시트에 가려지지 않게 학생회관 일대를 중심에 둔다.
            var initialLevel = 15
            var initialCoordinate = CampusCoordinate(latitude: 37.4600, longitude: 126.9520)
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-preview-map-zoom"), index + 1 < args.count, let level = Int(args[index + 1]) {
                initialLevel = min(20, max(7, level))
            }
            if args.contains("-preview-map-student-hall") {
                initialLevel = 17
                initialCoordinate = .init(latitude: 37.45925, longitude: 126.9506)
            }
            #endif
            let info = MapviewInfo(viewName: viewName, viewInfoName: "map",
                                   defaultPosition: MapPoint(longitude: initialCoordinate.longitude, latitude: initialCoordinate.latitude), defaultLevel: initialLevel)
            controller?.addView(info)
        }
        func addViewSucceeded(_ viewName: String, viewInfoName: String) {
            guard let map = controller?.getView(viewName) as? KakaoMap else { return }
            map.eventDelegate = self
            let manager = map.getLabelManager()
            _ = manager.addLabelLayer(option: LabelLayerOptions(layerID: layerID, competitionType: .none,
                                                                competitionUnit: .symbolFirst, orderType: .rank, zOrder: 20000)) // 지도 기본 글자(zOrder ~10000)보다 위에 그려야 이름표가 안 가려진다
            manager.getLabelLayer(layerID: layerID)?.setClickable(true) // 레이어에서도 켜야 핀 탭 이벤트가 온다
            _ = manager.addLabelLayer(option: LabelLayerOptions(
                layerID: userLayerID, competitionType: .none,
                competitionUnit: .symbolFirst, orderType: .rank, zOrder: 25000))
            userDot = nil
            userDirection = nil
            _ = manager.addLabelLayer(option: LabelLayerOptions(layerID: shuttleLayerID, competitionType: .none,
                competitionUnit: .symbolFirst, orderType: .rank, zOrder: 24000))
            refresh()
        }
        func addViewFailed(_ viewName: String, viewInfoName: String) { print("카카오맵 뷰 추가 실패") }
        func containerDidResized(_ size: CGSize) {
            (controller?.getView(viewName) as? KakaoMap)?.viewRect = CGRect(origin: .zero, size: size)
        }
        func viewWillDestroyed(_ view: ViewBase) { userDot = nil; userDirection = nil }
        func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) { refresh() }

        // MARK: 핀 갱신
        func refresh() {
            guard let map = controller?.getView(viewName) as? KakaoMap else { return }
            let manager = map.getLabelManager()
            guard let layer = manager.getLabelLayer(layerID: layerID) else { return }
            // Apply the current card's margins before creating camera updates or
            // measuring labels, so they never use stale margins.
            if lastSheetOpen != parent.sheetOpen {
                if parent.sheetOpen { map.setMargins(UIEdgeInsets(top: 0, left: 0, bottom: 190, right: 0)) }
                else { map.resetMargins() }
                lastSheetOpen = parent.sheetOpen
            }
            // User marker is always visible, even at map levels where pins are hidden.
            refreshUserLocation(on: map, manager: manager)
            refreshShuttles(on: map, manager: manager)
            if parent.zoomRequest != lastZoomRequest {
                let delta = parent.zoomRequest - lastZoomRequest
                lastZoomRequest = parent.zoomRequest
                let center = map.getPosition(CGPoint(x: map.viewRect.width / 2, y: map.viewRect.height / 2))
                let update = CameraUpdate.make(target: center, zoomLevel: min(20, max(7, Int(map.zoomLevel) + delta)), mapView: map)
                map.animateCamera(cameraUpdate: update, options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 300))
            }
            let visible = Set(parent.places.map(\.id))
            pinsVisible = map.zoomLevel >= Self.minPinLevel

            for p in Place.all {
                let count = parent.counts[p.id] ?? 0
                let isSel = parent.selected == p.id
                let styleID = p.type == .food ? "food-\(p.id)-\(isSel)" : "\(p.type)-\(count)-\(isSel)"
                if !addedStyles.contains(styleID) {
                    manager.addPoiStyle(Self.poiStyle(id: styleID, type: p.type, count: count, selected: isSel, name: p.name))
                    addedStyles.insert(styleID)
                }
                // 식당 이름은 아이콘 이미지 안에 그려 넣는다(지도 글자를 가리려면 불투명 배경이 필요).
                let texts = isSel && p.type != .food ? [PoiText(text: p.name, styleIndex: 0)] : []

                if pois[p.id] == nil {
                    let opt = PoiOptions(styleID: styleID, poiID: p.id)
                    opt.rank = isSel ? 100 : 0
                    opt.clickable = true
                    for t in texts { opt.addText(t) }
                    guard let poi = layer.addPoi(option: opt, at: MapPoint(longitude: p.lng, latitude: p.lat)) else { continue }
                    pois[p.id] = poi
                    placeTapHandlers[p.id] = poi.addPoiTappedEventHandler(target: self, handler: Coordinator.placePoiTapped)
                    appliedStyle[p.id] = styleID
                } else if appliedStyle[p.id] != styleID {
                    pois[p.id]?.changeTextAndStyle(texts: texts, styleID: styleID)
                    appliedStyle[p.id] = styleID
                }
                pinsVisible && visible.contains(p.id) ? pois[p.id]?.show() : pois[p.id]?.hide()
            }

            // Reuse the existing label manager/scene: do not create a second Kakao map.
            if lastBuildingID != parent.focusedBuilding?.id {
                if let previous = lastBuildingID { buildingPois[previous]?.hide() }
                if let building = parent.focusedBuilding {
                    let styleID = "campus-building-focus"
                    if !addedStyles.contains(styleID) {
                        manager.addPoiStyle(Self.buildingPoiStyle(id: styleID))
                        addedStyles.insert(styleID)
                    }
                    if buildingPois[building.id] == nil {
                        let opt = PoiOptions(styleID: styleID, poiID: "campus-\(building.id)")
                        opt.rank = 200
                        opt.clickable = false // Search selection handled in SwiftUI.
                        let poi = layer.addPoi(option: opt, at: MapPoint(longitude: building.longitude, latitude: building.latitude))
                        buildingPois[building.id] = poi
                    }
                    buildingPois[building.id]?.show()
                }
                lastBuildingID = parent.focusedBuilding?.id
            }
            if let building = parent.focusedBuilding, parent.focusSerial != lastFocusSerial {
                let target = MapPoint(longitude: building.longitude, latitude: building.latitude)
                let update = CameraUpdate.make(target: target, zoomLevel: 17, mapView: map)
                map.animateCamera(cameraUpdate: update,
                                  options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 500))
                lastFocusSerial = parent.focusSerial
            }

            if lastSelected != parent.selected {
                if lastSelected != nil, let p = Place.byID[parent.selected] {
                    let update = CameraUpdate.make(target: MapPoint(longitude: p.lng, latitude: p.lat), mapView: map)
                    map.animateCamera(cameraUpdate: update, options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 500))
                }
                lastSelected = parent.selected
            }
        }

        private func placePoiTapped(_ param: PoiInteractionEventParam) {
            guard parent.places.contains(where: { $0.id == param.poiItem.itemID }) else { return }
            lastPlaceTapAt = ProcessInfo.processInfo.systemUptime
            dismissKeyboard(); parent.onSelect(param.poiItem.itemID)
        }

        func shuttlesChanged() {
            guard let map = controller?.getView(viewName) as? KakaoMap else { return }
            refreshShuttles(on: map, manager: map.getLabelManager())
        }

        private func refreshShuttles(on map: KakaoMap, manager: LabelManager) {
            guard let layer = manager.getLabelLayer(layerID: shuttleLayerID) else { return }
            let positions = parent.shuttle?.positions ?? []
            let ids = Set(positions.map(\.id))
            for id in Array(shuttlePois.keys) where !ids.contains(id) {
                layer.removePoi(poiID: "circular-\(id)"); shuttlePois.removeValue(forKey: id)
            }
            guard map.zoomLevel >= Self.minShuttleLevel else {
                for poi in shuttlePois.values { poi.hide() }
                return
            }
            let styleID = "campus-circular-vehicle-small"
            if !addedStyles.contains(styleID) {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 27)).image { _ in
                    UIImage(named: "CampusShuttle")?.draw(in: CGRect(x: 0, y: 0, width: 18, height: 27))
                }
                let icon = PoiIconStyle(symbol: image, anchorPoint: CGPoint(x: 0.5, y: 0.5))
                manager.addPoiStyle(PoiStyle(styleID: styleID, styles: [PerLevelPoiStyle(iconStyle: icon, level: 0)]))
                addedStyles.insert(styleID)
            }
            for bus in positions {
                let point = MapPoint(longitude: bus.coordinate.longitude, latitude: bus.coordinate.latitude)
                if shuttlePois[bus.id] == nil {
                    let option = PoiOptions(styleID: styleID, poiID: "circular-\(bus.id)")
                    option.rank = 400; option.clickable = false; option.transformType = .absoluteRotation
                    shuttlePois[bus.id] = layer.addPoi(option: option, at: point)
                }
                shuttlePois[bus.id]?.position = point
                shuttlePois[bus.id]?.orientation = bus.bearingRadians
                shuttlePois[bus.id]?.show()
            }
        }

        // MARK: 현재 위치 / 기기가 바라보는 방향
        private func refreshUserLocation(on map: KakaoMap, manager: LabelManager) {
            guard let coord = parent.userCoordinate,
                  UserLocationMath.validCoordinate(latitude: coord.latitude, longitude: coord.longitude),
                  let layer = manager.getLabelLayer(layerID: userLayerID) else {
                userDot?.hide()
                userDirection?.hide()
                return
            }

            let point = MapPoint(longitude: coord.longitude, latitude: coord.latitude)
            if !addedStyles.contains("user-position-dot") {
                manager.addPoiStyle(Self.userPositionStyle())
                addedStyles.insert("user-position-dot")
            }
            if userDot == nil {
                let opt = PoiOptions(styleID: "user-position-dot", poiID: "my-location-dot")
                opt.rank = 500
                opt.clickable = false
                userDot = layer.addPoi(option: opt, at: point)
            }
            userDot?.position = point
            userDot?.show()

            if let direction = parent.userHeadingDegrees,
               let radians = UserLocationMath.headingRadians(direction) {
                if !addedStyles.contains("user-position-direction") {
                    manager.addPoiStyle(Self.userDirectionStyle())
                    addedStyles.insert("user-position-direction")
                }
                if userDirection == nil {
                    let opt = PoiOptions(styleID: "user-position-direction", poiID: "my-location-direction")
                    opt.rank = 499
                    opt.clickable = false
                    opt.transformType = .absoluteRotation // compass bearing is north-relative
                    userDirection = layer.addPoi(option: opt, at: point)
                }
                userDirection?.position = point
                userDirection?.orientation = radians
                userDirection?.show()
            } else {
                userDirection?.hide() // no compass or unreliable heading: dot only
            }

            if parent.userFocusSerial != lastUserFocusSerial {
                let update = CameraUpdate.make(target: point, zoomLevel: 17, mapView: map)
                map.animateCamera(cameraUpdate: update,
                                  options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 450))
                lastUserFocusSerial = parent.userFocusSerial
            }
        }

        private static func userPositionStyle() -> PoiStyle {
            let renderer = ImageRenderer(content: UserLocationDot())
            renderer.scale = 2
            let icon = PoiIconStyle(symbol: renderer.uiImage ?? UIImage(), anchorPoint: CGPoint(x: 0.5, y: 0.5))
            return PoiStyle(styleID: "user-position-dot", styles: [PerLevelPoiStyle(iconStyle: icon, level: 0)])
        }

        private static func userDirectionStyle() -> PoiStyle {
            let renderer = ImageRenderer(content: UserLocationDirection())
            renderer.scale = 2
            let icon = PoiIconStyle(symbol: renderer.uiImage ?? UIImage(), anchorPoint: CGPoint(x: 0.5, y: 0.5))
            return PoiStyle(styleID: "user-position-direction", styles: [PerLevelPoiStyle(iconStyle: icon, level: 0)])
        }

        // ponytail: SDK의 핀 클릭 판정이 우리 핀에 안 먹어서, 탭 좌표를 지도 좌표로 바꿔 가장 가까운 핀을 직접 고른다.
        func kakaoMapDidTapped(kakaoMap: KakaoMap, point: CGPoint) {
            dismissKeyboard() // 지도를 누르면 키보드 내림. 제스처를 따로 얹으면 SDK 탭이 안 먹어서 SDK 콜백에서 처리한다.
            // A POI tap can also emit a map tap. Keep one selection/zoom per touch.
            if ProcessInfo.processInfo.systemUptime - lastPlaceTapAt < 0.2 { return }
            // 점 중심이 앵커라서 탭한 지점을 그대로 기준으로 삼고, 반경은 화면 22pt 만큼의 거리.
            let probe = kakaoMap.getPosition(CGPoint(x: point.x, y: point.y)).wgsCoord
            let edge = kakaoMap.getPosition(CGPoint(x: point.x + 22, y: point.y)).wgsCoord
            let k = cos(probe.latitude * .pi / 180)
            func dist(_ a: (Double, Double), _ b: (Double, Double)) -> Double { hypot(a.0 - b.0, (a.1 - b.1) * k) }
            let radius = dist((probe.latitude, probe.longitude), (edge.latitude, edge.longitude))
            let hit = parent.places
                .map { place -> (String, Double) in
                    // 새 마커는 끝이 좌표에 놓이므로 터치 판정은 아이콘 몸통 중심에 맞춘다.
                    let offset: CGFloat = 17 * PinIcon.markerScale
                    let markerProbe = kakaoMap.getPosition(CGPoint(x: point.x, y: point.y + offset)).wgsCoord
                    return (place.id, dist((markerProbe.latitude, markerProbe.longitude), (place.lat, place.lng)))
                }
                .filter { $0.1 <= radius }
                .min { $0.1 < $1.1 }
            if pinsVisible, let hit { parent.onSelect(hit.0) }
        }

        // MARK: 핀 이미지
        static func buildingPoiStyle(id: String) -> PoiStyle {
            let renderer = ImageRenderer(content: CampusBuildingPin())
            renderer.scale = 2
            let icon = PoiIconStyle(symbol: renderer.uiImage, anchorPoint: CGPoint(x: 0.5, y: 1.0))
            let text = PoiTextStyle(textLineStyles: [
                PoiTextLineStyle(textStyle: TextStyle(fontSize: 26, fontColor: .black, strokeThickness: 4, strokeColor: .white)),
            ])
            text.textLayouts = [.right]
            return PoiStyle(styleID: id, styles: [PerLevelPoiStyle(iconStyle: icon, textStyle: text, level: 0)])
        }

        static func poiStyle(id: String, type: PlaceType, count: Int, selected: Bool, name: String) -> PoiStyle {
            let text = PoiTextStyle(textLineStyles: [
                PoiTextLineStyle(textStyle: TextStyle(fontSize: 24, fontColor: .black, strokeThickness: 4, strokeColor: .white)),
            ])
            text.textLayouts = [.right]
            func icon(label: String?) -> PoiIconStyle {
                // 이름표나 선택 크기가 바뀌어도 핀/기둥 끝을 실제 좌표에 고정한다.
                let pin = PinIcon(type: type, count: count, selected: selected, label: label)
                let image = render(pin)
                return PoiIconStyle(symbol: image, anchorPoint: CGPoint(x: 0.5, y: pin.coordinateAnchorY / image.size.height))
            }
            let plain = icon(label: nil)
            // 식당 이름은 핀이 보이는 레벨(14~)부터 보인다. 선택된 핀은 항상 보인다.
            if type == .food {
                let named = icon(label: name)
                return PoiStyle(styleID: id, styles: selected
                    ? [PerLevelPoiStyle(iconStyle: named, level: 0)]
                    : [PerLevelPoiStyle(iconStyle: plain, level: 0), PerLevelPoiStyle(iconStyle: named, level: 14)])
            }
            return PoiStyle(styleID: id, styles: [PerLevelPoiStyle(iconStyle: plain, textStyle: text, level: 0)])
        }

        private static func render(_ content: some View) -> UIImage {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            return renderer.uiImage ?? UIImage()
        }
    }
}

/// 지도 핀 이미지(SwiftUI로 그려 UIImage로 변환).
struct PinIcon: View {
    let type: PlaceType
    let count: Int
    let selected: Bool
    var label: String? = nil

    static let markerScale: CGFloat = 0.8
    /// Asset canvases are 32×40pt; their visible tips sit at y = 37pt.
    var coordinateAnchorY: CGFloat { 37 * Self.markerScale }

    var body: some View {
        VStack(spacing: 0) {
            pin
            if let label {
                Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x1b2328))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().stroke(type.color.opacity(selected ? 0.9 : 0.5), lineWidth: selected ? 1.5 : 1))
                    .padding(.top, 2).padding(.bottom, 2)
            }
        }
    }

    @ViewBuilder private var pin: some View {
        switch type {
        case .food, .stop:
            Image(type == .food ? "RestaurantPin" : "ShuttleStop")
                .resizable()
                .scaledToFit()
                .frame(width: 32 * Self.markerScale, height: 40 * Self.markerScale)
                .shadow(color: .black.opacity(selected ? 0.24 : 0.14), radius: 1, y: 1)
        }
    }
}

/// Dedicated marker for a building searched in the top search bar.
private struct CampusBuildingPin: View {
    var body: some View {
        VStack(spacing: -3) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 33, height: 33)
                .background(Color.cjTeal, in: Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8)).foregroundStyle(Color.cjTeal)
        }
        .padding(9)
    }
}

/// Familiar map-app blue dot: separate from the heading so the dot never rotates.
private struct UserLocationDot: View {
    var body: some View {
        Circle()
            .fill(Color(red: 0.12, green: 0.47, blue: 0.96))
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
            .frame(width: 80, height: 80)
    }
}

/// The translucent wedge points up at bearing 0 (north); Kakao rotates this POI
/// to the Core Location compass heading. Hidden when heading is unavailable.
private struct UserLocationDirection: View {
    var body: some View {
        Path { path in
            let center = CGPoint(x: 40, y: 40)
            path.move(to: center)
            path.addLine(to: CGPoint(x: 19, y: 9))
            path.addQuadCurve(to: CGPoint(x: 61, y: 9), control: CGPoint(x: 40, y: -1))
            path.closeSubpath()
        }
        .fill(Color(red: 0.12, green: 0.47, blue: 0.96).opacity(0.24))
        .frame(width: 80, height: 80)
    }
}

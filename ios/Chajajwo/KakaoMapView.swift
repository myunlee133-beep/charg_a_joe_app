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
    let lostPins: [LostFoundMapPin]
    let lostFocusID: String?
    let lostFocusSerial: Int
    var quests: [Quest] = []
    var shuttle: CircularShuttleService? = nil  // 셔틀 핀은 SwiftUI를 거치지 않고 위치가 바뀔 때 바로 옮긴다
    var selectedQuestID: String? = nil
    var zoomRequest = 0
    var onQuestSelect: ((String) -> Void)? = nil
    var onQuestGroupSelect: (([String]) -> Void)? = nil
    var onQuestDeselect: (() -> Void)? = nil
    let onSelect: (String) -> Void
    let onSelectLost: (String) -> Void

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
        private let questLayerID = "quests"
        private let questLeaderLayerID = "quest-leaders"
        private let shuttleLayerID = "circular-shuttle"
        private var questPois: [String: Poi] = [:]
        private var questStyles: [String: String] = [:]
        private var questTapHandlers: [String: DisposableEventHandler] = [:]
        private var questOffsets: [String: CGPoint] = [:]
        private var questLeaderPois: [String: Poi] = [:]
        private var questLeaderOffsets: [String: CGPoint] = [:]
        private var shuttlePois: [String: Poi] = [:]
        private var questGroups: [QuestMapGroup] = []
        private var lastZoomRequest = 0
        private var lastQuestFocusID: String?
        private var lastQuestTapAt = -Double.infinity
        private var lastQuestTapID: String?
        private var lastPlaceTapAt = -Double.infinity
        private var userDot: Poi?
        private var userDirection: Poi?
        private let lostLayerID = "lost-found"
        private var lostPois: [String: Poi] = [:]
        private var lastLostFocusSerial = -1
        // Zero means no locate-button request. Receiving the first GPS fix must
        // not replace the compact campus overview with an automatic zoom to 17.
        private var lastUserFocusSerial = 0
        private let viewName = "mapview"
        /// 이 지도 레벨보다 멀리서 볼 때는 핀을 모두 숨긴다(기본 화면은 레벨 14).
        private static let minPinLevel = 14
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
            questTapHandlers.values.forEach { $0.dispose() }
            questTapHandlers.removeAll()
            placeTapHandlers.values.forEach { $0.dispose() }
            placeTapHandlers.removeAll()
            // The six-tab container removes the home view when changing tabs.
            // Release this engine before a later home view creates another one.
            controller?.pauseEngine()
            controller?.delegate = nil
            (controller?.getView(viewName) as? KakaoMap)?.eventDelegate = nil
            controller?.resetEngine()
            controller = nil
            pois.removeAll(); buildingPois.removeAll(); questPois.removeAll(); shuttlePois.removeAll()
            questLeaderPois.removeAll(); questLeaderOffsets.removeAll(); questOffsets.removeAll()
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
            _ = manager.addLabelLayer(option: LabelLayerOptions(layerID: questLeaderLayerID,
                competitionType: .none, competitionUnit: .symbolFirst, orderType: .rank, zOrder: 19000))
            _ = manager.addLabelLayer(option: LabelLayerOptions(
                layerID: userLayerID, competitionType: .none,
                competitionUnit: .symbolFirst, orderType: .rank, zOrder: 25000))
            _ = manager.addLabelLayer(option: LabelLayerOptions(layerID: lostLayerID,
                competitionType: .none, competitionUnit: .symbolFirst, orderType: .rank, zOrder: 22000))
            lostPois.removeAll()
            userDot = nil
            userDirection = nil
            for (id, zOrder) in [(questLayerID, 22000), (shuttleLayerID, 24000)] {
                _ = manager.addLabelLayer(option: LabelLayerOptions(layerID: id, competitionType: .none,
                    competitionUnit: .symbolFirst, orderType: .rank, zOrder: zOrder))
                if id == questLayerID { manager.getLabelLayer(layerID: id)?.setClickable(true) }
            }
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
            // User marker is always visible, even at map levels where hub pins are hidden.
            refreshUserLocation(on: map, manager: manager)
            refreshLostPins(on: map, manager: manager)
            refreshQuests(on: map, manager: manager)
            refreshShuttles(manager: manager)
            if parent.selectedQuestID != lastQuestFocusID {
                lastQuestFocusID = parent.selectedQuestID
                if let quest = parent.quests.first(where: { $0.id == parent.selectedQuestID }) {
                    // Keep the selected name label clear of the search overlay
                    // and the new bottom card, while preserving the current zoom.
                    let update = CameraUpdate.make(target: MapPoint(longitude: quest.coordinate.longitude, latitude: quest.coordinate.latitude), mapView: map)
                    map.animateCamera(cameraUpdate: update, options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 300))
                }
            }
            if parent.zoomRequest != lastZoomRequest {
                let delta = parent.zoomRequest - lastZoomRequest
                lastZoomRequest = parent.zoomRequest
                let center = map.getPosition(CGPoint(x: map.viewRect.width / 2, y: map.viewRect.height / 2))
                let update = CameraUpdate.make(target: center, zoomLevel: min(20, max(7, Int(map.zoomLevel) + delta)), mapView: map)
                map.animateCamera(cameraUpdate: update, options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 300))
            }
            let visible = Set(parent.places.map(\.id))
            pinsVisible = map.zoomLevel >= Self.minPinLevel

            if lastSheetOpen != parent.sheetOpen {
                // 카드가 화면 아래쪽 대부분을 덮으므로, 열려 있을 땐 지도 아래쪽 여백을 줘서 중심을 위로 올린다.
                if parent.sheetOpen { map.setMargins(UIEdgeInsets(top: 0, left: 0, bottom: 190, right: 0)) } else { map.resetMargins() }
                lastSheetOpen = parent.sheetOpen
            }

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

        // MARK: 검증된 분실물센터와 회원 신고 위치. Existing Kakao map is reused.
        private func refreshLostPins(on map: KakaoMap, manager: LabelManager) {
            guard let layer = manager.getLabelLayer(layerID: lostLayerID) else { return }
            let ids = Set(parent.lostPins.map(\.id))
            for (id, poi) in lostPois where !ids.contains(id) { poi.hide() }
            for pin in parent.lostPins {
                let styleID: String
                switch pin.kind {
                case .center: styleID = "lf-center"
                case .found: styleID = "lf-found"
                case .lost: styleID = "lf-lost"
                }
                if !addedStyles.contains(styleID) {
                    manager.addPoiStyle(Self.lostPinStyle(id: styleID, kind: pin.kind))
                    addedStyles.insert(styleID)
                }
                let pos = MapPoint(longitude: pin.longitude, latitude: pin.latitude)
                if lostPois[pin.id] == nil {
                    let option = PoiOptions(styleID: styleID, poiID: pin.id)
                    option.rank = pin.kind == .center ? 320 : 250
                    option.clickable = false // coordinate hit-testing in SDK tap callback
                    lostPois[pin.id] = layer.addPoi(option: option, at: pos)
                }
                lostPois[pin.id]?.position = pos
                lostPois[pin.id]?.show()
            }
            if parent.lostFocusSerial != lastLostFocusSerial, let id = parent.lostFocusID,
               let pin = parent.lostPins.first(where: { $0.id == id }) {
                let update = CameraUpdate.make(target: MapPoint(longitude: pin.longitude, latitude: pin.latitude),
                                               zoomLevel: 17, mapView: map)
                map.animateCamera(cameraUpdate: update,
                    options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 450))
                lastLostFocusSerial = parent.lostFocusSerial
            }
        }
        private static func lostPinStyle(id: String, kind: LostFoundMapPin.Kind) -> PoiStyle {
            PoiStyle(styleID: id, styles: [PerLevelPoiStyle(iconStyle:
                PoiIconStyle(symbol: render(LostFoundPin(kind: kind)), anchorPoint: CGPoint(x: 0.5, y: 0.5)), level: 0)])
        }

        private func refreshQuests(on map: KakaoMap, manager: LabelManager) {
            guard let layer = manager.getLabelLayer(layerID: questLayerID) else { return }
            questGroups = QuestMapGroup.groups(parent.quests, zoom: Int(map.zoomLevel))
            let projection = screenProjection(on: map)
            let footprints = questGroups.map { group -> MapMarkerFootprint in
                let selected = group.quests.contains { $0.id == parent.selectedQuestID }
                let pin = QuestMapPin(quest: group.quests[0], count: group.quests.count,
                                      presentation: selected ? .detail : .at(zoom: Int(map.zoomLevel)), selected: selected)
                return .init(id: group.id, anchor: projection?.point(for: group.coordinate) ?? .zero,
                             size: pin.size, anchorY: pin.anchorY, priority: selected ? 1 : 0)
            }
            let obstacles: [CGRect] = map.zoomLevel < Self.minPinLevel ? [] : parent.places.filter { $0.type == .food }.map { place in
                let key = "\(place.id)-\(parent.counts[place.id] ?? 0)"
                if foodGeometry[key] == nil {
                    let plain = Self.render(PinIcon(type: .food, count: parent.counts[place.id] ?? 0, selected: false))
                    let named = Self.render(PinIcon(type: .food, count: parent.counts[place.id] ?? 0, selected: false, label: place.name))
                    foodGeometry[key] = (named.size, plain.size.height / 2 / named.size.height)
                }
                let geometry = foodGeometry[key]!
                return MapMarkerFootprint(id: place.id,
                    anchor: projection?.point(for: .init(latitude: place.lat, longitude: place.lng)) ?? .zero,
                    size: geometry.0, anchorY: geometry.1).frame
            }
            let placements = projection == nil ? [:] : MapMarkerLayout.place(footprints, avoiding: obstacles,
                in: CGRect(origin: .zero, size: map.viewRect.size))
            questOffsets = placements.mapValues(\.offset)
            let ids = Set(questGroups.map(\.id))
            for id in Array(questPois.keys) where !ids.contains(id) {
                questTapHandlers.removeValue(forKey: id)?.dispose()
                layer.removePoi(poiID: "quest-\(id)")
                questPois.removeValue(forKey: id); questStyles.removeValue(forKey: id)
                manager.getLabelLayer(layerID: questLeaderLayerID)?.removePoi(poiID: "leader-\(id)")
                questLeaderPois.removeValue(forKey: id)
                if questLeaderOffsets.removeValue(forKey: id) != nil { manager.removePoiStyle("quest-leader-\(id)") }
            }
            for group in questGroups {
                let q = group.quests[0]
                let reward = group.quests.map(\.reward).max() ?? q.reward
                let selected = group.quests.contains { $0.id == parent.selectedQuestID }
                let presentation = selected ? QuestMapPresentation.detail : .at(zoom: Int(map.zoomLevel))
                let styleID = "quest-\(presentation.rawValue)-\(q.id)-\(q.category.rawValue)-\(reward)-\(group.quests.count)-\(selected)"
                if !addedStyles.contains(styleID) {
                    let pin = QuestMapPin(quest: q, count: group.quests.count, presentation: presentation, selected: selected)
                    let icon = PoiIconStyle(symbol: Self.render(pin), anchorPoint: CGPoint(x: 0.5, y: pin.anchorY))
                    manager.addPoiStyle(PoiStyle(styleID: styleID, styles: [PerLevelPoiStyle(iconStyle: icon, level: 0)]))
                    addedStyles.insert(styleID)
                }
                let coord = group.coordinate
                let point = MapPoint(longitude: coord.longitude, latitude: coord.latitude)
                if questPois[group.id] == nil {
                    let option = PoiOptions(styleID: styleID, poiID: "quest-\(group.id)")
                    option.rank = 300; option.clickable = true
                    questPois[group.id] = layer.addPoi(option: option, at: point)
                    questTapHandlers[group.id] = questPois[group.id]?.addPoiTappedEventHandler(target: self, handler: Coordinator.questPoiTapped)
                } else if questStyles[group.id] != styleID {
                    questPois[group.id]?.changeTextAndStyle(texts: [], styleID: styleID)
                }
                questStyles[group.id] = styleID
                questPois[group.id]?.position = point
                let offset = questOffsets[group.id] ?? .zero
                questPois[group.id]?.pixelOffset = offset
                questPois[group.id]?.show()
                refreshQuestLeader(group.id, at: point, offset: offset, manager: manager)
            }
        }

        private func screenProjection(on map: KakaoMap) -> CampusScreenProjection? {
            let center = CGPoint(x: map.viewRect.width / 2, y: map.viewRect.height / 2)
            let span = min(64, min(map.viewRect.width, map.viewRect.height) / 4)
            func coordinate(_ point: CGPoint) -> CampusCoordinate {
                let geo = map.getPosition(point).wgsCoord
                return .init(latitude: geo.latitude, longitude: geo.longitude)
            }
            return CampusScreenProjection(center: center, origin: coordinate(center),
                horizontal: coordinate(CGPoint(x: center.x + span, y: center.y)),
                vertical: coordinate(CGPoint(x: center.x, y: center.y + span)), span: Double(span))
        }

        private func refreshQuestLeader(_ id: String, at point: MapPoint, offset: CGPoint, manager: LabelManager) {
            guard let layer = manager.getLabelLayer(layerID: questLeaderLayerID) else { return }
            guard hypot(offset.x, offset.y) > 1 else { questLeaderPois[id]?.hide(); return }
            if questLeaderOffsets[id] != offset {
                layer.removePoi(poiID: "leader-\(id)")
                if questLeaderOffsets[id] != nil { manager.removePoiStyle("quest-leader-\(id)") }
                manager.addPoiStyle(Self.questLeaderStyle(id: "quest-leader-\(id)", offset: offset))
                let option = PoiOptions(styleID: "quest-leader-\(id)", poiID: "leader-\(id)")
                option.clickable = false
                questLeaderPois[id] = layer.addPoi(option: option, at: point)
                questLeaderOffsets[id] = offset
            }
            questLeaderPois[id]?.position = point
            questLeaderPois[id]?.show()
        }

        private static func questLeaderStyle(id: String, offset: CGPoint) -> PoiStyle {
            let bounds = CGRect(x: min(0, offset.x) - 4, y: min(0, offset.y) - 4,
                                width: abs(offset.x) + 8, height: abs(offset.y) + 8)
            let origin = CGPoint(x: -bounds.minX, y: -bounds.minY)
            let length = hypot(offset.x, offset.y)
            let image = UIGraphicsImageRenderer(size: bounds.size).image { context in
                let line = UIBezierPath()
                line.move(to: CGPoint(x: origin.x + offset.x / length * min(10, length), y: origin.y + offset.y / length * min(10, length)))
                line.addLine(to: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y))
                UIColor.white.setStroke(); line.lineWidth = 3; line.stroke()
                context.cgContext.setLineDash(phase: 0, lengths: [3, 2])
                UIColor(Color.cjTeal).setStroke(); line.lineWidth = 1.3; line.stroke()
            }
            let icon = PoiIconStyle(symbol: image, anchorPoint: CGPoint(x: origin.x / bounds.width, y: origin.y / bounds.height))
            return PoiStyle(styleID: id, styles: [PerLevelPoiStyle(iconStyle: icon, level: 0)])
        }

        private func placePoiTapped(_ param: PoiInteractionEventParam) {
            guard parent.places.contains(where: { $0.id == param.poiItem.itemID }) else { return }
            lastPlaceTapAt = ProcessInfo.processInfo.systemUptime
            dismissKeyboard(); parent.onSelect(param.poiItem.itemID)
        }

        private func questPoiTapped(_ param: PoiInteractionEventParam) {
            guard let map = controller?.getView(viewName) as? KakaoMap,
                  let group = questGroups.first(where: { "quest-\($0.id)" == param.poiItem.itemID }) else { return }
            selectQuestGroup(group, on: map)
        }

        private func selectQuestGroup(_ group: QuestMapGroup, on map: KakaoMap) {
            let now = ProcessInfo.processInfo.systemUptime
            guard group.id != lastQuestTapID || now - lastQuestTapAt > 0.3 else { return }
            lastQuestTapAt = now; lastQuestTapID = group.id
            dismissKeyboard()
            if group.quests.count == 1 { parent.onQuestSelect?(group.quests[0].id); return }
            let coordinate = group.coordinate
            if map.zoomLevel >= 20 || group.quests.allSatisfy({ $0.coordinate.distance(to: coordinate) < 5 }) {
                parent.onQuestGroupSelect?(group.quests.map(\.id)); return
            }
            let update = CameraUpdate.make(target: MapPoint(longitude: coordinate.longitude, latitude: coordinate.latitude), zoomLevel: min(20, Int(map.zoomLevel) + 2), mapView: map)
            map.animateCamera(cameraUpdate: update, options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 450))
        }

        func shuttlesChanged() {
            guard let map = controller?.getView(viewName) as? KakaoMap else { return }
            refreshShuttles(manager: map.getLabelManager())
        }

        private func refreshShuttles(manager: LabelManager) {
            guard let layer = manager.getLabelLayer(layerID: shuttleLayerID) else { return }
            let positions = parent.shuttle?.positions ?? []
            let ids = Set(positions.map(\.id))
            for id in Array(shuttlePois.keys) where !ids.contains(id) {
                layer.removePoi(poiID: "circular-\(id)"); shuttlePois.removeValue(forKey: id)
            }
            let styleID = "campus-circular-vehicle-s"
            if !addedStyles.contains(styleID) {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 42)).image { _ in
                    UIImage(named: "CampusShuttle")?.draw(in: CGRect(x: 0, y: 0, width: 28, height: 42))
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
            if ProcessInfo.processInfo.systemUptime - max(lastQuestTapAt, lastPlaceTapAt) < 0.2 { return }
            // Hit-test lost-and-found pins independently of zoom and old hub pin visibility.
            // 점 중심이 앵커라서 탭한 지점을 그대로 기준으로 삼고, 반경은 화면 22pt 만큼의 거리.
            let probe = kakaoMap.getPosition(CGPoint(x: point.x, y: point.y)).wgsCoord
            let edge = kakaoMap.getPosition(CGPoint(x: point.x + 22, y: point.y)).wgsCoord
            let k = cos(probe.latitude * .pi / 180)
            func dist(_ a: (Double, Double), _ b: (Double, Double)) -> Double { hypot(a.0 - b.0, (a.1 - b.1) * k) }
            let radius = dist((probe.latitude, probe.longitude), (edge.latitude, edge.longitude))
            // Match the hit area to each zoom-dependent marker, including its label.
            if let group = questGroups.filter({
                let selected = $0.quests.contains { $0.id == parent.selectedQuestID }
                let pin = QuestMapPin(quest: $0.quests[0], count: $0.quests.count,
                                      presentation: selected ? .detail : .at(zoom: Int(kakaoMap.zoomLevel)), selected: selected)
                let width = max(44, pin.size.width), height = max(44, pin.size.height)
                let offset = questOffsets[$0.id] ?? .zero
                let hitRect = CGRect(x: point.x - offset.x - width / 2, y: point.y - offset.y - height * (1 - pin.anchorY), width: width, height: height)
                    .intersection(CGRect(origin: .zero, size: kakaoMap.viewRect.size))
                let corners = [CGPoint(x: hitRect.minX, y: hitRect.minY), CGPoint(x: hitRect.maxX, y: hitRect.minY),
                               CGPoint(x: hitRect.maxX, y: hitRect.maxY), CGPoint(x: hitRect.minX, y: hitRect.maxY)]
                    .map { kakaoMap.getPosition($0).wgsCoord }
                let area = Path { path in
                    path.move(to: CGPoint(x: corners[0].longitude, y: corners[0].latitude))
                    for corner in corners.dropFirst() { path.addLine(to: CGPoint(x: corner.longitude, y: corner.latitude)) }
                    path.closeSubpath()
                }
                return area.contains(CGPoint(x: $0.coordinate.longitude, y: $0.coordinate.latitude))
            }).min(by: {
                dist((probe.latitude, probe.longitude), ($0.coordinate.latitude, $0.coordinate.longitude)) <
                dist((probe.latitude, probe.longitude), ($1.coordinate.latitude, $1.coordinate.longitude))
            }) {
                selectQuestGroup(group, on: kakaoMap)
                return
            }
            let hit = parent.places
                .map { ($0.id, dist((probe.latitude, probe.longitude), ($0.lat, $0.lng))) }
                .filter { $0.1 <= radius }
                .min { $0.1 < $1.1 }
            let lostHit = parent.lostPins
                .map { ($0.id, dist((probe.latitude, probe.longitude), ($0.latitude, $0.longitude))) }
                .filter { $0.1 <= radius }
                .min { $0.1 < $1.1 }
            if let lostHit { parent.onSelectLost(lostHit.0); return }
            if pinsVisible, let hit { parent.onSelect(hit.0) }
            else { parent.onQuestDeselect?() }
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
                // 이름표가 붙어도 점 중심(앵커)이 좌표에 오도록, 이름표 없는 점의 높이 비율로 앵커를 잡는다.
                let pinHeight = render(PinIcon(type: type, count: count, selected: selected, label: nil)).size.height
                let image = render(PinIcon(type: type, count: count, selected: selected, label: label))
                return PoiIconStyle(symbol: image, anchorPoint: CGPoint(x: 0.5, y: pinHeight / 2 / image.size.height))
            }
            let plain = icon(label: nil)
            // 식당 이름은 점이 보이는 레벨(14~)부터 보인다. 선택된 핀은 항상 보인다.
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

/// Reference flow: small count clusters, individual icons, then short labels.
private struct QuestMapPin: View {
    let quest: Quest
    let count: Int
    let presentation: QuestMapPresentation
    let selected: Bool

    var size: CGSize {
        if count > 1 { return CGSize(width: 44, height: 44) }
        switch presentation {
        case .overview: return CGSize(width: 32, height: 32)
        case .icon: return CGSize(width: 44, height: 52)
        case .reward: return CGSize(width: 106, height: 48)
        case .detail: return CGSize(width: 144, height: 66)
        }
    }
    var anchorY: CGFloat { count > 1 || presentation == .overview ? 0.5 : (size.height - 6) / size.height }

    var body: some View {
        Group {
            if count > 1 {
                Text("\(count)").font(.system(size: 14, weight: .heavy)).foregroundStyle(Color.cjTealText)
                    .frame(width: 32, height: 32).background(Color.cjSuccessFill, in: Circle())
                    .overlay(Circle().stroke(Color.cjTeal.opacity(0.25), lineWidth: 5))
            } else if presentation == .overview {
                Image(systemName: quest.category.symbol).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white).frame(width: 24, height: 24).background(quest.category.accent, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            } else {
                VStack(spacing: -1) {
                    if presentation == .icon {
                        Image(systemName: quest.category.symbol).font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white).frame(width: 34, height: 34)
                            .background(quest.category.accent, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: quest.category.symbol).font(.system(size: 14, weight: .bold))
                            VStack(alignment: .leading, spacing: 3) {
                                if presentation == .detail {
                                    Text(quest.place).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                }
                                Text(quest.rewardText).font(.system(size: 12, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .foregroundStyle(selected ? Color.white : quest.category.accent)
                        .padding(.horizontal, 9).frame(width: size.width - 10, height: size.height - 22)
                        .background(selected ? quest.category.accent : Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(quest.category.accent, lineWidth: 1.5))
                    }
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(quest.category.accent)
                        .frame(height: 9)
                }
            }
        }
        .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
        .frame(width: size.width, height: size.height)
    }
}

/// 지도 핀 이미지(SwiftUI로 그려 UIImage로 변환).
struct PinIcon: View {
    let type: PlaceType
    let count: Int
    let selected: Bool
    var label: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            pin
            if let label {
                Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x1b2328))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().stroke(type.color.opacity(0.5), lineWidth: 1))
                    .padding(.top, 2).padding(.bottom, 2)
            }
        }
    }

    private var pin: some View { MapDot(color: type.color, count: count) }
}

/// 식당 핀과 같은 모양의 점. 묶음이면 개수 배지를 단다.
struct MapDot: View {
    let color: Color
    var count = 0
    var body: some View {
        Circle().fill(color)
            .frame(width: 11, height: 11)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14)
                        .background(Color(hex: 0x1b2328), in: Capsule()).offset(x: 7, y: -6)
                }
            }
            .padding(10)
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

/// Center, found-item, and lost-request pins are intentionally distinct.
private struct LostFoundPin: View {
    let kind: LostFoundMapPin.Kind
    private var accent: Color {
        switch kind {
        case .center: Color(hex: 0x0F7F74)
        case .found: Color(hex: 0x287AF0)
        case .lost: Color(hex: 0xF26B1D)
        }
    }
    var body: some View { MapDot(color: accent) }
}

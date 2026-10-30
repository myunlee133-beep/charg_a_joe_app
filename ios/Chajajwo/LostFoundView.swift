import SwiftUI
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct LostFoundView: View {
    var mapSelection: FoundItemMapSelection? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var lf: LostFoundAPI
    @State private var section = 0
    @State private var showEditor = false
    @State private var showAuth = false
    @State private var selected: LostFoundRecord?
    @State private var category = "전체"
    @State private var storage = "전체"
    @State private var query = ""
    private var filtered: [LostFoundRecord] {
        lf.found.filter {
            (mapSelection?.contains(latitude: $0.latitude, longitude: $0.longitude) ?? true) &&
            (category == "전체" || $0.category == category) &&
            (storage == "전체" || $0.storage.rawValue == storage) &&
            (query.isEmpty || "\($0.title) \($0.locationName) \($0.description)".localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("운영진·사용자가 등록한 습득물을 현재 보관 장소별로 확인해요.").font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        if lf.loggedIn { showEditor = true } else { showAuth = true }
                    } label: {
                        Label("습득물 등록", systemImage: "shippingbox.fill").font(.headline)
                            .frame(maxWidth: .infinity).padding(16).foregroundStyle(Color.cjTealText)
                            .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                    Picker("보기", selection: $section) {
                        Text("습득물 목록").tag(0); Text("수령 확인").tag(1); Text("분실물센터").tag(2)
                    }.pickerStyle(.segmented)
                    if let error = lf.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if lf.loading { ProgressView("최신 정보 확인 중") }
                    if section == 2 { centers }
                    else if !lf.loggedIn {
                        ContentUnavailableView("로그인이 필요해요", systemImage: "person.crop.circle", description: Text("습득물 정보와 비공개 수령 확인은 로그인 후 이용할 수 있어요."))
                        Button("로그인") { showAuth = true }.buttonStyle(.borderedProminent)
                    } else if section == 0 { records }
                    else {
                        Text("소유자 확인 후 실제 수령 결과를 남겨주세요.").font(.subheadline).foregroundStyle(.secondary)
                        if lf.claims.isEmpty && !lf.loading { ContentUnavailableView("수령 확인 요청이 없어요", systemImage: "checkmark.shield", description: Text("내 물건 같은 습득물의 상세 화면에서 확인을 요청할 수 있어요.")) }
                        ForEach(lf.claims) { LostFoundClaimCard(claim: $0) }
                    }
                }.padding(16)
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(mapSelection == nil ? "분실물" : "선택 위치 분실물")
                .toolbar {
                    if mapSelection != nil {
                        ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await lf.prepare(force: true) } } label: { Image(systemName: "arrow.clockwise") }.disabled(lf.loading)
                    }
                }
                .onAppear { Task { await lf.prepare() } }
                .onChange(of: store.tab) { _, tab in
                    if tab == .lostFound { Task { await lf.prepare() } }
                }
                .onChange(of: store.lostFocusSerial) { _, _ in
                    if mapSelection != nil { dismiss() }
                }
                .task(id: scenePhase == .active && store.tab == .lostFound) {
                    guard scenePhase == .active && store.tab == .lostFound else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                        guard !Task.isCancelled else { return }
                        await lf.prepare(force: true)
                    }
                }
                .refreshable { await lf.prepare(force: true) }
                .sheet(isPresented: $showEditor) { LostFoundEditor() }
                .sheet(item: $selected) { LostFoundRecordDetail(record: $0, type: .found) }
                .sheet(isPresented: $showAuth) { LostFoundAuthView() }
        }
    }
    private var records: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let mapSelection {
                Text(mapSelection.title).font(.headline)
                Text("지도에서 선택한 \(mapSelection.coordinates.count)곳의 보관 위치만 표시합니다. 물품을 누르면 상세 내용과 수령 확인을 볼 수 있어요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            TextField("제목·보관 장소 검색", text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Picker("종류", selection: $category) {
                    Text("전체 종류").tag("전체")
                    ForEach(LostFoundKind.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("보관 장소", selection: $storage) {
                    Text("전체 보관 장소").tag("전체")
                    ForEach(LostFoundStorage.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
            }.font(.subheadline)
            if storage == LostFoundStorage.police.rawValue {
                Text(LostFoundRules.policeReceiptNotice).font(.footnote).foregroundStyle(.secondary)
            }
            Text("\(filtered.count)건 · 등록일 기준").font(.caption).foregroundStyle(.secondary)
            if filtered.isEmpty && !lf.loading {
                ContentUnavailableView("해당하는 습득물이 없어요", systemImage: "shippingbox", description: Text("검색 조건을 바꾸거나 나중에 다시 확인해 주세요."))
            }
            ForEach(filtered) { item in
                Button { selected = item } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "shippingbox").font(.title2).foregroundStyle(Color.cjTeal).frame(width: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline)
                            Text("\(item.category) · \(item.sourceTitle)").font(.subheadline)
                            Text("등록일 \(LostFoundDate.label(item.registeredAt))").font(.caption).foregroundStyle(.secondary)
                            Text(item.locationName).font(.caption).foregroundStyle(.secondary)
                            Text(item.statusTitle).font(.caption.weight(.semibold)).foregroundStyle(Color.cjTealText)
                            if item.status == "police" {
                                Text("경찰서 이관 후 실제 수령 여부 확인 불가").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
            }
        }
    }
    private var centers: some View {
        VStack(spacing: 10) {
            ForEach(lf.centers) { center in
                VStack(alignment: .leading, spacing: 7) {
                    Text(center.name).font(.headline)
                    Text("\(center.building) · \(center.room)").font(.subheadline)
                    Text(center.weekdayHours ?? "운영시간 미확인").font(.subheadline).foregroundStyle(Color.cjTealText)
                    Text(center.weekendHolidayNote).font(.caption).foregroundStyle(.secondary)
                    Text(center.custodyNote).font(.caption)
                    HStack {
                        Button("지도에서 보기") {
                            store.showDining = false; store.lostMapOnly = true; store.lostPinID = "center:\(center.id)"
                            store.lostFocusSerial += 1; store.tab = .home
                        }
                        if let phone = center.phone, let tel = URL(string: "tel:\(phone)") { Link("전화", destination: tel) }
                        if let url = URL(string: center.sourceUrl), url.scheme == "https" { Link("공식 안내", destination: url) }
                    }.font(.footnote.weight(.semibold)).buttonStyle(.bordered)
                    Text("확인 기준: \(center.checkedOn)").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
                    .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }
}

private enum LostFoundDate {
    static func label(_ value: String) -> String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return String(value.prefix(10)) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul"); formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct LostFoundAuthView: View {
    @EnvironmentObject private var lf: LostFoundAPI
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var signup = false
    @State private var working = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("사랑방과 같은 계정을 사용합니다") {
                    TextField("이메일", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("비밀번호", text: $password)
                    if let message { Text(message).font(.footnote) }
                    Button(signup ? "회원가입" : "로그인") { Task { await submit() } }.disabled(working || !email.contains("@") || password.count < 6)
                    Button(signup ? "기존 계정으로 로그인" : "계정이 없나요? 회원가입") { signup.toggle(); message = nil }.disabled(working)
                }
            }.navigationTitle("찾아줘 계정").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.disabled(working) }
            }
        }.interactiveDismissDisabled(working)
    }
    private func submit() async {
        working = true; defer { working = false }
        do {
            if signup {
                if try await lf.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password) { dismiss() }
                else { message = "인증 메일을 확인한 뒤 로그인해 주세요." }
            } else { try await lf.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password); dismiss() }
        } catch { message = error.localizedDescription }
    }
}

/// Keep the place label and coordinates together; a label alone cannot move a map pin.
private struct LostFoundLocationFields: View {
    @Binding var building: CampusBuilding?
    @Binding var detail: String
    @Binding var direct: Bool
    @Binding var latitude: String
    @Binding var longitude: String
    @State private var query = ""
    let police: Bool
    private var locationLength: Int {
        let label = LostFoundRules.locationName(buildingTitle: building?.displayTitle, detail: detail, direct: direct) ?? detail
        return LostFoundRules.locationCharacterCount(label)
    }
    var body: some View {
        Section(police ? "이관한 경찰서의 실제 위치" : "현재 보관 장소") {
            Toggle("장소와 좌표 직접 입력", isOn: $direct)
            if direct {
                TextField(police ? "경찰서 이름과 보관 부서" : "구체적인 장소 이름", text: $detail)
                TextField("위도 (예: 37.46328)", text: $latitude).keyboardType(.numbersAndPunctuation)
                TextField("경도 (예: 126.95015)", text: $longitude).keyboardType(.numbersAndPunctuation)
            } else {
                TextField("건물 이름 또는 동 번호 검색", text: $query)
                if let building { Text("선택: \(building.displayTitle)").foregroundStyle(Color.cjTealText) }
                if !query.isEmpty {
                    ForEach(Array(CampusBuildingCatalog.search(query).prefix(10))) { place in
                        Button(place.displayTitle) { building = place; query = "" }
                    }
                }
                TextField("호실·보관 부서·건물 안 구체적 위치", text: $detail)
            }
            Text("장소명 \(locationLength)/\(LostFoundRules.maximumLocationCharacters)자 (건물명 포함)")
                .font(.caption).foregroundStyle(.secondary)
            if locationLength > LostFoundRules.maximumLocationCharacters {
                Text("장소명은 건물 이름을 포함해 \(LostFoundRules.maximumLocationCharacters)자 이하로 줄여 주세요.")
                    .font(.caption).foregroundStyle(.red)
            }
            Text(police ? "실제 이관한 경찰서 이름과 좌표를 입력하세요. 이전 보관 건물 위치를 그대로 사용하지 마세요." : "건물과 호실 또는 구체적 장소를 반드시 입력하세요. 지도에는 입력한 보관 위치가 표시됩니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LostFoundEditor: View {
    @EnvironmentObject private var lf: LostFoundAPI
    @Environment(\.dismiss) private var dismiss
    @State private var category = "지갑"
    @State private var title = ""
    @State private var description = ""
    @State private var building: CampusBuilding?
    @State private var locationDetail = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var direct = false
    @State private var working = false
    @State private var photoLoading = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: Data?
    @State private var photoError: String?
    @State private var error: String?
    private var location: (String, Double, Double)? {
        LostFoundLocation.make(building: building, detail: locationDetail, direct: direct, latitude: latitude, longitude: longitude, campusOnly: true)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("습득물 정보") {
                    Picker("물품 종류", selection: $category) { ForEach(LostFoundKind.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                    TextField("물건 이름 (2~100자)", text: $title)
                    TextField("공개 가능한 외형 설명 (선택)", text: $description, axis: .vertical).lineLimit(2...5)
                    Text("등록일은 서버에서 자동 기록합니다. 학교 담당자 또는 사용자 등록 여부는 로그인 계정 권한으로 결정됩니다.").font(.caption).foregroundStyle(.secondary)
                }
                LostFoundLocationFields(building: $building, detail: $locationDetail, direct: $direct, latitude: $latitude, longitude: $longitude, police: false)
                Section("사진 (선택)") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(photo == nil ? "사진 선택" : "사진 변경", systemImage: "photo") }.disabled(working)
                    if photoLoading { ProgressView("사진 준비 중") }
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    }
                    if selectedPhoto != nil || photo != nil {
                        Button("사진 제거", role: .destructive) { selectedPhoto = nil; self.photo = nil; photoError = nil }
                    }
                    if let photoError { Text(photoError).font(.footnote).foregroundStyle(.red) }
                    Text("사진은 JPEG 512KB 이하로 줄여 전송합니다. 카드·신분증의 개인정보가 보이지 않게 선택하세요.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.disabled(working).navigationTitle("습득물 등록").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.disabled(working) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("등록") { Task { await submit() } }
                            .disabled(working || photoLoading || photoError != nil || !LostFoundRules.validTitle(title) || !LostFoundRules.validDescription(description, required: false) || location == nil)
                    }
                }.task(id: selectedPhoto) { await loadPhoto() }
        }.interactiveDismissDisabled(working)
    }
    private func loadPhoto() async {
        guard let selectedPhoto else { photo = nil; photoLoading = false; return }
        photoLoading = true; photo = nil; photoError = nil
        defer { if selectedPhoto == self.selectedPhoto { photoLoading = false } }
        do {
            guard let original = try await selectedPhoto.loadTransferable(type: Data.self) else { throw CommunityError.message("선택한 사진을 읽을 수 없습니다. 다른 사진을 선택하세요.") }
            guard !Task.isCancelled, selectedPhoto == self.selectedPhoto else { return }
            guard let compressed = LostFoundPhoto.jpeg(original) else { throw CommunityError.message("사진을 JPEG 512KB 이하로 변환할 수 없습니다. 다른 사진을 선택하세요.") }
            guard !Task.isCancelled, selectedPhoto == self.selectedPhoto else { return }
            photo = compressed
        } catch { if !Task.isCancelled, selectedPhoto == self.selectedPhoto { photoError = error.localizedDescription } }
    }
    private func submit() async {
        guard let location else { return }
        working = true; defer { working = false }
        do {
            try await lf.add(category: category, title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: description.trimmingCharacters(in: .whitespacesAndNewlines), locationName: location.0, latitude: location.1, longitude: location.2, photo: photo)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private enum LostFoundLocation {
    static func make(building: CampusBuilding?, detail: String, direct: Bool, latitude: String, longitude: String, campusOnly: Bool) -> (String, Double, Double)? {
        guard let label = LostFoundRules.locationName(buildingTitle: building?.displayTitle, detail: detail, direct: direct) else { return nil }
        let lat: Double, lng: Double
        if direct {
            guard let a = Double(latitude.trimmingCharacters(in: .whitespaces)), let b = Double(longitude.trimmingCharacters(in: .whitespaces)) else { return nil }
            lat = a; lng = b
        } else {
            guard let building else { return nil }
            lat = building.latitude; lng = building.longitude
        }
        let coordinateValid = campusOnly ? LostFoundRules.validCampusCoordinate(latitude: lat, longitude: lng) : LostFoundRules.validCoordinate(latitude: lat, longitude: lng)
        guard LostFoundRules.validLocation(label), coordinateValid else { return nil }
        return (label, lat, lng)
    }
}

private enum LostFoundPhoto {
    static func jpeg(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        for size in [1600, 1100, 800, 500] {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size
            ] as CFDictionary) else { return nil }
            for quality in [0.82, 0.6, 0.4] {
                let result = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                if CGImageDestinationFinalize(destination), LostFoundRules.validPhoto(result as Data) { return result as Data }
            }
        }
        return nil
    }
}

struct LostFoundRecordDetail: View {
    @EnvironmentObject private var lf: LostFoundAPI
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let record: LostFoundRecord
    let type: LostFoundType // Existing map callers retain this argument; the screen only handles found items.
    @State private var loaded: LostFoundRecord?
    @State private var showClaim = false
    @State private var showTransfer = false
    @State private var loading = false
    @State private var error: String?
    private var item: LostFoundRecord { loaded ?? lf.found.first { $0.id == record.id } ?? record }
    var body: some View {
        NavigationStack {
            Form {
                Section(item.title) {
                    LabeledContent("종류", value: item.category)
                    LabeledContent("등록자", value: item.sourceTitle)
                    LabeledContent("등록일", value: LostFoundDate.label(item.registeredAt))
                    LabeledContent("보관 상태", value: item.statusTitle)
                    LabeledContent("보관 장소", value: item.locationName)
                    Text(item.description.isEmpty ? "추가 설명 없음" : item.description)
                }
                if item.status == "police" {
                    Section("경찰서 이관 안내") {
                        Text(LostFoundRules.policeReceiptNotice)
                        Text("앱의 수령 확인은 사용자가 직접 남긴 결과이며 경찰서의 수령 기록과 자동 연동되지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("사진") {
                    if loading { ProgressView("상세 사진 확인 중") }
                    if let encoded = item.photoBase64, let data = Data(base64Encoded: encoded), LostFoundRules.validPhoto(data), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                    } else if let raw = item.photoUrl, let url = URL(string: raw), url.scheme == "https" {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFit().frame(maxHeight: 360) }
                            else if phase.error != nil { Text("사진을 불러오지 못했습니다.").foregroundStyle(.secondary) }
                            else { ProgressView() }
                        }
                    } else if !loading { Text("등록된 사진이 없습니다.").foregroundStyle(.secondary) }
                }
                Section {
                    Button("지도에서 보관 위치 보기") {
                        store.showDining = false; store.lostMapOnly = true
                        store.lostPinID = "found:\(item.id.uuidString.lowercased())"
                        store.lostFocusSerial += 1; store.tab = .home; dismiss()
                    }
                }
                if item.status != "received" && !item.mine {
                    Section("소유자 확인 후 수령") {
                        Button("내 물건 같아요") { showClaim = true }.disabled(!lf.loggedIn)
                        Text("비공개 특징을 제출하면 보관자 또는 학교 담당자가 소유자를 확인합니다. 확인을 받아도 수령 완료로 바뀌지 않으며, 실제 수령 결과를 직접 남겨야 합니다.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(lf.claims.filter { $0.itemId == item.id }) { claim in
                    Section { LostFoundClaimCard(claim: claim) }
                }
                if (item.mine || lf.isModerator) && item.status != "received" {
                    Section("보관 장소 관리") {
                        Button("경찰서 이관 및 위치 변경") { showTransfer = true }
                        Text("실제 이관한 경우에만 경찰서 이름과 좌표를 입력하세요.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }.navigationTitle("습득물 정보").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) { Button("새로고침") { Task { await reload() } }.disabled(loading) }
                }.task(id: lf.claims.filter { $0.itemId == record.id }.map { "\($0.id):\($0.status)" }.joined(separator: "|")) { await reload() }
                .sheet(isPresented: $showClaim, onDismiss: { Task { await reload() } }) { LostFoundClaimEditor(itemID: item.id) }
                .sheet(isPresented: $showTransfer, onDismiss: { Task { await reload() } }) { LostFoundTransferEditor(itemID: item.id) }
        }
    }
    private func reload() async {
        loading = true; error = nil; defer { loading = false }
        do { loaded = try await lf.detail(record.id) } catch { self.error = error.localizedDescription }
    }
}

private struct LostFoundClaimCard: View {
    @EnvironmentObject private var lf: LostFoundAPI
    let claim: LostFoundClaim
    @State private var busy = false
    @State private var action: String?
    @State private var error: String?
    private var current: LostFoundClaim { lf.claims.first { $0.id == claim.id } ?? claim }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(current.title).font(.headline)
            Text(current.statusTitle).font(.subheadline).foregroundStyle(Color.cjTealText)
            Text("요청일 \(LostFoundDate.label(current.createdAt))").font(.caption).foregroundStyle(.secondary)
            Text("비공개 확인 내용: \(current.proof)").font(.footnote)
            if current.canVerify && current.status == "pending" {
                HStack {
                    Button("소유자 확인") { action = "verify" }
                    Button("소유자가 아니에요", role: .destructive) { action = "reject" }
                }.buttonStyle(.bordered)
            }
            if current.mine && ["pending", "accepted"].contains(current.status) {
                Text("보관자에게 확인받은 뒤 실제 수령 여부를 선택하세요.").font(.caption).foregroundStyle(.secondary)
                if current.status == "accepted" { Button("수령했어요") { action = "received" }.buttonStyle(.borderedProminent) }
                HStack {
                    Button("내 물건이 아니에요") { action = "not_mine" }
                    Button("수령하지 않았어요") { action = "not_received" }
                }.buttonStyle(.bordered)
            }
            if busy { ProgressView("저장 중") }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 12)).disabled(busy)
            .confirmationDialog("확인 결과를 저장할까요?", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
                if let action {
                    Button(action == "verify" ? "소유자로 확인" : action == "reject" ? "확인 거절" : action == "received" ? "실제 수령 완료" : action == "not_mine" ? "내 물건 아님" : "수령하지 않음") { Task { await save(action) } }
                }
                Button("취소", role: .cancel) { action = nil }
            } message: {
                Text(action == "received" ? "실제로 물건을 받았을 때만 수령 완료를 선택하세요. 완료한 물건은 지도에서 제외됩니다." : "소유자 확인과 실제 수령 결과는 별도로 기록됩니다.")
            }
    }
    private func save(_ action: String) async {
        busy = true; error = nil; self.action = nil; defer { busy = false }
        do {
            if action == "verify" || action == "reject" { try await lf.resolveClaim(current.id, accepted: action == "verify") }
            else { try await lf.completeClaim(current.id, outcome: action) }
        } catch { self.error = error.localizedDescription }
    }
}

private struct LostFoundClaimEditor: View {
    @EnvironmentObject private var lf: LostFoundAPI
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID
    @State private var proof = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("비공개 소유권 확인") {
                    TextField("사진에 없는 특징이나 소유 사실 (10~500자)", text: $proof, axis: .vertical).lineLimit(3...6)
                    Text("확인 내용은 보관자·학교 담당자에게 전달됩니다. 주민등록번호·학번·비밀번호를 입력하지 마세요.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy).navigationTitle("내 물건 같아요").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("확인 요청") { Task {
                        busy = true; defer { busy = false }
                        do { try await lf.claim(foundID: itemID, proof: proof); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } }.disabled(busy || !LostFoundRules.validProof(proof))
                }
            }
        }.interactiveDismissDisabled(busy)
    }
}

private struct LostFoundTransferEditor: View {
    @EnvironmentObject private var lf: LostFoundAPI
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID
    @State private var building: CampusBuilding?
    @State private var detail = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var direct = true
    @State private var busy = false
    @State private var confirmed = false
    @State private var error: String?
    private var location: (String, Double, Double)? { LostFoundLocation.make(building: building, detail: detail, direct: direct, latitude: latitude, longitude: longitude, campusOnly: false) }
    var body: some View {
        NavigationStack {
            Form {
                LostFoundLocationFields(building: $building, detail: $detail, direct: $direct, latitude: $latitude, longitude: $longitude, police: true)
                Section { Toggle("실제로 해당 경찰서로 이관했습니다", isOn: $confirmed) }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy).navigationTitle("경찰서 이관").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("이관 저장") { Task {
                        guard let location else { return }
                        busy = true; defer { busy = false }
                        do { try await lf.transfer(itemID, locationName: location.0, latitude: location.1, longitude: location.2); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } }.disabled(busy || !confirmed || location == nil)
                }
            }
        }.interactiveDismissDisabled(busy)
    }
}

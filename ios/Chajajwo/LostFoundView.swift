import SwiftUI

struct LostFoundView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var lf: LostFoundAPI
    @State private var section: Int = 0
    @State private var editor: LostFoundType?
    @State private var selected: LostFoundRecord?
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("학교 안에서 발견하거나 잃어버린 물건을 공유해요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        action("분실물을 발견했어요", icon: "shippingbox.fill", type: .found)
                        action("물건을 잃어버렸어요", icon: "magnifyingglass", type: .lost)
                    }
                    Picker("목록", selection: $section) {
                        Text("분실물센터").tag(0)
                        Text("발견된 물건").tag(1)
                        Text("찾는 물건").tag(2)
                    }.pickerStyle(.segmented)
                    if let error = lf.error {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                    if section == 0 { centerList }
                    if section == 1 { recordList(lf.found, type: .found) }
                    if section == 2 { recordList(lf.lost, type: .lost) }
                    if lf.loggedIn && (!lf.inbox.isEmpty || !lf.myClaims.isEmpty || !lf.leads.isEmpty) { myResponses }
                    if !lf.loggedIn {
                        Button("로그인하고 습득물·분실 의뢰 보기") { showAuth = true }
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Color.cjTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("분실물")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await lf.prepare() } } label: { Image(systemName: "arrow.clockwise") } } }
            .task { await lf.prepare() }
            .refreshable { await lf.prepare() }
            .sheet(item: $editor) { kind in LostFoundEditor(type: kind) }
            .sheet(item: $selected) { record in LostFoundRecordDetail(record: record, type: section == 1 ? .found : .lost) }
            .sheet(isPresented: $showAuth) { LostFoundAuthView() }
        }
    }
    private func action(_ title: String, icon: String, type: LostFoundType) -> some View {
        Button {
            if lf.loggedIn { editor = type }
            else { showAuth = true }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
            }
            .foregroundStyle(Color.cjTealText).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .padding(.horizontal, 14).background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
    private var centerList: some View {
        VStack(spacing: 10) {
            ForEach(lf.centers) { center in
                VStack(alignment: .leading, spacing: 7) {
                    Text(center.name).font(.headline)
                    Text("\(center.building) · \(center.room)").font(.subheadline)
                    Text(center.weekdayHours ?? "운영시간 미확인").font(.subheadline).foregroundStyle(Color.cjTealText)
                    Text(center.weekendHolidayNote).font(.caption).foregroundStyle(.secondary)
                    Text(center.custodyNote).font(.caption)
                    HStack {
                        Button("지도에서 보기") { focus("center:\(center.id)") }
                        if let phone = center.phone, let tel = URL(string: "tel:\(phone)") { Link("전화", destination: tel) }
                        if let source = URL(string: center.sourceUrl) { Link("공식 안내", destination: source) }
                    }.font(.footnote.weight(.semibold)).buttonStyle(.bordered)
                    Text("확인 기준: \(center.checkedOn)").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15).background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }
    private func recordList(_ items: [LostFoundRecord], type: LostFoundType) -> some View {
        VStack(spacing: 9) {
            if !lf.loggedIn { Text("게시물 조회는 로그인 후 이용할 수 있어요.").foregroundStyle(.secondary).padding(24) }
            else if items.isEmpty { ContentUnavailableView("등록된 물건이 없어요", systemImage: "shippingbox", description: Text("첫 신고를 등록해 주세요.")) }
            ForEach(lf.loggedIn ? items : []) { item in
                Button { selected = item } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: type == .found ? "shippingbox" : "magnifyingglass")
                            .foregroundStyle(Color.cjTeal).frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline)
                            Text("\(item.category) · \(item.locationName)").font(.subheadline).foregroundStyle(.secondary)
                            Text(type == .found ? "회원이 등록한 습득 정보" : "회원이 등록한 분실 추정 장소")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
            }
        }
    }
    private var myResponses: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !lf.myClaims.isEmpty {
                Text("내가 보낸 소유권 확인 요청").font(.headline)
                ForEach(lf.myClaims) { claim in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(claim.foundTitle).font(.subheadline.weight(.semibold))
                            Text(claim.status == "pending" ? "확인 대기" : claim.status == "accepted" ? "신고자가 확인했어요" : "요청이 반려되었어요")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if !lf.inbox.isEmpty { Text("내 습득물에 도착한 확인 요청").font(.headline) }
            ForEach(lf.inbox) { claim in
                VStack(alignment: .leading, spacing: 5) {
                    Text(claim.foundTitle).font(.subheadline.weight(.bold))
                    Text("비공개 소유권 확인: \(claim.proofNote)").font(.footnote)
                    Text(claim.status == "pending" ? "확인 대기" : claim.status == "accepted" ? "승인" : "반려")
                        .font(.caption).foregroundStyle(.secondary)
                    if claim.status == "pending" {
                        HStack {
                            Button("확인") { Task { try? await lf.resolveClaim(claim.id, accepted: true) } }
                            Button("반려", role: .destructive) { Task { try? await lf.resolveClaim(claim.id, accepted: false) } }
                        }.buttonStyle(.bordered)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 12))
            }
            if !lf.leads.isEmpty { Text("내 분실 의뢰 관련 제보").font(.headline) }
            ForEach(lf.leads.indices, id: \.self) { i in
                Text("관련 습득물: \(lf.leads[i].foundTitle)").font(.subheadline)
            }
        }
    }
    private func focus(_ id: String) {
        store.showDining = false
        store.lostMapOnly = true
        store.lostPinID = id
        store.lostFocusSerial += 1
        store.tab = .home
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
                    TextField("이메일", text: $email).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("비밀번호", text: $password)
                    if let message { Text(message).font(.footnote) }
                    Button(signup ? "회원가입" : "로그인") { Task { await submit() } }
                        .disabled(working || !email.contains("@") || password.count < 6)
                    Button(signup ? "기존 계정으로 로그인" : "계정이 없나요? 회원가입") { signup.toggle(); message = nil }
                }
            }.navigationTitle("찾아줘 계정")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
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

private struct LostFoundEditor: View {
    @EnvironmentObject private var lf: LostFoundAPI
    @Environment(\.dismiss) private var dismiss
    let type: LostFoundType
    @State private var category = "지갑"
    @State private var title = ""
    @State private var description = ""
    @State private var eventAt = Date()
    @State private var buildingQuery = ""
    @State private var building: CampusBuilding?
    @State private var custody = "finder"
    @State private var centerID = "snu101"
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(type.title) {
                    Picker("물품 종류", selection: $category) {
                        ForEach(LostFoundKind.allCases) { item in Text(item.rawValue).tag(item.rawValue) }
                    }
                    TextField("물건 이름", text: $title)
                    TextField(type == .found ? "공개 가능한 외형 설명 (선택)" : "물건 특징 (색상·형태 등)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker(type == .found ? "발견 시각" : "마지막 확인 시각", selection: $eventAt, in: ...Date())
                }
                Section(type == .found ? "발견한 장소" : "마지막으로 확인한 장소") {
                    TextField("건물 이름 또는 동 번호 검색", text: $buildingQuery)
                    if let building { Text("선택: \(building.displayTitle)").foregroundStyle(Color.cjTealText) }
                    if !buildingQuery.isEmpty {
                        ForEach(Array(CampusBuildingCatalog.search(buildingQuery).prefix(7))) { place in
                            Button(place.displayTitle) { building = place; buildingQuery = "" }
                        }
                    }
                    Text("서울대 건물 데이터에서 위치를 선택합니다. 지도에는 실제 습득 위치 또는 분실 추정 위치로 표시됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if type == .found {
                    Section("현재 물건 상태") {
                        Picker("보관 상황", selection: $custody) {
                            Text("제가 보관 중이에요").tag("finder")
                            Text("분실물센터에 인계했어요").tag("center")
                            Text("발견 사실만 제보해요").tag("sighting")
                        }
                        if custody == "center" {
                            Picker("인계한 보관처", selection: $centerID) {
                                ForEach(lf.centers) { center in Text(center.name).tag(center.id) }
                            }
                        }
                        Text("실제 인계하지 않았다면 보관처 인계를 선택하지 마세요. 신분증 번호·학번 등 개인정보를 적지 마세요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("실명, 학번, 연락처, 카드·학생증 번호와 비밀번호를 공개 설명에 입력하지 마세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(type.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("등록") { Task { await submit() } }
                        .disabled(working || !LostFoundRules.validTitle(title) || !LostFoundRules.validDescription(description, required: type == .lost) || building == nil)
                }
            }
        }
    }
    private func submit() async {
        guard let building else { return }
        working = true; defer { working = false }
        do {
            try await lf.add(type, category: category, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines), building: building,
                eventAt: eventAt, custody: custody, centerID: custody == "center" ? centerID : nil)
            dismiss()
        } catch { error = error.localizedDescription }
    }
}

private struct LostFoundRecordDetail: View {
    @EnvironmentObject private var lf: LostFoundAPI
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let record: LostFoundRecord
    let type: LostFoundType
    @State private var showClaim = false
    @State private var selectedRequest: UUID?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(record.title) {
                    LabeledContent("종류", value: record.category)
                    LabeledContent(type == .found ? "발견 장소" : "분실 추정 장소", value: record.locationName)
                    Text(record.description.isEmpty ? "추가 설명 없음" : record.description)
                    Text("회원 등록 정보이며 공식 확인을 의미하지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if type == .found { Text(record.custody == "center" ? "센터 인계(회원 신고)" : record.custody == "sighting" ? "발견 사실 제보" : "습득자 보관 중(회원 신고)") }
                }
                Section {
                    Button("지도에서 위치 보기") {
                        store.showDining = false
                        store.lostMapOnly = true
                        store.lostPinID = "\(type.rawValue):\(record.id.uuidString.lowercased())"
                        store.lostFocusSerial += 1
                        store.tab = .home
                        dismiss()
                    }
                }
                if type == .found && !record.mine {
                    Section("소유자 확인") {
                        Button("내 물건 같아요") { showClaim = true }
                        Text("사진에 보이지 않는 특징 등을 비공개로 제출해 주세요. 최종 소유권 확인은 신고자 또는 공식 보관처가 진행합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if type == .found && record.mine && !lf.lost.isEmpty {
                    Section("분실 의뢰에 발견 사실 연결") {
                        Picker("관련 의뢰", selection: $selectedRequest) {
                            Text("선택해 주세요").tag(UUID?.none)
                            ForEach(lf.lost.filter { !$0.mine }) { other in Text(other.title).tag(Optional(other.id)) }
                        }
                        Button("의뢰자에게 제보") { Task { await link() } }.disabled(selectedRequest == nil)
                    }
                }
                if record.mine {
                    Section("내 등록 관리") {
                        Button(type == .found ? "수령 완료 처리" : "찾았어요 · 완료 처리") {
                            Task { await updateStatus(type == .found ? "returned" : "resolved") }
                        }
                        Button("목록에서 종료", role: .destructive) { Task { await updateStatus("closed") } }
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(type == .found ? "습득물 정보" : "분실 의뢰")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .sheet(isPresented: $showClaim) { LostFoundClaimEditor(itemID: record.id) }
        }
    }
    private func updateStatus(_ status: String) async {
        do { try await lf.setStatus(type, id: record.id, status: status); dismiss() }
        catch { error = error.localizedDescription }
    }
    private func link() async {
        guard let requestID = selectedRequest else { return }
        do { try await lf.link(foundID: record.id, requestID: requestID); dismiss() }
        catch { error = error.localizedDescription }
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
                    TextField("사진에 없는 특징이나 소유 사실을 적어주세요", text: $proof, axis: .vertical).lineLimit(3...6)
                    Text("이 내용은 습득물 신고자에게만 전달됩니다. 주민등록번호·학번·비밀번호를 입력하지 마세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("내 물건 같아요")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("확인 요청") { Task {
                        busy = true; defer { busy = false }
                        do { try await lf.claim(foundID: itemID, proof: proof); dismiss() }
                        catch { error = error.localizedDescription }
                    } }.disabled(busy || !LostFoundRules.validProof(proof))
                }
            }
        }
    }
}

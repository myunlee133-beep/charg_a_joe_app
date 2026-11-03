import SwiftUI

struct QuestDetailView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    let quest: Quest
    @State private var results: [QuestResult] = []
    @State private var showSubmit = false
    @State private var showConsent = false
    @State private var confirmAccept = false
    @State private var reviewID: UUID?
    @State private var resultText = ""
    @State private var working = false
    @State private var error: String?
    private var current: Quest { (store.myQuests + store.quests).first { $0.id == quest.id } ?? quest }
    private var canSubmit: Bool {
        !current.isMine && (current.mode == .resultReward ? current.status == "open" && (current.myParticipationStatus == nil || current.myParticipationStatus == "rejected") : current.status == "assigned" && ["accepted", "rejected"].contains(current.myParticipationStatus ?? ""))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack { Badge(text: current.category.title, color: .cjTeal); Badge(text: current.mode.title, color: current.mode == .firstCome ? .cjTeal : .cjBlue) }
                    Text(current.title).font(.title2.weight(.heavy))
                    Text(current.rewardText).font(.largeTitle.weight(.heavy)).foregroundStyle(Color.cjTealText)
                    Label(current.building, systemImage: "mappin.and.ellipse").font(.subheadline)
                    Divider()
                    Text("부탁드리는 내용").font(.headline)
                    Text(current.details).lineSpacing(6)
                    Label(current.requester, systemImage: "person.crop.circle").font(.subheadline)
                    Text(current.mode == .firstCome ? "먼저 수락한 한 사람이 수행해요. 결과를 제출하고 의뢰자가 승인하면 보상을 직접 송금해요." : "여러 사람이 결과를 제출할 수 있어요. 의뢰자가 승인한 한 결과에 보상을 직접 송금해요.")
                        .font(.subheadline).foregroundStyle(Color.cjSub)
                    Text("보상은 이용자 간 직접 계좌송금입니다. 앱의 송금 신고와 실제 입금 확인은 구분되어 기록돼요.")
                        .font(.footnote).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cjInset, in: RoundedRectangle(cornerRadius: 12))
                    if current.isMine {
                        Text("수행·제출 결과").font(.headline)
                        if results.isEmpty { Text("아직 수락하거나 제출한 사람이 없어요.").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(result.nickname).font(.headline)
                                Text(result.resultText ?? "수락 후 결과 제출 전이에요.")
                                if result.status == "submitted" && ["open", "assigned"].contains(current.status) {
                                    HStack {
                                        Button("결과 승인 · 보상 확정") { reviewID = result.id }.buttonStyle(.borderedProminent)
                                        Button("보완 요청") { run { let _: Bool = try await account.rpc("quest_review", ["p_participation_id": result.id.uuidString, "p_accept": false], as: Bool.self) } }
                                    }.font(.footnote)
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.cjInset, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if current.status == "open" && results.isEmpty {
                            Button("의뢰 취소", role: .destructive) { run { let _: Bool = try await account.rpc("quest_cancel", ["p_quest_id": current.id], as: Bool.self) } }
                        }
                    }
                    if ["awaiting_transfer", "transfer_reported", "completed", "disputed"].contains(current.status) {
                        NavigationLink { QuestTransactionsView() } label: { Label("보상·송금 기록 보기", systemImage: "banknote") }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(22)
            }
            .navigationTitle("퀘스트 상세").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if !current.isMine && (canSubmit || current.status == "open" && current.mode == .firstCome && current.myParticipationId == nil) {
                    Button {
                        guard ready() else { return }
                        if canSubmit { showSubmit = true } else { confirmAccept = true }
                    } label: {
                        Text(!account.authenticated ? "로그인하고 참여하기" : canSubmit ? "결과 제출하기" : "퀘스트 수락하기")
                            .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(16)
                            .background(Color.cjTeal, in: RoundedRectangle(cornerRadius: 14))
                    }.disabled(working).padding(16).background(Color.cjSurface)
                }
            }
            .confirmationDialog("이 퀘스트를 수락할까요?", isPresented: $confirmAccept, titleVisibility: .visible) {
                Button("수락하기") { run { let _: UUID = try await account.rpc("quest_accept", ["p_quest_id": current.id], as: UUID.self) } }
            } message: { Text("\(current.rewardText) · 수행 후 결과 승인을 받으면 의뢰자가 직접 송금해요.") }
            .confirmationDialog("결과를 승인하고 보상을 확정할까요?", isPresented: Binding(get: { reviewID != nil }, set: { if !$0 { reviewID = nil } }), titleVisibility: .visible) {
                if let id = reviewID { Button("승인 · \(current.rewardText) 지급 약정") { run { let _: Bool = try await account.rpc("quest_review", ["p_participation_id": id.uuidString, "p_accept": true], as: Bool.self) } } }
            } message: { Text("승인 후 보상을 직접 송금해야 해요. 이 버튼은 은행 이체를 실행하지 않습니다.") }
            .sheet(isPresented: $showConsent) { QuestTransactionConsentView() }
            .sheet(isPresented: $showSubmit) {
                NavigationStack {
                    Form {
                        Section("수행 결과 · 10~2000자") { TextEditor(text: $resultText).frame(minHeight: 150) }
                        Section { Text("결과는 의뢰자와 본인에게만 보여요. 주민번호·계좌 비밀번호 등 불필요한 개인정보를 포함하지 마세요.").font(.caption) }
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    }.navigationTitle("결과 제출")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("취소") { showSubmit = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("제출") { run { let _: UUID = try await account.rpc("quest_submit", ["p_quest_id": current.id, "p_result": resultText], as: UUID.self); showSubmit = false; resultText = "" } }
                                .disabled(working || !(10...2000).contains(resultText.trimmingCharacters(in: .whitespacesAndNewlines).count))
                        }
                    }
                }
            }
            .task { await reload() }
            .onChange(of: account.userID) { _, _ in results = []; resultText = ""; Task { await reload() } }
        }
    }
    private func ready() -> Bool {
        if !account.authenticated { store.showAccountLogin = true; dismiss(); return false }
        if account.details?.ready != true { return false }
        if account.details?.transactionConsent != true { showConsent = true; return false }
        return true
    }
    private func reload() async {
        await store.refreshQuests()
        guard account.authenticated else { results = []; return }
        do { results = try await QuestAccountAPI.results(current) }
        catch { self.error = error.localizedDescription }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard ready() else { return }
        working = true; error = nil
        Task { @MainActor in
            defer { working = false }
            do { try await operation(); await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct CreateQuestView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var reward = "3000"
    @State private var category = QuestCategory.errand
    @State private var mode = QuestMode.firstCome
    @State private var buildingID = ""
    @State private var working = false
    @State private var error: String?
    @State private var showConsent = false
    private var buildings: [CampusBuilding] { CampusBuildingCatalog.all.sorted { $0.name < $1.name } }
    private var building: CampusBuilding? { buildings.first { $0.id == buildingID } }
    private var valid: Bool { (2...120).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count) && (10...4000).contains(details.trimmingCharacters(in: .whitespacesAndNewlines).count) && (1...1_000_000).contains(Int(reward) ?? 0) && building != nil && !working }
    var body: some View {
        NavigationStack {
            Form {
                Section("어떤 도움이 필요한가요?") {
                    TextField("제목 · 2~120자", text: $title)
                    Picker("종류", selection: $category) { ForEach(QuestCategory.allCases) { Text($0.title).tag($0) } }
                    Picker("보상 방식", selection: $mode) { ForEach(QuestMode.allCases) { Text($0.title).tag($0) } }
                    TextField("수행 기준·실비 포함 여부 · 10자 이상", text: $details, axis: .vertical).lineLimit(5...10)
                }
                Section("장소와 보상") {
                    Picker("캠퍼스 건물", selection: $buildingID) { Text("선택해 주세요").tag(""); ForEach(buildings) { Text($0.displayTitle).tag($0.id) } }
                    TextField("보상액 · 1~1,000,000원", text: $reward).keyboardType(.numberPad)
                    Text("결과 승인 후 수행자에게 직접 계좌송금해요. 보상액과 별도 실비 여부를 등록 전에 확인해 주세요.").font(.footnote)
                }
                if !account.authenticated {
                    Button("로그인하고 등록하기") { store.showAccountLogin = true; dismiss() }
                } else if account.details?.transactionConsent != true {
                    Button("퀘스트 거래 약관 확인") { showConsent = true }
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }.navigationTitle("퀘스트 등록")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(working ? "등록 중…" : "등록") { create() }.disabled(!valid || !account.authenticated || account.details?.ready != true || account.details?.transactionConsent != true) }
            }
            .sheet(isPresented: $showConsent) { QuestTransactionConsentView() }
        }
    }
    private func create() {
        guard valid, let building, let amount = Int(reward) else { return }
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                let _: UUID = try await account.rpc("quest_create", ["p_title": title, "p_details": details,
                    "p_category": category.rawValue, "p_mode": mode.rawValue, "p_reward": amount,
                    "p_place": building.name, "p_building": building.displayTitle,
                    "p_latitude": building.latitude, "p_longitude": building.longitude], as: UUID.self)
                await store.refreshQuests(); store.toast("퀘스트를 등록했어요"); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct MyQuestsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: AccountStore
    var body: some View {
        List {
            if !account.authenticated {
                Button("로그인하고 내 퀘스트 보기") { store.showAccountLogin = true }
            } else {
                Section { NavigationLink { QuestTransactionsView() } label: { Label("보상·송금 기록", systemImage: "banknote") } }
                if store.myQuests.isEmpty { Text("참여하거나 등록한 퀘스트가 없어요.").foregroundStyle(.secondary) }
                ForEach(store.myQuests) { quest in
                    NavigationLink { QuestDetailView(quest: quest) } label: {
                        VStack(alignment: .leading) {
                            QuestRow(quest: quest)
                            Text(quest.isMine ? "내 의뢰" : "내 수행").font(.caption).foregroundStyle(Color.cjTealText)
                        }
                    }
                }
            }
            if let error = store.questError { Text(error).font(.footnote).foregroundStyle(.red) }
        }.navigationTitle("내 퀘스트").refreshable { await store.refreshQuests() }.task { await store.refreshQuests() }
    }
}

import SwiftUI
import PhotosUI

// MARK: 분실물 발견
struct FoundView: View {
    @EnvironmentObject var store: Store
    @State private var kind = "전체"

    var body: some View {
        let all = store.items
        let list = kind == "전체" ? all : all.filter { $0.kind == kind }
        let today = all.filter { Date().timeIntervalSince($0.at) < 86400 }.count
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["전체"] + kinds, id: \.self) { k in
                                Button(k) { kind = k }
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(kind == k ? Color.white : .primary)
                                    .padding(.horizontal, 14).frame(height: 34)
                                    .background(kind == k ? Color.cjTeal : Color.cjSurface, in: Capsule())
                                    .overlay(Capsule().stroke(Color.cjLine))
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)).listRowBackground(Color.clear)
                } footer: {
                    Text("운영팀이 실물 위치를 확인한 분실물만 올라와요 · 오늘 \(today)건")
                }
                Section {
                    if list.isEmpty { Text("해당 종류의 분실물이 없어요").foregroundStyle(Color.cjSub) }
                    ForEach(list) { i in ItemRow(item: i) { store.focus(hub: i.hub, item: i.id) } }
                }
            }
            .navigationTitle("분실물 발견")
        }
    }
}

// MARK: 내 분실 신고
struct ReportView: View {
    @EnvironmentObject var store: Store
    @State private var kind = kinds[0]
    @State private var place = ""
    @State private var date = Date()
    @State private var feat = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("분실 신고 등록") {
                    Picker("물건 종류", selection: $kind) { ForEach(kinds, id: \.self) { Text($0) } }
                    TextField("잃어버린 곳 (예: 학생회관 식당)", text: $place)
                    DatePicker("잃어버린 날", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("특징 (색상, 브랜드 등)", text: $feat)
                    Button("신고 등록", action: submit).disabled(place.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("찾은 후보 \(store.matches.count)건") {
                    if store.matches.isEmpty {
                        Text("아직 비슷한 습득물이 없어요. 등록되면 알려 드릴게요").foregroundStyle(Color.cjSub)
                    }
                    ForEach(store.matches) { i in ItemRow(item: i) { store.focus(hub: i.hub, item: i.id) } }
                }
                Section("내 신고 \(store.lost.count)건") {
                    if store.lost.isEmpty { Text("등록한 신고가 없어요").foregroundStyle(Color.cjSub) }
                    ForEach(store.lost) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.kind).font(.body.weight(.bold))
                            Text("\(l.place) · \(l.date.formatted(.dateTime.year().month().day()))")
                                .font(.footnote).foregroundStyle(Color.cjSub)
                        }
                    }
                    .onDelete { store.deleteLost(at: $0) }
                }
                Section("수령 확인 요청 \(store.claims.count)건") {
                    if store.claims.isEmpty { Text("아직 요청이 없어요").foregroundStyle(Color.cjSub) }
                    ForEach(store.claims) { c in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.body.weight(.bold))
                                Text("\(Place.byID[c.hub]?.name ?? "") · \(ago(c.at))").font(.footnote).foregroundStyle(Color.cjSub)
                            }
                            Spacer()
                            if c.done {
                                Badge(text: "수령 완료", color: .cjTeal)
                            } else {
                                Button("수령 완료 체크") { store.markDone(c) }.buttonStyle(.borderless).font(.caption.weight(.bold))
                            }
                        }
                    }
                }
            }
            .navigationTitle("내 분실 신고")
        }
    }

    private func submit() {
        store.addLost(LostReport(kind: kind, place: place, date: Calendar.current.startOfDay(for: date), feat: feat))
        place = ""; feat = ""
        store.toast(store.matches.isEmpty ? "신고를 등록했어요" : "비슷한 습득물을 찾았어요")
    }
}

// MARK: 내 정보 + 운영팀 등록
struct MeView: View {
    @EnvironmentObject var store: Store
    @State private var pick: PhotosPickerItem?
    @State private var photo: Data?
    @State private var title = ""
    @State private var kind = kinds[0]
    @State private var feat = ""
    @State private var found = ""
    @State private var hub = Place.hubs[0].id

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label(photo == nil ? "사진 선택" : "사진 선택됨", systemImage: "camera")
                    }
                    TextField("물건 이름 (예: 검정 반지갑)", text: $title)
                    Picker("종류", selection: $kind) { ForEach(kinds, id: \.self) { Text($0) } }
                    TextField("특징 (사진에 보이는 것만)", text: $feat)
                    TextField("습득 장소 (예: 학생회관 2층 식당)", text: $found)
                    Picker("보관 거점", selection: $hub) { ForEach(Place.hubs) { Text($0.name).tag($0.id) } }
                    Button("지도에 등록", action: submit)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || found.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("운영팀 습득물 등록")
                } footer: {
                    Text("신분증과 카드 정보는 가리고 찍어 주세요.")
                }
                Section("내가 등록한 습득물 \(store.mine.count)건") {
                    if store.mine.isEmpty { Text("아직 없어요").foregroundStyle(Color.cjSub) }
                    ForEach(store.mine) { i in ItemRow(item: i) { store.focus(hub: i.hub, item: i.id) } }
                }
            }
            .navigationTitle("내 정보")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { MyQuestsView() } label: { Label("내 퀘스트", systemImage: "bolt.circle") }
                }
            }
            .onChange(of: pick) { _, p in
                Task { photo = try? await p?.loadTransferable(type: Data.self) }
            }
        }
    }

    private func submit() {
        store.addItem(Item(id: "u\(Int(Date().timeIntervalSince1970 * 1000))", hub: hub, kind: kind, title: title,
                           feat: feat.isEmpty ? "-" : feat, found: found, at: Date(), photo: photo.flatMap(Photo.shrink)))
        title = ""; feat = ""; found = ""; photo = nil; pick = nil
        store.toast("지도에 등록했어요")
    }
}

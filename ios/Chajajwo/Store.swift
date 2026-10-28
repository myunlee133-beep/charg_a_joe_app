import SwiftUI

// ponytail: 웹 버전처럼 기기 로컬 저장(UserDefaults). 여러 기기·운영팀 공유가 필요하면 Supabase(places, items, claims)로 교체.
final class Store: ObservableObject {
    enum Tab: Hashable { case home, found, report, community, me }

    // 화면 상태
    @Published var tab = Tab.home
    @Published var showDining = false   // 홈 탭 안에서 지도 대신 식당 화면을 보여준다
    @Published var sel = Place.all[0].id
    @Published var open = false
    @Published var itemID: String?
    @Published var claim = false
    @Published var menu = false
    @Published var filter: PlaceType?
    @Published var toastText: String?
    @Published private(set) var dining = DiningData.startup()
    private var diningFetchedAt = Date.distantPast
    private var diningLoading = false

    // 저장되는 데이터
    @Published private(set) var mine: [Item] = [] { didSet { save() } }
    @Published private(set) var lost: [LostReport] = [] { didSet { save() } }
    @Published private(set) var claims: [Claim] = [] { didSet { save() } }
    @Published private(set) var claimed: Set<String> = [] { didSet { save() } }

    private struct Saved: Codable { var mine: [Item]; var lost: [LostReport]; var claims: [Claim]; var claimed: Set<String> }
    private let key = "cj_saved"

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            mine = s.mine; lost = s.lost; claims = s.claims; claimed = s.claimed
        }
    }

    private func save() {
        let s = Saved(mine: mine, lost: lost, claims: claims, claimed: claimed)
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
    }

    var items: [Item] { (mine + Item.seed).filter { !claimed.contains($0.id) }.sorted { $0.at > $1.at } }

    /// 내 분실 신고와 종류가 같고 분실일 3일 전 이후에 습득된 물건
    var matches: [Item] {
        items.filter { i in lost.contains { $0.kind == i.kind && i.at >= $0.date.addingTimeInterval(-3 * 86400) } }
    }

    // MARK: 지도 시트
    func select(_ id: String, item: String? = nil) {
        sel = id; open = true; itemID = item; claim = false; menu = false; showDining = false
    }
    func closeSheet() { open = false; itemID = nil }
    func focus(hub: String, item: String) { tab = .home; filter = nil; select(hub, item: item) }

    /// 최신 식단을 받아 온다. 실패하면 기존(캐시/번들) 식단을 그대로 쓴다.
    @MainActor func refreshDining() async {
        guard !diningLoading, Date().timeIntervalSince(diningFetchedAt) > 600 else { return }
        diningLoading = true
        defer { diningLoading = false }
        if let fresh = await DiningData.fetch() {
            dining = dining.merged(with: fresh)
            dining.save()
            diningFetchedAt = Date()
        }
    }

    func toast(_ s: String) {
        toastText = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toastText == s { self?.toastText = nil }
        }
    }

    // MARK: 데이터 변경
    func addClaim(item: Item, secret: String, contact: String) {
        claims.insert(Claim(itemID: item.id, title: item.title, hub: item.hub, secret: secret, contact: contact), at: 0)
    }
    func markDone(_ c: Claim) {
        guard let i = claims.firstIndex(where: { $0.id == c.id }) else { return }
        claims[i].done = true
        claimed.insert(c.itemID)
        toast("수령 완료로 표시했어요")
    }
    func addLost(_ r: LostReport) { lost.insert(r, at: 0) }
    func deleteLost(at offsets: IndexSet) { lost.remove(atOffsets: offsets) }
    func addItem(_ i: Item) { mine.insert(i, at: 0) }
}

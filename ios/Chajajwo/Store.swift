import SwiftUI

final class Store: ObservableObject {
    enum Tab: Hashable { case home, dining }
    enum HomeFilter { case all, food, shuttle }

    // 화면 상태
    @Published var tab = Tab.home
    @Published var homeFilter = HomeFilter.all
    @Published var sel = Place.all[0].id
    @Published var open = false
    @Published var toastText: String?
    @Published private(set) var dining = DiningData.startup()
    private var diningFetchedAt = Date.distantPast
    private var diningLoading = false

    // MARK: 지도 시트
    func select(_ id: String) {
        sel = id; open = true
    }
    func closeSheet() { open = false }

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
}

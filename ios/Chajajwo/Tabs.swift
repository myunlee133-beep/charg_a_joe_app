import SwiftUI

// The old local demo registration/claims tabs were replaced by the shared,
// authenticated LostFoundView. Keep the "내 정보" tab intentionally simple.
struct MeView: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        NavigationStack {
            List {
                Section("찾아줘") {
                    Label("서울대 캠퍼스 지도 · 식단 · 분실물 · 사랑방", systemImage: "map")
                    Button { store.tab = .lostFound } label: {
                        Label("내 분실물 신고와 의뢰 관리", systemImage: "shippingbox.fill")
                    }
                    Button { store.tab = .community } label: {
                        Label("사랑방 커뮤니티", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                Section("안내") {
                    Text("분실물·커뮤니티 글은 Supabase 계정으로 등록합니다. 식단과 지도는 로그인하지 않아도 이용할 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("내 정보")
        }
    }
}

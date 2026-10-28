// xcode: set sdk=iOS

import SwiftUI

@main
struct ChajajwoApp: App {
    @StateObject private var store = Store()
    @StateObject private var lostFound = LostFoundAPI()

    init() { KakaoMapView.initSDK() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(lostFound)
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .tint(Color.cjTealText)
                .preferredColorScheme(.light) // 다크모드여도 라이트 화면 그대로
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $store.tab) {
            Group { if store.showDining { DiningView() } else { HomeView() } }.tabItem { Label("홈", systemImage: "house.fill") }.tag(Store.Tab.home)
            LostFoundView().tabItem { Label("분실물", systemImage: "shippingbox.fill") }.tag(Store.Tab.lostFound)
            CommunityView().tabItem { Label("사랑방", systemImage: "bubble.left.and.bubble.right.fill") }.tag(Store.Tab.community)
            MeView().tabItem { Label("내 정보", systemImage: "person.crop.circle") }.tag(Store.Tab.me)
        }
        .overlay(alignment: .bottom) {
            if let t = store.toastText {
                Text(t)
                    .font(.subheadline).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(hex: 0x1b2328).opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.toastText)
        .task { await store.refreshDining() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshDining() } }
        }
    }
}

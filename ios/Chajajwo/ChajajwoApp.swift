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
    @StateObject private var shuttle = CircularShuttleService()
    #if DEBUG
    @State private var previewDirections = false
    #endif

    private var shouldTrackShuttle: Bool {
        scenePhase == .active && store.tab == .home &&
        (store.homeFilter == .all || store.homeFilter == .shuttle)
    }

    var body: some View {
        // Retain visited screens and their sessions without TabView's five-item
        // limit, which otherwise moves the sixth destination into a More screen.
        ZStack {
            RetainedTab(selected: store.tab == .home) {
                if store.showDining { DiningView() } else { HomeView() }
            }
            RetainedTab(selected: store.tab == .dining) { DiningView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                tab(.home, "홈", "house.fill")
                tab(.dining, "식당", "fork.knife")
            }
            .padding(.top, 9).padding(.bottom, 5)
            .background(Color.cjSurface.shadow(color: .black.opacity(0.06), radius: 5, y: -2).ignoresSafeArea(edges: .bottom))
        }
        .environmentObject(shuttle)
        #if DEBUG
        .fullScreenCover(isPresented: $previewDirections) {
            if ProcessInfo.processInfo.arguments.contains("-preview-building-directions") {
                BuildingDirectionsView(origin: CampusBuildingCatalog.search("학생회관").first,
                                       destination: CampusBuildingCatalog.search("중앙도서관").first)
            } else if ProcessInfo.processInfo.arguments.contains("-preview-building-route"),
                      let start = CampusBuildingCatalog.search("학생회관").first,
                      let end = CampusBuildingCatalog.search("중앙도서관").first,
                      let url = DirectionsURL.route(from: start.directionsEndpoint, to: end.directionsEndpoint) {
                DirectionsView(destination: url, name: "학생회관 → 중앙도서관")
            } else if let url = CampusBuildingCatalog.search("학생회관").first?.directionsURL {
                DirectionsView(destination: url, name: "학생회관")
            }
        }
        #endif
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-quests") { store.tab = .quests }
            if ProcessInfo.processInfo.arguments.contains(where: {
                ["-preview-directions", "-preview-building-directions", "-preview-building-route"].contains($0)
            }) { previewDirections = true }
            #endif
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
        .task(id: shouldTrackShuttle) {
            if shouldTrackShuttle { await shuttle.run() }
        }
        .task { await store.refreshDining() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshDining() } }
        }
    }

    private func tab(_ value: Store.Tab, _ title: String, _ icon: String) -> some View {
        Button { store.tab = value } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium))
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(store.tab == value ? Color.cjTeal : Color.cjSub)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(store.tab == value ? .isSelected : [])
        .accessibilityIdentifier("main-tab-\(title)")
    }
}

private struct RetainedTab<Content: View>: View {
    let selected: Bool
    @ViewBuilder var content: () -> Content
    @State private var visited = false

    var body: some View {
        ZStack {
            if selected || visited {
                content()
                    .opacity(selected ? 1 : 0)
                    .allowsHitTesting(selected)
                    .accessibilityHidden(!selected)
                    .disabled(!selected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if selected { visited = true } }
        .onChange(of: selected) { _, value in if value { visited = true } }
    }
}

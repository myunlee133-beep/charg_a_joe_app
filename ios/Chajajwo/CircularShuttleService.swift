import SwiftUI

/// The public endpoint used by the Android app returns schematic coordinates,
/// not GPS. Only route 41946 is requested; no simulated fallback is displayed.
@MainActor final class CircularShuttleService: ObservableObject {
    /// 애니메이션 중 1초에 20번 바뀐다. @Published면 그때마다 ContentView·HomeView 전체가 다시 그려지므로
    /// 지도 핀에만 onPositionsChange로 직접 알린다. 상태 카드는 5초마다 바뀌는 status·queriedAt으로 갱신된다.
    private(set) var positions: [ShuttlePosition] = [] { didSet { onPositionsChange?() } }
    var onPositionsChange: (@MainActor () -> Void)?
    @Published private(set) var status = "실시간 위치 확인 중"
    @Published private(set) var queriedAt: Date?
    @Published private(set) var heldCount = 0
    private let tracker = CircularRoute.load().flatMap { try? CircularShuttleTracker(route: $0) }
    private var generation = UUID()
    private var animation: Task<Void, Never>?

    func run() async {
        let runID = UUID()
        generation = runID
        defer { if generation == runID { stop() } }
        guard let tracker else { status = "노선 정보를 불러오지 못했어요"; return }
        animation?.cancel()
        animation = Task { [weak self] in
            // One render loop survives repeated feed coordinates and slow requests.
            // Only native map POIs are updated; the SwiftUI screen stays untouched.
            while !Task.isCancelled {
                guard let self, self.generation == runID else { return }
                self.positions = tracker.positions(at: ProcessInfo.processInfo.systemUptime)
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
        while !Task.isCancelled && generation == runID {
            let requestStarted = ProcessInfo.processInfo.systemUptime
            do {
                var request = URLRequest(url: URL(string: "https://chajajwo-web-mu.vercel.app/api/shuttle?route=41946")!)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 7
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard generation == runID else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let feed = try JSONDecoder().decode(CircularFeed.self, from: data)
                guard feed.validated(at: Date()) else { throw URLError(.cannotParseResponse) }
                tracker.update(feed.vehicles, at: ProcessInfo.processInfo.systemUptime)
                queriedAt = feed.queryDate
                heldCount = tracker.heldCount
                positions = tracker.positions(at: ProcessInfo.processInfo.systemUptime)
                status = feed.vehicles.isEmpty ? "제공된 차량 위치가 없어요" : (positions.isEmpty ? "위치 신뢰도 확인 중" : "교내순환 · 실시간 기반 추정 위치")
            } catch {
                guard !Task.isCancelled, generation == runID else { return }
                tracker.clear(); positions = []; heldCount = 0
                status = "실시간 위치를 불러오지 못했어요"
            }
            let delay = max(0, Self.pollInterval - (ProcessInfo.processInfo.systemUptime - requestStarted))
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
    }

    private static let pollInterval = 5.0

    func stop() {
        generation = UUID()
        animation?.cancel(); animation = nil
        tracker?.clear(); positions = []; heldCount = 0
    }
}

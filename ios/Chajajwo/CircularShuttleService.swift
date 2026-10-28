import SwiftUI

/// The public endpoint used by the Android app returns schematic coordinates,
/// not GPS. Only route 41946 is requested; no simulated fallback is displayed.
@MainActor final class CircularShuttleService: ObservableObject {
    @Published private(set) var positions: [ShuttlePosition] = []
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
        while !Task.isCancelled && generation == runID {
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
                animation?.cancel()
                animation = Task { [weak self] in
                    // Ease between received points, then stop. Never predict onward.
                    for _ in 0..<25 {
                        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                        guard let self, self.generation == runID, !Task.isCancelled else { return }
                        self.positions = tracker.positions(at: ProcessInfo.processInfo.systemUptime)
                    }
                }
            } catch {
                guard !Task.isCancelled, generation == runID else { return }
                animation?.cancel()
                tracker.clear(); positions = []; heldCount = 0
                status = "실시간 위치를 불러오지 못했어요"
            }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    func stop() {
        generation = UUID()
        animation?.cancel(); animation = nil
        tracker?.clear(); positions = []; heldCount = 0
    }
}

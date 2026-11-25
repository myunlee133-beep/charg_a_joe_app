import SwiftUI
import ARKit
import RealityKit
import Combine

/// 수집한 랜드마크 id. 기기에만 저장한다(서버 동기화 없음).
@MainActor final class LandmarkCollection: ObservableObject {
    private static let key = "collectedLandmarks"
    @Published private(set) var ids: Set<String>

    init() { ids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? []) }

    func collect(_ landmark: Landmark) {
        guard ids.insert(landmark.id).inserted else { return }
        UserDefaults.standard.set(Array(ids), forKey: Self.key)
    }
}

/// 카메라 앞 1m에 떠서 도는 금색 배지. 탭하면 수집.
/// AR을 못 쓰는 기기(시뮬레이터 포함)는 버튼으로 수집한다.
struct LandmarkARView: View {
    let landmark: Landmark
    let onCollect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var collected = false

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                ARBadgeView(landmark: landmark, onTap: collect).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                Button(action: collect) {
                    Image(systemName: landmark.symbol)
                        .font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 160, height: 160)
                        .background(Color.cjTeal.gradient, in: Circle())
                }
                .accessibilityLabel("\(landmark.name) 수집하기")
            }

            VStack {
                HStack {
                    Text(collected ? "획득!" : "배지를 찾아 탭하세요")
                        .font(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("닫기")
                }
                Spacer()
                if collected {
                    VStack(spacing: 6) {
                        Label(landmark.name, systemImage: landmark.symbol).font(.title2.weight(.heavy))
                        Text(landmark.blurb).font(.subheadline).multilineTextAlignment(.center)
                    }
                    .padding(20).frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(16)
        }
    }

    private func collect() {
        guard !collected else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCollect()
        withAnimation(.spring) { collected = true }
        Task { try? await Task.sleep(for: .seconds(2.5)); dismiss() }
    }
}

private struct ARBadgeView: UIViewRepresentable {
    let landmark: Landmark
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session.run(ARWorldTrackingConfiguration())

        // 금색 동전(둥근 상자) + 이름. 세션 시작 위치 기준 정면 1m, 눈높이 약간 아래.
        let coin = ModelEntity(mesh: .generateBox(width: 0.3, height: 0.3, depth: 0.03, cornerRadius: 0.15),
                               materials: [SimpleMaterial(color: .systemYellow, roughness: 0.2, isMetallic: true)])
        let label = ModelEntity(mesh: .generateText(landmark.name, extrusionDepth: 0.01, font: .boldSystemFont(ofSize: 0.06),
                                                    alignment: .center),
                                materials: [SimpleMaterial(color: .white, isMetallic: false)])
        let bounds = label.visualBounds(relativeTo: nil)
        label.position = [-bounds.center.x, -0.28, 0]
        coin.generateCollisionShapes(recursive: false)

        let anchor = AnchorEntity(world: [0, -0.1, -1])
        anchor.addChild(coin); anchor.addChild(label)
        view.scene.addAnchor(anchor)

        context.coordinator.spin = view.scene.subscribe(to: SceneEvents.Update.self) { event in
            coin.orientation *= simd_quatf(angle: Float(event.deltaTime) * 1.5, axis: [0, 1, 0])
        }
        context.coordinator.coin = coin
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.spin?.cancel()
        uiView.session.pause()
    }

    final class Coordinator: NSObject {
        let onTap: () -> Void
        var spin: Cancellable?
        weak var coin: ModelEntity?
        init(onTap: @escaping () -> Void) { self.onTap = onTap }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? ARView, let coin,
                  view.entity(at: gesture.location(in: view)) === coin else { return }
            coin.removeFromParent()
            onTap()
        }
    }
}

/// 도감: 다섯 곳 중 몇 곳을 모았는지와 남은 거리.
struct LandmarkDexView: View {
    @ObservedObject var collection: LandmarkCollection
    let here: CampusCoordinate?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Landmark.all) { landmark in
                let done = collection.ids.contains(landmark.id)
                HStack(spacing: 12) {
                    Image(systemName: landmark.symbol)
                        .font(.title3).foregroundStyle(done ? .white : Color.cjSub)
                        .frame(width: 44, height: 44)
                        .background(done ? AnyShapeStyle(Color.cjTeal.gradient) : AnyShapeStyle(Color.cjSub.opacity(0.15)), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(landmark.name).font(.headline).foregroundStyle(done ? Color.primary : Color.cjSub)
                        Text(done ? landmark.blurb : hint(for: landmark)).font(.caption).foregroundStyle(Color.cjSub)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .navigationTitle("랜드마크 도감 \(collection.ids.count)/\(Landmark.all.count)")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
    }

    private func hint(for landmark: Landmark) -> String {
        guard let here else { return "\(landmark.name) 근처에 가면 AR로 잡을 수 있어요" }
        let meters = Int(landmark.coordinate.distance(to: here))
        return "\(landmark.name)까지 약 \(meters >= 1000 ? String(format: "%.1fkm", Double(meters) / 1000) : "\(meters)m")"
    }
}

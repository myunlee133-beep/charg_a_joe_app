import SwiftUI
import ARKit
import RealityKit
import AudioToolbox
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

/// 카메라 앞 1m에 떠서 도는 금테·청록 메달. 탭하면 파티클·사운드와 함께 수집.
/// AR을 못 쓰는 기기(시뮬레이터 포함)는 동일한 메달 버튼으로 수집한다.
struct LandmarkARView: View {
    let landmark: Landmark
    let onCollect: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var collected = false
    @State private var pulse = false
    @State private var burstProgress: CGFloat = 0
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                ARBadgeView(landmark: landmark, onTap: collect).ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.16, blue: 0.15), .black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                Button(action: collect) {
                    MedallionFallbackView(symbol: landmark.symbol, pulse: pulse)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(landmark.name) 수집하기")
            }

            // 상하단 가독성을 위한 부드러운 비네트
            VStack {
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 중앙 조준 브래킷 & 플로팅 이름 태그
            if !collected {
                VStack(spacing: 24) {
                    ARReticleBrackets(pulse: pulse)
                        .frame(width: 220, height: 220)
                        .allowsHitTesting(false)

                    VStack(spacing: 3) {
                        Text(landmark.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("탭하여 수집")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cjTeal)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    )
                    .allowsHitTesting(false)
                }
                .offset(y: 28)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // 수집 순간 파티클 & 확장 링 연출
            if collected {
                CollectBurstView(progress: burstProgress)
                    .allowsHitTesting(false)
            }

            // 상단 HUD & 하단 가이드/획득 카드
            VStack {
                topHUD
                Spacer()
                if collected {
                    collectedCard
                } else {
                    Text("주변을 둘러보며 빛나는 배지를 찾아 탭하세요")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                }
            }
            .padding(16)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear { dismissTask?.cancel() }
    }

    private var topHUD: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                if collected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                    Text("\(landmark.name) 배지를 획득했어요!")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .fill(Color.cjTeal)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulse ? 1.4 : 0.9)
                    Text("\(landmark.name) · 배지를 탭하세요")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                collected ? AnyShapeStyle(Color(red: 0.06, green: 0.73, blue: 0.51)) : AnyShapeStyle(.black.opacity(0.6)),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.6), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
            .accessibilityLabel("닫기")
        }
    }

    private var collectedCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.06, green: 0.73, blue: 0.51).gradient)
                    .frame(width: 60, height: 60)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                Image(systemName: landmark.symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .offset(y: -42)
            .padding(.bottom, -42)

            Text("NEW · 랜드마크 획득")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.02, green: 0.37, blue: 0.27))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(red: 0.82, green: 0.98, blue: 0.90), in: Capsule())

            VStack(spacing: 6) {
                Text(landmark.name)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.primary)
                Text(landmark.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                dismissTask?.cancel()
                dismiss()
            } label: {
                Text("도감에서 확인하기")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.cjTeal.gradient, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.cjTeal.opacity(0.45), lineWidth: 1.5)
        )
        .padding(.top, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func collect() {
        guard !collected else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1057) // 경쾌한 시스템 차임벨
        onCollect()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            collected = true
        }
        withAnimation(.easeOut(duration: 0.85)) {
            burstProgress = 1
        }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3.0))
            if !Task.isCancelled { dismiss() }
        }
    }
}

/// AR 미지원 기기/시뮬레이터용 메달 버튼
private struct MedallionFallbackView: View {
    let symbol: String
    let pulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cjTeal.opacity(0.22))
                .frame(width: 210, height: 210)
                .scaleEffect(pulse ? 1.08 : 0.94)
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.99, green: 0.90, blue: 0.54), Color(red: 0.96, green: 0.62, blue: 0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 164, height: 164)
                .shadow(color: Color.cjTeal.opacity(0.5), radius: 20)
            Circle()
                .fill(Color.cjTeal.gradient)
                .frame(width: 136, height: 136)
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 2))
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// 화면 중앙 AR 조준 코너 브래킷
private struct ARReticleBrackets: View {
    let pulse: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let len: CGFloat = 24
            Path { path in
                // 좌상단
                path.move(to: CGPoint(x: 0, y: len))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: len, y: 0))
                // 우상단
                path.move(to: CGPoint(x: w - len, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: len))
                // 좌하단
                path.move(to: CGPoint(x: 0, y: h - len))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: len, y: h))
                // 우하단
                path.move(to: CGPoint(x: w - len, y: h))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w, y: h - len))
            }
            .stroke(Color.cjTeal.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .scaleEffect(pulse ? 1.04 : 0.97)
    }
}

/// 수집 순간 퍼지는 금빛·청록 파티클과 확장 링
private struct CollectBurstView: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.99, green: 0.90, blue: 0.54).opacity(1.0 - progress), lineWidth: 4)
                .frame(width: 80 + 260 * progress, height: 80 + 260 * progress)

            ForEach(0..<16, id: \.self) { idx in
                let angle = Double(idx) / 16.0 * .pi * 2
                let radius = (idx % 2 == 0 ? 150.0 : 105.0) * progress
                Circle()
                    .fill(idx % 2 == 0 ? Color(red: 0.99, green: 0.90, blue: 0.54) : Color.cjTeal)
                    .frame(width: idx % 2 == 0 ? 10 : 7, height: idx % 2 == 0 ? 10 : 7)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                    .opacity(1.0 - progress)
            }
        }
    }
}

private struct ARBadgeView: UIViewRepresentable {
    let landmark: Landmark
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session.run(ARWorldTrackingConfiguration())

        // 어두운 실내에서도 시커멓지 않게 비추는 전용 포인트 라이트 + 금테·청록 메달
        let goldMat = SimpleMaterial(color: UIColor(red: 0.96, green: 0.68, blue: 0.12, alpha: 1), roughness: 0.25, isMetallic: false)
        let tealMat = SimpleMaterial(color: UIColor(red: 0.05, green: 0.58, blue: 0.53, alpha: 1), roughness: 0.2, isMetallic: false)

        // generateCylinder는 iOS 18부터라(배포 타깃 17) 구를 납작하게 눌러 동전 모양을 만든다.
        let rim = ModelEntity(mesh: .generateSphere(radius: 0.17), materials: [goldMat])
        rim.scale = [1, 0.075, 1]   // 두께 약 2.5cm
        let core = ModelEntity(mesh: .generateSphere(radius: 0.132), materials: [tealMat])
        core.scale = [1, 0.12, 1]   // 금테보다 살짝 도톰하게 튀어나오도록

        let coin = ModelEntity()
        coin.addChild(rim)
        coin.addChild(core)
        // 원기둥이 카메라를 정면으로 바라보도록 X축 기준 90도 회전
        coin.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        coin.generateCollisionShapes(recursive: true)

        let light = PointLight()
        light.light.intensity = 1500
        light.light.attenuationRadius = 2.0
        light.position = [0, 0.25, 0.5]

        let anchor = AnchorEntity(world: [0, -0.05, -1])
        anchor.addChild(coin)
        anchor.addChild(light)
        view.scene.addAnchor(anchor)

        context.coordinator.spin = view.scene.subscribe(to: SceneEvents.Update.self) { event in
            coin.orientation = simd_quatf(angle: Float(event.deltaTime) * 1.6, axis: [0, 1, 0]) * coin.orientation
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
                  let hit = view.entity(at: gesture.location(in: view)),
                  hit === coin || hit.parent === coin else { return }
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
    @State private var activeAR: Landmark?

    private var collectedCount: Int { collection.ids.count }
    private var totalCount: Int { Landmark.all.count }
    private var progressRatio: Double {
        totalCount > 0 ? Double(collectedCount) / Double(totalCount) : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    progressHeaderCard

                    LazyVStack(spacing: 12) {
                        ForEach(Landmark.all) { landmark in
                            landmarkCard(for: landmark)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .fullScreenCover(item: $activeAR) { landmark in
                LandmarkARView(landmark: landmark) { collection.collect(landmark) }
            }
            .navigationTitle("랜드마크 도감")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("닫기")
                }
            }
        }
    }

    private var progressHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("관악 캠퍼스 명소를 찾아 AR 배지를 모아보세요")
                .font(.subheadline)
                .foregroundStyle(Color.cjSub)

            VStack(spacing: 8) {
                HStack {
                    Text("수집 진행도")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.cjTeal)
                    Spacer()
                    Text("\(collectedCount) / \(totalCount) (\(Int(progressRatio * 100))%)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.cjTeal)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.cjTeal.opacity(0.16))
                        Capsule()
                            .fill(Color.cjTeal.gradient)
                            .frame(width: max(progressRatio > 0 ? 12 : 0, geo.size.width * progressRatio))
                            .animation(.spring(response: 0.5), value: progressRatio)
                    }
                }
                .frame(height: 10)
            }
            .padding(14)
            .background(Color.cjTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.cjTeal.opacity(0.22), lineWidth: 1)
            )
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func landmarkCard(for landmark: Landmark) -> some View {
        let done = collection.ids.contains(landmark.id)
        let nearby = isNearby(landmark)
        let emerald = Color(red: 0.06, green: 0.73, blue: 0.51)

        HStack(spacing: 14) {
            Image(systemName: landmark.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(done || nearby ? .white : Color.cjSub)
                .frame(width: 52, height: 52)
                .background(
                    done ? AnyShapeStyle(emerald.gradient) :
                    (nearby ? AnyShapeStyle(Color.cjTeal.gradient) : AnyShapeStyle(Color.cjSub.opacity(0.15))),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(landmark.name)
                    .font(.headline)
                    .foregroundStyle(done || nearby ? Color.primary : Color.cjSub)
                Text(done ? landmark.blurb : hint(for: landmark, nearby: nearby))
                    .font(.caption)
                    .foregroundStyle(nearby && !done ? Color.cjTeal : Color.cjSub)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if done {
                Label("수집 완료", systemImage: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.02, green: 0.37, blue: 0.27))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.82, green: 0.98, blue: 0.90), in: Capsule())
            } else if nearby {
                Button { activeAR = landmark } label: {
                    Text("AR 찾기 →")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.cjTeal.gradient, in: Capsule())
                }
            } else {
                #if DEBUG
                Button { activeAR = landmark } label: {
                    Text("AR 테스트")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cjTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cjTeal.opacity(0.12), in: Capsule())
                }
                #else
                Text("미수집")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.cjSub)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cjSub.opacity(0.12), in: Capsule())
                #endif
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    done ? emerald.opacity(0.45) : (nearby ? Color.cjTeal.opacity(0.6) : Color.primary.opacity(0.06)),
                    lineWidth: (done || nearby) ? 1.5 : 1
                )
        )
        .accessibilityElement(children: .combine)
    }

    private func isNearby(_ landmark: Landmark) -> Bool {
        guard let here, here.isValid else { return false }
        return landmark.coordinate.distance(to: here) <= Landmark.collectRadius
    }

    private func hint(for landmark: Landmark, nearby: Bool) -> String {
        guard let here, here.isValid else { return "\(landmark.name) 근처에 가면 AR로 잡을 수 있어요" }
        let meters = Int(landmark.coordinate.distance(to: here))
        if nearby {
            return "현재 \(meters)m 앞 · AR 수집 가능!"
        }
        return "\(landmark.name)까지 약 \(meters >= 1000 ? String(format: "%.1fkm", Double(meters) / 1000) : "\(meters)m")"
    }
}

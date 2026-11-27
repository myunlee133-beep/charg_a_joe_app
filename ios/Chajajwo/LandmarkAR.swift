import SwiftUI
import ARKit
import RealityKit
import AudioToolbox
import Combine

/// 발견한 보물 id. 기기에만 저장한다(서버 동기화 없음).
@MainActor final class LandmarkCollection: ObservableObject {
    private static let key = "collectedLandmarks"
    @Published private(set) var ids: Set<String>

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset-treasures") { UserDefaults.standard.removeObject(forKey: Self.key) }
        #endif
        ids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func collect(_ landmark: Landmark) {
        guard ids.insert(landmark.id).inserted else { return }
        UserDefaults.standard.set(Array(ids), forKey: Self.key)
    }
}

extension TreasureGrade {
    var color: Color {
        switch self {
        case .common: Color(hex: 0x7c838c)
        case .rare: Color(hex: 0x2f6fe4)
        case .legendary: Color(hex: 0xb8860b)
        }
    }
}

/// 보물 일러스트. 미발견이면 회색 실루엣 + "?". `size`가 없으면 주어진 칸을 채운다.
struct TreasureIcon: View {
    let treasure: Landmark
    var size: CGFloat?
    var locked = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Image(locked ? "\(treasure.art)-locked" : treasure.art).resizable().scaledToFit()
                if locked {
                    Text("?").font(.system(size: side * 0.32, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// AR 보물 찾기 화면.
/// 1. 근처: "보물이 근처에 있어요" + 단서. 단서 속 대상(AR Resource Group `TreasureTargets`의 사진)을 찾는다.
/// 2. 대상을 정확히 비추면: "보물 발견!" + 대상 위에 보물상자. 상자 탭이나 "보물 열기"로 연다.
/// 3. 열면: 상자에서 보물이 튀어나오고 도감에 등록된다.
struct LandmarkARView: View {
    let landmark: Landmark
    @ObservedObject var collection: LandmarkCollection
    @Environment(\.dismiss) private var dismiss
    @AppStorage("arSoundOn") private var soundOn = true

    enum Phase { case searching, found, opened }
    @State private var phase: Phase = .searching
    @State private var pulse = false

    private static let forest = Color(hex: 0x24502f)
    private static let cream = Color(hex: 0xfbf6e4)
    private static let coral = Color(hex: 0xe9634a)
    private static let gold = Color(hex: 0xf6c744)

    /// 대상 사진이 등록돼 있고 AR을 쓸 수 있을 때만 이미지 인식을 한다.
    private var referenceImage: ARReferenceImage? {
        guard ARWorldTrackingConfiguration.isSupported else { return nil }
        return ARReferenceImage.referenceImages(inGroupNamed: "TreasureTargets", bundle: nil)?
            .first { $0.name == landmark.targetImage }
    }

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                ARTreasureView(target: referenceImage, opened: phase == .opened,
                               onFound: markFound, onTapChest: open)
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(hex: 0x9cc78a), Color(hex: 0x4f7d4a)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if phase == .found {
                    Button(action: open) {
                        Image("ARChest").resizable().scaledToFit().frame(width: 190)
                            .shadow(color: Self.gold.opacity(0.9), radius: pulse ? 26 : 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("보물상자 열기")
                }
            }

            if phase != .opened { reticle }

            VStack(spacing: 14) {
                topBar
                titleBadge
                clueCapsule
                Spacer()
                HStack {
                    Image("ARFox").resizable().scaledToFit().frame(width: 118)
                        .rotationEffect(.degrees(pulse ? -4 : 3), anchor: .bottom)
                        .accessibilityHidden(true)
                    Spacer()
                }
                openButton
                Label(phase == .found ? "상자를 탭해도 열 수 있어요" : "단서 속 대상을 화면에 비춰보세요", systemImage: "eye")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4)
            }
            .font(.headline.weight(.heavy))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .opacity(phase == .opened ? 0 : 1)

            if phase == .opened {
                TreasureRevealView(treasure: landmark) { dismiss() }
                    .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            // ponytail: 대상 사진이 아직 없는 보물은 반경 안에 온 것만으로 발견 처리. 사진을 등록하면 자동으로 인식 모드가 된다.
            if referenceImage == nil { markFound() }
        }
    }

    private var reticle: some View {
        let found = phase == .found
        return ZStack {
            Ellipse()
                .stroke(found ? Self.gold : Self.cream.opacity(0.6), lineWidth: 3)
                .frame(width: 230, height: 46)
                .shadow(color: Self.gold, radius: found ? 8 : 0)
                .offset(y: 78)
                .opacity(pulse ? 1 : 0.55)
            ARReticleBrackets(color: found ? Self.gold : Self.cream)
                .frame(width: 250, height: 250)
                .scaleEffect(pulse ? 1.03 : 0.98)
            Image(systemName: found ? "mappin.circle.fill" : "magnifyingglass.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white, found ? Self.coral : Self.forest)
                .offset(y: -150 + (pulse ? -4 : 0))
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            circleButton("arrow.left", label: "뒤로") { dismiss() }
            Spacer()
            circleButton(soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         label: soundOn ? "효과음 끄기" : "효과음 켜기") { soundOn.toggle() }
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(Self.forest)
                .frame(width: 52, height: 52)
                .background(Self.cream, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .accessibilityLabel(label)
    }

    private var titleBadge: some View {
        let found = phase == .found
        return Text(found ? "보물 발견!" : "보물이 근처에 있어요")
            .font(.system(size: found ? 44 : 30, weight: .black, design: .rounded))
            .foregroundStyle(Self.forest)
            .padding(.horizontal, found ? 38 : 28)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .background(Self.cream, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(alignment: .leading) { leaf.scaleEffect(x: -1).offset(x: -18) }
            .overlay(alignment: .trailing) { leaf.offset(x: 18) }
            .overlay(alignment: .top) {
                ZStack(alignment: .bottom) {
                    Image(systemName: "mountain.2.fill").font(.title2).foregroundStyle(Color(hex: 0x6fae5a))
                    Image(systemName: "mappin.circle.fill").font(.title2)
                        .foregroundStyle(.white, Self.coral).offset(y: -12)
                }
                .offset(y: -22)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .padding(.top, 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: found)
            .accessibilityAddTraits(.isHeader)
    }

    private var leaf: some View {
        Image(systemName: "leaf.fill")
            .font(.title)
            .foregroundStyle(Color(hex: 0x4f8f3c))
            .rotationEffect(.degrees(35))
    }

    private var clueCapsule: some View {
        (Text("단서  ").foregroundStyle(Self.gold) + Text(landmark.clue).foregroundStyle(Self.cream))
            .font(.system(size: 16, weight: .bold))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .frame(maxWidth: 320)
            .background(Self.forest, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Self.cream, lineWidth: 2.5))
            .accessibilityLabel("단서: \(landmark.clue)")
    }

    private var openButton: some View {
        let enabled = phase == .found
        return Button(action: open) {
            Label(enabled ? "보물 열기" : "대상을 찾는 중…", systemImage: enabled ? "shippingbox.fill" : "viewfinder")
                .font(.system(size: enabled ? 30 : 24, weight: .black, design: .rounded))
                .foregroundStyle(Self.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(enabled ? AnyShapeStyle(Self.coral.gradient) : AnyShapeStyle(Color.gray.opacity(0.75)), in: Capsule())
                .overlay(Capsule().strokeBorder(Self.cream, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func markFound() {
        guard phase == .searching else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        if soundOn { AudioServicesPlaySystemSound(1113) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { phase = .found }
    }

    private func open() {
        guard phase == .found else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if soundOn { AudioServicesPlaySystemSound(1057) }
        collection.collect(landmark)
        withAnimation(.easeOut(duration: 0.3)) { phase = .opened }
    }
}

/// 보물 열기 연출: 상자가 흔들리다 빛과 함께 열리고, 보물이 튀어나와 도감 카드가 된다.
private struct TreasureRevealView: View {
    let treasure: Landmark
    let onDone: () -> Void

    @State private var shake = false
    @State private var burst = false
    @State private var showItem = false
    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            // 뒤에서 도는 빛줄기
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(treasure.grade.color.opacity(0.35))
                    .frame(width: 14, height: 300)
                    .rotationEffect(.degrees(Double(i) * 15 + (spin ? 30 : 0)))
            }
            .scaleEffect(burst ? 1 : 0.1)
            .opacity(burst ? 1 : 0)

            Circle()
                .fill(RadialGradient(colors: [.white, treasure.grade.color.opacity(0)], center: .center, startRadius: 0, endRadius: 160))
                .frame(width: 320, height: 320)
                .opacity(burst && !showItem ? 1 : (showItem ? 0.5 : 0))

            if !showItem {
                Image("ARChest").resizable().scaledToFit().frame(width: 200)
                    .rotationEffect(.degrees(shake ? 7 : -7))
                    .scaleEffect(burst ? 1.25 : 1)
                    .opacity(burst ? 0 : 1)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 14) {
                Spacer()
                TreasureIcon(treasure: treasure, size: 220)
                    .shadow(color: .white.opacity(0.6), radius: 18)
                    .scaleEffect(showItem ? 1 : 0.2)
                    .offset(y: showItem ? 0 : 60)
                Text(treasure.grade.rawValue)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(treasure.grade.color, in: Capsule())
                Text(treasure.name)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(treasure.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Label("보물 도감에 등록됐어요", systemImage: "book.closed.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(hex: 0xf6c744))
                Button(action: onDone) {
                    Text("확인")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color(hex: 0xfbf6e4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: 0xe9634a).gradient, in: Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .opacity(showItem ? 1 : 0)
        }
        .task {
            withAnimation(.easeInOut(duration: 0.08).repeatCount(9, autoreverses: true)) { shake = true }
            try? await Task.sleep(for: .seconds(0.75))
            withAnimation(.easeOut(duration: 0.45)) { burst = true }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spin = true }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { showItem = true }
        }
    }
}

/// 화면 중앙 조준 코너 브래킷
private struct ARReticleBrackets: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, len: CGFloat = 34
            Path { p in
                p.move(to: .init(x: 0, y: len)); p.addLine(to: .zero); p.addLine(to: .init(x: len, y: 0))
                p.move(to: .init(x: w - len, y: 0)); p.addLine(to: .init(x: w, y: 0)); p.addLine(to: .init(x: w, y: len))
                p.move(to: .init(x: 0, y: h - len)); p.addLine(to: .init(x: 0, y: h)); p.addLine(to: .init(x: len, y: h))
                p.move(to: .init(x: w - len, y: h)); p.addLine(to: .init(x: w, y: h)); p.addLine(to: .init(x: w, y: h - len))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.25), radius: 3)
        }
    }
}

/// 대상 사진(`target`)이 화면에 잡히면 그 위에 보물상자를 띄우고 `onFound`를 부른다.
/// 대상 사진이 없으면 카메라 앞 1m에 상자를 띄운다.
private struct ARTreasureView: UIViewRepresentable {
    let target: ARReferenceImage?
    let opened: Bool
    let onFound: () -> Void
    let onTapChest: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound, onTap: onTapChest) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        let config = ARWorldTrackingConfiguration()
        if let target {
            config.detectionImages = [target]
            config.maximumNumberOfTrackedImages = 1
        }
        view.session.delegate = context.coordinator
        view.session.run(config)
        context.coordinator.view = view

        let chest = Self.makeChest()
        context.coordinator.chest = chest
        if target == nil {
            let anchor = AnchorEntity(world: [0, 0, -1])
            anchor.addChild(chest)
            view.scene.addAnchor(anchor)
        }

        var time: Float = 0
        context.coordinator.update = view.scene.subscribe(to: SceneEvents.Update.self) { [weak view, weak chest] event in
            guard let view, let chest, chest.parent != nil else { return }
            time += Float(event.deltaTime)
            chest.position.y = (target == nil ? 0 : 0.18) + sin(time * 2) * 0.02
            // 판의 앞면(+Z)이 카메라를 향하도록 돌린다.
            let dir = view.cameraTransform.translation - chest.position(relativeTo: nil)
            chest.look(at: chest.position(relativeTo: nil) - dir, from: chest.position(relativeTo: nil), relativeTo: nil)
        }
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return view
    }

    /// 보물상자 그림을 붙인 약 36cm 폭의 판
    private static func makeChest() -> ModelEntity {
        let chest: ModelEntity
        if let cg = UIImage(named: "ARChest")?.cgImage,
           let texture = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
            var mat = UnlitMaterial()
            mat.color = .init(tint: .white, texture: .init(texture))
            mat.blending = .transparent(opacity: 1.0)
            chest = ModelEntity(mesh: .generatePlane(width: 0.36, height: 0.30), materials: [mat])
        } else {
            chest = ModelEntity(mesh: .generateBox(size: 0.25),
                                materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)])
        }
        chest.generateCollisionShapes(recursive: false)
        return chest
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if opened { context.coordinator.chest?.removeFromParent() }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.update?.cancel()
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let onFound: () -> Void
        let onTap: () -> Void
        var update: Cancellable?
        weak var view: ARView?
        var chest: ModelEntity?
        private var placed = false
        init(onFound: @escaping () -> Void, onTap: @escaping () -> Void) { self.onFound = onFound; self.onTap = onTap }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let imageAnchor = anchors.compactMap({ $0 as? ARImageAnchor }).first else { return }
            DispatchQueue.main.async { [self] in
                guard !placed, let view, let chest else { return }
                placed = true
                let anchor = AnchorEntity(anchor: imageAnchor)
                anchor.addChild(chest)
                view.scene.addAnchor(anchor)
                onFound()
            }
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? ARView, let chest, chest.parent != nil,
                  view.entity(at: gesture.location(in: view)) === chest else { return }
            onTap()
        }
    }
}

/// 보물 도감 (design-drafts/ar 도감.png): 발견한 보물은 일러스트, 미발견은 실루엣·단서.
struct LandmarkDexView: View {
    @ObservedObject var collection: LandmarkCollection
    let here: CampusCoordinate?
    @Environment(\.dismiss) private var dismiss
    @State private var filter: TreasureGrade?
    @State private var selected: Landmark?

    static let green = Color(hex: 0x1f6b3d)
    static let ink = Color(hex: 0x1d2229)
    static let gray = Color(hex: 0x6f7680)
    static let page = Color(hex: 0xf2f5f7)

    private var shown: [Landmark] {
        Landmark.all.filter { filter == nil || $0.grade == filter }
            .sorted { collection.ids.contains($0.id) && !collection.ids.contains($1.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            progressHeader
            tabs
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3), spacing: 18) {
                    ForEach(shown) { treasure in
                        Button { selected = treasure } label: { card(treasure) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                Text("미발견 보물을 눌러 단서를 확인하세요")
                    .font(.system(size: 14))
                    .foregroundStyle(Self.gray)
                    .padding(.vertical, 24)
            }
            .background(Self.page)
        }
        .background(Color.white)
        .sheet(item: $selected) { treasure in
            TreasureDetailSheet(treasure: treasure, collection: collection, here: here)
                .presentationDetents([.medium, .large])
        }
    }

    private var navBar: some View {
        ZStack {
            Text("보물 도감").font(.system(size: 22, weight: .bold)).foregroundStyle(Self.ink)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 22, weight: .medium)).foregroundStyle(Self.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("닫기")
                Spacer()
                Text("서울대").font(.system(size: 17)).foregroundStyle(Self.gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xe6e9ec)).frame(height: 1).padding(.horizontal, 12) }
    }

    private var progressHeader: some View {
        let count = collection.ids.count, total = Landmark.all.count
        let ratio = total > 0 ? CGFloat(count) / CGFloat(total) : 0
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("발견한 보물").font(.system(size: 20, weight: .semibold)).foregroundStyle(Self.ink)
                Spacer()
                Text("\(count) / \(total)").font(.system(size: 24, weight: .bold)).foregroundStyle(Self.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xe3e6e9))
                    Capsule().fill(Self.green).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("발견한 보물 \(total)개 중 \(count)개")
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach([nil] + TreasureGrade.allCases.map(Optional.some), id: \.self) { grade in
                let on = filter == grade
                Button { withAnimation(.snappy) { filter = grade } } label: {
                    VStack(spacing: 12) {
                        Text(grade?.rawValue ?? "전체")
                            .font(.system(size: 19, weight: on ? .bold : .medium))
                            .foregroundStyle(on ? Self.green : Self.gray)
                        Rectangle().fill(on ? Self.green : .clear).frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xe6e9ec)).frame(height: 1) }
    }

    private func card(_ treasure: Landmark) -> some View {
        let done = collection.ids.contains(treasure.id)
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
                .aspectRatio(1, contentMode: .fit)
                .overlay { TreasureIcon(treasure: treasure, locked: !done).padding(done ? 12 : 22) }
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                .padding(.bottom, 8)
            Text(done ? treasure.name : "미발견")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Self.ink)
                .lineLimit(1)
            if !done {
                Text(treasure.hint).font(.system(size: 14)).foregroundStyle(Self.gray).lineLimit(1)
            }
            Text(treasure.grade.rawValue)
                .font(.system(size: 15, weight: treasure.grade == .common ? .regular : .semibold))
                .foregroundStyle(treasure.grade.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done ? "\(treasure.name), \(treasure.grade.rawValue)" : "미발견 \(treasure.grade.rawValue) 보물, 단서 \(treasure.hint)")
    }
}

/// 도감 칸을 누르면 뜨는 상세. 미발견이면 단서와 거리만 보여준다.
private struct TreasureDetailSheet: View {
    let treasure: Landmark
    @ObservedObject var collection: LandmarkCollection
    let here: CampusCoordinate?
    @State private var showAR = false

    var body: some View {
        let done = collection.ids.contains(treasure.id)
        VStack(spacing: 12) {
            TreasureIcon(treasure: treasure, size: 140, locked: !done)
                .padding(.top, 28)
            Text(done ? treasure.name : "미발견 보물")
                .font(.system(size: 24, weight: .bold)).foregroundStyle(LandmarkDexView.ink)
            Text(treasure.grade.rawValue)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(treasure.grade.color)
            if done {
                Label(treasure.place, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 15)).foregroundStyle(LandmarkDexView.gray)
                Text(treasure.blurb).font(.system(size: 16)).foregroundStyle(LandmarkDexView.ink)
                    .multilineTextAlignment(.center).padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("단서", systemImage: "lightbulb.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(LandmarkDexView.green)
                    Text(treasure.clue).font(.system(size: 16)).foregroundStyle(LandmarkDexView.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(LandmarkDexView.page, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(distanceText).font(.system(size: 15, weight: .semibold)).foregroundStyle(LandmarkDexView.green)
            }
            #if DEBUG
            Button("AR 테스트") { showAR = true }.font(.system(size: 14, weight: .semibold)).padding(.top, 4)
            #endif
            Spacer()
        }
        .padding(.horizontal, 24)
        .fullScreenCover(isPresented: $showAR) { LandmarkARView(landmark: treasure, collection: collection) }
    }

    private var distanceText: String {
        guard let here, here.isValid else { return "가까이 가면 지도에 여우가 나타나요" }
        let meters = Int(treasure.coordinate.distance(to: here))
        if Double(meters) <= Landmark.collectRadius { return "근처예요! 지도에서 여우를 찾아 눌러보세요" }
        return meters >= 1000 ? String(format: "약 %.1fkm 떨어져 있어요", Double(meters) / 1000) : "약 \(meters)m 떨어져 있어요"
    }
}

import SwiftUI

struct PlaceIcon: View {
    let type: PlaceType
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(type.color, in: Circle())
    }
}

enum BtnStyle { case orangeFill, orangeLine, tealFill, tealLine }

struct BigLabel: View {
    let text: String
    let style: BtnStyle
    private var fg: Color {
        switch style {
        case .orangeFill: .cjOrangeText
        case .orangeLine: .cjOrangeText
        case .tealFill: .white
        case .tealLine: .cjTealText
        }
    }
    private var bg: Color {
        switch style {
        case .orangeFill: .cjOrangeFill
        case .tealFill: .cjTeal
        default: .clear
        }
    }
    private var stroke: Color? {
        switch style {
        case .orangeLine: .cjOrangeText
        case .tealLine: .cjTealText
        default: nil
        }
    }
    var body: some View {
        Text(text)
            .font(.body.weight(.bold))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay { if let s = stroke { RoundedRectangle(cornerRadius: 14).stroke(s, lineWidth: 1.5) } }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 지도 하단 시트 단계. 아래로 쓸면 펼침 → 기본 → 접힘, 위로 쓸면 반대로 한 단계씩.
enum SheetDetent { case collapsed, normal, expanded }

/// 지도 하단 시트 공통 틀. 손잡이·헤더를 위아래로 쓸거나 손잡이를 눌러 단계를 바꾼다. 접힘이면 헤더만 보인다.
struct SwipeSheet<Header: View, Content: View>: View {
    @Binding var detent: SheetDetent
    var normalHeight: CGFloat? = nil  // nil이면 내용 높이
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    private var expandedHeight: CGFloat { min(580, UIScreen.main.bounds.height * 0.65) }

    private func step(up: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) {
            switch detent {
            case .collapsed: if up { detent = .normal }
            case .normal: detent = up ? .expanded : .collapsed
            case .expanded: if !up { detent = .normal }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Button { step(up: detent != .expanded) } label: {
                    Capsule().fill(Color.cjHandle).frame(width: 40, height: 4)
                        .frame(maxWidth: .infinity).frame(height: 20).contentShape(Rectangle())
                }
                .accessibilityLabel(detent == .expanded ? "시트 접기" : "시트 펼치기")
                header
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12).onEnded { step(up: $0.translation.height < 0) })
            if detent != .collapsed { content }
        }
        .padding(.horizontal, 18).padding(.bottom, 8)
        .frame(height: detent == .expanded ? expandedHeight : detent == .normal ? normalHeight : nil, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color.cjSurface, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .shadow(color: .black.opacity(0.13), radius: 10, y: -3)
    }
}

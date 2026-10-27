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

struct ItemThumb: View {
    let item: Item
    var width: CGFloat = 52
    var height: CGFloat = 52
    var radius: CGFloat = 12
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(Color.cjInset)
            if let d = item.photo, let img = Photo.image(d) {
                img.resizable().scaledToFill()
            } else {
                Text(item.emoji).font(.system(size: min(width, height) * 0.46))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct ItemRow: View {
    let item: Item
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ItemThumb(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.body.weight(.bold))
                    Text("\(Place.byID[item.hub]?.name ?? "") · \(ago(item.at))")
                        .font(.footnote).foregroundStyle(Color.cjSub)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

extension View {
    func field() -> some View {
        padding(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cjLine, lineWidth: 1.5))
    }
}

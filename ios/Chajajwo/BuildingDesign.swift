import SwiftUI

enum BuildingDesign {
    static let green = Color(hex: 0x00866b)
    static let mint = Color(hex: 0xe5f5ef)
    static let line = Color(hex: 0xe4eae7)
    static let canvas = Color(uiColor: .systemGroupedBackground)
}

struct BuildingSurface<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(BuildingDesign.line.opacity(0.8)))
            .shadow(color: .black.opacity(0.025), radius: 7, y: 3)
    }
}

struct BuildingHeroPhoto: View {
    let building: CampusBuilding
    var height: CGFloat = 168
    private var photo: CampusBuildingPhoto? { CampusBuildingPhoto.photo(for: building) }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let asset = photo?.assetName { Image(asset).resizable().scaledToFill() }
                else if let url = photo?.remoteURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
                } else { placeholder }
            }
            .frame(maxWidth: .infinity).frame(height: height).clipped()
            if photo != nil {
                Text("공식 건물 사진").font(.caption2.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.5), in: Capsule()).padding(10)
            }
        }
        .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore).accessibilityLabel(building.name + (photo == nil ? " 사진 미등록" : " 공식 건물 사진"))
    }
    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [BuildingDesign.mint, Color(uiColor: .secondarySystemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Image(systemName: "building.2").font(.system(size: 38, weight: .light)).foregroundStyle(BuildingDesign.green.opacity(0.7))
                Text("건물 사진 준비 중").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct BuildingDirectionsBanner: View {
    let building: CampusBuilding
    var body: some View {
        if let url = building.directionsURL {
            DirectionsButton(destination: url, name: building.name) {
                HStack(spacing: 12) {
                    Image(systemName: "location").font(.title2)
                    Text("길찾기").font(.headline)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 38, weight: .light)).opacity(0.3)
                }
                .foregroundStyle(BuildingDesign.green).padding(.horizontal, 20).frame(minHeight: 58)
                .background(LinearGradient(colors: [BuildingDesign.mint, Color(hex: 0xc8eade)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
            }
            .accessibilityIdentifier("building.directions")
        }
    }
}

struct BuildingEmptyCard: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(BuildingDesign.green)
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity)
    }
}

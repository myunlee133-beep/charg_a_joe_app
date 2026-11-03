import SwiftUI

/// 셔틀 정류장을 눌렀을 때 뜨는 하단 카드.
struct HomePlaceCard: View {
    @EnvironmentObject var store: Store
    let place: Place
    @Binding var detent: SheetDetent
    var body: some View {
        SwipeSheet(detent: $detent) {
            HStack {
                PlaceIcon(type: place.type)
                Text(place.name).font(.headline)
                Spacer()
                Button { store.closeSheet() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.cjSub).padding(6) }
                    .accessibilityLabel("장소 정보 닫기")
            }
        } content: {
            ShuttleStatusContent() // 정류장 전용. 식당은 SheetView의 식단 시트로 연다.
            Link(destination: place.directionsURL) { Label("길찾기", systemImage: "arrow.triangle.turn.up.right.diamond") }.font(.subheadline)
        }
    }
}

struct ShuttleStatusContent: View {
    @EnvironmentObject var shuttle: CircularShuttleService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shuttle.status).font(.subheadline.weight(.semibold)).foregroundStyle(Color.cjBlue)
            if let date = shuttle.queriedAt { Text("조회 \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(Color.cjSub) }
            ForEach(shuttle.positions.prefix(3)) { bus in
                Label("교내순환 · 다음 \(bus.nextStop)", systemImage: "bus.fill").font(.subheadline)
            }
            Text("위치는 노선도 좌표를 도로 위에 보정한 추정치예요. 도착예정시간은 현재 데이터에서 제공하지 않아요.")
                .font(.caption).foregroundStyle(Color.cjSub)
            if shuttle.heldCount > 0 { Text("불확실한 위치 \(shuttle.heldCount)건 확인 중").font(.caption).foregroundStyle(Color.cjSub) }
        }
    }
}

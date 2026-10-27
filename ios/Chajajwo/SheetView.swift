import SwiftUI

struct SheetView: View {
    @EnvironmentObject var store: Store
    @State private var secret = ""
    @State private var contact = ""
    @State private var menuDate = Date()

    private var place: Place { Place.byID[store.sel] ?? Place.all[0] }
    private var item: Item? { store.itemID.flatMap { id in store.items.first { $0.id == id } } }
    private var hubItems: [Item] { store.items.filter { $0.hub == place.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.open {
                Capsule().fill(Color.cjHandle).frame(width: 40, height: 4).frame(maxWidth: .infinity).padding(.bottom, 12)
                header
                Divider()
                if place.type == .food {
                    foodBody
                } else {
                    ViewThatFits(in: .vertical) {
                        content
                        ScrollView { content }
                    }
                    .frame(maxHeight: 380)
                }
            } else {
                peek
            }
        }
        .padding(.horizontal, 20).padding(.top, store.open ? 10 : 16).padding(.bottom, 18)
        .frame(height: store.open && place.type == .food ? 470 : nil)
        .onChange(of: store.sel) { _, _ in menuDate = Date() }
        .onChange(of: store.open) { _, isOpen in if isOpen { menuDate = Date() } }
        .background(Color.cjSurface, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .shadow(color: .black.opacity(0.16), radius: 10, y: -2)
    }

    // MARK: 접힌 상태
    private var peek: some View {
        Button { store.open = true } label: {
            HStack(spacing: 14) {
                PlaceIcon(type: place.type)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.title3.weight(.heavy))
                    Text(peekSub).font(.footnote).foregroundStyle(Color.cjSub)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var peekSub: String {
        switch place.type {
        case .food: "식단과 운영정보 보기"
        case .hub: "보관 중 \(hubItems.count)건 보기"
        case .stop: "셔틀 도착 정보 보기"
        }
    }

    // MARK: 펼친 상태
    private var header: some View {
        HStack(spacing: 12) {
            PlaceIcon(type: place.type)
            if place.type == .food {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(place.name).font(.title3.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.8)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            let status = store.dining.status(for: place, at: context.date)
                            Badge(text: status.title, color: status.isOpen ? .cjTeal : .cjSub)
                        }
                    }
                    foodDate
                }
            } else {
                Text(item?.title ?? place.name).font(.title3.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
                badge
            }
            Spacer(minLength: 0)
            Button { store.closeSheet() } label: {
                Image(systemName: "xmark").foregroundStyle(Color.cjSub).padding(6)
            }
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder private var badge: some View {
        switch place.type {
        case .food: EmptyView()
        case .stop: Badge(text: "운행 정보 예시", color: .cjBlue)
        case .hub: Badge(text: item?.kind ?? "보관 중 \(hubItems.count)건", color: .cjTeal)
        }
    }

    @ViewBuilder private var content: some View {
        switch place.type {
        case .food: foodBody
        case .stop: stopBody
        case .hub: if let item { itemBody(item) } else { hubBody }
        }
    }

    private var foodDate: some View {
        HStack(spacing: 8) {
            Text(DiningData.dateTitle(menuDate))
                .font(.subheadline.weight(.semibold))
            Button("오늘") { menuDate = Date() }
                .font(.caption2.weight(.bold)).foregroundStyle(Color.cjOrangeText)
                .frame(minHeight: 44)
                .accessibilityLabel("오늘 식단으로 돌아가기")
        }
        .frame(height: 28, alignment: .leading)
    }

    private var foodBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    let hasMeals = store.dining.hasUnits(in: place, foodCourt: false) || !store.dining.hasUnits(in: place, foodCourt: true)
                    let hasCourt = store.dining.hasUnits(in: place, foodCourt: true)
                    VStack(alignment: .leading, spacing: 0) {
                        if hasMeals {
                            ForEach(DiningMeal.allCases, id: \.rawValue) { meal in
                                mealRow(meal)
                                    .frame(minHeight: max(0, (geometry.size.height - 2) / 3))
                                if meal != .dinner || hasCourt { Divider() }
                            }
                        }
                        if hasCourt { foodCourtRow }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                }
                .overlay(alignment: .leading) {
                    dayButton(-1, label: "전날", symbol: "chevron.left")
                        .offset(x: -32)
                }
                .overlay(alignment: .trailing) {
                    dayButton(1, label: "다음날", symbol: "chevron.right")
                        .offset(x: 32)
                }
            }

            HStack(spacing: 10) {
                Button { store.tab = .found } label: { BigLabel(text: "분실물 보기", style: .orangeFill) }
                Link(destination: place.directionsURL) { BigLabel(text: "길찾기", style: .orangeLine) }
            }
            .padding(.top, 12)
        }
    }

    private func dayButton(_ offset: Int, label: String, symbol: String) -> some View {
        let allowed = DiningData.canShow(menuDate, offset: offset)
        return Button {
            if allowed, let date = DiningData.calendar.date(byAdding: .day, value: offset, to: menuDate) {
                menuDate = date
            }
        } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .ultraLight))
                .foregroundStyle(Color.cjSub)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(allowed ? 1 : 0.25)
        .disabled(!allowed)
        .accessibilityLabel(label + " 식단")
    }

    private func mealRow(_ meal: DiningMeal) -> some View {
        let menus = store.dining.menus(for: place, on: menuDate, meal: meal)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Label(meal.title, systemImage: meal.symbol)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.cjOrangeText)
                Text(store.dining.hours(for: place, on: menuDate, meal: meal))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.cjSub)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background(Color.cjInset, in: RoundedRectangle(cornerRadius: 5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if menus.isEmpty {
                    Text("등록된 메뉴가 없어요").foregroundStyle(Color.cjSub)
                } else {
                    ForEach(Array(menus.enumerated()), id: \.offset) { index, menu in
                        if index == 0 || menus[index - 1].unit != menu.unit, Set(menus.map(\.unit)).count > 1 {
                            Text(menu.unit).font(.caption.weight(.bold)).foregroundStyle(Color.cjSub)
                                .padding(.top, index == 0 ? 0 : 6)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(menu.name).frame(maxWidth: .infinity, alignment: .leading)
                            if let price = menu.priceWon {
                                Text("\(price.formatted())원").font(.caption).foregroundStyle(Color.cjSub)
                            }
                        }
                    }
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }

    private var foodCourtRow: some View {
        let stalls = store.dining.foodCourtMenus(for: place, on: menuDate)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Label("푸드코트", systemImage: "fork.knife")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.cjOrangeText)
                Text(store.dining.foodCourtHours(for: place, on: menuDate))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.cjSub)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background(Color.cjInset, in: RoundedRectangle(cornerRadius: 5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if stalls.isEmpty {
                    Text("등록된 메뉴가 없어요").foregroundStyle(Color.cjSub)
                }
                ForEach(Array(stalls.enumerated()), id: \.offset) { index, stall in
                    Text(stall.stall).font(.caption.weight(.bold)).foregroundStyle(Color.cjSub)
                        .padding(.top, index == 0 ? 0 : 10)
                    ForEach(Array(stall.menus.enumerated()), id: \.offset) { _, menu in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(menu.name).frame(maxWidth: .infinity, alignment: .leading)
                            if let price = menu.priceWon {
                                Text("\(price.formatted())원").font(.caption).foregroundStyle(Color.cjSub)
                            }
                        }
                    }
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }

    private var stopBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(place.next.enumerated()), id: \.offset) { i, m in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(i == 0 ? "다음 셔틀" : "\(i + 1)번째 셔틀") 약 \(m)분 후").font(.body.weight(.bold))
                    Text("정문 → 학생회관 → 공대 순환").font(.footnote).foregroundStyle(Color.cjSub)
                }
                .padding(.vertical, 14)
                Divider()
            }
            Link(destination: place.directionsURL) { BigLabel(text: "길찾기", style: .tealLine) }.padding(.top, 14)
        }
    }

    private var hubBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("📍 \(place.storage)").font(.footnote).foregroundStyle(Color.cjSub).padding(.top, 10)
            if hubItems.isEmpty {
                Text("지금 보관 중인 분실물이 없어요").font(.subheadline).foregroundStyle(Color.cjSub)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            ForEach(hubItems) { i in
                ItemRow(item: i) { store.select(i.hub, item: i.id) }.padding(.vertical, 14)
                Divider()
            }
        }
    }

    private func itemBody(_ i: Item) -> some View {
        let requested = store.claims.contains { $0.itemID == i.id }
        return VStack(alignment: .leading, spacing: 0) {
            ItemThumb(item: i, width: 1000, height: 180, radius: 16)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            kv("습득 장소", i.found)
            kv("습득 시각", i.at.formatted(.dateTime.month(.wide).day().hour().minute()))
            kv("보관 위치", place.storage)
            kv("특징", i.feat)
            if store.claim && !requested {
                claimForm(i)
            } else if requested {
                Text("확인 요청을 보냈어요. 운영팀이 특징을 확인하면 수령 안내를 드려요. 진행 상황은 내 분실 신고 탭에서 볼 수 있어요.")
                    .font(.subheadline).foregroundStyle(Color.cjSuccessText)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cjSuccessFill, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 14)
            } else {
                HStack(spacing: 10) {
                    Button { store.itemID = nil } label: { BigLabel(text: "목록", style: .tealLine) }
                    Button { store.claim = true } label: { BigLabel(text: "내 물건이에요", style: .tealFill) }
                }
                .padding(.top, 14)
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(k).foregroundStyle(Color.cjSub).frame(width: 72, alignment: .leading)
            Text(v)
            Spacer(minLength: 0)
        }
        .font(.subheadline).padding(.vertical, 4)
    }

    private func claimForm(_ i: Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("본인 확인을 위해 사진에 나오지 않는 특징을 먼저 알려 주세요. 운영팀이 확인 후 수령 안내를 드려요.")
                .font(.footnote).foregroundStyle(Color.cjSub)
            TextField("숨은 특징 (예: 지갑 안쪽에 영수증과 스티커가 있어요)", text: $secret, axis: .vertical)
                .lineLimit(3...5).field()
            TextField("연락처 (학교 메일)", text: $contact)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).textContentType(.emailAddress).field()
            HStack(spacing: 10) {
                Button { store.claim = false } label: { BigLabel(text: "취소", style: .tealLine) }
                Button {
                    store.addClaim(item: i, secret: secret, contact: contact)
                    secret = ""; contact = ""; store.claim = false
                    store.toast("확인 요청을 보냈어요")
                } label: { BigLabel(text: "확인 요청", style: .tealFill) }
                .disabled(secret.trimmingCharacters(in: .whitespaces).isEmpty || !contact.contains("@"))
            }
        }
        .padding(.top, 14)
    }
}

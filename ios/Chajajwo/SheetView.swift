import SwiftUI

struct SheetView: View {
    @EnvironmentObject var store: Store
    @State private var menuDate = Date()
    @Binding var detent: SheetDetent  // 식단 시트의 펼침·기본·접힘

    private var place: Place { Place.byID[store.sel] ?? Place.all[0] }

    var body: some View {
        Group {
            if store.open && place.type == .food {
                SwipeSheet(detent: $detent, normalHeight: 400) { header } content: {
                    Divider()
                    foodBody
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if store.open {
                        Capsule().fill(Color.cjHandle).frame(width: 40, height: 4).frame(maxWidth: .infinity).padding(.bottom, 12)
                        header
                        Divider()
                        ViewThatFits(in: .vertical) {
                            content
                            ScrollView { content }
                        }
                        .frame(maxHeight: 380)
                    } else {
                        peek
                    }
                }
                .padding(.horizontal, 20).padding(.top, store.open ? 10 : 16).padding(.bottom, 18)
                .background(Color.cjSurface, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
                .shadow(color: .black.opacity(0.16), radius: 10, y: -2)
            }
        }
        .onChange(of: store.sel) { _, _ in menuDate = Date() }
        .onChange(of: store.open) { _, isOpen in if isOpen { menuDate = Date() } }
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
                Text(place.name).font(.title3.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
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
        case .stop: Badge(text: "교내순환", color: .cjBlue)
        }
    }

    @ViewBuilder private var content: some View {
        switch place.type {
        case .food: foodBody
        case .stop: stopBody
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
                    .padding(.horizontal, 30)  // 화살표(시트 가장자리 44pt) 자리를 비운다
                }
                .overlay(alignment: .leading) {
                    dayButton(-1, label: "전날", symbol: "chevron.left")
                        .offset(x: -18)
                }
                .overlay(alignment: .trailing) {
                    dayButton(1, label: "다음날", symbol: "chevron.right")
                        .offset(x: 18)
                }
            }

            HStack(spacing: 10) {
                Link(destination: place.directionsURL) { BigLabel(text: "길찾기", style: .orangeFill) }
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
            ShuttleStatusContent().padding(.vertical, 14)
            Link(destination: place.directionsURL) { BigLabel(text: "길찾기", style: .tealLine) }.padding(.top, 14)
        }
    }
}

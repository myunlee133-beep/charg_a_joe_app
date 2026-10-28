import SwiftUI

/// 식당 모아보기: 날짜·끼니별 공개 메뉴를 비교하고 지도에서 다시 찾는다.
struct DiningView: View {
    @EnvironmentObject var store: Store
    @State private var date = Date()
    @State private var meal = DiningMeal.lunch
    @State private var query = ""
    @State private var onlyOpen = false
    @State private var onlyFavorites = false
    @State private var priceLimit = 0
    @AppStorage("cj_favorite_restaurants") private var savedFavorites = ""

    private var favorites: Set<String> { Set(savedFavorites.split(separator: "|").map(String.init)) }
    private var isToday: Bool { DiningData.calendar.isDateInToday(date) }

    private func menus(for place: Place) -> [DiningData.Menu] {
        let regular = store.dining.menus(for: place, on: date, meal: meal)
        let stalls = store.dining.foodCourtMenus(for: place, on: date).flatMap(\.menus)
        return (regular + stalls).filter { priceLimit == 0 || ($0.priceWon.map { $0 <= priceLimit } ?? false) }
    }

    /// 식당마다 메뉴를 한 번만 계산해 필터·정렬·카드가 같이 쓴다.
    private struct Row: Identifiable {
        let place: Place
        let dishes: [DiningData.Menu]
        var id: String { place.id }
    }

    private var rows: [Row] {
        let search = query.trimmingCharacters(in: .whitespaces)
        return Place.all.compactMap { place -> Row? in
            guard place.type == .food else { return nil }
            if onlyFavorites && !favorites.contains(place.id) { return nil }
            if onlyOpen && !store.dining.status(for: place, at: Date()).isOpen { return nil }
            let dishes = menus(for: place)
            if priceLimit > 0 && dishes.isEmpty { return nil }
            guard search.isEmpty || place.name.localizedCaseInsensitiveContains(search)
                || dishes.contains(where: { ($0.name + $0.unit).localizedCaseInsensitiveContains(search) }) else { return nil }
            return Row(place: place, dishes: dishes)
        }.sorted { lhs, rhs in
            if lhs.dishes.isEmpty != rhs.dishes.isEmpty { return !lhs.dishes.isEmpty }
            return lhs.place.name.localizedStandardCompare(rhs.place.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        let rows = self.rows
                        HStack {
                            Text("서울대 관악캠퍼스").font(.caption).foregroundStyle(Color.cjSub)
                            Spacer()
                            Text("식당 \(rows.count)곳").font(.caption.weight(.semibold))
                        }
                        .padding(.top, 16)
                        if rows.isEmpty {
                            ContentUnavailableView("조건에 맞는 식당이 없어요", systemImage: "fork.knife",
                                                   description: Text("검색어나 필터를 바꿔 보세요."))
                        }
                        ForEach(rows) { restaurantCard($0.place, dishes: $0.dishes) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .background(Color.cjSurface)
            .navigationTitle("식당")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.tab = .home; store.homeFilter = .all } label: { Label("지도", systemImage: "chevron.left") }
                        .font(.subheadline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("오늘") { date = Date() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.cjOrangeText)
                }
            }
            .onChange(of: date) { _, _ in if !isToday { onlyOpen = false } }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                dateArrow(-1, symbol: "chevron.left", label: "전날 식단")
                Spacer()
                Text(DiningData.dateTitle(date)).font(.headline)
                Spacer()
                dateArrow(1, symbol: "chevron.right", label: "다음날 식단")
            }
            .background(Color.cjInset, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 0) {
                ForEach(DiningMeal.allCases, id: \.rawValue) { option in
                    Button { meal = option } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.symbol).font(.system(size: 23, weight: .regular))
                            Text(option.title).font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(meal == option ? Color.cjOrangeText : Color.cjSub)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(meal == option ? Color.cjOrangeFill.opacity(0.5) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(meal == option ? .isSelected : [])
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.cjSub)
                TextField("식당이나 메뉴 검색", text: $query).submitLabel(.search)
                    .accessibilityLabel("식당이나 메뉴 검색")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Color.cjSub).accessibilityLabel("검색 지우기")
                }
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(Color.cjInset, in: RoundedRectangle(cornerRadius: 12))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterButton("지금 운영 중", symbol: "circle.fill", selected: onlyOpen) { onlyOpen.toggle() }
                        .disabled(!isToday).opacity(isToday ? 1 : 0.45)
                    filterButton("즐겨찾기", symbol: "star", selected: onlyFavorites) { onlyFavorites.toggle() }
                    Menu {
                        Picker("메뉴 가격", selection: $priceLimit) {
                            Text("모든 가격").tag(0)
                            Text("6,000원 이하").tag(6000)
                            Text("8,000원 이하").tag(8000)
                        }
                    } label: {
                        Label(priceLimit == 0 ? "가격" : "\(priceLimit.formatted())원 이하", systemImage: "chevron.down")
                            .font(.caption.weight(.medium)).padding(.horizontal, 12).frame(height: 36)
                            .background(Color.cjInset, in: Capsule())
                    }
                    .foregroundStyle(priceLimit == 0 ? Color.primary : Color.cjOrangeText)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
    }

    private func restaurantCard(_ place: Place, dishes: [DiningData.Menu]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(place.name).font(.title3.weight(.bold))
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let status = store.dining.status(for: place, at: context.date)
                        HStack(spacing: 6) {
                            if isToday { Badge(text: status.title, color: status.isOpen ? .cjTealText : .cjSub) }
                            Text(place.building).font(.caption).foregroundStyle(Color.cjSub)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button { toggleFavorite(place.id) } label: {
                    Image(systemName: favorites.contains(place.id) ? "star.fill" : "star")
                        .font(.system(size: 20)).foregroundStyle(Color.cjOrangeText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(place.name + (favorites.contains(place.id) ? " 즐겨찾기 해제" : " 즐겨찾기 추가"))
                Button {
                    store.tab = .home; store.homeFilter = .all; store.filter = nil; store.select(place.id)
                } label: {
                    Image(systemName: "map").font(.system(size: 18))
                        .foregroundStyle(Color.cjTealText).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel(place.name + " 지도에서 보기")
            }
            Label(store.dining.hours(for: place, on: date).replacingOccurrences(of: "-", with: "–"), systemImage: "clock")
                .font(.caption).foregroundStyle(Color.cjSub)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.cjOrange.opacity(0.7)).frame(height: 1)
            if dishes.isEmpty {
                Text("이 날짜에 등록된 \(meal.title) 메뉴가 없어요")
                    .font(.subheadline).foregroundStyle(Color.cjSub).padding(.vertical, 12)
            } else {
                ForEach(Array(dishes.enumerated()), id: \.offset) { index, dish in
                    if index == 0 || dishes[index - 1].unit != dish.unit {
                        Text(DiningData.stallName(dish.unit) + (DiningData.isFoodCourt(dish.unit) ? " · 상시 메뉴" : ""))
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.cjSub)
                            .padding(.top, index == 0 ? 0 : 8)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(dish.name).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        Text(dish.priceWon.map { "\($0.formatted())원" } ?? "가격 미공개")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(Color.cjSub)
                            .fixedSize()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(16)
        .background(Color.cjSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cjLine.opacity(0.25)))
    }

    private func toggleFavorite(_ id: String) {
        var updated = favorites
        if updated.contains(id) { updated.remove(id) } else { updated.insert(id) }
        savedFavorites = updated.sorted().joined(separator: "|")
    }

    private func dateArrow(_ direction: Int, symbol: String, label: String) -> some View {
        Button {
            if let next = DiningData.calendar.date(byAdding: .day, value: direction, to: date) { date = next }
        } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func filterButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.caption.weight(.medium))
                .padding(.horizontal, 12).frame(height: 36)
                .foregroundStyle(selected ? Color.cjOrangeText : Color.primary)
                .background(selected ? Color.cjOrangeFill.opacity(0.5) : Color.cjInset, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

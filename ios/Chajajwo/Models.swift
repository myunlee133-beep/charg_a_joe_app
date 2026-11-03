import SwiftUI
import UIKit
import MapKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
    static let cjTeal = Color(hex: 0x0f7f74)
    static let cjOrange = Color(hex: 0xf26b1d)
    static let cjBlue = Color(hex: 0x1e7be0)
    static let cjBerry = Color(hex: 0xa63d66)
    static let cjShuttle = Color(hex: 0x365fc7)
    /// Keep text, surfaces, and borders in the same system appearance.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func uiColor(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        let lightColor = uiColor(light)
        let darkColor = uiColor(dark)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
    static let cjSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let cjInset = Color(uiColor: .tertiarySystemGroupedBackground)
    static let cjSub = adaptive(light: 0x6b767d, dark: 0xaab4bd)
    static let cjLine = Color(uiColor: .separator)
    static let cjHandle = adaptive(light: 0xd4d9dc, dark: 0x63676b)
    static let cjTealText = adaptive(light: 0x0f7f74, dark: 0x64d9ca)
    static let cjOrangeText = adaptive(light: 0xc4500f, dark: 0xffb17a)
    static let cjBlueText = adaptive(light: 0x1e7be0, dark: 0x8bbdff)
    static let cjBerryText = adaptive(light: 0xa63d66, dark: 0xf0a0bf)
    static let cjOrangeFill = adaptive(light: 0xfdd3b8, dark: 0x4a2d1c)
    static let cjSuccessFill = adaptive(light: 0xe4f3f1, dark: 0x173c36)
    static let cjSuccessText = adaptive(light: 0x0b6158, dark: 0x8ce2d2)
}

enum PlaceType {
    case food, stop
    var color: Color { switch self { case .food: .cjBerry; case .stop: .cjShuttle } }
    var textColor: Color { switch self { case .food: .cjBerryText; case .stop: .cjBlueText } }
    var symbol: String { switch self { case .food: "fork.knife"; case .stop: "bus.fill" } }
    var chipTitle: String { switch self { case .food: "식당"; case .stop: "셔틀" } }
}

struct Place: Identifiable {
    let id: String
    let type: PlaceType
    let name: String
    let lat: Double
    let lng: Double
    var hours = ""
    var menu: [(String, [String])] = []
    var building = ""

    var coord: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }

    static let all: [Place] = DiningData.bundled.foodPlaces + (CircularRoute.load()?.stops.enumerated().map { index, stop in
        Place(id: "circular-stop-\(index)", type: .stop, name: stop.name + " · 교내순환", lat: stop.coordinate.latitude, lng: stop.coordinate.longitude)
    } ?? [])
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    var directionsURL: URL {
        let n = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://map.kakao.com/link/to/\(n),\(lat),\(lng)")!
    }
}

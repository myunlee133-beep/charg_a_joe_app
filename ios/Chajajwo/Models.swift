import SwiftUI
import UIKit
import MapKit
import ImageIO
import UniformTypeIdentifiers

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
    static let cjTeal = Color(hex: 0x0f7f74)
    static let cjOrange = Color(hex: 0xf26b1d)
    static let cjBlue = Color(hex: 0x1e7be0)
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
    static let cjOrangeFill = adaptive(light: 0xfdd3b8, dark: 0x4a2d1c)
    static let cjSuccessFill = adaptive(light: 0xe4f3f1, dark: 0x173c36)
    static let cjSuccessText = adaptive(light: 0x0b6158, dark: 0x8ce2d2)
}

enum PlaceType {
    case hub, food, stop
    var color: Color { switch self { case .hub: .cjTeal; case .food: .cjOrange; case .stop: .cjBlue } }
    var textColor: Color { switch self { case .hub: .cjTealText; case .food: .cjOrangeText; case .stop: .cjBlueText } }
    var symbol: String { switch self { case .hub: "checkmark"; case .food: "fork.knife"; case .stop: "bus.fill" } }
    var chipTitle: String { switch self { case .hub: "보관 거점"; case .food: "식당"; case .stop: "셔틀" } }
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
    var storage = ""
    var next: [Int] = []

    var coord: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }

    static let all: [Place] = DiningData.bundled.foodPlaces + [
        Place(id: "hub1", type: .hub, name: "학생회관 보관 거점", lat: 37.4617, lng: 126.9520, storage: "학생회관 1층 안내데스크"),
        Place(id: "hub2", type: .hub, name: "정문 셔틀 정류장 거점", lat: 37.4659, lng: 126.9489, storage: "정문 셔틀 정류장 옆 보관함"),
        Place(id: "hub3", type: .hub, name: "신공학관 셔틀 종점 거점", lat: 37.4495, lng: 126.9512, storage: "신공학관 1층 경비실"),
        Place(id: "s1", type: .stop, name: "정문 셔틀 정류장", lat: 37.4664, lng: 126.9481, next: [3, 13, 23]),
        Place(id: "s2", type: .stop, name: "학생회관 앞 정류장", lat: 37.4603, lng: 126.9545, next: [7, 17, 27]),
        Place(id: "s3", type: .stop, name: "신공학관 셔틀 종점", lat: 37.4490, lng: 126.9520, next: [12, 22, 32]),
    ]
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let hubs = all.filter { $0.type == .hub }

    var directionsURL: URL {
        let n = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://map.kakao.com/link/to/\(n),\(lat),\(lng)")!
    }
}

let kinds = ["지갑", "전자기기", "학생증", "우산", "의류", "가방", "기타"]

struct Item: Identifiable, Codable {
    var id: String
    var hub: String
    var kind: String
    var emoji = "📦"
    var title: String
    var feat: String
    var found: String
    var at: Date
    var photo: Data?

    private static func ago(_ h: Double) -> Date { Date().addingTimeInterval(-h * 3600) }
    static let seed: [Item] = [
        Item(id: "i1", hub: "hub1", kind: "지갑", emoji: "👛", title: "검정 반지갑", feat: "카드 수납형, 모서리 해짐", found: "학생회관 2층 식당", at: ago(2)),
        Item(id: "i2", hub: "hub1", kind: "전자기기", emoji: "🎧", title: "흰색 무선 이어폰", feat: "케이스 포함", found: "학생회관 라운지", at: ago(5)),
        Item(id: "i3", hub: "hub2", kind: "우산", emoji: "☂️", title: "남색 장우산", feat: "나무 손잡이", found: "정문 셔틀 정류장", at: ago(1)),
        Item(id: "i4", hub: "hub3", kind: "학생증", emoji: "🪪", title: "학생증", feat: "개인정보 가림 처리", found: "5511번 버스 하차장", at: ago(3)),
        Item(id: "i5", hub: "hub3", kind: "의류", emoji: "🧥", title: "회색 후드집업", feat: "L 사이즈", found: "신공학관 셔틀 종점", at: ago(26)),
    ]
}

struct LostReport: Identifiable, Codable {
    var id = UUID().uuidString
    var kind: String
    var place: String
    var date: Date
    var feat: String
}

struct Claim: Identifiable, Codable {
    var id = UUID().uuidString
    var itemID: String
    var title: String
    var hub: String
    var secret: String
    var contact: String
    var at = Date()
    var done = false
}

func ago(_ d: Date) -> String {
    let m = Int(Date().timeIntervalSince(d) / 60)
    if m < 60 { return "\(m)분 전" }
    if m < 1440 { return "\(Int((Double(m) / 60).rounded()))시간 전" }
    return "\(Int((Double(m) / 1440).rounded()))일 전"
}

enum Photo {
    /// 사진을 480px JPEG로 줄여 저장 용량을 아낀다.
    static func shrink(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 480,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }

    static func image(_ data: Data) -> Image? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return Image(decorative: cg, scale: 1)
    }
}

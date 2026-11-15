import XCTest
@testable import CampusCore

final class DirectionsURLTests: XCTestCase {
    private let studentHall = DirectionsEndpoint(name: "63동 · 학생회관", latitude: 37.4590, longitude: 126.9502)
    private let library = DirectionsEndpoint(name: "62동 · 중앙도서관", latitude: 37.4598, longitude: 126.9525)

    func testBuildingToBuildingDefaultsToWalkingAndPreservesBothEndpoints() throws {
        let url = try XCTUnwrap(DirectionsURL.route(from: studentHall, to: library))
        let path = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath.removingPercentEncoding)
        XCTAssertEqual(path, "/link/by/walk/63동 · 학생회관,37.459,126.9502/62동 · 중앙도서관,37.4598,126.9525")
        XCTAssertEqual(DirectionsURL.inAppURL(url), url)
    }

    func testSwappingBuildingsReversesTheRoute() throws {
        let url = try XCTUnwrap(DirectionsURL.route(from: library, to: studentHall, transport: .traffic))
        let path = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath.removingPercentEncoding)
        XCTAssertEqual(path, "/link/by/traffic/62동 · 중앙도서관,37.4598,126.9525/63동 · 학생회관,37.459,126.9502")
    }

    func testTransportTypesUseDocumentedKakaoValues() throws {
        for transport in DirectionsTransport.allCases {
            let url = try XCTUnwrap(DirectionsURL.route(from: studentHall, to: library, transport: transport))
            XCTAssertTrue(url.path.hasPrefix("/link/by/\(transport.rawValue)/"))
        }
    }

    func testSameLocationAndInvalidEndpointsCannotStartARoute() {
        XCTAssertNil(DirectionsURL.route(from: studentHall, to: studentHall))
        let samePosition = DirectionsEndpoint(name: "다른 이름", latitude: studentHall.latitude, longitude: studentHall.longitude)
        XCTAssertNil(DirectionsURL.route(from: studentHall, to: samePosition))
        let invalid = DirectionsEndpoint(name: "건물", latitude: .nan, longitude: 126.95)
        XCTAssertNil(DirectionsURL.route(from: invalid, to: library))
        XCTAssertNil(DirectionsURL.route(from: studentHall, to: invalid))
        let unnamed = DirectionsEndpoint(name: "  ", latitude: 37.46, longitude: 126.95)
        XCTAssertNil(DirectionsURL.route(from: unnamed, to: library))
    }

    func testDestinationPreservesNameAndCoordinates() throws {
        let url = try XCTUnwrap(DirectionsURL.destination(name: "학생회관", latitude: 37.4617, longitude: 126.952))
        XCTAssertEqual(url.host, "map.kakao.com")
        XCTAssertEqual(url.path, "/link/to/학생회관,37.4617,126.952")
        XCTAssertEqual(DirectionsURL.inAppURL(url), url)
    }

    func testPlaceNameCannotChangeTheRouteOrAddURLParameters() throws {
        let name = "식당, 1/2층?출발=#도착% & +"
        let url = try XCTUnwrap(DirectionsURL.destination(name: name, latitude: 37.46, longitude: 126.95))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
        XCTAssertEqual(components.percentEncodedPath.filter { $0 == "/" }.count, 3)
        XCTAssertEqual(components.percentEncodedPath.filter { $0 == "," }.count, 2)
        XCTAssertEqual(components.percentEncodedPath.removingPercentEncoding, "/link/to/\(name),37.46,126.95")
    }

    func testInvalidCoordinatesDoNotCreateABrokenLink() {
        for (latitude, longitude) in [(Double.nan, 126.95), (.infinity, 126.95),
                                      (37.46, -.infinity), (90.01, 126.95),
                                      (-90.01, 126.95), (37.46, 180.01), (37.46, -180.01)] {
            XCTAssertNil(DirectionsURL.destination(name: "목적지", latitude: latitude, longitude: longitude))
        }
    }

    func testKakaoMobileLandingAndMapPagesStayInApp() throws {
        for address in ["https://map.kakao.com/link/to/37.46,126.95",
                        "https://applink.map.kakao.com/route?ep=37.46%2C126.95&en=campus",
                        "https://m.map.kakao.com/actions/routeView#!/walk",
                        "https://place.map.kakao.com/12345", "https://map.daum.net/",
                        "https://m.map.daum.net/"] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(DirectionsURL.inAppURL(url), url, address)
        }
    }

    func testLegacyHTTPMapLinksUpgradeWithoutLosingRoute() throws {
        let url = try XCTUnwrap(URL(string: "http://m.map.kakao.com:80/actions/routeView?end=campus#!/walk"))
        let upgraded = try XCTUnwrap(DirectionsURL.inAppURL(url))
        XCTAssertEqual(upgraded.absoluteString, "https://m.map.kakao.com/actions/routeView?end=campus#!/walk")
    }

    func testAppLaunchStoreAndUnrelatedLinksAreBlocked() throws {
        for address in ["kakaomap://route?ep=37.46,126.95", "kakaotalk://inappbrowser",
                        "itms-apps://itunes.apple.com/app/id304608425",
                        "https://apps.apple.com/app/id304608425", "https://itunes.apple.com/app/id304608425",
                        "https://map.kakao.com.example.org/route", "https://fakemap.kakao.com/route",
                        "https://map.kakao.com@evil.example/route", "https://user@map.kakao.com/route",
                        "https://map.kakao.com:8443/route", "https://example.org/",
                        "file:///etc/passwd", "javascript:alert(1)", "about:blank"] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertNil(DirectionsURL.inAppURL(url), address)
        }
    }
}

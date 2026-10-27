import CoreLocation
import Foundation
import Combine

/// Foreground-only location + compass, never sent to a server or persisted.
/// One instance belongs to the Home map; stop() releases active GPS/compass updates.
@MainActor
final class UserLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var accuracyMeters: Double?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var approximateLocation = false

    private let manager = CLLocationManager()
    private var isActive = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3                 // metres, avoids unnecessary GPS/UI churn
        manager.headingFilter = 3                  // degrees, on supported devices
        manager.headingOrientation = .portrait     // the app is portrait-only
        authorizationStatus = manager.authorizationStatus
        approximateLocation = manager.accuracyAuthorization == .reducedAccuracy
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        errorMessage = nil
        guard CLLocationManager.locationServicesEnabled() else {
            errorMessage = "기기의 위치 서비스가 꺼져 있어요. 설정에서 위치 서비스를 켜주세요."
            isActive = false
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startSensors()
        case .denied, .restricted:
            errorMessage = "위치 접근이 허용되지 않았어요. 설정에서 권한을 변경할 수 있어요."
        @unknown default:
            errorMessage = "위치 권한 상태를 확인할 수 없어요."
        }
    }

    func stop() {
        isActive = false
        manager.stopUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.stopUpdatingHeading() }
        coordinate = nil
        headingDegrees = nil
        accuracyMeters = nil
    }

    private func startSensors() {
        guard isActive else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        } else {
            headingDegrees = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        approximateLocation = manager.accuracyAuthorization == .reducedAccuracy
        guard isActive else { return }
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            errorMessage = nil
            startSensors()
        case .denied, .restricted:
            coordinate = nil
            headingDegrees = nil
            accuracyMeters = nil
            errorMessage = "위치 접근이 허용되지 않았어요. 설정에서 권한을 변경할 수 있어요."
        case .notDetermined: break
        @unknown default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isActive, let location = locations.last else { return }
        let coord = location.coordinate
        guard UserLocationMath.validCoordinate(latitude: coord.latitude, longitude: coord.longitude),
              UserLocationMath.validFix(ageSeconds: location.timestamp.timeIntervalSinceNow,
                                       accuracyMeters: location.horizontalAccuracy) else { return }
        coordinate = coord
        accuracyMeters = location.horizontalAccuracy
        approximateLocation = manager.accuracyAuthorization == .reducedAccuracy
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        guard isActive else { return }
        guard UserLocationMath.usableHeading(accuracyDegrees: heading.headingAccuracy,
                                            ageSeconds: heading.timestamp.timeIntervalSinceNow) else {
            headingDegrees = nil            // do not display a misleading direction
            return
        }
        // The device's top edge (portrait), NOT its GPS course of movement.
        let candidate = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        headingDegrees = UserLocationMath.normalizedHeading(candidate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isActive else { return }
        let code = (error as? CLError)?.code
        if code == .locationUnknown { return } // transient, wait for a valid fix
        errorMessage = "현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해주세요."
    }
}

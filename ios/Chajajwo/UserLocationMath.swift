import Foundation

/// Location validation and heading conversions, kept independent of iOS frameworks
/// so the same rules can be verified with the Swift command-line compiler.
enum UserLocationMath {
    static func validCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    static func validFix(ageSeconds: Double, accuracyMeters: Double) -> Bool {
        ageSeconds.isFinite && abs(ageSeconds) <= 30 &&
            accuracyMeters.isFinite && accuracyMeters >= 0 && accuracyMeters <= 5_000
    }

    static func normalizedHeading(_ degrees: Double) -> Double? {
        guard degrees.isFinite, degrees >= 0 else { return nil }
        let result = degrees.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }

    static func headingRadians(_ degrees: Double) -> Double? {
        normalizedHeading(degrees).map { $0 * .pi / 180 }
    }

    static func usableHeading(accuracyDegrees: Double, ageSeconds: Double) -> Bool {
        accuracyDegrees.isFinite && accuracyDegrees >= 0 && accuracyDegrees <= 65 &&
            ageSeconds.isFinite && abs(ageSeconds) <= 15
    }
}

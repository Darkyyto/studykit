import CoreLocation
import Foundation

struct Airport: Identifiable, Hashable, Sendable {
    typealias Code = String

    let code: Code
    let city: String
    let latitude: Double
    let longitude: Double

    var id: Code { code }
}

extension Airport {
    private static let cruiseSpeedKilometersPerHour = 780.0
    private static let groundTime: TimeInterval = 20 * 60
    static let earthRadiusKilometers = 6371.0

    func distance(to other: Airport) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * Self.earthRadiusKilometers * atan2(sqrt(a), sqrt(1 - a))
    }

    func blockTime(to other: Airport) -> TimeInterval {
        distance(to: other) / Self.cruiseSpeedKilometersPerHour * 3600 + Self.groundTime
    }

    func routes(closestTo duration: TimeInterval) -> [Airport] {
        Self.catalog
            .filter { $0 != self }
            .sorted { abs(blockTime(to: $0) - duration) < abs(blockTime(to: $1) - duration) }
    }

    static func named(_ code: Code) -> Airport? {
        catalog.first { $0.code == code }
    }

    static let fallback = Airport(code: "MXP", city: "Milan", latitude: 45.630, longitude: 8.723)

    static let catalog: [Airport] = [
        fallback,
        Airport(code: "LIN", city: "Milan Linate", latitude: 45.445, longitude: 9.277),
        Airport(code: "BGY", city: "Bergamo", latitude: 45.674, longitude: 9.704),
        Airport(code: "TRN", city: "Turin", latitude: 45.200, longitude: 7.650),
        Airport(code: "GOA", city: "Genoa", latitude: 44.413, longitude: 8.838),
        Airport(code: "VCE", city: "Venice", latitude: 45.505, longitude: 12.352),
        Airport(code: "BLQ", city: "Bologna", latitude: 44.535, longitude: 11.289),
        Airport(code: "FLR", city: "Florence", latitude: 43.810, longitude: 11.205),
        Airport(code: "PSA", city: "Pisa", latitude: 43.684, longitude: 10.393),
        Airport(code: "FCO", city: "Rome", latitude: 41.800, longitude: 12.239),
        Airport(code: "NAP", city: "Naples", latitude: 40.886, longitude: 14.291),
        Airport(code: "BRI", city: "Bari", latitude: 41.139, longitude: 16.761),
        Airport(code: "OLB", city: "Olbia", latitude: 40.899, longitude: 9.518),
        Airport(code: "CAG", city: "Cagliari", latitude: 39.251, longitude: 9.054),
        Airport(code: "PMO", city: "Palermo", latitude: 38.176, longitude: 13.091),
        Airport(code: "CTA", city: "Catania", latitude: 37.467, longitude: 15.066),
        Airport(code: "ZRH", city: "Zurich", latitude: 47.464, longitude: 8.549),
        Airport(code: "GVA", city: "Geneva", latitude: 46.238, longitude: 6.109),
        Airport(code: "NCE", city: "Nice", latitude: 43.658, longitude: 7.216),
        Airport(code: "LYS", city: "Lyon", latitude: 45.726, longitude: 5.091),
        Airport(code: "MRS", city: "Marseille", latitude: 43.439, longitude: 5.221),
        Airport(code: "MUC", city: "Munich", latitude: 48.354, longitude: 11.786),
        Airport(code: "VIE", city: "Vienna", latitude: 48.110, longitude: 16.570),
        Airport(code: "FRA", city: "Frankfurt", latitude: 50.038, longitude: 8.562),
        Airport(code: "CDG", city: "Paris", latitude: 49.010, longitude: 2.548),
        Airport(code: "BCN", city: "Barcelona", latitude: 41.297, longitude: 2.078),
        Airport(code: "PRG", city: "Prague", latitude: 50.101, longitude: 14.260),
        Airport(code: "BUD", city: "Budapest", latitude: 47.439, longitude: 19.262),
        Airport(code: "BRU", city: "Brussels", latitude: 50.901, longitude: 4.484),
        Airport(code: "AMS", city: "Amsterdam", latitude: 52.310, longitude: 4.768),
        Airport(code: "BER", city: "Berlin", latitude: 52.366, longitude: 13.503),
        Airport(code: "LHR", city: "London", latitude: 51.470, longitude: -0.454),
        Airport(code: "MAD", city: "Madrid", latitude: 40.472, longitude: -3.561),
        Airport(code: "WAW", city: "Warsaw", latitude: 52.166, longitude: 20.967),
        Airport(code: "ATH", city: "Athens", latitude: 37.936, longitude: 23.947),
        Airport(code: "CPH", city: "Copenhagen", latitude: 55.618, longitude: 12.656),
        Airport(code: "DUB", city: "Dublin", latitude: 53.421, longitude: -6.270),
        Airport(code: "LIS", city: "Lisbon", latitude: 38.774, longitude: -9.134),
        Airport(code: "IST", city: "Istanbul", latitude: 41.275, longitude: 28.752),
        Airport(code: "OSL", city: "Oslo", latitude: 60.194, longitude: 11.100),
        Airport(code: "ARN", city: "Stockholm", latitude: 59.652, longitude: 17.919),
        Airport(code: "HEL", city: "Helsinki", latitude: 60.317, longitude: 24.963),
        Airport(code: "CAI", city: "Cairo", latitude: 30.122, longitude: 31.406),
        Airport(code: "KEF", city: "Reykjavik", latitude: 63.985, longitude: -22.605),
        Airport(code: "DXB", city: "Dubai", latitude: 25.253, longitude: 55.364),
        Airport(code: "DOH", city: "Doha", latitude: 25.273, longitude: 51.608),
        Airport(code: "JFK", city: "New York", latitude: 40.641, longitude: -73.778),
        Airport(code: "BOS", city: "Boston", latitude: 42.366, longitude: -71.010),
        Airport(code: "YYZ", city: "Toronto", latitude: 43.678, longitude: -79.625),
        Airport(code: "ORD", city: "Chicago", latitude: 41.974, longitude: -87.907),
        Airport(code: "DEL", city: "Delhi", latitude: 28.556, longitude: 77.100),
        Airport(code: "CPT", city: "Cape Town", latitude: -33.971, longitude: 18.602),
        Airport(code: "MEX", city: "Mexico City", latitude: 19.436, longitude: -99.072),
        Airport(code: "SFO", city: "San Francisco", latitude: 37.621, longitude: -122.379),
        Airport(code: "LAX", city: "Los Angeles", latitude: 33.942, longitude: -118.408),
        Airport(code: "GRU", city: "São Paulo", latitude: -23.432, longitude: -46.469),
        Airport(code: "HKG", city: "Hong Kong", latitude: 22.308, longitude: 113.918),
        Airport(code: "ICN", city: "Seoul", latitude: 37.460, longitude: 126.441),
        Airport(code: "SIN", city: "Singapore", latitude: 1.364, longitude: 103.991),
        Airport(code: "NRT", city: "Tokyo", latitude: 35.772, longitude: 140.393),
        Airport(code: "EZE", city: "Buenos Aires", latitude: -34.822, longitude: -58.536),
        Airport(code: "SYD", city: "Sydney", latitude: -33.940, longitude: 151.175),
    ]
}

extension Airport {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func coordinate(towards other: Airport, fraction: Double) -> CLLocationCoordinate2D {
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let lon2 = other.longitude * .pi / 180
        let angle = distance(to: other) / Self.earthRadiusKilometers
        guard angle > 1e-6 else { return coordinate }

        let f = min(1, max(0, fraction))
        let a = sin((1 - f) * angle) / sin(angle)
        let b = sin(f * angle) / sin(angle)
        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)
        return CLLocationCoordinate2D(
            latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    func heading(towards other: Airport, fraction: Double) -> Double {
        let start = min(fraction, 0.995)
        let from = coordinate(towards: other, fraction: start)
        let to = coordinate(towards: other, fraction: start + 0.005)
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    func path(towards other: Airport, through fraction: Double = 1, samples: Int = 96) -> [CLLocationCoordinate2D] {
        let end = min(1, max(0, fraction))
        let count = max(2, Int(Double(samples) * end))
        return (0...count).map { coordinate(towards: other, fraction: end * Double($0) / Double(count)) }
    }
}

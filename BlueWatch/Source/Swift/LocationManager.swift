// LocationManager.swift

import Foundation
import CoreLocation
@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let clManager  = CLLocationManager()
    private let geocoder   = CLGeocoder()

    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    // ── GPS forwarding to Bangle.js ────────────────────────────────────────────
    private var gpsTimer: Timer?
    private let gpsInterval: TimeInterval = 12   // seconds between Bangle.GPS events
    private var isForwardingGPS = false

    override init() {
        super.init()
        clManager.delegate = self
        clManager.requestAlwaysAuthorization()
    }

    // MARK: - GPS forwarding

    func startGPSForwarding() {
        guard !isForwardingGPS else { return }
        isForwardingGPS = true
        clManager.desiredAccuracy = kCLLocationAccuracyBest
        clManager.distanceFilter  = kCLDistanceFilterNone
        clManager.startUpdatingLocation()

        gpsTimer = Timer.scheduledTimer(withTimeInterval: gpsInterval, repeats: true) { [weak self] _ in
            self?.sendGPSToBangle()
        }
        print("[GPS] Started forwarding phone GPS to Bangle.js every \(Int(gpsInterval))s")
    }

    func stopGPSForwarding() {
        guard isForwardingGPS else { return }
        isForwardingGPS = false
        gpsTimer?.invalidate()
        gpsTimer = nil
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        clManager.distanceFilter  = kCLDistanceFilterNone
        print("[GPS] Stopped GPS forwarding")
    }

    private func sendGPSToBangle() {
        guard let loc = clManager.location else {
            print("[GPS] No location available yet"); return
        }

        let hasFix   = loc.horizontalAccuracy > 0 && loc.horizontalAccuracy < 100
        let fix      = hasFix ? 1 : 0
        let course   = loc.course  >= 0 ? loc.course  : 0
        let speedKmh = loc.speed   >= 0 ? loc.speed * 3.6 : 0
        let hdop     = max(0.5, min(99.9, loc.horizontalAccuracy / 5.0))

        // Bangle.emit('GPS', {...}) — standard Bangle.js GPS event shape.
        // Any watch app using Bangle.getGPS() or Bangle.on('GPS', cb) receives
        // this as if it came from the watch's own GPS chip.
        let js = """
        Bangle.emit('GPS',{\
        lat:\(loc.coordinate.latitude),\
        lon:\(loc.coordinate.longitude),\
        alt:\(String(format:"%.1f", loc.altitude)),\
        speed:\(String(format:"%.1f", speedKmh)),\
        course:\(String(format:"%.1f", course)),\
        fix:\(fix),\
        satellites:8,\
        hdop:\(String(format:"%.1f", hdop))\
        })
        """

        BLEManager.instance.send(js)
        print("[GPS] Sent fix lat=\(String(format:"%.5f", loc.coordinate.latitude)) " +
              "lon=\(String(format:"%.5f", loc.coordinate.longitude)) " +
              "acc=\(Int(loc.horizontalAccuracy))m")
    }

    // MARK: - Location packet (your existing LocationUpdate)

    func sendLocation() async {
        print("Doing Location Collection from Function")
        guard let location = await getLocation(useCache: false) else { print("Not there");return }
        do {
            print("Got location")
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            let cityName   = placemarks?.first?.locality ?? "Unknown"

            let packet = WatchLocationPacket(
                id:     "LocationUpdate",
                lat:    location.coordinate.latitude,
                lon:    location.coordinate.longitude,
                alt:    location.altitude,
                speed:  location.speed,
                course: location.course,
                city:   cityName
            )

            let jsonData   = try JSONEncoder().encode(packet)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Sending location JSON (\(jsonString.count) bytes)")
                print("JSON: \(jsonString)")
                BLEManager.instance.send(jsonString)
            }
        } catch {
            print("Location Error: \(error)")
        }
    }

    // MARK: - Location retrieval (used by WeatherManager too)

    func getLocation(useCache:Bool) async -> CLLocation? {
        if let lastKnown = clManager.location,
           lastKnown.timestamp.timeIntervalSinceNow > -1800 && useCache {
            print("Using cached location")
            return lastKnown
        }
        do {
            let loc = try await requestCurrentLocation()
            print("Got fresh location")
            return loc
        } catch {
            print("Failed to get location: \(error)")
            return nil
        }
    }

    private var locationContinuations: [CheckedContinuation<CLLocation, Error>] = []

    private func requestCurrentLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuations.append(continuation)
            clManager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let pending = locationContinuations
            locationContinuations.removeAll()
            for c in pending { c.resume(returning: locations.last!) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let pending = locationContinuations
            locationContinuations.removeAll()
            for c in pending { c.resume(throwing: error) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            // Only request once, don't loop
            break
        case .denied, .restricted:
            print("[GPS] Location access denied by user")
        case .authorizedAlways, .authorizedWhenInUse:
            print("[GPS] Location access granted")
        @unknown default:
            break
        }
    }

   
}

// MARK: - Packet type
struct WatchLocationPacket: Encodable {
    let id: String
    let lat: Double
    let lon: Double
    let alt: Double
    let speed: Double
    let course: Double
    let city: String
}

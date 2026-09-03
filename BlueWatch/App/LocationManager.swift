// LocationManager.swift

import Foundation
import CoreLocation
@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let clManager  = CLLocationManager()
    private let geocoder   = CLGeocoder()

    // ── GPS forwarding to Bangle.js ────────────────────────────────────────────
    private var gpsTimer: Timer?
    private let gpsInterval: TimeInterval = 6   // seconds between Bangle.GPS events
    private var isForwardingGPS = false
    private var settings = Settings.shared
    private var cachedLocation: CLLocation?
    private var locationRequestInProgress = false
    private var locationRequestTimeoutTask: Task<Void, Never>?
    override init() {
        super.init()
        clManager.delegate = self
        //requestAuthorization()
    }
    
    func requestAuthorization(){
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
            Task{
               await self?.sendLocation()
            }
        }
        logger.log("[GPS] Started forwarding phone GPS to Bangle.js every \(Int(self.gpsInterval))s")
    }

    func stopGPSForwarding() {
        guard isForwardingGPS else { return }
        isForwardingGPS = false
        gpsTimer?.invalidate()
        gpsTimer = nil
        // Cancel any pending continuations so requestCurrentLocation doesn't restart things
        let pending = locationContinuations
        locationContinuations.removeAll()
        for c in pending { c.resume(throwing: CancellationError()) }
        clManager.stopUpdatingLocation()
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        logger.log("[GPS] Stopped GPS forwarding")
    }

   

    // MARK: - Location packet (your existing LocationUpdate)

    func sendLocation() async {
        logger.log("Doing Location Collection from Function")
        
        let location: CLLocation?
        if isForwardingGPS {
            // Already have continuous updates running, just read the latest
            location = clManager.location
        } else {
            location = await getLocation(useCache: false)
        }
        
        guard let location else { logger.log("Not there"); return }
       
    
        logger.log("Got location")
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        let cityName  = placemarks?.first?.locality ?? "undefined"
        let hasFix   = location.horizontalAccuracy > 0 && location.horizontalAccuracy < 100
        let fix      = hasFix ? 1 : 0
        let course   = location.course  >= 0 ? location.course  : 0
        let speedKmh = location.speed   >= 0 ? location.speed * 3.6 : 0
        let hdop     = max(0.5, min(99.9, location.horizontalAccuracy / 5.0))
        let packet = LocationPacket(
            id: "GPS",
            lat:location.coordinate.latitude ,
            lon: location.coordinate.longitude,
            alt: round(location.altitude*10)/10,
            speed: round(speedKmh*10)/10,
            course: round(course*10)/10,
            fix: fix,
            satellites: 8,
            hdop: round(hdop*10)/10,
            city: cityName)
        BLEManager.shared.sendJSON(data: packet)
              
        
    }
    // MARK: - Packet type
    struct LocationPacket: Codable {
        let id: String
        let lat: Double
        let lon: Double
        let alt: Double
        let speed: Double
        let course: Double
        let fix: Int
        let satellites: Int
        let hdop: Double
        let city: String
    }

    // MARK: - Location retrieval (used by WeatherManager too)

    func getLocation(useCache: Bool) async -> CLLocation? {
        await AuthManager.shared.requestLocationAuth()
        if useCache,
           let cachedLocation = cachedLocation,
           let lastUpdate = UserDefaults.standard.object(forKey: "lastLocationUpdate") as? Date {

            let age = Date().timeIntervalSince(lastUpdate)
            let cacheLifetime = TimeInterval(settings.locationRateLimit * 60)

            if age < cacheLifetime {
                logger.log("Using cached location; age \(Int(age / 60)) minutes")
                return cachedLocation
            }

            logger.log("Cached location expired; requesting fresh location")
        } else if useCache {
            logger.log("No valid cached location; requesting fresh location")
        } else {
            logger.log("Fresh location explicitly requested")
        }

        do {
            let location = try await requestCurrentLocation()
            logger.log("Got fresh location")
            cachedLocation = location
            UserDefaults.standard.set(Date(), forKey: "lastLocationUpdate")
            return location
        } catch {
            logger.log("Failed to get location: \(error)")
            return nil
        }
    }

    private var locationContinuations: [CheckedContinuation<CLLocation, Error>] = []

    private func requestCurrentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuations.append(continuation)

            if locationRequestInProgress {
                logger.log("Location request already in progress; joining existing request")
                return
            }

            locationRequestInProgress = true
            logger.log("Starting Core Location request")

            clManager.requestLocation()

            locationRequestTimeoutTask?.cancel()
            locationRequestTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))

                guard !Task.isCancelled else { return }
                guard let self, self.locationRequestInProgress else { return }

                logger.log("Location request timed out")

                self.locationRequestInProgress = false
                self.locationRequestTimeoutTask = nil

                let continuations = self.locationContinuations
                self.locationContinuations.removeAll()

                for continuation in continuations {
                    continuation.resume(throwing: LocationError.timeout)
                }
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            logger.log("Core Location returned no locations")
            return
        }

        Task { @MainActor in
            logger.log("Core Location returned location: \(location.coordinate.latitude), \(location.coordinate.longitude)")

            self.cachedLocation = location
            UserDefaults.standard.set(Date(), forKey: "lastLocationUpdate")

            self.locationRequestTimeoutTask?.cancel()
            self.locationRequestTimeoutTask = nil

            self.locationRequestInProgress = false

            let continuations = self.locationContinuations
            self.locationContinuations.removeAll()

            for continuation in continuations {
                continuation.resume(returning: location)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            logger.log("Core Location failed: \(error)")

            self.locationRequestTimeoutTask?.cancel()
            self.locationRequestTimeoutTask = nil

            self.locationRequestInProgress = false

            let continuations = self.locationContinuations
            self.locationContinuations.removeAll()

            for continuation in continuations {
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            // Only request once, don't loop
            break
        case .denied, .restricted:
            logger.log("[GPS] Location access denied by user")
        case .authorizedAlways, .authorizedWhenInUse:
            logger.log("[GPS] Location access granted")
        @unknown default:
            break
        }
    }

   
}

private enum LocationError: Error {
    case timeout
}

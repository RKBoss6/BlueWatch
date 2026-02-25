import Foundation
import UIKit
import WeatherKit
import CoreLocation
import UserNotifications
class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherManager()
    private let locationManager = CLLocationManager()
    private let service = WeatherService.shared
    private let geocoder = CLGeocoder()
    
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    func requestNotifPermission(){
        // Request authorization in AppDelegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

    }
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
    }
    
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }

    func updateWeatherAndSend() async {
        print("Starting weather update...")
        
        // 1. Get Location safely
        let location: CLLocation
        if let lastKnown = locationManager.location,
           lastKnown.timestamp.timeIntervalSinceNow > -1800 {
            location = lastKnown
            print("Using cached location")
        } else {
            do {
                location = try await requestCurrentLocation()
                print("Got fresh location")
            } catch {
                print("Failed to get location: \(error)")
                return
            }
        }

        do {
            requestNotifPermission()
            let (current, daily) = try await service.weather(for: location, including: .current, .daily)
            
            // Reverse Geocode (Optional: Cache this)
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            let cityName = placemarks?.first?.locality ?? "Unknown"
            
            guard let today = daily.first else {
                print("No daily forecast available")
                return
            }
            
            let iconCode = getIconCode(condition: current.condition)
            
            let packet = WatchWeatherPacket(
                id: "WeatherUpdate",
                temp: Int(current.temperature.converted(to: .fahrenheit).value),
                feels: Int(current.apparentTemperature.converted(to: .fahrenheit).value),
                hi: Int(today.highTemperature.converted(to: .fahrenheit).value),
                lo: Int(today.lowTemperature.converted(to: .fahrenheit).value),
                hum: Int(current.humidity * 100),
                rain: Int(today.precipitationChance * 100),
                uv: current.uvIndex.value,
                wind: Int(current.wind.speed.converted(to: .milesPerHour).value),
                code: iconCode,
                txt: current.condition.description,
                wdir: current.wind.compassDirection,
                loc: cityName
            )
            
            let jsonData = try JSONEncoder().encode(packet)
            
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                pushNotification(title: "weather", subtitle: String(data: jsonData, encoding: .utf8)!, body: "", id: "BlueWatch")
                print("Sending weather JSON (\(jsonString.count) bytes)")
                print("JSON: \(jsonString)")
                
                // CRITICAL FIX: Use sendJSON instead of send to avoid wrapping in quotes
                BLEManager.shared.send(jsonString)
            }

        } catch {
            print("Weather Error: \(error)")
        }
    }
    
    private func requestCurrentLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
     func pushNotification(title:String,subtitle:String,body:String,id:String){
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = subtitle
            content.sound = UNNotificationSound.default

            // Schedule for 5 seconds from now (example)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error adding notification: \(error)")
                }
            }
            print("pushed")
        }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location failed: \(error)")
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}

// MARK: - Icon Logic
extension WeatherManager {
    func getIconCode(condition: WeatherCondition) -> Int {
        switch condition {
        case .blizzard, .blowingSnow, .flurries, .snow, .heavySnow, .frigid:
            return 601
        case .rain, .sunShowers, .heavyRain:
            return 501
        case .drizzle, .freezingDrizzle, .sleet, .freezingRain:
            return 301
        case .thunderstorms, .isolatedThunderstorms, .strongStorms:
            return 202
        case .cloudy, .mostlyCloudy:
            return 803
        case .partlyCloudy:
            return 802
        case .clear, .mostlyClear:
            return 800
        case .foggy, .haze, .smoky:
            return 741
        case .breezy, .windy, .hurricane, .tropicalStorm:
            return 801
        default:
            return 800
        }
    }
}

extension Wind {
    var compassDirection: String {
        let degrees = self.direction.converted(to: .degrees).value
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5)
        return directions[index % 16]
    }
}

struct WatchWeatherPacket: Encodable {
    let id: String
    let temp: Int
    let feels: Int
    let hi: Int
    let lo: Int
    let hum: Int
    let rain: Int
    let uv: Int
    let wind: Int
    let code: Int
    let txt: String
    let wdir: String
    let loc: String
}

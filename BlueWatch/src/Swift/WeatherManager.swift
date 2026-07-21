// WeatherManager.swift

import Foundation
import UIKit
import WeatherKit
import CoreLocation
import UserNotifications

class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    private let service  = WeatherService.shared
    private let geocoder = CLGeocoder()
    private let settings = Settings.instance
    // MARK: - Permissions

    
    // MARK: - Weather update
    
    
    func updateWeatherAndSend() async {
        logger.log("Starting weather update...")

        // Retrieve the last update date from UserDefaults safely
        let lastDate = UserDefaults.standard.object(forKey: "lastWeatherUpdate") as? Date

        // If we have a last date and the elapsed time is less than the rate limit set, cancel request
        if let last = lastDate, let diff = Utils.minutesBetweenDates(last, toDate: Date()), diff < Int(settings.weatherRateLimit) {
            logger.log("Skipping weather update; only \(diff) minutes since last update.")
            return;
        }
        UserDefaults.standard.set(Date(), forKey: "lastWeatherUpdate")
        
        
        guard let location = await LocationManager.shared.getLocation(useCache: true) else { return }
        
        do {
            let (current, daily) = try await service.weather(
                for: location, including: .current, .daily
            )

            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            let cityName   = placemarks?.first?.locality ?? "Unknown"

            guard let today = daily.first else {
                logger.log("No daily forecast available"); return
            }
            // Record this update time immediately for rate limiting
            UserDefaults.standard.set(Date(), forKey: "lastWeatherUpdate")

            let packet = WatchWeatherPacket(
                id:    "WeatherUpdate",
                temp:  Int(current.temperature.converted(to: .kelvin).value),
                feels: Int(current.apparentTemperature.converted(to: .kelvin).value),
                hi:    Int(today.highTemperature.converted(to: .kelvin).value),
                lo:    Int(today.lowTemperature.converted(to: .kelvin).value),
                hum:   Int(current.humidity * 100),
                rain:  Int(today.precipitationChance * 100),
                uv:    current.uvIndex.value,
                wind:  Int(current.wind.speed.converted(to: .kilometersPerHour).value),
                code:  getIconCode(condition: current.condition),
                txt:   current.condition.description,
                wdir:  Int(current.wind.direction.value),
                loc:   cityName
            )

            let jsonData = try JSONEncoder().encode(packet)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                logger.log("Sending weather JSON (\(jsonString.count) bytes)")
                logger.log("JSON: \(jsonString)")
                BLEManager.instance.send(jsonString)
                
            }
        } catch {
            logger.log("Weather Error: \(error)")
        }
    }

    // MARK: - Icon mapping

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

// MARK: - Wind compass
extension Wind {
    var compassDirection: String {
        let degrees = self.direction.converted(to: .degrees).value
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0)
        return directions[index % 8]
    }
}

// MARK: - Packet type
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
    let wdir: Int
    let loc: String
}

//
//  WeatherLocationManager.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 1/6/26.
//

import Foundation
import CoreLocation
import WeatherKit

struct WeatherPayload: Codable {
    let latitude: Double
    let longitude: Double
    let city: String?
    let region: String?
    let temperatureC: Double
    let condition: String
    let symbol: String
    let timestamp: Date
}

extension WeatherPayload {
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try? String(
            data: encoder.encode(self),
            encoding: .utf8
        )
    }
}

struct LocationPayload: Codable {
    let latitude: Double
    let longitude: Double
    let city: String?
    let region: String?
    let temperatureC: Double
    let condition: String
    let symbol: String
    let timestamp: Date
}
extension LocationPayload {
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try? String(
            data: encoder.encode(self),
            encoding: .utf8
        )
    }
}

@MainActor
final class WeatherLocationService: NSObject {

    static let shared = WeatherLocationService()

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let weatherService = WeatherService.shared

    private var locationContinuation:
        CheckedContinuation<CLLocation, Error>?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public API

    func getWeatherAndLocation() async throws -> WeatherPayload {

        let location = try await requestLocation()
        let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        let weather = try await weatherService.weather(for: location)

        return WeatherPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            city: placemark?.locality,
            region: placemark?.administrativeArea,
            temperatureC: weather.currentWeather.temperature.value,
            condition: weather.currentWeather.condition.description,
            symbol: weather.currentWeather.symbolName,
            timestamp: Date()
        )
    }
}

extension WeatherLocationService: CLLocationManagerDelegate {

    func requestLocation() async throws -> CLLocation {

        let status = locationManager.authorizationStatus

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}


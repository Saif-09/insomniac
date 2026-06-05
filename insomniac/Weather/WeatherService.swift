//
//  WeatherService.swift
//  insomniac
//
//  Fetches current temperature from Open-Meteo (FR-15/16): free, key-less, no
//  account. Weather is a soft modifier and always degrades gracefully (FR-17) —
//  every failure path returns nil rather than throwing into the advisory.
//

import Foundation
import Observation

@MainActor
@Observable
final class WeatherService {
    /// Most recent temperature in °C, or nil if unknown/unavailable.
    private(set) var currentCelsius: Double?
    /// When the last successful reading was taken.
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Refresh the temperature for a coordinate. Never throws; on failure it
    /// records `lastError` and leaves `currentCelsius` as-is.
    func refresh(latitude: Double, longitude: Double) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
        ]
        guard let url = components.url else {
            lastError = "Bad weather URL."
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = "Weather server unavailable."
                return
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            currentCelsius = decoded.current.temperature_2m
            lastUpdated = Date()
            lastError = nil
        } catch {
            lastError = "Couldn't reach weather service."
        }
    }

    // Open-Meteo's current-weather payload shape.
    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
        }
        let current: Current
    }
}

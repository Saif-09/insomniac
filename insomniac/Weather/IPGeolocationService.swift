//
//  IPGeolocationService.swift
//  insomniac
//
//  Approximate, permission-free location from the device's public IP, used to
//  bootstrap coordinates for the weather lookup (FR-16). This replaces
//  CoreLocation: a menu-bar (LSUIElement) app can't reliably surface the
//  location-permission prompt, and city-level accuracy is plenty for a soft
//  ambient nudge. No API key, no prompt — degrades gracefully to nil.
//
//  Privacy: this sends the device's public IP to a third-party geolocation
//  provider to estimate the city. No GPS, no account. Only the resulting
//  approximate coordinates are then sent to Open-Meteo for the temperature.
//

import Foundation

struct IPLocation {
    let latitude: Double
    let longitude: Double
    /// Human-readable area (city/region/country), best-effort.
    let area: String?
}

final class IPGeolocationService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Best-effort approximate location. Tries GeoJS, then freeipapi.com.
    /// Never throws; returns nil on total failure so weather stays optional.
    func currentLocation() async -> IPLocation? {
        if let location = await fetchGeoJS() { return location }
        return await fetchFreeIPAPI()
    }

    // MARK: - Providers

    private func fetchGeoJS() async -> IPLocation? {
        guard let url = URL(string: "https://get.geojs.io/v1/ip/geo.json"),
              let data = await get(url),
              let response = try? JSONDecoder().decode(GeoJSResponse.self, from: data) else {
            return nil
        }
        return response.toLocation()
    }

    private func fetchFreeIPAPI() async -> IPLocation? {
        guard let url = URL(string: "https://freeipapi.com/api/json"),
              let data = await get(url),
              let response = try? JSONDecoder().decode(FreeIPAPIResponse.self, from: data) else {
            return nil
        }
        return response.toLocation()
    }

    private func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return data
    }

    // MARK: - Response shapes

    // GeoJS returns latitude/longitude as STRINGS.
    private struct GeoJSResponse: Decodable {
        let city: String?
        let region: String?
        let country: String?
        let latitude: String
        let longitude: String

        func toLocation() -> IPLocation? {
            guard let lat = Double(latitude), let lon = Double(longitude) else { return nil }
            return IPLocation(latitude: lat, longitude: lon, area: city ?? region ?? country)
        }
    }

    // freeipapi.com returns latitude/longitude as numbers.
    private struct FreeIPAPIResponse: Decodable {
        let cityName: String?
        let regionName: String?
        let countryName: String?
        let latitude: Double?
        let longitude: Double?

        func toLocation() -> IPLocation? {
            guard let lat = latitude, let lon = longitude else { return nil }
            return IPLocation(latitude: lat, longitude: lon, area: cityName ?? regionName ?? countryName)
        }
    }
}

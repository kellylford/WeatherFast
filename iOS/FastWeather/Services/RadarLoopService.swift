//
//  RadarLoopService.swift
//  Fast Weather
//
//  Fetches the NWS RIDGE animated radar loop for a city's nearest NEXRAD
//  station and hands back the individual frames as images.
//
//  Why individual frames and not a map tile overlay: VoiceOver's Image
//  Explorer can only describe an *image* element. A MapKit tile overlay is
//  not one, so a tile-based radar is invisible to it. The RIDGE GIFs are also
//  the exact images that scored well in the Image Explorer testing — they
//  carry city labels, the warning legend, the dBZ scale and a timestamp,
//  which is what makes them describable in the first place.
//
//  Data: NOAA/NWS NEXRAD base reflectivity, public domain.
//

import Foundation
import UIKit
import ImageIO

/// A NEXRAD radar station near a city.
struct RadarLoopStation {
    let id: String
    let name: String
    let distanceKm: Double
}

/// A fetched radar loop: the frames plus where they came from.
struct RadarLoop {
    /// Frames in chronological order — `frames.last` is the most recent.
    let frames: [UIImage]
    let station: RadarLoopStation
    let fetchedAt: Date
}

enum RadarLoopResult {
    case success(RadarLoop)
    /// The city is outside NEXRAD coverage (or too far from any station to
    /// appear in its image at all).
    case noCoverage(String)
    case failure(String)
}

/// Loads NWS RIDGE radar loops.
final class RadarLoopService {
    static let shared = RadarLoopService()
    private init() {}

    /// A RIDGE standard image covers roughly a 248 km radius around its
    /// station. Beyond that the city is literally not in the picture, so we
    /// say "no coverage" rather than showing a map the user isn't on.
    private static let maxUsefulDistanceKm: Double = 300

    private static let userAgent = "WeatherFast (weatherfast.online)"

    /// Cached station list — the NWS list is large and effectively static.
    private var cachedStations: [Station]?

    private struct Station {
        let id: String
        let name: String
        let lat: Double
        let lon: Double
    }

    // MARK: - Public

    func loadLoop(for city: City) async -> RadarLoopResult {
        guard let station = await nearestStation(lat: city.latitude, lon: city.longitude) else {
            return .failure("Could not reach the National Weather Service station list.")
        }

        guard station.distanceKm <= Self.maxUsefulDistanceKm else {
            return .noCoverage(
                "\(city.name) is outside NEXRAD radar coverage. The nearest station, "
                + "\(station.name), is \(Int(station.distanceKm.rounded())) km away — "
                + "too far for this city to appear on its radar image. "
                + "NEXRAD covers the United States only.")
        }

        guard let frames = await downloadLoopFrames(stationId: station.id), !frames.isEmpty else {
            return .failure("Could not download the radar loop for station \(station.id).")
        }

        return .success(RadarLoop(frames: frames, station: station, fetchedAt: Date()))
    }

    // MARK: - Station lookup

    private func nearestStation(lat: Double, lon: Double) async -> RadarLoopStation? {
        guard let stations = await stationList() else { return nil }

        var best: Station?
        var bestDist = Double.infinity
        for s in stations {
            let d = haversineKm(lat1: lat, lon1: lon, lat2: s.lat, lon2: s.lon)
            if d < bestDist {
                bestDist = d
                best = s
            }
        }
        guard let s = best else { return nil }
        return RadarLoopStation(id: s.id, name: s.name, distanceKm: bestDist)
    }

    private func stationList() async -> [Station]? {
        if let cached = cachedStations { return cached }

        let url = URL(string: "https://api.weather.gov/radar/stations")!
        var request = URLRequest(url: url)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            AppLogger.network.error("Radar loop: station list fetch failed")
            return nil
        }

        var out: [Station] = []
        for feature in features {
            guard let props = feature["properties"] as? [String: Any],
                  let sid = props["id"] as? String,
                  let geometry = feature["geometry"] as? [String: Any],
                  let coords = geometry["coordinates"] as? [Double], coords.count >= 2
            else { continue }

            // Only WSR-88D sites have RIDGE imagery. Filtering on stationType
            // rather than an ID prefix matters: it keeps the Alaska (PA*),
            // Hawaii (PH*) and Puerto Rico (TJUA) sites, and drops the 45
            // TDWR stations, which also start with T.
            guard (props["stationType"] as? String) == "WSR-88D" else { continue }

            out.append(Station(id: sid.uppercased(),
                               name: props["name"] as? String ?? sid,
                               lat: coords[1], lon: coords[0]))
        }

        guard !out.isEmpty else { return nil }
        cachedStations = out
        return out
    }

    // MARK: - Loop download

    private func downloadLoopFrames(stationId: String) async -> [UIImage]? {
        let sid = stationId.uppercased()
        let candidates = [
            "https://radar.weather.gov/ridge/standard/\(sid)_loop.gif",
            "https://radar.weather.gov/ridge/standard/\(sid.lowercased())_loop.gif",
        ]

        for urlString in candidates {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count > 1000,
                  let frames = extractGIFFrames(data: data), !frames.isEmpty else { continue }

            AppLogger.network.debug("Radar loop: \(frames.count) frames from \(sid)")
            return frames
        }
        AppLogger.network.error("Radar loop: no loop GIF for station \(sid)")
        return nil
    }

    /// Every frame of the animated GIF, in file order (oldest first).
    private func extractGIFFrames(data: Data) -> [UIImage]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        for i in 0..<count {
            if let cg = CGImageSourceCreateImageAtIndex(source, i, nil) {
                frames.append(UIImage(cgImage: cg))
            }
        }
        return frames.isEmpty ? nil : frames
    }

    // MARK: - Geometry

    private func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

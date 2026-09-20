//
//  CanadianRadarService.swift
//  Fast Weather
//
//  One Canadian radar site's own picture, the counterpart to NWS RIDGE.
//
//  ECCC publishes a finished GIF per site per scan on the MSC Datamart:
//  basemap, lakes, provincial boundaries, the site name, the valid time in
//  UTC, a distance scale and a colour legend, all flattened into the image —
//  which is exactly what makes it describable. Unlike RIDGE there is no
//  ready-made loop, so the loop is assembled here from consecutive scans.
//
//  Two details worth keeping:
//
//  • The filenames carry the valid time, so frame times here are read rather
//    than inferred — better than the RIDGE path, which has to derive them
//    from a Last-Modified header.
//  • Each scan is published twice, in the standard palette and in an "A11Y"
//    one built for colour vision deficiency. The app takes the A11Y variant:
//    same radar, a palette chosen so the intensities stay distinguishable.
//
//  Radar: Environment and Climate Change Canada, Open Government Licence –
//  Canada.
//

import Foundation
import UIKit

final class CanadianRadarService {
    static let shared = CanadianRadarService()
    private init() {}

    private static let userAgent = "WeatherFast (weatherfast.online)"
    private static let root = "https://dd.weather.gc.ca"

    /// Scans land on a six-minute clock, the same cadence as the composite.
    private static let scanInterval: TimeInterval = 6 * 60
    /// Ten frames is an hour of weather, and matches the RIDGE loop's length.
    private static let wantedFrames = 10
    /// Stop looking after this many scans back. The newest scan is often not
    /// published yet, and a site can miss one, but a long gap means trouble
    /// rather than something worth waiting for.
    private static let maxAttempts = 16

    /// Rain first: in a Canadian winter the snow product is the one that
    /// exists, so a site with no rain scan is asked for snow before giving up.
    private static let products = ["CAPPI_1.5_RAIN_A11Y", "CAPPI_1.0_SNOW_A11Y"]

    func loadLoop(forStation station: RadarStationInfo) async -> RadarLoopResult {
        var frames: [UIImage] = []
        var times: [Date] = []

        let newest = Date(timeIntervalSince1970:
            (Date().timeIntervalSince1970 / Self.scanInterval).rounded(.down) * Self.scanInterval)

        var attempt = 0
        while frames.count < Self.wantedFrames && attempt < Self.maxAttempts {
            let time = newest.addingTimeInterval(-Double(attempt) * Self.scanInterval)
            attempt += 1
            if let image = await fetchScan(site: station.id, time: time) {
                frames.append(image)
                times.append(time)
            }
        }

        guard !frames.isEmpty else {
            return .failure("Could not download radar for \(station.name). "
                          + "Environment and Climate Change Canada may not have "
                          + "published a recent scan for this site.")
        }

        AppLogger.network.debug("ECCC site radar: \(frames.count) frames from \(station.id)")

        // Collected newest first; the rest of the app expects oldest first.
        return .success(RadarLoop(
            frames: frames.reversed(),
            frameTimes: times.reversed(),
            station: RadarLoopStation(id: station.id, name: station.name, distanceKm: nil),
            sourceName: "ECCC radar site",
            attribution: "Radar: Environment and Climate Change Canada",
            fetchedAt: Date()))
    }

    private func fetchScan(site: String, time: Date) async -> UIImage? {
        let stamp = Self.stampFormatter.string(from: time)
        let day = String(stamp.prefix(8))
        for product in Self.products {
            let path = "\(Self.root)/\(day)/WXO-DD/radar/CAPPI/GIF/\(site)/"
                     + "\(stamp)_\(site)_\(product).gif"
            guard let url = URL(string: path) else { continue }
            if let image = await RadarMapCompositor.fetchImage(url, userAgent: Self.userAgent) {
                return image
            }
        }
        return nil
    }

    /// Filenames are stamped in UTC: 202609201400_CASBV_CAPPI_1.5_RAIN_A11Y.gif
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

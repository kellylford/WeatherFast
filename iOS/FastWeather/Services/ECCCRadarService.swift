//
//  ECCCRadarService.swift
//  Fast Weather
//
//  Environment and Climate Change Canada's radar, via the MSC GeoMet WMS.
//
//  Despite the name this is a NORTH AMERICAN composite: Canada's radars and
//  the American ones together, up to 180 sites, 1 km, rebuilt every 6 minutes.
//  Two things make it worth having beside the other sources:
//
//    • It is the only one that covers Canada at all.
//    • It keeps three hours, against 55 minutes from IEM and 18 from RIDGE.
//      Three hours is the difference between seeing that it is raining and
//      seeing where the rain has come from.
//
//  Unlike IEM's tiles this is one image per request, cut to exactly the
//  rectangle asked for — so a frame is one fetch, not a dozen. Rain and snow
//  are separate layers and GeoMet refuses more than one layer per request, so
//  each frame costs two: rain, then snow drawn over it.
//
//  Radar: Environment and Climate Change Canada, Open Government Licence –
//  Canada. Basemap: Apple.
//

import Foundation
import UIKit
import MapKit

final class ECCCRadarService {
    static let shared = ECCCRadarService()
    private init() {}

    private static let userAgent = "WeatherFast (weatherfast.online)"
    private static let endpoint = "https://geo.weather.gc.ca/geomet"

    /// GeoMet holds three hours at six-minute steps and rejects any time that
    /// is not one of them — an off-grid minute comes back "time outside valid
    /// hours", not a nearby frame — so the times are read from the service
    /// rather than guessed, and sampled at a multiple of its own step.
    /// Eleven frames every eighteen minutes spans the window; all thirty-one
    /// would be smoother and nearly three times the requests for a picture
    /// that barely moves between them.
    private static let frameCount = 11
    private static let frameStride = 3          // × the service's own step

    /// Rain and snow are drawn by separate layers. Snow goes on last so a
    /// changeover line reads as snow rather than being hidden under the rain.
    private static let rainLayer = "RADAR_1KM_RRAI"
    private static let snowLayer = "RADAR_1KM_RSNO"
    /// Shades everywhere no radar can see, which is the difference between
    /// "nothing is falling" and "nobody is looking".
    private static let noCoverageLayer = "RADAR_COVERAGE_RRAI.INV"

    // MARK: - Public

    func loadLoop(for city: City, area: RadarArea = .local) async -> RadarLoopResult {
        let region = RadarMapCompositor.squareRegion(
            center: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            latitudeSpan: area.latitudeSpan)

        guard let snapshot = await RadarMapCompositor.makeBasemap(region: region) else {
            return .failure("Could not render the map for \(city.name).")
        }

        guard let extent = await timeExtent() else {
            return .failure("Could not reach Environment and Climate Change Canada's radar service.")
        }

        // The basemap and the out-of-coverage shading are the same in every
        // frame, so they are fetched once and redrawn, not refetched eleven times.
        let bbox = Self.mercatorBBox(region)
        let noCoverage = await RadarMapCompositor.fetchImage(
            Self.url(layer: Self.noCoverageLayer, bbox: bbox, time: nil), userAgent: Self.userAgent)

        var frames: [UIImage] = []
        var times: [Date] = []

        for time in Self.frameTimes(in: extent) {
            let rain = await RadarMapCompositor.fetchImage(
                Self.url(layer: Self.rainLayer, bbox: bbox, time: time), userAgent: Self.userAgent)
            let snow = await RadarMapCompositor.fetchImage(
                Self.url(layer: Self.snowLayer, bbox: bbox, time: time), userAgent: Self.userAgent)
            guard rain != nil || snow != nil else { continue }

            let base = snapshot.image
            let renderer = UIGraphicsImageRenderer(size: base.size)
            let frame = renderer.image { _ in
                let rect = CGRect(origin: .zero, size: base.size)
                base.draw(in: rect)
                noCoverage?.draw(in: rect, blendMode: .normal, alpha: 0.55)
                rain?.draw(in: rect, blendMode: .normal, alpha: 0.85)
                snow?.draw(in: rect, blendMode: .normal, alpha: 0.85)
                RadarMapCompositor.drawCityMarker(named: city.name, size: base.size)
                RadarMapCompositor.drawMapAttribution(size: base.size)
            }
            frames.append(frame)
            times.append(time)
        }

        guard !frames.isEmpty else {
            return .failure("Could not download radar from Environment and Climate Change Canada.")
        }

        AppLogger.network.debug("ECCC radar: \(frames.count) frames for \(city.name)")

        return .success(RadarLoop(
            frames: frames,
            frameTimes: times,
            station: nil,                    // a composite has no single station
            sourceName: "ECCC composite",
            attribution: "Radar: Environment and Climate Change Canada · Map: Apple",
            fetchedAt: Date()))
    }

    // MARK: - Request building

    /// Oldest first, to match the other sources, and never older than the
    /// window the service says it holds — its oldest frame ages out while the
    /// user is looking at it.
    private static func frameTimes(in extent: TimeExtent) -> [Date] {
        let stride = extent.step * Double(frameStride)
        let span = extent.end.timeIntervalSince(extent.start)
        let count = min(frameCount, Int(span / stride) + 1)
        return (0..<count).reversed().map { extent.end.addingTimeInterval(-Double($0) * stride) }
    }

    // MARK: - Time dimension

    struct TimeExtent {
        let start: Date
        let end: Date
        let step: TimeInterval
    }

    private var cachedExtent: (value: TimeExtent, fetchedAt: Date)?

    /// The layer's published time dimension, e.g.
    /// `2026-09-20T10:42:00Z/2026-09-20T13:42:00Z/PT6M`. Held briefly: it moves
    /// forward every six minutes, but not between two frames of one loop.
    private func timeExtent() async -> TimeExtent? {
        if let cachedExtent, Date().timeIntervalSince(cachedExtent.fetchedAt) < 120 {
            return cachedExtent.value
        }

        let url = URL(string: "\(Self.endpoint)?service=WMS&version=1.3.0"
                             + "&request=GetCapabilities&LAYERS=\(Self.rainLayer)")!
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let xml = String(data: data, encoding: .utf8) else {
            AppLogger.network.error("ECCC radar: capabilities fetch failed")
            return nil
        }

        guard let match = xml.firstMatch(of: #/(?<start>\d{4}-\d{2}-\d{2}T[\d:]+Z)\/(?<end>\d{4}-\d{2}-\d{2}T[\d:]+Z)\/PT(?<minutes>\d+)M/#),
              let start = Self.wmsTime.date(from: String(match.start)),
              let end = Self.wmsTime.date(from: String(match.end)),
              let minutes = Double(String(match.minutes)), minutes > 0 else {
            AppLogger.network.error("ECCC radar: no time dimension in capabilities")
            return nil
        }

        let extent = TimeExtent(start: start, end: end, step: minutes * 60)
        cachedExtent = (extent, Date())
        return extent
    }

    private static let wmsTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func url(layer: String, bbox: String, time: Date?) -> URL {
        var query = "service=WMS&version=1.3.0&request=GetMap"
            + "&layers=\(layer)&crs=EPSG:3857&bbox=\(bbox)"
            + "&width=\(Int(RadarMapCompositor.imageSize))&height=\(Int(RadarMapCompositor.imageSize))"
            + "&format=image/png&transparent=true"
        if let time { query += "&time=\(wmsTime.string(from: time))" }
        return URL(string: "\(endpoint)?\(query)")!
    }

    /// GeoMet wants the box in Web Mercator metres, west,south,east,north.
    private static func mercatorBBox(_ region: MKCoordinateRegion) -> String {
        let west  = region.center.longitude - region.span.longitudeDelta / 2
        let east  = region.center.longitude + region.span.longitudeDelta / 2
        let south = region.center.latitude  - region.span.latitudeDelta / 2
        let north = region.center.latitude  + region.span.latitudeDelta / 2
        let (x0, y0) = mercator(lat: south, lon: west)
        let (x1, y1) = mercator(lat: north, lon: east)
        return "\(x0),\(y0),\(x1),\(y1)"
    }

    private static func mercator(lat: Double, lon: Double) -> (Double, Double) {
        let x = lon * 20037508.34 / 180
        let y = log(tan((90 + lat) * .pi / 360)) / (.pi / 180) * 20037508.34 / 180
        return (x, y)
    }
}

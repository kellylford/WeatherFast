//
//  IEMRadarService.swift
//  Fast Weather
//
//  The other way to get a radar loop, for comparison against NWS RIDGE.
//
//  RIDGE hands you a finished picture: basemap, roads, city labels, echoes,
//  NOAA header and legend, all flattened into one GIF. You show it and you're
//  done — which is exactly why VoiceOver's Image Explorer can read it.
//
//  IEM hands you only the echoes: NEXRAD base reflectivity as transparent Web
//  Mercator tiles, no geography at all. On its own it is undescribable — just
//  coloured blobs in a void. So this service has to *be* the cartographer:
//  take a MapKit basemap, composite the reflectivity on top, and mark the
//  user's city, before there is anything worth describing.
//
//  What that buys, measured 2026-09-06:
//
//    RIDGE   10 frames, 2 min apart, 18 minutes, one station, fixed framing
//    IEM     12 frames, 5 min apart, 55 minutes, CONUS composite, any framing
//
//  So IEM trades time resolution for three times the history, loses the
//  single-station edge, and lets the city sit in the middle of the picture
//  instead of wherever it happens to fall relative to the radar tower.
//
//  Forecast frames (behind the radarForecastEnabled flag): IEM also renders
//  NOAA's HRRR model "simulated reflectivity" — the model's picture of what
//  radar will show — as tiles in the same projection and palette. This is
//  what other apps call "future radar". It is a model guess, not a
//  measurement, so every forecast frame is stamped as such on the image.
//
//  Radar: NOAA/NWS NEXRAD base reflectivity (N0Q) via Iowa Environmental
//  Mesonet — public domain data, university-hosted service. Forecast: NOAA
//  HRRR, public domain, same service. Basemap: Apple.
//

import Foundation
import UIKit
import MapKit

/// How much of the country the Composite picture shows. The mosaic itself
/// covers the whole contiguous US; this is the square cut out around the city.
enum RadarArea: String, CaseIterable, Identifiable {
    case local
    case regional

    var id: String { rawValue }

    var name: String {
        switch self {
        case .local:    return "Local"
        case .regional: return "Regional"
        }
    }

    /// Degrees of latitude from the top of the picture to the bottom.
    /// A degree of latitude is about 111 km anywhere on Earth, so this fixes
    /// the north-south distance; MapKit then widens longitude to keep it square.
    var latitudeSpan: Double {
        switch self {
        case .local:    return 2.0   // ~222 km / ~138 mi
        case .regional: return 5.8   // ~644 km / ~400 mi
        }
    }

    var kilometresAcross: Double { latitudeSpan * 111.0 }

    /// "about 140 miles", rounded to the nearest 10 in the user's unit.
    func across(_ unit: DistanceUnit) -> String {
        Self.phrase(kilometresAcross, unit)
    }

    /// Distance from the city to each edge: half the width.
    func toEachEdge(_ unit: DistanceUnit) -> String {
        Self.phrase(kilometresAcross / 2, unit)
    }

    private static func phrase(_ km: Double, _ unit: DistanceUnit) -> String {
        let value = Int((unit.convert(km) / 10).rounded()) * 10
        return "about \(value) " + (unit == .miles ? "miles" : "kilometres")
    }
}

final class IEMRadarService {
    static let shared = IEMRadarService()
    private init() {}

    private static let userAgent = "WeatherFast (weatherfast.online)"

    /// IEM publishes the current layer plus `-m05m` … `-m55m` in five-minute
    /// steps. `-m00m` and `-m60m` are 404s, so this is the whole ladder:
    /// twelve frames covering 55 minutes. Oldest first, to match RIDGE.
    private static let minutesAgo: [Int] = [55, 50, 45, 40, 35, 30, 25, 20, 15, 10, 5, 0]

    /// HRRR writes simulated reflectivity every 15 minutes. Two hours of it
    /// is eight frames: enough to see where a storm is heading without
    /// leaning on the model further out, where it drifts from reality.
    private static let forecastStep = 15
    private static let forecastHorizon = 120
    /// HRRR's subhourly output runs to 18 hours. Past that the tiles are
    /// blank, and a blank forecast frame would read as "clear skies".
    private static let maxForecastMinute = 1080

    /// Rendered frame size in points.
        // MARK: - Public

    func loadLoop(for city: City, area: RadarArea = .local,
                  includeForecast: Bool = false) async -> RadarLoopResult {
        guard Self.isInCONUS(lat: city.latitude, lon: city.longitude) else {
            return .noCoverage(
                "\(city.name) is outside the NEXRAD composite. This radar layer covers "
                + "the contiguous United States only — Alaska, Hawaii and everywhere "
                + "outside the US have no coverage in it.")
        }

        // The basemap never changes between frames, so snapshot it once and
        // reuse it. Twelve MapKit snapshots would be twelve times the work for
        // twelve identical maps.
        let region = RadarMapCompositor.squareRegion(
            center: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            latitudeSpan: area.latitudeSpan)

        guard let snapshot = await RadarMapCompositor.makeBasemap(region: region) else {
            return .failure("Could not render the map for \(city.name).")
        }

        var frames: [UIImage] = []
        var times: [Date] = []
        let now = Date()

        // Ask for the model run while the observed frames download.
        async let latestRun: Date? = includeForecast ? await Self.latestHRRRRun() : nil

        for minutes in Self.minutesAgo {
            guard let frame = await composite(
                snapshot: snapshot, region: region,
                layer: Self.observedLayer(minutesAgo: minutes), cityName: city.name)
            else { continue }
            frames.append(frame)
            times.append(now.addingTimeInterval(-Double(minutes) * 60))
        }

        guard !frames.isEmpty else {
            return .failure("Could not download radar tiles from the Iowa Environmental Mesonet.")
        }

        var loop = RadarLoop(
            frames: frames,
            frameTimes: times,
            station: nil,                    // a composite has no single station
            sourceName: "IEM composite",
            attribution: "Radar: NWS NEXRAD via Iowa Environmental Mesonet · Map: Apple",
            fetchedAt: now)

        // Forecast is extra. If the run can't be found or no frame renders,
        // the observed loop still stands on its own.
        if let run = await latestRun {
            let forecast = await forecastFrames(run: run, after: now, snapshot: snapshot,
                                                region: region, cityName: city.name)
            if !forecast.isEmpty {
                loop = RadarLoop(
                    frames: frames + forecast.map(\.0),
                    frameTimes: times + forecast.map(\.1),
                    station: nil,
                    sourceName: "IEM composite",
                    attribution: "Radar: NWS NEXRAD · Forecast: NOAA HRRR model · "
                               + "via Iowa Environmental Mesonet · Map: Apple",
                    fetchedAt: now,
                    forecastStart: frames.count,
                    forecastRun: run)
            }
        }

        AppLogger.network.debug("IEM radar: \(loop.observedCount) observed + \(loop.forecastCount) forecast frames for \(city.name)")
        return .success(loop)
    }

    // MARK: - Forecast

    /// Forecast frames on the quarter hours after `now`, oldest first. Each
    /// is the newest available run's forecast for that valid time, so the
    /// forecast lead (time since the run started) is typically 2–4 hours:
    /// IEM publishes a run about two hours after it starts.
    private func forecastFrames(run: Date, after now: Date,
                                snapshot: MKMapSnapshotter.Snapshot,
                                region: MKCoordinateRegion,
                                cityName: String) async -> [(UIImage, Date)] {
        let step = Double(Self.forecastStep * 60)
        let firstValid = (now.timeIntervalSince1970 / step).rounded(.up) * step

        var out: [(UIImage, Date)] = []
        for k in 0..<(Self.forecastHorizon / Self.forecastStep) {
            let valid = Date(timeIntervalSince1970: firstValid + Double(k) * step)
            let fMinute = Int((valid.timeIntervalSince(run) / 60).rounded())
            guard fMinute > 0, fMinute <= Self.maxForecastMinute,
                  fMinute % Self.forecastStep == 0 else { continue }

            let ahead = Int((valid.timeIntervalSince(now) / 60).rounded())
            let stamp = "FORECAST · model, not radar · in \(ahead) min"
            guard let frame = await composite(
                snapshot: snapshot, region: region,
                layer: Self.forecastLayer(run: run, minute: fMinute),
                cityName: cityName, banner: stamp)
            else { continue }
            out.append((frame, valid))
        }
        return out
    }

    /// The newest HRRR run IEM has finished rendering. Its 0-minute metadata
    /// file names the run; the tile cache can't be asked, because an unknown
    /// layer comes back as a blank 200, not a 404.
    private static func latestHRRRRun() async -> Date? {
        guard let url = URL(string: "https://mesonet.agron.iastate.edu/data/gis/images/4326/hrrr/refd_0000.json")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let initString = json["model_init_utc"] as? String,
              let run = ISO8601DateFormatter().date(from: initString)
        else {
            AppLogger.network.error("IEM radar: could not read the latest HRRR run")
            return nil
        }
        // A run more than six hours old means IEM has stalled. Its forecast
        // would be stale enough to mislead, so leave the forecast off.
        guard Date().timeIntervalSince(run) < 6 * 3600 else {
            AppLogger.network.error("IEM radar: HRRR run \(initString) is too old to use")
            return nil
        }
        return run
    }

    private static let runFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func forecastLayer(run: Date, minute: Int) -> String {
        String(format: "hrrr::REFD-F%04d-", minute) + runFormatter.string(from: run)
    }

    /// Current frame has no suffix; every older one is `-mNNm`.
    private static func observedLayer(minutesAgo: Int) -> String {
        minutesAgo == 0
            ? "nexrad-n0q-900913"
            : String(format: "nexrad-n0q-900913-m%02dm", minutesAgo)
    }

    // MARK: - Basemap


    // MARK: - Compositing

    private func composite(snapshot: MKMapSnapshotter.Snapshot,
                           region: MKCoordinateRegion,
                           layer: String,
                           cityName: String,
                           banner: String? = nil) async -> UIImage? {
        let base = snapshot.image
        let z = Self.chooseZoom(longitudeSpan: region.span.longitudeDelta)
        let tiles = await fetchTiles(snapshot: snapshot, region: region,
                                     layer: layer, zoom: z)
        guard !tiles.isEmpty else { return nil }

        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: base.size))

            // UIKit's origin is top-left and so is `point(for:)`, so unlike the
            // Mac bench tool there is no y-flip to undo here.
            for (tile, rect) in tiles {
                tile.draw(in: rect, blendMode: .normal, alpha: 0.85)
            }

            RadarMapCompositor.drawCityMarker(named: cityName, size: base.size)
            RadarMapCompositor.drawMapAttribution(size: base.size)
            if let banner { RadarMapCompositor.drawForecastBanner(banner, size: base.size) }
        }
    }

    /// Every reflectivity tile covering the snapshot's region, already placed.
    private func fetchTiles(snapshot: MKMapSnapshotter.Snapshot,
                            region: MKCoordinateRegion,
                            layer: String,
                            zoom z: Int) async -> [(UIImage, CGRect)] {
        // Pad by a tenth on every side. Tiles snap outward to whole tiles
        // anyway, so this rarely costs an extra request, and it guarantees no
        // bare strip at the edge where MapKit's fit differs slightly from ours.
        let padLon = region.span.longitudeDelta * 0.1
        let padLat = region.span.latitudeDelta * 0.1
        let west = region.center.longitude - region.span.longitudeDelta / 2 - padLon
        let east = region.center.longitude + region.span.longitudeDelta / 2 + padLon
        let north = min(region.center.latitude + region.span.latitudeDelta / 2 + padLat, 85)
        let south = max(region.center.latitude - region.span.latitudeDelta / 2 - padLat, -85)

        let x0 = Self.tileX(west, z), x1 = Self.tileX(east, z)
        let y0 = Self.tileY(north, z), y1 = Self.tileY(south, z)

        var coords: [(Int, Int)] = []
        for tx in min(x0, x1)...max(x0, x1) {
            for ty in min(y0, y1)...max(y0, y1) { coords.append((tx, ty)) }
        }

        return await withTaskGroup(of: (UIImage, CGRect)?.self) { group in
            for (tx, ty) in coords {
                group.addTask {
                    guard let image = await Self.fetchTile(
                        x: tx, y: ty, z: z, layer: layer) else { return nil }
                    let nw = CLLocationCoordinate2D(
                        latitude: Self.tileLat(ty, z), longitude: Self.tileLon(tx, z))
                    let se = CLLocationCoordinate2D(
                        latitude: Self.tileLat(ty + 1, z), longitude: Self.tileLon(tx + 1, z))
                    let pNW = snapshot.point(for: nw)
                    let pSE = snapshot.point(for: se)
                    let rect = CGRect(x: pNW.x, y: pNW.y,
                                      width: pSE.x - pNW.x, height: pSE.y - pNW.y)
                    return (image, rect)
                }
            }
            var out: [(UIImage, CGRect)] = []
            for await result in group { if let result { out.append(result) } }
            return out
        }
    }

    private static func fetchTile(x: Int, y: Int, z: Int, layer: String) async -> UIImage? {
        let urlString = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/\(layer)/\(z)/\(x)/\(y).png"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        return image
    }

    // MARK: - Marker

    /// Put the city on the map. Nothing can describe a place that isn't drawn,
    /// and a composite has no built-in "you are here".

    /// Credit Apple on the image itself. MKMapView draws its own attribution,
    /// but an MKMapSnapshotter image comes back bare, and Apple's developer
    /// terms treat snapshots as part of the Apple Maps Service. The full legal
    /// link lives in About Radar; this keeps the credit on the picture too.

    // MARK: - Web Mercator tile maths

    /// The most detailed zoom at which the picture is at most three tiles
    /// wide — about 9 to 16 tiles a frame. Local lands on z8 and Regional on
    /// z7. z8 pixels are already about the size of the mosaic's own ~0.005°
    /// cells, so going finer would only fetch more tiles of upscaled data.
    private static func chooseZoom(longitudeSpan: Double) -> Int {
        for z in stride(from: 12, through: 4, by: -1) {
            let tilesAcross = longitudeSpan / (360.0 / pow(2.0, Double(z)))
            if tilesAcross <= 3 { return z }
        }
        return 4
    }

    /// A region whose shape matches the square image. MapKit fits whatever it
    /// is given to the image's aspect ratio, and in Web Mercator a degree of
    /// latitude is drawn taller than a degree of longitude — so asking for
    /// equal degrees each way comes back far wider than asked (2.7° of
    /// longitude instead of 2° at Madison). The radar tiles were fetched for
    /// the region as asked, which could leave a strip with no radar at the
    /// left or right edge: it looked like clear weather and was described as
    /// such. Working out the true width up front keeps map and radar in step.

    private static func tileX(_ lon: Double, _ z: Int) -> Int {
        Int(floor((lon + 180.0) / 360.0 * pow(2.0, Double(z))))
    }
    private static func tileY(_ lat: Double, _ z: Int) -> Int {
        let r = lat * .pi / 180
        return Int(floor((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * pow(2.0, Double(z))))
    }
    private static func tileLon(_ x: Int, _ z: Int) -> Double {
        Double(x) / pow(2.0, Double(z)) * 360.0 - 180.0
    }
    private static func tileLat(_ y: Int, _ z: Int) -> Double {
        let n = Double.pi - 2 * .pi * Double(y) / pow(2.0, Double(z))
        return 180.0 / .pi * atan(0.5 * (exp(n) - exp(-n)))
    }

    /// The n0q layer is a contiguous-US mosaic. Outside this box it is empty,
    /// so say so rather than render a bare basemap and call it radar.
    private static func isInCONUS(lat: Double, lon: Double) -> Bool {
        lat >= 24.0 && lat <= 50.0 && lon >= -125.5 && lon <= -66.0
    }
}

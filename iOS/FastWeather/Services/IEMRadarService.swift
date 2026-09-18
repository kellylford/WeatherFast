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
//  Radar: NOAA/NWS NEXRAD base reflectivity (N0Q) via Iowa Environmental
//  Mesonet — public domain data, university-hosted service. Basemap: Apple.
//

import Foundation
import UIKit
import MapKit

final class IEMRadarService {
    static let shared = IEMRadarService()
    private init() {}

    private static let userAgent = "WeatherFast (weatherfast.online)"

    /// IEM publishes the current layer plus `-m05m` … `-m55m` in five-minute
    /// steps. `-m00m` and `-m60m` are 404s, so this is the whole ladder:
    /// twelve frames covering 55 minutes. Oldest first, to match RIDGE.
    private static let minutesAgo: [Int] = [55, 50, 45, 40, 35, 30, 25, 20, 15, 10, 5, 0]

    /// Degrees of latitude/longitude across the rendered map.
    private static let spanDegrees: Double = 2.0

    /// Rendered frame size in points.
    private static let imageSize: CGFloat = 900

    // MARK: - Public

    func loadLoop(for city: City) async -> RadarLoopResult {
        guard Self.isInCONUS(lat: city.latitude, lon: city.longitude) else {
            return .noCoverage(
                "\(city.name) is outside the NEXRAD composite. This radar layer covers "
                + "the contiguous United States only — Alaska, Hawaii and everywhere "
                + "outside the US have no coverage in it.")
        }

        // The basemap never changes between frames, so snapshot it once and
        // reuse it. Twelve MapKit snapshots would be twelve times the work for
        // twelve identical maps.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            span: MKCoordinateSpan(latitudeDelta: Self.spanDegrees,
                                   longitudeDelta: Self.spanDegrees))

        guard let snapshot = await makeBasemap(region: region) else {
            return .failure("Could not render the map for \(city.name).")
        }

        var frames: [UIImage] = []
        var times: [Date] = []
        let now = Date()

        for minutes in Self.minutesAgo {
            guard let frame = await composite(
                snapshot: snapshot, region: region,
                minutesAgo: minutes, cityName: city.name)
            else { continue }
            frames.append(frame)
            times.append(now.addingTimeInterval(-Double(minutes) * 60))
        }

        guard !frames.isEmpty else {
            return .failure("Could not download radar tiles from the Iowa Environmental Mesonet.")
        }

        AppLogger.network.debug("IEM radar: \(frames.count) frames for \(city.name)")

        return .success(RadarLoop(
            frames: frames,
            frameTimes: times,
            station: nil,                    // a composite has no single station
            sourceName: "IEM composite",
            attribution: "Radar: NWS NEXRAD via Iowa Environmental Mesonet · Map: Apple",
            fetchedAt: now))
    }

    // MARK: - Basemap

    @MainActor
    private func makeBasemap(region: MKCoordinateRegion) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: Self.imageSize, height: Self.imageSize)
        options.pointOfInterestFilter = .excludingAll
        options.mapType = .mutedStandard
        // Force light. The reflectivity palette has to be the loudest thing on
        // screen, and a dark basemap buries the greens and blues.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, error in
                if let error {
                    AppLogger.network.error("IEM basemap snapshot failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: snapshot)
            }
        }
    }

    // MARK: - Compositing

    private func composite(snapshot: MKMapSnapshotter.Snapshot,
                           region: MKCoordinateRegion,
                           minutesAgo: Int,
                           cityName: String) async -> UIImage? {
        let base = snapshot.image
        let z = Self.chooseZoom(spanDegrees: Self.spanDegrees)
        let tiles = await fetchTiles(snapshot: snapshot, region: region,
                                     minutesAgo: minutesAgo, zoom: z)
        guard !tiles.isEmpty else { return nil }

        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: base.size))

            // UIKit's origin is top-left and so is `point(for:)`, so unlike the
            // Mac bench tool there is no y-flip to undo here.
            for (tile, rect) in tiles {
                tile.draw(in: rect, blendMode: .normal, alpha: 0.85)
            }

            Self.drawCityMarker(named: cityName, size: base.size)
        }
    }

    /// Every reflectivity tile covering the snapshot's region, already placed.
    private func fetchTiles(snapshot: MKMapSnapshotter.Snapshot,
                            region: MKCoordinateRegion,
                            minutesAgo: Int,
                            zoom z: Int) async -> [(UIImage, CGRect)] {
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2

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
                        x: tx, y: ty, z: z, minutesAgo: minutesAgo) else { return nil }
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

    private static func fetchTile(x: Int, y: Int, z: Int, minutesAgo: Int) async -> UIImage? {
        // Current frame has no suffix; every older one is `-mNNm`.
        let layer = minutesAgo == 0
            ? "nexrad-n0q-900913"
            : String(format: "nexrad-n0q-900913-m%02dm", minutesAgo)
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
    private static func drawCityMarker(named name: String, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = 11

        let dot = UIBezierPath(arcCenter: center, radius: radius,
                               startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.black.setFill(); dot.fill()
        let inner = UIBezierPath(arcCenter: center, radius: radius - 4,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.white.setFill(); inner.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: UIColor.black,
            .strokeColor: UIColor.white,
            .strokeWidth: -4.0,
        ]
        let text = name as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: center.x - textSize.width / 2,
                              y: center.y - radius - textSize.height - 6),
                  withAttributes: attributes)
    }

    // MARK: - Web Mercator tile maths

    /// IEM serves this layer to z12; past that it just upscales.
    private static func chooseZoom(spanDegrees: Double) -> Int {
        for z in stride(from: 12, through: 4, by: -1) {
            let tilesAcross = spanDegrees / (360.0 / pow(2.0, Double(z)))
            if tilesAcross <= 5 { return z }
        }
        return 6
    }

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

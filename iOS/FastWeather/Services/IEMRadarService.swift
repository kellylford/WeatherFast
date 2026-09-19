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

    /// Rendered frame size in points.
    private static let imageSize: CGFloat = 900

    // MARK: - Public

    func loadLoop(for city: City, area: RadarArea = .local) async -> RadarLoopResult {
        guard Self.isInCONUS(lat: city.latitude, lon: city.longitude) else {
            return .noCoverage(
                "\(city.name) is outside the NEXRAD composite. This radar layer covers "
                + "the contiguous United States only — Alaska, Hawaii and everywhere "
                + "outside the US have no coverage in it.")
        }

        // The basemap never changes between frames, so snapshot it once and
        // reuse it. Twelve MapKit snapshots would be twelve times the work for
        // twelve identical maps.
        let region = Self.squareRegion(
            center: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            latitudeSpan: area.latitudeSpan)

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
        let z = Self.chooseZoom(longitudeSpan: region.span.longitudeDelta)
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
            Self.drawMapAttribution(size: base.size)
        }
    }

    /// Every reflectivity tile covering the snapshot's region, already placed.
    private func fetchTiles(snapshot: MKMapSnapshotter.Snapshot,
                            region: MKCoordinateRegion,
                            minutesAgo: Int,
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

    /// Credit Apple on the image itself. MKMapView draws its own attribution,
    /// but an MKMapSnapshotter image comes back bare, and Apple's developer
    /// terms treat snapshots as part of the Apple Maps Service. The full legal
    /// link lives in About Radar; this keeps the credit on the picture too.
    private static func drawMapAttribution(size: CGSize) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: UIColor.black,
        ]
        let text = "Map: Apple Maps" as NSString
        let textSize = text.size(withAttributes: attributes)
        let pad: CGFloat = 6
        let origin = CGPoint(x: 10, y: size.height - textSize.height - pad * 2 - 10)
        let box = CGRect(x: origin.x, y: origin.y,
                         width: textSize.width + pad * 2, height: textSize.height + pad * 2)
        UIColor.white.withAlphaComponent(0.8).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 5).fill()
        text.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad), withAttributes: attributes)
    }

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
    private static func squareRegion(center: CLLocationCoordinate2D,
                                     latitudeSpan: Double) -> MKCoordinateRegion {
        func mercatorY(_ lat: Double) -> Double { log(tan(.pi / 4 + lat * .pi / 360)) }
        let north = center.latitude + latitudeSpan / 2
        let south = center.latitude - latitudeSpan / 2
        let longitudeSpan = (mercatorY(north) - mercatorY(south)) * 180 / .pi
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan))
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

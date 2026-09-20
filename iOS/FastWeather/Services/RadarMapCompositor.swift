//
//  RadarMapCompositor.swift
//  Fast Weather
//
//  Shared map drawing for the radar sources that hand back bare precipitation
//  with no geography — IEM's tiles and Environment Canada's WMS images.
//
//  Neither source draws a map. On its own each is coloured blobs in a void,
//  undescribable and unplaceable, so the app has to be the cartographer: take
//  a MapKit basemap, put the precipitation on top, mark the user's city, and
//  credit Apple for the map before there is anything worth looking at.
//

import Foundation
import UIKit
import MapKit

enum RadarMapCompositor {
    /// Rendered frame size in points.
    static let imageSize: CGFloat = 900

    /// A region shaped to match the square image. MapKit fits whatever it is
    /// given to the image's aspect ratio, and in Web Mercator a degree of
    /// latitude is drawn taller than a degree of longitude — so asking for
    /// equal degrees each way comes back far wider than asked (2.7° of
    /// longitude instead of 2° at Madison). Working out the true width up
    /// front is what keeps the precipitation covering the whole map.
    static func squareRegion(center: CLLocationCoordinate2D,
                             latitudeSpan: Double) -> MKCoordinateRegion {
        func mercatorY(_ lat: Double) -> Double { log(tan(.pi / 4 + lat * .pi / 360)) }
        let north = center.latitude + latitudeSpan / 2
        let south = center.latitude - latitudeSpan / 2
        let longitudeSpan = (mercatorY(north) - mercatorY(south)) * 180 / .pi
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan))
    }

    @MainActor
    static func makeBasemap(region: MKCoordinateRegion) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: imageSize, height: imageSize)
        options.pointOfInterestFilter = .excludingAll
        options.mapType = .mutedStandard
        // Force light. The reflectivity palette has to be the loudest thing on
        // screen, and a dark basemap buries the greens and blues.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, error in
                if let error {
                    AppLogger.network.error("Radar basemap snapshot failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: snapshot)
            }
        }
    }

    /// Put the city on the map. Nothing can describe a place that isn't drawn,
    /// and a composite has no built-in "you are here".
    static func drawCityMarker(named name: String, size: CGSize) {
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
    static func drawMapAttribution(size: CGSize) {
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

    /// One PNG fetch, decoded. Returns nil rather than throwing: a missing
    /// frame is a gap in a loop, not a reason to lose the whole loop.
    static func fetchImage(_ url: URL, userAgent: String) async -> UIImage? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        return image
    }
}

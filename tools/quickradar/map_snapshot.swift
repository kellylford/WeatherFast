//
//  map_snapshot.swift
//  QuickRadar — Mac bench
//
//  Renders a MapKit basemap with NWS NEXRAD radar composited on top and the
//  user's location marked, then writes it as a PNG.
//
//  Why this exists: VoiceOver's Image Explorer can only describe an *image*
//  element, and a live MKTileOverlay is not one. If the app shows a real
//  pannable radar map (what sighted users want), the describable artefact has
//  to be a still snapshot of that map. This tool produces exactly that
//  artefact outside the app, so we can test whether Image Explorer reads it as
//  well as it read the NWS RIDGE GIFs — before building the feature.
//
//  Usage:
//    swift map_snapshot.swift --lat 43.0731 --lon -89.4012 --name "Madison, WI" \
//        --span 2.0 --out madison_map.png [--legend] [--no-marker] \
//        [--maptype standard|muted|hybrid] [--size 900]
//
//  Radar: NOAA/NWS NEXRAD base reflectivity (N0Q) via Iowa Environmental
//  Mesonet. Public domain. US coverage only.
//

import Foundation
import MapKit
import AppKit

// MARK: - Arguments

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: "--\(name)"), i + 1 < a.count else { return nil }
    return a[i + 1]
}
func flag(_ name: String) -> Bool { CommandLine.arguments.contains("--\(name)") }

guard let latS = arg("lat"), let lonS = arg("lon"),
      let lat = Double(latS), let lon = Double(lonS) else {
    FileHandle.standardError.write("usage: --lat <deg> --lon <deg> [--name X] [--span 2.0] [--out f.png]\n".data(using: .utf8)!)
    exit(2)
}
let placeName = arg("name") ?? ""
let span = Double(arg("span") ?? "2.0") ?? 2.0
let outPath = arg("out") ?? "map_snapshot.png"
let pxSize = Double(arg("size") ?? "900") ?? 900
let drawMarker = !flag("no-marker")
let drawLegend = flag("legend")
let mapTypeName = arg("maptype") ?? "muted"   // grey land; green basemap collides with green echo

// MARK: - Web Mercator tile maths

func tileX(_ lon: Double, _ z: Int) -> Int {
    Int(floor((lon + 180.0) / 360.0 * pow(2.0, Double(z))))
}
func tileY(_ lat: Double, _ z: Int) -> Int {
    let r = lat * .pi / 180
    return Int(floor((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * pow(2.0, Double(z))))
}
func tileLon(_ x: Int, _ z: Int) -> Double {
    Double(x) / pow(2.0, Double(z)) * 360.0 - 180.0
}
func tileLat(_ y: Int, _ z: Int) -> Double {
    let n = Double.pi - 2 * .pi * Double(y) / pow(2.0, Double(z))
    return 180.0 / .pi * atan(0.5 * (exp(n) - exp(-n)))
}

/// Pick a zoom that puts a sensible number of radar tiles across the view.
/// IEM serves this layer up to z12; beyond that it just upscales.
func chooseZoom(spanDegrees: Double) -> Int {
    for z in stride(from: 12, through: 4, by: -1) {
        let tilesAcross = spanDegrees / (360.0 / pow(2.0, Double(z)))
        if tilesAcross <= 5 { return z }
    }
    return 6
}

// MARK: - Snapshot

let region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))

let opts = MKMapSnapshotter.Options()
opts.region = region
opts.size = CGSize(width: pxSize, height: pxSize)
opts.showsPointsOfInterest = false
switch mapTypeName {
case "hybrid":   opts.mapType = .hybrid
case "standard": opts.mapType = .standard
default:         opts.mapType = .mutedStandard
}
// Force the light appearance. A CLI process has no app appearance, so the
// snapshotter defaults to dark — which turns the basemap dark teal and buries
// the radar palette. Consumer radar apps all use a light/muted base for the
// same reason: the reflectivity colours have to be the loudest thing present.
opts.appearance = NSAppearance(named: .aqua)

MKMapSnapshotter(options: opts).start(with: .main) { snapshot, error in
    guard let snapshot else {
        FileHandle.standardError.write("snapshot failed: \(error?.localizedDescription ?? "unknown")\n".data(using: .utf8)!)
        exit(1)
    }

    let base = snapshot.image
    let w = Int(base.size.width), h = Int(base.size.height)

    // Draw into an NSBitmapImageRep via AppKit rather than raw CoreGraphics —
    // the CG path produced horizontally mirrored output in this toolchain
    // (see resumework.md, "CoreGraphics Horizontal Flip").
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    base.draw(in: NSRect(x: 0, y: 0, width: w, height: h))

    // ---- Composite radar tiles -------------------------------------------
    let z = chooseZoom(spanDegrees: span)
    let west = lon - span / 2, east = lon + span / 2
    let north = lat + span / 2, south = lat - span / 2
    let x0 = tileX(west, z), x1 = tileX(east, z)
    let y0 = tileY(north, z), y1 = tileY(south, z)

    var tilesDrawn = 0, tilesMissing = 0
    for tx in x0...max(x0, x1) {
        for ty in y0...max(y0, y1) {
            let urlStr = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/\(z)/\(tx)/\(ty).png"
            guard let url = URL(string: urlStr),
                  let data = try? Data(contentsOf: url),
                  let tile = NSImage(data: data) else { tilesMissing += 1; continue }

            // Tile corners -> snapshot points. AppKit's origin is bottom-left,
            // MKMapSnapshotter's point(for:) is top-left, so flip y.
            let nw = CLLocationCoordinate2D(latitude: tileLat(ty, z), longitude: tileLon(tx, z))
            let se = CLLocationCoordinate2D(latitude: tileLat(ty + 1, z), longitude: tileLon(tx + 1, z))
            let pNW = snapshot.point(for: nw), pSE = snapshot.point(for: se)
            let rect = NSRect(x: pNW.x,
                              y: Double(h) - pSE.y,
                              width: pSE.x - pNW.x,
                              height: pSE.y - pNW.y)
            tile.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.85)
            tilesDrawn += 1
        }
    }

    // ---- Location marker --------------------------------------------------
    if drawMarker {
        let p = snapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        let c = NSPoint(x: p.x, y: Double(h) - p.y)
        let r: CGFloat = 11

        // White ring so the dot survives on top of red/green echo.
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r - 3, y: c.y - r - 3,
                                    width: (r + 3) * 2, height: (r + 3) * 2)).fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)).fill()

        if !placeName.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 22),
                .foregroundColor: NSColor.black,
                .strokeColor: NSColor.white,
                .strokeWidth: -5.0,
            ]
            let label = NSAttributedString(string: placeName, attributes: attrs)
            let size = label.size()
            label.draw(at: NSPoint(x: c.x - size.width / 2, y: c.y + r + 8))
        }
    }

    // ---- Optional dBZ legend ---------------------------------------------
    // The RIDGE GIFs carry a legend, and it is an open question how much of
    // their describability came from it. This makes that a variable we can
    // test rather than assume.
    if drawLegend {
        let bandColors: [(String, NSColor)] = [
            ("light",    NSColor(calibratedRed: 0.02, green: 0.62, blue: 0.98, alpha: 1)),
            ("moderate", NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.12, alpha: 1)),
            ("heavy",    NSColor(calibratedRed: 1.00, green: 0.98, blue: 0.10, alpha: 1)),
            ("intense",  NSColor(calibratedRed: 0.98, green: 0.16, blue: 0.10, alpha: 1)),
        ]
        let boxW: CGFloat = 130, boxH: CGFloat = 30
        let originY: CGFloat = 14
        NSColor(white: 1, alpha: 0.92).setFill()
        NSBezierPath(rect: NSRect(x: 10, y: originY - 8,
                                  width: boxW * CGFloat(bandColors.count) + 20,
                                  height: boxH + 16)).fill()
        for (i, band) in bandColors.enumerated() {
            let x = 20 + CGFloat(i) * boxW
            band.1.setFill()
            NSBezierPath(rect: NSRect(x: x, y: originY, width: 26, height: boxH)).fill()
            NSAttributedString(string: band.0, attributes: [
                .font: NSFont.systemFont(ofSize: 17),
                .foregroundColor: NSColor.black,
            ]).draw(at: NSPoint(x: x + 32, y: originY + 5))
        }
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do {
        try png.write(to: URL(fileURLWithPath: outPath))
    } catch {
        FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }

    print("wrote \(outPath)  zoom=z\(z) tiles=\(tilesDrawn) missing=\(tilesMissing) size=\(w)x\(h)")
    exit(0)
}

RunLoop.main.run()

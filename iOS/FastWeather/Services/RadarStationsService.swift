//
//  RadarStationsService.swift
//  Fast Weather
//
//  The NEXRAD radar stations themselves, as a browsable list.
//
//  The NWS station feed gives a name and a position but no state, so the
//  state and nearest town for each site were resolved once against
//  api.weather.gov/points and baked in below. 159 sites that change very
//  rarely; a lookup per row at runtime would be 159 requests to learn
//  something that has not moved since the tower was built.
//
//  Live from the feed each time: whether the radar is actually reporting.
//  A site can be down for maintenance, and a list that offers a dead
//  station without saying so wastes the user's time.
//

import Foundation
import CoreLocation

struct RadarStationInfo: Identifiable, Hashable {
    let id: String              // "KMKX"
    let name: String            // "Milwaukee"
    let stateCode: String       // "WI"
    let nearestTown: String     // "Sullivan" — may be empty
    let latitude: Double
    let longitude: Double
    let elevationMetres: Double?
    /// When the site last sent data, from the feed. nil if it never said.
    let lastDataReceived: Date?

    var stateName: String {
        RadarStationsService.stateNames[stateCode] ?? stateCode
    }

    /// "Milwaukee, WI"
    var displayName: String {
        stateCode.isEmpty ? name : "\(name), \(stateCode)"
    }

    /// A radar that has not reported in half an hour is treated as down:
    /// long enough to rule out an ordinary gap between volume scans.
    var isReporting: Bool {
        guard let t = lastDataReceived else { return true }
        return Date().timeIntervalSince(t) < 30 * 60
    }

    func distanceKm(from location: CLLocation) -> Double {
        location.distance(from: CLLocation(latitude: latitude, longitude: longitude)) / 1000
    }
}

final class RadarStationsService {
    static let shared = RadarStationsService()
    private init() {}

    private static let userAgent = "WeatherFast (weatherfast.online)"
    private var cached: [RadarStationInfo]?

    /// Every WSR-88D site, with the live reporting state folded in.
    func allStations() async -> [RadarStationInfo]? {
        if let cached { return cached }

        let url = URL(string: "https://api.weather.gov/radar/stations")!
        var request = URLRequest(url: url)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            AppLogger.network.error("Radar stations: list fetch failed")
            return nil
        }

        var out: [RadarStationInfo] = []
        for feature in features {
            guard let props = feature["properties"] as? [String: Any],
                  (props["stationType"] as? String) == "WSR-88D",
                  let sid = (props["id"] as? String)?.uppercased(),
                  let geometry = feature["geometry"] as? [String: Any],
                  let coords = geometry["coordinates"] as? [Double], coords.count >= 2
            else { continue }

            let place = Self.places[sid]
            let elevation = (props["elevation"] as? [String: Any])?["value"] as? Double
            var lastData: Date?
            if let latency = props["latency"] as? [String: Any],
               let stamp = latency["levelTwoLastReceivedTime"] as? String {
                lastData = Self.timestamps.date(from: stamp)
            }

            out.append(RadarStationInfo(
                id: sid,
                name: props["name"] as? String ?? sid,
                stateCode: place?.state ?? "",
                nearestTown: place?.near ?? "",
                latitude: coords[1],
                longitude: coords[0],
                elevationMetres: elevation,
                lastDataReceived: lastData))
        }

        guard !out.isEmpty else { return nil }
        cached = out
        return out
    }

    /// The feed stamps times like 2026-09-20T13:10:58+00:00.
    private static let timestamps: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Baked place data

    private static let places: [String: (state: String, near: String)] = [
        "KABR": ("SD", "Aberdeen"),
        "KABX": ("NM", "Albuquerque"),
        "KAKQ": ("VA", "Wakefield"),
        "KAMA": ("TX", "Amarillo"),
        "KAMX": ("FL", "Richmond West"),
        "KAPX": ("MI", "Gaylord"),
        "KARX": ("WI", "La Crosse"),
        "KATX": ("WA", "Camano"),
        "KBBX": ("CA", "Oroville"),
        "KBGM": ("NY", "Johnson City"),
        "KBHX": ("CA", "Ferndale"),
        "KBIS": ("ND", "Bismarck"),
        "KBLX": ("MT", "Billings"),
        "KBMX": ("AL", "Calera"),
        "KBOX": ("MA", "Taunton"),
        "KBRO": ("TX", "Brownsville"),
        "KBUF": ("NY", "Cheektowaga"),
        "KBYX": ("FL", "Stock Island"),
        "KCAE": ("SC", "Cayce"),
        "KCBW": ("ME", "Houlton"),
        "KCBX": ("ID", "Kuna"),
        "KCCX": ("PA", "Julian"),
        "KCLE": ("OH", "Cleveland"),
        "KCLX": ("SC", "Gillisonville"),
        "KCRP": ("TX", "Corpus Christi"),
        "KCXX": ("VT", "Winooski"),
        "KCYS": ("WY", "Cheyenne"),
        "KDAX": ("CA", "El Macero"),
        "KDDC": ("KS", "Dodge City"),
        "KDFX": ("TX", "Brackettville"),
        "KDGX": ("MS", "Brandon"),
        "KDIX": ("NJ", "Cedar Glen Lakes"),
        "KDLH": ("MN", "Duluth"),
        "KDMX": ("IA", "Johnston"),
        "KDOX": ("DE", "Ellendale"),
        "KDTX": ("MI", "Village of Clarkston"),
        "KDVN": ("IA", "Davenport"),
        "KDYX": ("TX", "Moran"),
        "KEAX": ("MO", "Pleasant Hill"),
        "KEMX": ("AZ", "Vail"),
        "KENX": ("NY", "Voorheesville"),
        "KEOX": ("AL", "Newville"),
        "KEPZ": ("NM", "Santa Teresa"),
        "KESX": ("NV", "Nelson"),
        "KEVX": ("FL", "Ebro"),
        "KEWX": ("TX", "New Braunfels"),
        "KEYX": ("CA", "Boron"),
        "KFCX": ("VA", "Floyd"),
        "KFDR": ("OK", "Frederick"),
        "KFDX": ("NM", "Melrose"),
        "KFFC": ("GA", "Peachtree City"),
        "KFSD": ("SD", "Sioux Falls"),
        "KFSX": ("AZ", "Blue Ridge"),
        "KFTG": ("CO", "Aurora"),
        "KFWS": ("TX", "Fort Worth"),
        "KGGW": ("MT", "Glasgow"),
        "KGJX": ("CO", "Palisade"),
        "KGLD": ("KS", "Goodland"),
        "KGRB": ("WI", "Ashwaubenon"),
        "KGRK": ("TX", "Granger"),
        "KGRR": ("MI", "Kentwood"),
        "KGSP": ("SC", "Greer"),
        "KGWX": ("MS", "Gattman"),
        "KGYX": ("ME", "Gray"),
        "KHDC": ("LA", "Hammond"),
        "KHDX": ("NM", "Tularosa"),
        "KHGX": ("TX", "League City"),
        "KHNX": ("CA", "Hanford"),
        "KHPX": ("KY", "Trenton"),
        "KHTX": ("AL", "Hytop"),
        "KICT": ("KS", "Wichita"),
        "KICX": ("UT", "Brian Head"),
        "KILN": ("OH", "Wilmington"),
        "KILX": ("IL", "Lincoln"),
        "KIND": ("IN", "Indianapolis city (balance)"),
        "KINX": ("OK", "Gregory"),
        "KIWA": ("AZ", "Mesa"),
        "KIWX": ("IN", "North Webster"),
        "KJAX": ("FL", "Jacksonville"),
        "KJGX": ("GA", "Jeffersonville"),
        "KJKL": ("KY", "Jackson"),
        "KLBB": ("TX", "Lubbock"),
        "KLCH": ("LA", "Lake Charles"),
        "KLGX": ("WA", "Copalis Beach"),
        "KLNX": ("NE", "Thedford"),
        "KLOT": ("IL", "Romeoville"),
        "KLRX": ("NV", "Battle Mountain"),
        "KLSX": ("MO", "Weldon Spring Heights"),
        "KLTX": ("NC", "Shallotte"),
        "KLVX": ("KY", "West Point"),
        "KLWX": ("VA", "Loudoun Valley Estates"),
        "KLZK": ("AR", "North Little Rock"),
        "KMAF": ("TX", "Midland"),
        "KMAX": ("OR", "Ashland"),
        "KMBX": ("ND", "Deering"),
        "KMHX": ("NC", "Newport"),
        "KMKX": ("WI", "Sullivan"),
        "KMLB": ("FL", "Melbourne"),
        "KMOB": ("AL", "Mobile"),
        "KMPX": ("MN", "Chanhassen"),
        "KMQT": ("MI", "Negaunee"),
        "KMRX": ("TN", "Morristown"),
        "KMSX": ("MT", "Evaro"),
        "KMTX": ("UT", "Hooper"),
        "KMUX": ("CA", "Lexington Hills"),
        "KMVX": ("ND", "Mayville"),
        "KMXX": ("AL", "Tuskegee"),
        "KNKX": ("CA", "San Diego"),
        "KNQA": ("TN", "Millington"),
        "KOAX": ("NE", "Valley"),
        "KOHX": ("TN", "Green Hill"),
        "KOKX": ("NY", "Manorville"),
        "KOTX": ("WA", "Airway Heights"),
        "KPAH": ("KY", "Paducah"),
        "KPBZ": ("PA", "Carnot-Moon"),
        "KPDT": ("OR", "Pendleton"),
        "KPOE": ("LA", "Simpson"),
        "KPUX": ("CO", "Boone"),
        "KRAX": ("NC", "Clayton"),
        "KRGX": ("NV", "Nixon"),
        "KRIW": ("WY", "Riverton"),
        "KRLX": ("WV", "Charleston"),
        "KRTX": ("OR", "Scappoose"),
        "KSFX": ("ID", "Rockford"),
        "KSGF": ("MO", "Springfield"),
        "KSHV": ("LA", "Shreveport"),
        "KSJT": ("TX", "San Angelo"),
        "KSOX": ("CA", "Corona"),
        "KSRX": ("AR", "Fort Smith"),
        "KTBW": ("FL", "Ruskin"),
        "KTFX": ("MT", "Great Falls"),
        "KTLH": ("FL", "Tallahassee"),
        "KTLX": ("OK", "Oklahoma City"),
        "KTWX": ("KS", "Alma"),
        "KTYX": ("NY", "Copenhagen"),
        "KUDX": ("SD", "New Underwood"),
        "KUEX": ("NE", "Blue Hill"),
        "KVAX": ("GA", "Echols County"),
        "KVBX": ("CA", "Orcutt"),
        "KVNX": ("OK", "Nescatunga"),
        "KVTX": ("CA", "Ojai"),
        "KVWX": ("IN", "Johnson"),
        "KYUX": ("AZ", "San Luis"),
        "PABC": ("AK", "Bethel"),
        "PACG": ("AK", "Sitka"),
        "PAEC": ("AK", "Nome"),
        "PAHG": ("AK", "Nikiski"),
        "PAIH": ("AK", "Chenega"),
        "PAKC": ("AK", "King Salmon"),
        "PAPD": ("AK", "Fox"),
        "PGUA": ("GU", "Mangilao"),
        "PHKI": ("HI", "Kalaheo"),
        "PHKM": ("HI", "Halaula"),
        "PHMO": ("HI", "Maunaloa"),
        "PHWA": ("HI", "Naalehu"),
        "RKJK": ("OK_KR", ""),
        "RKSG": ("OK_KR", ""),
        "RODN": ("OK_JP", ""),
        "TJUA": ("PR", "G. L. García"),
    ]

    static let stateNames: [String: String] = [
        "AK": "Alaska",
        "AL": "Alabama",
        "AR": "Arkansas",
        "AZ": "Arizona",
        "CA": "California",
        "CO": "Colorado",
        "DE": "Delaware",
        "FL": "Florida",
        "GA": "Georgia",
        "GU": "Guam",
        "HI": "Hawaii",
        "IA": "Iowa",
        "ID": "Idaho",
        "IL": "Illinois",
        "IN": "Indiana",
        "KS": "Kansas",
        "KY": "Kentucky",
        "LA": "Louisiana",
        "MA": "Massachusetts",
        "ME": "Maine",
        "MI": "Michigan",
        "MN": "Minnesota",
        "MO": "Missouri",
        "MS": "Mississippi",
        "MT": "Montana",
        "NC": "North Carolina",
        "ND": "North Dakota",
        "NE": "Nebraska",
        "NJ": "New Jersey",
        "NM": "New Mexico",
        "NV": "Nevada",
        "NY": "New York",
        "OH": "Ohio",
        "OK": "Oklahoma",
        "OK_JP": "Okinawa, Japan",
        "OK_KR": "South Korea",
        "OR": "Oregon",
        "PA": "Pennsylvania",
        "PR": "Puerto Rico",
        "SC": "South Carolina",
        "SD": "South Dakota",
        "TN": "Tennessee",
        "TX": "Texas",
        "UT": "Utah",
        "VA": "Virginia",
        "VT": "Vermont",
        "WA": "Washington",
        "WI": "Wisconsin",
        "WV": "West Virginia",
        "WY": "Wyoming",
    ]
}

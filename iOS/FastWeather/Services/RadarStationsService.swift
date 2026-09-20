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

/// Which country's radar network a site belongs to. They publish different
/// things: the NWS a ready-made loop GIF, ECCC one finished image per scan.
enum RadarNetwork: String, Hashable {
    case nws
    case eccc

    var shortName: String {
        switch self {
        case .nws:  return "NWS"
        case .eccc: return "ECCC"
        }
    }

    var countryName: String {
        switch self {
        case .nws:  return "United States"
        case .eccc: return "Canada"
        }
    }
}

struct RadarStationInfo: Identifiable, Hashable {
    let id: String              // "KMKX" or "CASBV"
    let name: String            // "Milwaukee"
    let network: RadarNetwork
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
    /// long enough to rule out an ordinary gap between volume scans. Only the
    /// NWS feed says; ECCC publishes no such status, so a Canadian site is
    /// never claimed to be down rather than being guessed at.
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

    /// Every site in both networks: the WSR-88D list fetched live, with its
    /// reporting state, plus Canada's fixed 33.
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
                network: .nws,
                stateCode: place?.state ?? "",
                nearestTown: place?.near ?? "",
                latitude: coords[1],
                longitude: coords[0],
                elevationMetres: elevation,
                lastDataReceived: lastData))
        }

        guard !out.isEmpty else { return nil }
        out += Self.canadianStations
        cached = out
        return out
    }

    /// Canada's network is 32 fixed sites. Unlike the NWS list there is no
    /// feed to ask, so the sites are baked in; they change on the scale of
    /// years, and an app that cannot list them offline gains nothing.
    private static let canadianStations: [RadarStationInfo] = canadianSites.map {
        RadarStationInfo(id: $0.id, name: $0.name, network: .eccc,
                         stateCode: $0.province, nearestTown: "",
                         latitude: $0.lat, longitude: $0.lon,
                         elevationMetres: nil, lastDataReceived: nil)
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

    private static let canadianSites: [(id: String, name: String, province: String, lat: Double, lon: Double)] = [
        (id: "CASAG", name: "Aldergrove", province: "BC", lat: 49.01662, lon: -122.48698),
        (id: "CASBE", name: "Bethune", province: "SK", lat: 50.57118, lon: -105.1829),
        (id: "CASBV", name: "Blainville", province: "QC", lat: 45.70634, lon: -73.85852),
        (id: "CASBI", name: "Britt", province: "ON", lat: 45.79317, lon: -80.53385),
        (id: "CASCV", name: "Carvel", province: "AB", lat: 53.56056, lon: -114.14495),
        (id: "CASCM", name: "Chipman", province: "NB", lat: 46.22232, lon: -65.69924),
        (id: "CASCL", name: "Cold Lake", province: "AB", lat: 54.3785, lon: -110.06138),
        (id: "CASDR", name: "Dryden", province: "ON", lat: 49.85823, lon: -92.79698),
        (id: "CASET", name: "Exeter", province: "ON", lat: 43.37243, lon: -81.3807),
        (id: "CASFM", name: "Fort McMurray", province: "AB", lat: 56.37564, lon: -111.21518),
        (id: "CASFW", name: "Foxwarren", province: "MB", lat: 50.54887, lon: -101.0857),
        (id: "CASFT", name: "Franktown", province: "ON", lat: 45.04101, lon: -76.11617),
        (id: "CASGO", name: "Gore", province: "NS", lat: 45.0985, lon: -63.70433),
        (id: "CASHP", name: "Halfmoon Peak", province: "BC", lat: 49.52702, lon: -123.85358),
        (id: "CASHR", name: "Holyrood", province: "NL", lat: 47.32644, lon: -53.12658),
        (id: "CASKR", name: "King City", province: "ON", lat: 43.96393, lon: -79.57388),
        (id: "CASLA", name: "Landrienne", province: "QC", lat: 48.55136, lon: -77.80809),
        (id: "CASMM", name: "Marble Mountain", province: "NL", lat: 48.93028, lon: -57.83417),
        (id: "CASMB", name: "Marion Bridge", province: "NS", lat: 45.94972, lon: -60.20521),
        (id: "CASMA", name: "Mont Apica", province: "QC", lat: 47.97791, lon: -71.43083),
        (id: "CASMR", name: "Montreal River", province: "ON", lat: 47.24773, lon: -84.59652),
        (id: "CASSS", name: "Mount Silver Star", province: "BC", lat: 50.3695, lon: -119.06436),
        (id: "CASPG", name: "Prince George", province: "BC", lat: 53.61308, lon: -122.95441),
        (id: "CASRA", name: "Radisson", province: "SK", lat: 52.52048, lon: -107.44269),
        (id: "CASSF", name: "Sainte-Françoise", province: "QC", lat: 46.44956, lon: -71.91383),
        (id: "CASSU", name: "Schuler", province: "AB", lat: 50.3125, lon: -110.19556),
        (id: "CASRF", name: "Smooth Rock Falls", province: "ON", lat: 49.28146, lon: -81.79406),
        (id: "CASSR", name: "Spirit River", province: "AB", lat: 55.69494, lon: -119.23043),
        (id: "CASSM", name: "Strathmore", province: "AB", lat: 51.20613, lon: -113.39937),
        (id: "CASSN", name: "Superior West", province: "ON", lat: 48.59588, lon: -89.10013),
        (id: "CASVD", name: "Val d'Irène", province: "QC", lat: 48.48028, lon: -67.60111),
        (id: "CASWL", name: "Woodlands", province: "MB", lat: 50.15389, lon: -97.77833),
    ]

    static let stateNames: [String: String] = [
        "AB": "Alberta",
        "BC": "British Columbia",
        "MB": "Manitoba",
        "NB": "New Brunswick",
        "NL": "Newfoundland and Labrador",
        "NS": "Nova Scotia",
        "ON": "Ontario",
        "QC": "Quebec",
        "SK": "Saskatchewan",
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

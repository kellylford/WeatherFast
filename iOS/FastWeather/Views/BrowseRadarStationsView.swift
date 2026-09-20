//
//  BrowseRadarStationsView.swift
//  Fast Weather
//
//  Browse the radar networks themselves — the 159 US WSR-88D sites and
//  Canada's 33 — and open any one of them, the same way Browse Cities opens
//  a city.
//
//  Why browse radars at all: a city gives you the radar nearest that city.
//  Sometimes the question is the other way round — what does the radar at
//  Sullivan see, what is the storm doing over the next state, is the site
//  that covers my area even up right now.
//

import SwiftUI
import CoreLocation

/// Sorts that mean something for radar sites. Temperature doesn't apply here;
/// distance does, which is why this isn't BrowseSortOrder.
enum RadarStationSort: String, CaseIterable, Identifiable {
    case nameAZ     = "Name (A–Z)"
    case nameZA     = "Name (Z–A)"
    case stateAZ    = "State or Province (A–Z)"
    case nearest    = "Nearest to Me"
    case northSouth = "North to South"
    case southNorth = "South to North"
    case eastWest   = "East to West"
    case westEast   = "West to East"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .nameAZ, .nameZA: return "textformat.abc"
        case .stateAZ:         return "map"
        case .nearest:         return "location"
        case .northSouth:      return "arrow.down"
        case .southNorth:      return "arrow.up"
        case .eastWest:        return "arrow.right"
        case .westEast:        return "arrow.left"
        }
    }
}

struct BrowseRadarStationsView: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var myLocationService: MyLocationService

    @State private var stations: [RadarStationInfo] = []
    @State private var isLoading = true
    @State private var message: String?
    @State private var searchText = ""
    @AppStorage("radarStationSort") private var sortRaw: String = RadarStationSort.nameAZ.rawValue
    @State private var here: CLLocation?

    private var sort: RadarStationSort {
        RadarStationSort(rawValue: sortRaw) ?? .nameAZ
    }

    private var unit: DistanceUnit { settingsManager.settings.distanceUnit }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading radar stations…")
                    .accessibilityLabel("Loading radar stations")
            } else if let message {
                VStack(spacing: 16) {
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Try Again") { Task { await load() } }
                        .accessibilityHint("Attempts to download the radar station list again.")
                }
                .padding()
            } else {
                stationList
            }
        }
        .navigationTitle("Radar Stations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !stations.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) { sortMenu }
            }
        }
        .task { await load() }
    }

    private var stationList: some View {
        List {
            Section(footer: Text(countLine)) {
                ForEach(visibleStations) { station in
                    NavigationLink(destination: RadarLoopView(station: station)
                        .environmentObject(settingsManager)) {
                        row(station)
                    }
                    .accessibilityLabel(label(station))
                    .accessibilityHint("Shows this station's radar loop.")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by station, state or code")
    }

    private func row(_ station: RadarStationInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(station.displayName)
                .font(.headline)
            Text(detailLine(station))
                .font(.caption)
                .foregroundColor(.secondary)
            if !station.isReporting {
                Text("No recent data")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .accessibilityElement(children: .ignore)
    }

    /// "KMKX · near Sullivan · 34 miles away"
    private func detailLine(_ station: RadarStationInfo) -> String {
        var parts = [station.id]
        if station.network == .eccc { parts.append("Canada") }
        if !station.nearestTown.isEmpty { parts.append("near \(station.nearestTown)") }
        if let away = distancePhrase(station) { parts.append("\(away) away") }
        return parts.joined(separator: " · ")
    }

    private func label(_ station: RadarStationInfo) -> String {
        var parts = ["\(station.name), \(station.stateName)"]
        parts.append("station \(spelled(station.id))")
        if station.network == .eccc { parts.append("Environment and Climate Change Canada") }
        if !station.nearestTown.isEmpty { parts.append("near \(station.nearestTown)") }
        if let away = distancePhrase(station) { parts.append("\(away) away") }
        if !station.isReporting { parts.append("no recent data") }
        return parts.joined(separator: ", ") + "."
    }

    /// Station codes are read letter by letter; "KMKX" as a word is noise.
    private func spelled(_ id: String) -> String {
        id.map(String.init).joined(separator: " ")
    }

    private func distancePhrase(_ station: RadarStationInfo) -> String? {
        guard let here else { return nil }
        let value = Int(unit.convert(station.distanceKm(from: here)).rounded())
        return "\(value) " + (unit == .miles ? "miles" : "kilometres")
    }

    private var countLine: String {
        let shown = visibleStations.count
        let total = stations.count
        guard shown == total else {
            return "\(shown) of \(total) stations match your search."
        }
        let us = stations.filter { $0.network == .nws }.count
        let ca = stations.count - us
        return "\(us) United States NEXRAD stations from the National Weather Service "
             + "and \(ca) Canadian sites from Environment and Climate Change Canada."
    }

    // MARK: - Sorting and filtering

    private var visibleStations: [RadarStationInfo] {
        var base = stations
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            base = base.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
                || $0.stateCode.localizedCaseInsensitiveContains(query)
                || $0.stateName.localizedCaseInsensitiveContains(query)
                || $0.nearestTown.localizedCaseInsensitiveContains(query)
                || $0.network.countryName.localizedCaseInsensitiveContains(query)
                || $0.network.shortName.localizedCaseInsensitiveContains(query)
            }
        }
        return base.sorted(by: comparator)
    }

    private func comparator(_ a: RadarStationInfo, _ b: RadarStationInfo) -> Bool {
        switch sort {
        case .nameAZ:  return a.name.localizedCompare(b.name) == .orderedAscending
        case .nameZA:  return a.name.localizedCompare(b.name) == .orderedDescending
        case .stateAZ:
            if a.stateName != b.stateName {
                return a.stateName.localizedCompare(b.stateName) == .orderedAscending
            }
            return a.name.localizedCompare(b.name) == .orderedAscending
        case .nearest:
            guard let here else { return a.name.localizedCompare(b.name) == .orderedAscending }
            return a.distanceKm(from: here) < b.distanceKm(from: here)
        case .northSouth: return a.latitude  > b.latitude
        case .southNorth: return a.latitude  < b.latitude
        case .eastWest:   return a.longitude > b.longitude
        case .westEast:   return a.longitude < b.longitude
        }
    }

    private var sortMenu: some View {
        Menu {
            Section("Alphabetical") {
                ForEach([RadarStationSort.nameAZ, .nameZA, .stateAZ]) { sortButton($0) }
            }
            Section("Distance") {
                sortButton(.nearest)
            }
            Section("Geographic") {
                ForEach([RadarStationSort.northSouth, .southNorth, .eastWest, .westEast]) { sortButton($0) }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort stations. Current sort: \(sort.rawValue)")
    }

    private func sortButton(_ option: RadarStationSort) -> some View {
        Button {
            sortRaw = option.rawValue
            if option == .nearest { Task { await findMe() } }
        } label: {
            Label(option.rawValue, systemImage: sort == option ? "checkmark" : option.systemImage)
        }
        .accessibilityAddTraits(sort == option ? .isSelected : [])
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        message = nil
        here = currentLocation()

        guard let list = await RadarStationsService.shared.allStations() else {
            message = "Could not reach the National Weather Service station list. "
                    + "Check your connection and try again."
            isLoading = false
            return
        }
        stations = list
        isLoading = false

        // Only ask the system where we are if the chosen sort needs it.
        if sort == .nearest, here == nil { await findMe() }
    }

    /// Distance sorting is the one thing here that needs a location, so it is
    /// only requested when the user asks for it.
    private func findMe() async {
        if let known = currentLocation() {
            here = known
            return
        }
        myLocationService.requestPermissionIfNeeded()
        await myLocationService.refresh()
        here = currentLocation()
        if here == nil {
            AppLogger.location.debug("Radar stations: no location for nearest-first sort")
        }
    }

    /// The app already keeps the user's location as a city; its coordinates
    /// are all this list needs, so there is no second location request here.
    private func currentLocation() -> CLLocation? {
        guard let city = myLocationService.locationCity else { return nil }
        return CLLocation(latitude: city.latitude, longitude: city.longitude)
    }
}

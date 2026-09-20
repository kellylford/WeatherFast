//
//  BrowseCitiesView.swift
//  Fast Weather
//
//  View for browsing cities by state (US) or country (International)
//

import SwiftUI

// Navigation destinations for the Browse Cities stack
enum BrowseDestination: Hashable {
    case region(BrowseRegionType)
    case stateCities(name: String, sortOrder: BrowseSortOrder?)
    case countryCities(name: String, sortOrder: BrowseSortOrder?)
    case alertBrowser
    case alertMeteoAlarmCountries
    case alertDigest(AlertRegion)
    case radarStations
}

struct BrowseCitiesView: View {
    @StateObject private var cityDataService = CityDataService()
    @StateObject private var favoritesService = BrowseFavoritesService()
    @ObservedObject private var featureFlags = FeatureFlags.shared
    @State private var navPath: [BrowseDestination] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                if !favoritesService.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favoritesService.favorites) { favorite in
                            Button {
                                switch favorite.regionType {
                                case .us:
                                    navPath.append(.stateCities(name: favorite.name, sortOrder: favorite.sortOrder))
                                case .international:
                                    navPath.append(.countryCities(name: favorite.name, sortOrder: favorite.sortOrder))
                                }
                            } label: {
                                Text(favorite.name)
                                    .foregroundColor(.primary)
                            }
                            .accessibilityLabel(favorite.name)
                            .accessibilityHint("Double tap to browse cities")
                        }
                    }
                }

                Section("Browse by Region") {
                    Button {
                        navPath.append(.region(.us))
                    } label: {
                        Label("United States", systemImage: "flag.fill")
                            .foregroundColor(.primary)
                    }
                    .accessibilityHint("Double tap to browse U.S. states")

                    Button {
                        navPath.append(.region(.international))
                    } label: {
                        Label("International", systemImage: "globe")
                            .foregroundColor(.primary)
                    }
                    .accessibilityHint("Double tap to browse countries")
                }

                if featureFlags.radarLoopEnabled {
                    Section(header: Text("Radar"),
                            footer: Text("Open the radar for any National Weather Service station, rather than the one nearest a saved city.")) {
                        Button {
                            navPath.append(.radarStations)
                        } label: {
                            Label("Browse Radar Stations", systemImage: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.primary)
                        }
                        .accessibilityHint("Double tap to browse all National Weather Service radar stations")
                    }
                }

                if featureFlags.alertBrowserEnabled {
                    Section(header: Text("Weather Alerts"),
                            footer: Text("View active government weather alerts by country, independent of your saved cities.")) {
                        Button {
                            navPath.append(.alertBrowser)
                        } label: {
                            Label("Browse Alerts", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.primary)
                        }
                        .accessibilityHint("Double tap to browse active weather alerts by country")
                    }
                }
            }
            .navigationTitle("Weather Browser")
            .navigationDestination(for: BrowseDestination.self) { destination in
                switch destination {
                case .region(.us):
                    USStatesListView(cityDataService: cityDataService, navPath: $navPath)
                case .region(.international):
                    CountriesListView(cityDataService: cityDataService, navPath: $navPath)
                case .stateCities(let name, let sortOrder):
                    StateCitiesView(
                        state: name,
                        cityDataService: cityDataService,
                        favoritesService: favoritesService,
                        overrideSortOrder: sortOrder
                    )
                case .countryCities(let name, let sortOrder):
                    CountryCitiesView(
                        country: name,
                        cityDataService: cityDataService,
                        favoritesService: favoritesService,
                        overrideSortOrder: sortOrder
                    )
                case .alertBrowser:
                    AlertRegionsView(navPath: $navPath)
                case .alertMeteoAlarmCountries:
                    AlertMeteoAlarmCountriesView(navPath: $navPath)
                case .alertDigest(let region):
                    NationalAlertDigestView(region: region)
                case .radarStations:
                    BrowseRadarStationsView()
                }
            }
        }
    }
}

struct USStatesListView: View {
    @ObservedObject var cityDataService: CityDataService
    @Binding var navPath: [BrowseDestination]
    @State private var searchText = ""

    private var filteredStates: [String] {
        searchText.isEmpty ? cityDataService.usStates :
            cityDataService.usStates.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if cityDataService.usStates.isEmpty {
                Text("Loading states...")
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredStates, id: \.self) { state in
                    Button {
                        navPath.append(.stateCities(name: state, sortOrder: nil))
                    } label: {
                        Text(state)
                            .foregroundColor(.primary)
                    }
                    .accessibilityHint("Double tap to browse cities in \(state)")
                }
            }
        }
        .navigationTitle("United States")
        .searchable(text: $searchText, prompt: "Search states")
    }
}

struct CountriesListView: View {
    @ObservedObject var cityDataService: CityDataService
    @Binding var navPath: [BrowseDestination]
    @State private var searchText = ""

    private var filteredCountries: [String] {
        searchText.isEmpty ? cityDataService.countries :
            cityDataService.countries.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if cityDataService.countries.isEmpty {
                Text("Loading countries...")
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredCountries, id: \.self) { country in
                    Button {
                        navPath.append(.countryCities(name: country, sortOrder: nil))
                    } label: {
                        Text(country)
                            .foregroundColor(.primary)
                    }
                    .accessibilityHint("Double tap to browse cities in \(country)")
                }
            }
        }
        .navigationTitle("International")
        .searchable(text: $searchText, prompt: "Search countries")
    }
}
//
//  LaunchCityService.swift
//  Fast Weather
//
//  Remembers which city (or My Location) the app opens to at launch.
//  Stored in plain UserDefaults, deliberately outside AppSettings, so it is
//  per-device and never roams through iCloud sync.
//

import Foundation
import SwiftUI

enum LaunchCity: Equatable, Hashable {
    case cityList
    case myLocation
    case city(UUID)

    fileprivate static let myLocationValue = "myLocation"

    fileprivate init(storedValue: String?) {
        switch storedValue {
        case Self.myLocationValue:
            self = .myLocation
        case let value?:
            self = UUID(uuidString: value).map { .city($0) } ?? .cityList
        case nil:
            self = .cityList
        }
    }

    fileprivate var storedValue: String? {
        switch self {
        case .cityList: return nil
        case .myLocation: return Self.myLocationValue
        case .city(let id): return id.uuidString
        }
    }
}

@MainActor
class LaunchCityService: ObservableObject {
    static let shared = LaunchCityService()

    private let storageKey = "LaunchCity"

    @Published var launchCity: LaunchCity {
        didSet {
            UserDefaults.standard.set(launchCity.storedValue, forKey: storageKey)
        }
    }

    /// Set once the launch destination has been handled, so returning to the
    /// city list (tab switches, foregrounding) never re-opens the city.
    private var hasHandledLaunch = false

    private init() {
        launchCity = LaunchCity(storedValue: UserDefaults.standard.string(forKey: storageKey))
    }

    func isLaunchCity(_ city: City) -> Bool {
        launchCity == .city(city.id)
    }

    /// Toggles a saved city as the launch city and announces the result.
    func toggle(_ city: City) {
        let wasSelected = isLaunchCity(city)
        launchCity = wasSelected ? .cityList : .city(city.id)
        announce(wasSelected
            ? "Weather Fast will open to your city list"
            : "Weather Fast will open to \(city.displayName)")
    }

    /// Toggles My Location as the launch city and announces the result.
    func toggleMyLocation() {
        let wasSelected = launchCity == .myLocation
        launchCity = wasSelected ? .cityList : .myLocation
        announce(wasSelected
            ? "Weather Fast will open to your city list"
            : "Weather Fast will open to My Location")
    }

    /// Resolves the city to open at app start. Returns nil (stay on the city list)
    /// after the first call, when no launch city is set, or when it can't be found.
    func cityForLaunch(
        savedCities: [City],
        myLocationService: MyLocationService,
        showMyLocation: Bool
    ) async -> City? {
        guard !hasHandledLaunch else { return nil }
        hasHandledLaunch = true

        switch launchCity {
        case .cityList:
            return nil
        case .myLocation:
            guard showMyLocation else { return nil }
            // The cached location may be from a previous place; refresh first when stale.
            await myLocationService.refreshIfStale()
            return myLocationService.locationCity
        case .city(let id):
            guard let city = savedCities.first(where: { $0.id == id }) else {
                // The city was removed (possibly on another device); fall back to the list.
                AppLogger.service.info("Launch city no longer in list; clearing")
                launchCity = .cityList
                return nil
            }
            return city
        }
    }

    private func announce(_ message: String) {
        // Delay so VoiceOver finishes the menu or action gesture before the announcement.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}

/// Menu label for the Open at Launch toggle, shared by the Flat and List views.
struct LaunchCityLabel: View {
    let isSelected: Bool

    static func title(isSelected: Bool) -> String {
        isSelected ? "Stop Opening at Launch" : "Open at Launch"
    }

    var body: some View {
        Label(Self.title(isSelected: isSelected), systemImage: isSelected ? "pin.slash" : "pin")
    }
}

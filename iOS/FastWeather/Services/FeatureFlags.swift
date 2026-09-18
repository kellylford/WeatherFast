//
//  FeatureFlags.swift
//  Fast Weather
//
//  Feature flags for controlling visibility of in-development features
//

import Foundation

/// Manages feature flags for controlling app features
/// Use this to hide features in development without needing separate branches
class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()
    
    // MARK: - Feature Flags
    
    /// Enable/disable precipitation forecast feature (in development)
    /// Set to true to show expected precipitation button and functionality
    @Published var radarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(radarEnabled, forKey: "feature_radar_enabled")
        }
    }

    /// Enable/disable the NEXRAD radar loop screen (experimental)
    /// Animated NWS radar frames, steppable one at a time so VoiceOver's
    /// Image Explorer can describe each frame. US coverage only.
    @Published var radarLoopEnabled: Bool {
        didSet {
            UserDefaults.standard.set(radarLoopEnabled, forKey: "feature_radar_loop_enabled")
        }
    }
    
    /// Enable/disable weather around me feature (in development)
    /// Set to true to show regional weather comparison button and functionality
    @Published var weatherAroundMeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weatherAroundMeEnabled, forKey: "feature_weather_around_me_enabled")
        }
    }
    
    /// Enable/disable user guide link in settings
    /// Set to true to show user guide link in settings
    @Published var userGuideEnabled: Bool {
        didSet {
            UserDefaults.standard.set(userGuideEnabled, forKey: "feature_user_guide_enabled")
        }
    }
    
    /// Enable/disable WeatherKit alerts for international cities
    /// When enabled, uses Apple WeatherKit for alerts in non-US cities
    /// US cities continue to use NWS for more detailed alerts
    @Published var weatherKitAlertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weatherKitAlertsEnabled, forKey: "feature_weatherkit_alerts_enabled")
        }
    }
    
    /// Enable/disable My Data custom section in city detail view
    /// When enabled, users can configure a custom data section with any Open-Meteo parameter
    @Published var myDataEnabled: Bool {
        didSet {
            UserDefaults.standard.set(myDataEnabled, forKey: "feature_my_data_enabled")
        }
    }
    
    /// Enable/disable Table view mode on the home screen
    /// Off by default — Table view has text clipping issues and is an experimental layout.
    /// When disabled the Table option is hidden from the View Mode picker in Settings.
    @Published var tableViewEnabled: Bool {
        didSet {
            UserDefaults.standard.set(tableViewEnabled, forKey: "feature_table_view_enabled")
        }
    }
    
    /// Use WeatherKit daily snow totals instead of Open-Meteo snowfall_sum.
    /// Off by default. When on, WeatherKit daily snowfallAmount (cm) overwrites
    /// the Open-Meteo value after each fetch. Falls back to Open-Meteo on error.
    @Published var weatherKitSnowEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weatherKitSnowEnabled, forKey: "feature_weatherkit_snow_enabled")
        }
    }

    /// Use WeatherKit radar-quality minute-by-minute nowcast for Expected Precipitation.
    /// On by default. When disabled, all cities fall back to Open-Meteo NWP regardless
    /// of country — restoring the pre-WeatherKit nowcast experience.
    @Published var weatherKitNowcastEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weatherKitNowcastEnabled, forKey: "feature_weatherkit_nowcast_enabled")
        }
    }

    /// Use WeatherKit's observation/nowcast-informed current condition instead of Open-Meteo's
    /// model `weather_code` for "now". On by default. Fixes cases like a thunderstorm code
    /// showing while it's dry. Applies to today's conditions only (forecasts stay Open-Meteo);
    /// unmappable WeatherKit conditions fall back to the Open-Meteo code. See #73.
    @Published var weatherKitConditionsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weatherKitConditionsEnabled, forKey: "feature_weatherkit_conditions_enabled")
        }
    }

    /// Extend the WeatherKit condition overlay to the hourly and daily forecast (not just "now").
    /// On by default. Within WeatherKit's horizon (~10 days) each forecast hour/day uses
    /// WeatherKit's condition translated to WMO; hours/days WeatherKit doesn't cover, unmappable
    /// conditions, and days 11–16 keep the Open-Meteo code. Fixes the phantom-thunderstorm code
    /// (95/96/99 with ~0 precip) appearing in the 24-hour and 16-day forecasts. See #74.
    @Published var weatherKitForecastConditionsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weatherKitForecastConditionsEnabled, forKey: "feature_weatherkit_forecast_conditions_enabled")
        }
    }

    /// Show specific place names (airports, universities, streets) instead of just the city name.
    /// On by default. When disabled, all searches fall back to the locality-only label ("Madison, WI")
    /// regardless of what was searched. Does not affect cities already saved.
    @Published var specificPlaceNamesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(specificPlaceNamesEnabled, forKey: "feature_specific_place_names_enabled")
        }
    }

    /// Enable/disable the My Location section on the city list.
    /// On by default. When disabled, the entire My Location feature is hidden regardless of the
    /// user-facing setting in Settings > My Location.
    @Published var myLocationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(myLocationEnabled, forKey: "feature_my_location_enabled")
        }
    }

    /// Enable/disable the Browse Alerts feature (browse active government weather
    /// alerts by service/country, independent of any saved city).
    /// On by default. When disabled, the Weather Alerts section is hidden from the Browse tab.
    @Published var alertBrowserEnabled: Bool {
        didSet {
            UserDefaults.standard.set(alertBrowserEnabled, forKey: "feature_alert_browser_enabled")
        }
    }

    /// Enable/disable the Air Quality detail section. Observation-first (AirNow, US)
    /// and alert-aware (defers to active NWS air quality alerts). On by default.
    /// When disabled, the Air Quality section is hidden from city detail.
    @Published var airQualityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(airQualityEnabled, forKey: "feature_air_quality_enabled")
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved feature flag states
        self.radarEnabled = UserDefaults.standard.bool(forKey: "feature_radar_enabled")
        self.radarLoopEnabled = UserDefaults.standard.bool(forKey: "feature_radar_loop_enabled")
        self.weatherAroundMeEnabled = UserDefaults.standard.bool(forKey: "feature_weather_around_me_enabled")
        self.userGuideEnabled = UserDefaults.standard.bool(forKey: "feature_user_guide_enabled")
        self.weatherKitAlertsEnabled = UserDefaults.standard.bool(forKey: "feature_weatherkit_alerts_enabled")
        self.myDataEnabled = UserDefaults.standard.bool(forKey: "feature_my_data_enabled")
        self.tableViewEnabled = UserDefaults.standard.bool(forKey: "feature_table_view_enabled")
        self.weatherKitSnowEnabled = UserDefaults.standard.bool(forKey: "feature_weatherkit_snow_enabled")
        self.weatherKitNowcastEnabled = UserDefaults.standard.bool(forKey: "feature_weatherkit_nowcast_enabled")
        self.weatherKitConditionsEnabled = UserDefaults.standard.bool(forKey: "feature_weatherkit_conditions_enabled")
        self.weatherKitForecastConditionsEnabled = UserDefaults.standard.bool(forKey: "feature_weatherkit_forecast_conditions_enabled")
        self.specificPlaceNamesEnabled = UserDefaults.standard.bool(forKey: "feature_specific_place_names_enabled")
        self.myLocationEnabled = UserDefaults.standard.bool(forKey: "feature_my_location_enabled")
        self.alertBrowserEnabled = UserDefaults.standard.bool(forKey: "feature_alert_browser_enabled")
        self.airQualityEnabled = UserDefaults.standard.bool(forKey: "feature_air_quality_enabled")

        // Default values (if first launch or not set)
        // All features enabled by default for production
        if !UserDefaults.standard.contains(key: "feature_radar_enabled") {
            self.radarEnabled = true  // Enabled by default
        }
        if !UserDefaults.standard.contains(key: "feature_radar_loop_enabled") {
            self.radarLoopEnabled = false  // Off by default; opt in via Developer Settings
        }
        if !UserDefaults.standard.contains(key: "feature_weather_around_me_enabled") {
            self.weatherAroundMeEnabled = true  // Enabled by default
        }
        if !UserDefaults.standard.contains(key: "feature_user_guide_enabled") {
            self.userGuideEnabled = true  // Enabled by default
        }
        if !UserDefaults.standard.contains(key: "feature_weatherkit_alerts_enabled") {
            self.weatherKitAlertsEnabled = true  // Enabled by default for international alerts
        }
        if !UserDefaults.standard.contains(key: "feature_my_data_enabled") {
            self.myDataEnabled = true  // Enabled by default
        }
        if !UserDefaults.standard.contains(key: "feature_table_view_enabled") {
            self.tableViewEnabled = false  // Disabled by default — experimental layout
        }
        if !UserDefaults.standard.contains(key: "feature_weatherkit_snow_enabled") {
            self.weatherKitSnowEnabled = true  // On by default
        }
        if !UserDefaults.standard.contains(key: "feature_weatherkit_nowcast_enabled") {
            self.weatherKitNowcastEnabled = true  // On by default
        }
        if !UserDefaults.standard.contains(key: "feature_weatherkit_conditions_enabled") {
            self.weatherKitConditionsEnabled = true  // On by default
        }
        if !UserDefaults.standard.contains(key: "feature_weatherkit_forecast_conditions_enabled") {
            self.weatherKitForecastConditionsEnabled = true  // On by default
        }
        if !UserDefaults.standard.contains(key: "feature_specific_place_names_enabled") {
            self.specificPlaceNamesEnabled = true  // On by default
        }
        if !UserDefaults.standard.contains(key: "feature_my_location_enabled") {
            self.myLocationEnabled = true  // On by default
        }
        if !UserDefaults.standard.contains(key: "feature_alert_browser_enabled") {
            self.alertBrowserEnabled = true  // On by default
        }
        if !UserDefaults.standard.contains(key: "feature_air_quality_enabled") {
            self.airQualityEnabled = true  // On by default
        }
    }
    
    // MARK: - Helper Methods
    
    /// Reset all feature flags to defaults
    func resetToDefaults() {
        radarEnabled = true
        weatherAroundMeEnabled = true
        userGuideEnabled = true
        weatherKitAlertsEnabled = true
        myDataEnabled = true
        tableViewEnabled = false
        weatherKitSnowEnabled = true
        weatherKitNowcastEnabled = true
        weatherKitConditionsEnabled = true
        weatherKitForecastConditionsEnabled = true
        specificPlaceNamesEnabled = true
        myLocationEnabled = true
        alertBrowserEnabled = true
        airQualityEnabled = true
        debugLog("🔧 Feature flags reset to defaults")
    }
    
    /// Enable all features (for testing)
    func enableAll() {
        radarEnabled = true
        weatherAroundMeEnabled = true
        userGuideEnabled = true
        weatherKitAlertsEnabled = true
        myDataEnabled = true
        tableViewEnabled = true
        weatherKitSnowEnabled = true
        weatherKitNowcastEnabled = true
        weatherKitConditionsEnabled = true
        weatherKitForecastConditionsEnabled = true
        specificPlaceNamesEnabled = true
        myLocationEnabled = true
        alertBrowserEnabled = true
        airQualityEnabled = true
        debugLog("🔧 All features enabled")
    }

    func disableAll() {
        radarEnabled = false
        weatherAroundMeEnabled = false
        userGuideEnabled = false
        weatherKitAlertsEnabled = false
        myDataEnabled = false
        tableViewEnabled = false
        weatherKitSnowEnabled = false
        weatherKitNowcastEnabled = false
        weatherKitConditionsEnabled = false
        weatherKitForecastConditionsEnabled = false
        specificPlaceNamesEnabled = false
        myLocationEnabled = false
        alertBrowserEnabled = false
        airQualityEnabled = false
        debugLog("🔧 All features disabled")
    }
}

// MARK: - UserDefaults Extension
extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}

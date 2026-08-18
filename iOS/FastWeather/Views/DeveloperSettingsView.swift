//
//  DeveloperSettingsView.swift
//  Fast Weather
//
//  Developer settings for toggling feature flags and testing
//

import SwiftUI

struct DeveloperSettingsView: View {
    @StateObject private var featureFlags = FeatureFlags.shared
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var weatherService: WeatherService
    @Environment(\.dismiss) private var dismiss
    @State private var showingMyDataConfig = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Feature Flags")) {

                    Toggle("Radar Loop", isOn: $featureFlags.radarLoopEnabled)
                        .accessibilityLabel("Radar Loop feature toggle")
                        .accessibilityHint(featureFlags.radarLoopEnabled ? "Radar Loop is enabled. A Radar button appears in city detail showing an animated NEXRAD loop you can step through one frame at a time. US coverage only." : "Radar Loop is disabled. The Radar button will not appear in city detail.")

                    Toggle("My Location Section", isOn: $featureFlags.myLocationEnabled)
                        .accessibilityLabel("My Location feature toggle")
                        .accessibilityHint(featureFlags.myLocationEnabled ? "My Location is enabled. A My Location section appears on the city list when the user setting is also on." : "My Location is disabled globally. The My Location section will not appear regardless of user settings.")

                    Toggle("Browse Alerts", isOn: $featureFlags.alertBrowserEnabled)
                        .accessibilityLabel("Browse Alerts feature toggle")
                        .accessibilityHint(featureFlags.alertBrowserEnabled ? "Browse Alerts is enabled. A Weather Alerts section appears in the Browse tab for viewing active alerts by country, independent of your saved cities." : "Browse Alerts is disabled. The Weather Alerts section will not appear in the Browse tab.")

                    Toggle("Air Quality Section", isOn: $featureFlags.airQualityEnabled)
                        .accessibilityLabel("Air Quality feature toggle")
                        .accessibilityHint(featureFlags.airQualityEnabled ? "Air Quality is enabled. An Air Quality section appears in city detail, using observed monitors where available and deferring to active air quality alerts." : "Air Quality is disabled. The Air Quality section will not appear in city detail.")

                    Toggle("Specific Place Names", isOn: $featureFlags.specificPlaceNamesEnabled)
                        .accessibilityLabel("Specific Place Names feature toggle")
                        .accessibilityHint(featureFlags.specificPlaceNamesEnabled ? "Specific place names are enabled. Searching for an airport or university shows its full name instead of just the city." : "Specific place names are disabled. All searches label the result by city name only.")

                    Toggle("WeatherKit International Alerts", isOn: $featureFlags.weatherKitAlertsEnabled)
                        .accessibilityLabel("WeatherKit International Alerts feature toggle")
                        .accessibilityHint(featureFlags.weatherKitAlertsEnabled ? "WeatherKit alerts for international cities are currently enabled. US cities use NWS." : "WeatherKit alerts are currently disabled. Only US cities will show alerts via NWS.")
                    
                    Toggle("My Data Custom Section", isOn: $featureFlags.myDataEnabled)
                        .accessibilityLabel("My Data custom section feature toggle")
                        .accessibilityHint(featureFlags.myDataEnabled ? "My Data section is enabled. You can add custom data points to city detail views." : "My Data section is disabled and will not appear in city detail views.")
                    
                    Toggle("WeatherKit Snow Totals", isOn: $featureFlags.weatherKitSnowEnabled)
                        .accessibilityLabel("WeatherKit Snow Totals feature toggle")
                        .accessibilityHint(featureFlags.weatherKitSnowEnabled ? "WeatherKit snow is enabled. Daily snow totals come from Apple WeatherKit instead of Open-Meteo." : "WeatherKit snow is disabled. Daily snow totals use Open-Meteo. Enable to test WeatherKit accuracy on lake-effect snow events.")
                        .onChange(of: featureFlags.weatherKitSnowEnabled) {
                            weatherService.clearWeatherCache()
                            Task { await weatherService.refreshAllWeather() }
                        }

                    Toggle("WeatherKit Expected Precipitation", isOn: $featureFlags.weatherKitNowcastEnabled)
                        .accessibilityLabel("WeatherKit Expected Precipitation feature toggle")
                        .accessibilityHint(featureFlags.weatherKitNowcastEnabled ? "WeatherKit nowcast is enabled. Expected Precipitation uses radar-quality minute-by-minute data from Apple WeatherKit for supported countries." : "WeatherKit nowcast is disabled. Expected Precipitation uses Open-Meteo NWP for all cities, restoring the older experience.")

                    Toggle("WeatherKit Current Conditions", isOn: $featureFlags.weatherKitConditionsEnabled)
                        .accessibilityLabel("WeatherKit Current Conditions feature toggle")
                        .accessibilityHint(featureFlags.weatherKitConditionsEnabled ? "WeatherKit current conditions are enabled. The 'now' condition comes from Apple WeatherKit's observation-informed data instead of Open-Meteo's forecast model, so it won't show a thunderstorm when it is dry. Forecasts still use Open-Meteo." : "WeatherKit current conditions are disabled. The current condition uses Open-Meteo's model weather code for all cities.")
                        .onChange(of: featureFlags.weatherKitConditionsEnabled) {
                            weatherService.clearWeatherCache()
                            Task { await weatherService.refreshAllWeather() }
                        }

                    Toggle("WeatherKit Forecast Conditions", isOn: $featureFlags.weatherKitForecastConditionsEnabled)
                        .accessibilityLabel("WeatherKit Forecast Conditions feature toggle")
                        .accessibilityHint(featureFlags.weatherKitForecastConditionsEnabled ? "WeatherKit forecast conditions are enabled. The 24-hour and 16-day forecast icons come from Apple WeatherKit for about the first ten days, so a thunderstorm won't appear when the forecast is dry. Days eleven to sixteen still use Open-Meteo." : "WeatherKit forecast conditions are disabled. The hourly and daily forecast conditions use Open-Meteo's model weather code for all days.")
                        .onChange(of: featureFlags.weatherKitForecastConditionsEnabled) {
                            weatherService.clearWeatherCache()
                            Task { await weatherService.refreshAllWeather() }
                        }

                    Toggle("Enable Table View", isOn: $featureFlags.tableViewEnabled)
                        .accessibilityLabel("Enable Table View feature toggle")
                        .accessibilityHint(featureFlags.tableViewEnabled ? "Table view is enabled. Table option will appear in the View Mode picker in Settings." : "Table view is disabled. Table option will not appear in the View Mode picker in Settings.")
                        .onChange(of: featureFlags.tableViewEnabled) {
                            // If table view is being disabled and user is currently in table mode, switch to list
                            if !featureFlags.tableViewEnabled && settingsManager.settings.viewMode == .table {
                                settingsManager.settings.viewMode = .list
                                settingsManager.saveSettings()
                            }
                        }
                }
                
                // My Data configuration
                if featureFlags.myDataEnabled {
                    Section(header: Text("My Data"),
                            footer: Text("Configure a custom section in the city detail view with any available weather data point from the Open-Meteo API.")) {
                        Button(action: { showingMyDataConfig = true }) {
                            HStack {
                                Image(systemName: "chart.bar.doc.horizontal")
                                    .foregroundColor(.accentColor)
                                    .accessibilityHidden(true)
                                Text("My Data")
                                Spacer()
                                let count = settingsManager.settings.myDataFields.filter { $0.isEnabled }.count
                                if count > 0 {
                                    Text("\(count) data point\(count == 1 ? "" : "s")")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel("My Data configuration")
                        .accessibilityHint("Opens the My Data configuration screen to add or remove custom data points")
                    }
                }
                
                Section(header: Text("Location Features"), footer: Text("Current location uses GPS to automatically detect your city. This requires location permission.")) {
                    HStack {
                        Text("Find My Location")
                        Spacer()
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                    }
                    
                    Text("Available in Add Location screen. Press \"Use My Current Location\" button to automatically add your current location.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Alert Sources"), footer: Text("US cities always use National Weather Service for detailed alerts. When enabled, international cities use Apple WeatherKit for government weather warnings. Note: WeatherKit alert coverage is limited to select countries (Canada, parts of Europe, Japan, Australia, etc.). Not all countries are supported.")) {
                    HStack {
                        Text("US Cities")
                        Spacer()
                        Text("NWS")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("International")
                        Spacer()
                        Text(featureFlags.weatherKitAlertsEnabled ? "WeatherKit*" : "None")
                            .foregroundColor(featureFlags.weatherKitAlertsEnabled ? .green : .secondary)
                    }
                    
                    if featureFlags.weatherKitAlertsEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("* Limited Coverage")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("WeatherKit alerts work in: Canada, UK, Germany, France, Spain, Italy, Japan, Australia, and other select countries. Russia, many Asian countries, and Africa have limited/no coverage.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                #if targetEnvironment(simulator)
                Section(header: Text("⚠️ Simulator Detected")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WeatherKit may not work properly on iOS Simulator")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        
                        Text("To test international alerts:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("1. Build to a real iPhone device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("2. Ensure device is signed in to iCloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("3. Check console for authentication errors")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                #endif
                
                Section(header: Text("Quick Actions")) {
                    Button(action: {
                        featureFlags.enableAll()
                    }) {
                        Label("Enable All Features", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    Button(action: {
                        featureFlags.disableAll()
                    }) {
                        Label("Disable All Features", systemImage: "xmark.circle.fill")
                            .foregroundColor(.orange)
                    }
                    
                    Button(action: {
                        featureFlags.resetToDefaults()
                    }) {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                }
                
                Section(footer: Text("These settings control experimental features that are in development. Changes take effect immediately. Note: Expected Precipitation, Weather Around Me, and Historical Weather settings are now in the main Settings screen.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Developer Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingMyDataConfig) {
                MyDataConfigView()
                    .environmentObject(settingsManager)
                    .environmentObject(weatherService)
            }
        }
    }
}

#Preview {
    DeveloperSettingsView()
        .environmentObject(SettingsManager())
        .environmentObject(WeatherService())
}

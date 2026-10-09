//
//  SettingsView.swift
//  Fast Weather
//
//  Settings and preferences view
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var weatherService: WeatherService
    @StateObject private var featureFlags = FeatureFlags.shared
    @ObservedObject private var launchCityService = LaunchCityService.shared
    @AppStorage("defaultBrowseSortOrder") private var defaultBrowseSortOrderRaw: String = "Name (A–Z)"
    @AppStorage(iCloudSyncService.enabledKey) private var iCloudSyncEnabled: Bool = false
    @State private var showingResetAlert = false
    @State private var showingICloudConflictAlert = false
    @State private var cloudCityCount = 0
    @State private var showingDeveloperSettings = false
    @State private var showingMyDataConfig = false
    
    // Get app version and build number from Info.plist
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    
    private var showMyLocationOption: Bool {
        featureFlags.myLocationEnabled && settingsManager.settings.myLocationEnabled
    }

    /// The launch city, shown as City List when it no longer exists or My Location is hidden.
    private var launchCitySelection: Binding<LaunchCity> {
        Binding(
            get: {
                switch launchCityService.launchCity {
                case .myLocation where !showMyLocationOption:
                    return .cityList
                case .city(let id) where !weatherService.savedCities.contains(where: { $0.id == id }):
                    return .cityList
                default:
                    return launchCityService.launchCity
                }
            },
            set: { launchCityService.launchCity = $0 }
        )
    }

    private var launchCityName: String {
        switch launchCitySelection.wrappedValue {
        case .cityList:
            return "City List"
        case .myLocation:
            return "My Location"
        case .city(let id):
            return weatherService.savedCities.first(where: { $0.id == id })?.displayName ?? "City List"
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // My Location section (first, per user preference)
                Section(header: Text("My Location")) {
                    Toggle("Show My Location", isOn: $settingsManager.settings.myLocationEnabled)
                        .onChange(of: settingsManager.settings.myLocationEnabled) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Show My Location, currently \(settingsManager.settings.myLocationEnabled ? "on" : "off")")
                        .accessibilityHint("When on, your current GPS location appears as a separate section above or below your city list.")

                    if settingsManager.settings.myLocationEnabled {
                        Picker("Position", selection: $settingsManager.settings.myLocationPosition) {
                            ForEach(MyLocationPosition.allCases, id: \.self) { position in
                                Text(position.rawValue).tag(position)
                            }
                        }
                        .onChange(of: settingsManager.settings.myLocationPosition) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("My Location position, currently \(settingsManager.settings.myLocationPosition.rawValue)")
                        .accessibilityHint("Controls whether My Location appears before or after your saved city list.")
                    }
                }

                // Units section
                Section(header: Text("Units")) {
                    Picker(selection: $settingsManager.settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    } label: {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(settingsManager.settings.temperatureUnit.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settingsManager.settings.temperatureUnit) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Temperature unit, currently \(settingsManager.settings.temperatureUnit.rawValue)")
                    
                    Picker(selection: $settingsManager.settings.windSpeedUnit) {
                        ForEach(WindSpeedUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    } label: {
                        HStack {
                            Text("Wind Speed")
                            Spacer()
                            Text(settingsManager.settings.windSpeedUnit.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settingsManager.settings.windSpeedUnit) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Wind speed unit, currently \(settingsManager.settings.windSpeedUnit.rawValue)")
                    
                    Picker(selection: $settingsManager.settings.precipitationUnit) {
                        ForEach(PrecipitationUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    } label: {
                        HStack {
                            Text("Precipitation")
                            Spacer()
                            Text(settingsManager.settings.precipitationUnit.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settingsManager.settings.precipitationUnit) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Precipitation unit, currently \(settingsManager.settings.precipitationUnit.rawValue)")
                    
                    Picker(selection: $settingsManager.settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    } label: {
                        HStack {
                            Text("Distance")
                            Spacer()
                            Text(settingsManager.settings.distanceUnit.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settingsManager.settings.distanceUnit) { oldValue, newValue in
                        // Convert and snap weatherAroundMeDistance to nearest nice value in new unit
                        // Must update both values atomically to prevent picker confusion
                        DispatchQueue.main.async {
                            let kilometers = oldValue.toKilometers(settingsManager.settings.weatherAroundMeDistance)
                            let convertedValue = newValue.convert(kilometers)
                            let snappedValue = newValue.snapToNearest(convertedValue)
                            settingsManager.settings.weatherAroundMeDistance = snappedValue
                            settingsManager.saveSettings()
                        }
                    }
                    .accessibilityLabel("Distance unit, currently \(settingsManager.settings.distanceUnit.rawValue)")
                    
                    Picker(selection: $settingsManager.settings.pressureUnit) {
                        ForEach(PressureUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    } label: {
                        HStack {
                            Text("Pressure")
                            Spacer()
                            Text(settingsManager.settings.pressureUnit.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settingsManager.settings.pressureUnit) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Pressure unit, currently \(settingsManager.settings.pressureUnit.rawValue)")
                }
                
                // Weather Around Me section
                Section(header: Text("Weather Around Me")) {
                    Picker("Default Distance", selection: $settingsManager.settings.weatherAroundMeDistance) {
                        ForEach(settingsManager.settings.distanceUnit.weatherAroundMeOptions, id: \.self) { distance in
                            Text(settingsManager.settings.distanceUnit.format(distance)).tag(distance)
                        }
                    }
                    .onChange(of: settingsManager.settings.weatherAroundMeDistance) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Default distance for Weather Around Me, currently \(settingsManager.settings.distanceUnit.format(settingsManager.settings.weatherAroundMeDistance))")
                    .accessibilityHint("Sets the default radius when viewing weather conditions around a city")
                    
                    Picker("Exploration Mode", selection: $settingsManager.settings.weatherAroundMeExplorationMode) {
                        ForEach(ExplorationMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .onChange(of: settingsManager.settings.weatherAroundMeExplorationMode) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Exploration mode, currently \(settingsManager.settings.weatherAroundMeExplorationMode.rawValue)")
                    .accessibilityHint(settingsManager.settings.weatherAroundMeExplorationMode.description)
                    
                    if settingsManager.settings.weatherAroundMeExplorationMode == .arc {
                        Picker("Arc Width", selection: $settingsManager.settings.weatherAroundMeArcWidth) {
                            ForEach(ArcWidth.allCases, id: \.self) { width in
                                Text(width.displayName).tag(width)
                            }
                        }
                        .onChange(of: settingsManager.settings.weatherAroundMeArcWidth) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Arc width, currently \(settingsManager.settings.weatherAroundMeArcWidth.displayName)")
                        .accessibilityHint(settingsManager.settings.weatherAroundMeArcWidth.description)
                    } else {
                        Picker("Corridor Width", selection: $settingsManager.settings.weatherAroundMeCorridorWidth) {
                            ForEach(CorridorWidth.allCases, id: \.self) { width in
                                Text(width.displayName).tag(width)
                            }
                        }
                        .onChange(of: settingsManager.settings.weatherAroundMeCorridorWidth) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Corridor width, currently \(settingsManager.settings.weatherAroundMeCorridorWidth.displayName)")
                        .accessibilityHint(settingsManager.settings.weatherAroundMeCorridorWidth.description)
                    }
                    
                    Toggle("Show Distance from Center Line", isOn: $settingsManager.settings.showWeatherAroundMeOffsetDistance)
                        .onChange(of: settingsManager.settings.showWeatherAroundMeOffsetDistance) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Show distance from center line")
                        .accessibilityHint("Display distance from center line for each city (e.g., '5 miles west of center line')")
                    
                    Toggle("Show Bearing", isOn: $settingsManager.settings.showWeatherAroundMeBearing)
                        .onChange(of: settingsManager.settings.showWeatherAroundMeBearing) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Show bearing")
                        .accessibilityHint("Display compass bearing for each city (e.g., '145 degrees')")
                    
                    Toggle("Show Weather Movement", isOn: $settingsManager.settings.showWeatherAroundMeMovement)
                        .onChange(of: settingsManager.settings.showWeatherAroundMeMovement) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Show weather movement")
                        .accessibilityHint("Indicate if weather is approaching, moving away, or moving parallel")
                    
                    Toggle("Show Pressure Trends", isOn: $settingsManager.settings.showWeatherAroundMePressureTrends)
                        .onChange(of: settingsManager.settings.showWeatherAroundMePressureTrends) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Show pressure trends")
                        .accessibilityHint("Display pressure changes along the path to identify weather systems")
                    
                    Toggle("Show Weather Alerts", isOn: $settingsManager.settings.showWeatherAroundMeAlerts)
                        .onChange(of: settingsManager.settings.showWeatherAroundMeAlerts) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Show weather alerts")
                        .accessibilityHint("Announce severe weather alerts for each city (e.g., 'Alert: Tornado Warning')")
                }
                
                // Browse Cities section
                Section(header: Text("Browse Cities")) {
                    Picker(selection: Binding(
                        get: { BrowseSortOrder(rawValue: defaultBrowseSortOrderRaw) ?? .nameAZ },
                        set: { defaultBrowseSortOrderRaw = $0.rawValue }
                    )) {
                        ForEach(BrowseSortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    } label: {
                        HStack {
                            Text("Default City Sort")
                            Spacer()
                            Text(BrowseSortOrder(rawValue: defaultBrowseSortOrderRaw)?.rawValue ?? "Name (A–Z)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityLabel("Default browse city sort order, currently \(BrowseSortOrder(rawValue: defaultBrowseSortOrderRaw)?.rawValue ?? "Name (A–Z)")")
                    .accessibilityHint("Sets the initial sort order when opening a state or country's city list")
                }
                
                // Features section
                Section(header: Text("Features"),
                       footer: Text("Enable or disable app features.")) {
                    Toggle("Expected Precipitation", isOn: $featureFlags.radarEnabled)
                        .accessibilityLabel("Expected Precipitation")
                        .accessibilityHint("Shows precipitation forecast visualization")
                    
                    Toggle("Weather Around Me", isOn: $featureFlags.weatherAroundMeEnabled)
                        .accessibilityLabel("Weather Around Me")
                        .accessibilityHint("Compare weather conditions in nearby cities")
                    
                    Toggle("International Weather Alerts", isOn: $featureFlags.weatherKitAlertsEnabled)
                        .accessibilityLabel("International Weather Alerts")
                        .accessibilityHint("Enable weather alerts for international cities using Apple WeatherKit. US cities always use National Weather Service.")
                }
                
                // Display preferences section
                Section(header: Text("Display Options")) {
                    Picker(selection: $settingsManager.settings.viewMode) {
                        ForEach(ViewMode.allCases.filter { $0 != .table || featureFlags.tableViewEnabled }, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    } label: {
                        HStack {
                            Text("View Mode")
                            Spacer()
                            Text(settingsManager.settings.viewMode.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settingsManager.settings.viewMode) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("View mode, currently \(settingsManager.settings.viewMode.rawValue)")
                    .accessibilityHint("Choose between Flat and List view. Table view can be enabled in Developer Settings.")

                    Picker(selection: launchCitySelection) {
                        Text("City List").tag(LaunchCity.cityList)
                        if showMyLocationOption {
                            Text("My Location").tag(LaunchCity.myLocation)
                        }
                        ForEach(weatherService.savedCities) { city in
                            Text(city.displayName).tag(LaunchCity.city(city.id))
                        }
                    } label: {
                        HStack {
                            Text("Open at Launch")
                            Spacer()
                            Text(launchCityName)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityLabel("Open at launch, currently \(launchCityName)")
                    .accessibilityHint("Choose what Weather Fast shows when it starts. This setting stays on this device.")
                    
                    Picker(selection: $settingsManager.settings.displayMode) {
                        ForEach(DisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    } label: {
                        HStack {
                            Text("List Content Display")
                            Spacer()
                            Text(settingsManager.settings.displayMode.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settingsManager.settings.displayMode) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("List content display, currently \(settingsManager.settings.displayMode.rawValue)")
                    .accessibilityHint("Condensed shows values only in List view, Details shows labels with values")
                }
                
                // City List View Data
                Section(header: Text("City List View"),
                       footer: Text("Choose which data appears in your city list. Toggle to show/hide, use VoiceOver actions to reorder.")) {
                    // Section description
                    Text("Configure what weather information appears in the city list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    ForEach(Array(settingsManager.settings.weatherFields.enumerated()), id: \.element.id) { index, field in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                            
                            Toggle(isOn: Binding(
                                get: { field.isEnabled },
                                set: { newValue in
                                    settingsManager.settings.weatherFields[index].isEnabled = newValue
                                    settingsManager.saveSettings()
                                }
                            )) {
                                Text(field.type.rawValue)
                                    .font(.body)
                            }
                            .accessibilityLabel("\(field.type.rawValue)")
                            .accessibilityHint(field.isEnabled ? "Enabled, double tap to disable" : "Disabled, double tap to enable")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Move Up") {
                            moveFieldUp(at: index)
                        }
                        .accessibilityAction(named: "Move Down") {
                            moveFieldDown(at: index)
                        }
                    }
                    .onMove { from, to in
                        settingsManager.settings.weatherFields.move(fromOffsets: from, toOffset: to)
                        settingsManager.saveSettings()
                    }
                    
                    // Daily High/Low for list view
                    Toggle("Daily High/Low", isOn: $settingsManager.settings.showDailyHighLowInCityList)
                        .onChange(of: settingsManager.settings.showDailyHighLowInCityList) {
                            settingsManager.saveSettings()
                        }
                        .accessibilityLabel("Daily High and Low temperatures")
                        .accessibilityHint(settingsManager.settings.showDailyHighLowInCityList ? "Enabled, double tap to disable" : "Disabled, double tap to enable")

                    Picker("Glance Ahead Time", selection: $settingsManager.settings.glanceAheadHours) {
                        ForEach(1...8, id: \.self) { hours in
                            Text("\(hours) \(hours == 1 ? "hour" : "hours")").tag(hours)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settingsManager.settings.glanceAheadHours) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Glance Ahead Time, \(settingsManager.settings.glanceAheadHours) \(settingsManager.settings.glanceAheadHours == 1 ? "hour" : "hours")")
                }
                
                // Hourly and Daily Display section
                Section(header: Text("Hourly and Daily Display")) {
                    Picker(selection: $settingsManager.settings.forecastDetailLayout) {
                        ForEach(ForecastDetailLayout.allCases, id: \.self) { layout in
                            Text(layout.rawValue).tag(layout)
                        }
                    } label: {
                        HStack {
                            Text("Forecast Layout")
                            Spacer()
                            Text(settingsManager.settings.forecastDetailLayout.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settingsManager.settings.forecastDetailLayout) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Forecast layout, currently \(settingsManager.settings.forecastDetailLayout.rawValue)")
                    .accessibilityHint("List shows the standard compact forecast. Headings shows each time period as a section with individual field rows.")
                }

                // Current Weather Detail Sections
                Section(header: Text("Current Weather Detail View"),
                       footer: Text("Toggle which sections appear in the current weather detail view. Use VoiceOver actions to reorder sections.")) {
                    ForEach(settingsManager.settings.detailCategories.indices, id: \.self) { index in
                        let category = settingsManager.settings.detailCategories[index]
                        
                        // Hide My Data category if feature flag is disabled
                        if category.category == .myData && !featureFlags.myDataEnabled {
                            EmptyView()
                        } else {
                        VStack(alignment: .leading, spacing: 8) {
                            // Section name as heading with move actions
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                                
                                Text(category.category.rawValue)
                                    .font(.body.weight(.semibold))
                            }
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel(category.category.rawValue)
                            .accessibilityAction(named: "Move Up") {
                                moveCategoryUp(at: index)
                            }
                            .accessibilityAction(named: "Move Down") {
                                moveCategoryDown(at: index)
                            }
                            .accessibilityAction(named: "Move to Top") {
                                moveCategoryToTop(at: index)
                            }
                            .accessibilityAction(named: "Move to Bottom") {
                                moveCategoryToBottom(at: index)
                            }
                            
                            // Description text
                            Text(categoryDescription(for: category.category))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Toggle for overall section
                            Toggle("Enable \(category.category.rawValue)", isOn: Binding(
                                get: { category.isEnabled },
                                set: { newValue in
                                    settingsManager.settings.detailCategories[index].isEnabled = newValue
                                    settingsManager.saveSettings()
                                }
                            ))
                            .accessibilityLabel("Enable \(category.category.rawValue) section")
                            .accessibilityHint(category.isEnabled ? "Enabled, double tap to disable" : "Disabled, double tap to enable")
                            
                            // Show data items for this category
                            if category.isEnabled {
                                categoryDataItems(for: category.category)
                                    .padding(.leading, 16)
                            }
                        }
                        .padding(.vertical, 8)
                        }
                    }
                    .onMove { from, to in
                        settingsManager.settings.detailCategories.move(fromOffsets: from, toOffset: to)
                        settingsManager.saveSettings()
                    }
                }
                
                // Data management section
                Section(header: Text("Data Management")) {
                    Button("Clear All Cities") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.red)
                    .accessibilityLabel("Clear all saved cities")
                    
                    Button("Reset Settings to Default") {
                        settingsManager.resetToDefaults()
                    }
                    .accessibilityLabel("Reset all settings to default values")
                }
                
                // iCloud Sync section
                Section(
                    header: Text("iCloud"),
                    footer: Text("When enabled, your settings and saved cities sync across all your devices signed in to the same Apple ID. Feature flags and Developer Settings are not synced.")
                ) {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { iCloudSyncEnabled },
                        set: { newValue in
                            guard newValue else {
                                iCloudSyncEnabled = false
                                return
                            }
                            iCloudSyncService.shared.synchronize()
                            let localCount = weatherService.savedCities.count
                            let remoteCount = iCloudSyncService.shared.pullCities()?.count ?? 0
                            if remoteCount > 0 && localCount > 0 {
                                // Both sides have cities — show dialog before committing the toggle
                                cloudCityCount = remoteCount
                                showingICloudConflictAlert = true
                            } else if remoteCount > 0 {
                                // No local cities to lose — enable and pull silently. Explicit
                                // enable with nothing local to protect, so adopt iCloud's list.
                                iCloudSyncEnabled = true
                                weatherService.applyRemoteCities(force: true)
                                if iCloudSyncService.shared.hasCloudSettings() {
                                    settingsManager.applyRemoteSettings()
                                } else {
                                    iCloudSyncService.shared.pushSettings(settingsManager.settings)
                                }
                            } else {
                                // iCloud is empty — enable and push this device's data up
                                iCloudSyncEnabled = true
                                weatherService.pushCitiesToCloud()
                                iCloudSyncService.shared.pushSettings(settingsManager.settings)
                            }
                        }
                    ))
                        .accessibilityLabel("Sync with iCloud")
                        .accessibilityHint("When enabled, your settings and saved cities sync across all your devices")
                }

                // User Guide section
                Section {
                    NavigationLink(destination: UserGuideView()) {
                        HStack {
                            Image(systemName: "book.fill")
                                .foregroundColor(.blue)
                            Text("User Guide")
                        }
                    }
                    .accessibilityLabel("User Guide")
                    .accessibilityHint("Learn how to use Weather Fast features")
                }
                
                // About section
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (build \(buildNumber))")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Version \(appVersion) build \(buildNumber)")

                    NavigationLink(destination: DataSourcesView()) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                                .accessibilityHidden(true)
                            Text("Data Sources & Attribution")
                        }
                    }
                    .accessibilityLabel("Data Sources and Attribution")
                    .accessibilityHint("View the weather and location data providers Weather Fast relies on")
                }
                
                // Developer Settings section (hidden by default)
                Section {
                    Button(action: { showingDeveloperSettings = true }) {
                        HStack {
                            Image(systemName: "hammer.fill")
                                .foregroundColor(.orange)
                            Text("Developer Settings")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityLabel("Developer Settings")
                    .accessibilityHint("Configure feature flags and experimental features")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                EditButton()
                    .accessibilityLabel("Edit weather fields order")
                    .accessibilityHint("Tap to enable reordering of weather fields")
            }
            .alert("iCloud Has a Saved City List", isPresented: $showingICloudConflictAlert) {
                Button("Use iCloud List") {
                    iCloudSyncEnabled = true
                    // Explicit user choice — adopt the iCloud list regardless of timestamps.
                    weatherService.applyRemoteCities(force: true)
                    if iCloudSyncService.shared.hasCloudSettings() {
                        settingsManager.applyRemoteSettings()
                    } else {
                        iCloudSyncService.shared.pushSettings(settingsManager.settings)
                    }
                }
                Button("Keep My List") {
                    iCloudSyncEnabled = true
                    weatherService.pushCitiesToCloud()
                    iCloudSyncService.shared.pushSettings(settingsManager.settings)
                }
                Button("Don't Sync", role: .cancel) { }
            } message: {
                let cityWord = cloudCityCount == 1 ? "city" : "cities"
                let localWord = weatherService.savedCities.count == 1 ? "city" : "cities"
                Text("iCloud has \(cloudCityCount) saved \(cityWord). This device has \(weatherService.savedCities.count) saved \(localWord). Which list would you like to use?\n\nSettings will follow the same choice. Choose \"Don't Sync\" to leave iCloud sync off and keep both lists unchanged.")
            }
            .alert("Clear All Cities", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    weatherService.savedCities.removeAll()
                    weatherService.weatherCache.removeAll()
                }
            } message: {
                Text("Are you sure you want to remove all saved cities? This action cannot be undone.")
            }
            .onChange(of: showingResetAlert) { oldValue, newValue in
                // Flash detection: Alert should never go from true to true
                if oldValue == true && newValue == true {
                    debugLog("⚠️ ALERT FLASH DETECTED in SettingsView reset alert!")
                }
            }
            .sheet(isPresented: $showingDeveloperSettings) {
                DeveloperSettingsView()
            }
            .sheet(isPresented: $showingMyDataConfig) {
                MyDataConfigView()
                    .environmentObject(settingsManager)
                    .environmentObject(weatherService)
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Helper Methods
    
    private func clearHistoricalCache() {
        // Clear cache for all saved cities
        for city in weatherService.savedCities {
            HistoricalWeatherCache.shared.clearCache(for: city)
        }
        UIAccessibility.post(notification: .announcement, argument: "Historical weather cache cleared for all cities")
    }
    
    private func moveCategoryUp(at index: Int) {
        guard index > 0 else { return }
        let categoryName = settingsManager.settings.detailCategories[index].category.rawValue
        let aboveCategoryName = settingsManager.settings.detailCategories[index - 1].category.rawValue
        settingsManager.settings.detailCategories.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(categoryName) above \(aboveCategoryName)")
    }
    
    private func moveCategoryDown(at index: Int) {
        guard index < settingsManager.settings.detailCategories.count - 1 else { return }
        let categoryName = settingsManager.settings.detailCategories[index].category.rawValue
        let belowCategoryName = settingsManager.settings.detailCategories[index + 1].category.rawValue
        settingsManager.settings.detailCategories.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(categoryName) below \(belowCategoryName)")
    }
    
    private func moveCategoryToTop(at index: Int) {
        guard index > 0 else { return }
        let categoryName = settingsManager.settings.detailCategories[index].category.rawValue
        settingsManager.settings.detailCategories.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(categoryName) to top")
    }
    
    // MARK: - Category Descriptions
    private func categoryDescription(for category: DetailCategory) -> String {
        switch category {
        case .weatherAlerts:
            return "Active weather warnings and alerts"
        case .airQuality:
            return "Air quality index, pollutants, and health guidance (observed monitors where available)"
        case .currentConditions:
            return "Temperature, wind, humidity, and atmospheric conditions"
        case .todaysForecast:
            return "Daily summary with high/low temperatures, sunrise/sunset, and precipitation alerts"
        case .hourlyForecast:
            return "24-hour detailed forecast with customizable data fields"
        case .dailyForecast:
            return "16-day forecast with customizable data fields"
        case .marineForecast:
            return "Wave heights, ocean currents, sea temperature, and tides"
        case .historicalWeather:
            return "Past year weather comparisons"
        case .location:
            return "Coordinates, elevation, and location details"
        case .myData:
            return "Your custom data points from the Open-Meteo API"
        case .astronomy:
            return "Moon phase, illumination, moonrise, and moonset"
        }
    }
    
    // MARK: - Category Data Items
    @ViewBuilder
    private func categoryDataItems(for category: DetailCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch category {
            case .weatherAlerts:
                Text("• Active weather warnings")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .airQuality:
                Text("• Air quality index and category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Pollutant breakdown and health guidance")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .currentConditions:
                Text("• Temperature, Feels Like")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Wind Speed, Direction")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Humidity, Pressure")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Wind Gusts", isOn: $settingsManager.settings.showWindGustsInCurrentConditions)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showWindGustsInCurrentConditions) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Wind gusts in current conditions")
                Toggle("UV Index", isOn: $settingsManager.settings.showUVIndexInCurrentConditions)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showUVIndexInCurrentConditions) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("UV index in current conditions")
                Toggle("Current Precipitation Rate", isOn: $settingsManager.settings.showCurrentPrecipitationInCurrentConditions)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showCurrentPrecipitationInCurrentConditions) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Current precipitation rate in current conditions")
                Toggle("Dew Point", isOn: $settingsManager.settings.showDewPoint)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showDewPoint) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Dew point in current conditions")
                
            case .todaysForecast:
                Text("• Automatic daily summary")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Sunrise, Sunset times")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Precipitation Alerts", isOn: $settingsManager.settings.showPrecipitationProbabilityInTodaysForecast)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showPrecipitationProbabilityInTodaysForecast) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Precipitation probability alerts")
                    .accessibilityHint("Shows alert when precipitation probability exceeds 20 percent")
                
                Toggle("Precipitation Amount", isOn: $settingsManager.settings.showPrecipitationAmount)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showPrecipitationAmount) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Precipitation amount")
                    .accessibilityHint("Shows rain or snow amounts when available")
                
                Toggle("UV Warnings", isOn: $settingsManager.settings.showUVIndexInTodaysForecast)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showUVIndexInTodaysForecast) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("UV warnings")
                    .accessibilityHint("Shows warning when UV index is 6 or higher")
                
                Toggle("Wind Alerts", isOn: $settingsManager.settings.showWindGustsInTodaysForecast)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showWindGustsInTodaysForecast) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Wind alerts")
                    .accessibilityHint("Shows alert when wind exceeds 25 kilometers per hour")
                
                Toggle("Daylight Duration", isOn: $settingsManager.settings.showDaylightDuration)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showDaylightDuration) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Daylight duration")
                
                Toggle("Sunshine Duration", isOn: $settingsManager.settings.showSunshineDuration)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showSunshineDuration) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Sunshine duration")
                
            case .hourlyForecast:
                Text("Configure what data appears in the 24-hour forecast")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                ForEach(settingsManager.settings.hourlyFields.indices, id: \.self) { index in
                    let field = settingsManager.settings.hourlyFields[index]
                    Toggle(field.type.rawValue, isOn: Binding(
                        get: { settingsManager.settings.hourlyFields[index].isEnabled },
                        set: { newValue in
                            settingsManager.settings.hourlyFields[index].isEnabled = newValue
                            settingsManager.saveSettings()
                        }
                    ))
                    .font(.caption)
                    .accessibilityLabel("\(field.type.rawValue) in hourly forecast")
                    .accessibilityAction(named: "Move Up") {
                        moveHourlyFieldUp(at: index)
                    }
                    .accessibilityAction(named: "Move Down") {
                        moveHourlyFieldDown(at: index)
                    }
                }
                
            case .dailyForecast:
                Text("Configure what data appears in the 16-day forecast")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                ForEach(settingsManager.settings.dailyFields.indices, id: \.self) { index in
                    let field = settingsManager.settings.dailyFields[index]
                    Toggle(field.type.rawValue, isOn: Binding(
                        get: { settingsManager.settings.dailyFields[index].isEnabled },
                        set: { newValue in
                            settingsManager.settings.dailyFields[index].isEnabled = newValue
                            settingsManager.saveSettings()
                        }
                    ))
                    .font(.caption)
                    .accessibilityLabel("\(field.type.rawValue) in daily forecast")
                    .accessibilityAction(named: "Move Up") {
                        moveDailyFieldUp(at: index)
                    }
                    .accessibilityAction(named: "Move Down") {
                        moveDailyFieldDown(at: index)
                    }
                }
                
            case .marineForecast:
                Text("Configure marine forecast data (wave heights, currents, sea temperature)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                ForEach(settingsManager.settings.marineFields.indices, id: \.self) { index in
                    let field = settingsManager.settings.marineFields[index]
                    Toggle(field.type.rawValue, isOn: Binding(
                        get: { settingsManager.settings.marineFields[index].isEnabled },
                        set: { newValue in
                            settingsManager.settings.marineFields[index].isEnabled = newValue
                            settingsManager.saveSettings()
                        }
                    ))
                    .font(.caption)
                    .accessibilityLabel("\(field.type.rawValue) in marine forecast")
                    .accessibilityAction(named: "Move Up") {
                        moveMarineFieldUp(at: index)
                    }
                    .accessibilityAction(named: "Move Down") {
                        moveMarineFieldDown(at: index)
                    }
                }
                
            case .historicalWeather:
                Text("• Past year comparisons")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Years of Data", selection: $settingsManager.settings.historicalYearsBack) {
                    ForEach(1...85, id: \.self) { years in
                        Text("\(years) \(years == 1 ? "year" : "years")").tag(years)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .onChange(of: settingsManager.settings.historicalYearsBack) {
                    settingsManager.saveSettings()
                }
                .accessibilityLabel("Years of historical data, \(settingsManager.settings.historicalYearsBack) years")
                
                Button("Clear Historical Cache") {
                    clearHistoricalCache()
                }
                .font(.caption)
                .accessibilityLabel("Clear all cached historical weather data")
                .accessibilityHint("Tap to delete cached historical data for all cities")
                
            case .location:
                Text("• Coordinates, elevation")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .astronomy:
                Text("• Moon phase and illumination percentage")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Moonrise", isOn: $settingsManager.settings.showMoonriseInAstronomy)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showMoonriseInAstronomy) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Moonrise time in astronomy section")
                Toggle("Moonset", isOn: $settingsManager.settings.showMoonsetInAstronomy)
                    .font(.caption)
                    .onChange(of: settingsManager.settings.showMoonsetInAstronomy) {
                        settingsManager.saveSettings()
                    }
                    .accessibilityLabel("Moonset time in astronomy section")
                
            case .myData:
                if settingsManager.settings.myDataFields.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No data points configured.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            showingMyDataConfig = true
                        }) {
                            Label("Choose Fields", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .accessibilityLabel("Choose My Data fields")
                        .accessibilityHint("Opens configuration to select which weather data points to display")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configure which of your selected data points appear")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(settingsManager.settings.myDataFields.indices, id: \.self) { index in
                            let field = settingsManager.settings.myDataFields[index]
                            Toggle(field.parameter.displayName, isOn: Binding(
                                get: { 
                                    guard index < settingsManager.settings.myDataFields.count else { return false }
                                    return settingsManager.settings.myDataFields[index].isEnabled 
                                },
                                set: { newValue in
                                    guard index < settingsManager.settings.myDataFields.count else { return }
                                    settingsManager.settings.myDataFields[index].isEnabled = newValue
                                    settingsManager.saveSettings()
                                }
                            ))
                            .font(.caption)
                            .accessibilityLabel("\(field.parameter.displayName) in My Data")
                            .accessibilityAction(named: "Move Up") {
                                moveMyDataFieldUp(at: index)
                            }
                            .accessibilityAction(named: "Move Down") {
                                moveMyDataFieldDown(at: index)
                            }
                            .accessibilityAction(named: "Move to Top") {
                                moveMyDataFieldToTop(at: index)
                            }
                            .accessibilityAction(named: "Move to Bottom") {
                                moveMyDataFieldToBottom(at: index)
                            }
                        }
                        .onMove { from, to in
                            settingsManager.settings.myDataFields.move(fromOffsets: from, toOffset: to)
                            settingsManager.saveSettings()
                        }
                        
                        Button(action: {
                            showingMyDataConfig = true
                        }) {
                            Label("Choose Fields", systemImage: "slider.horizontal.3")
                                .font(.caption)
                        }
                        .accessibilityLabel("Choose My Data fields")
                        .accessibilityHint("Opens configuration to add or remove weather data points")
                    }
                }
            }
        }
    }
    
    private func moveCategoryToBottom(at index: Int) {
        guard index < settingsManager.settings.detailCategories.count - 1 else { return }
        let categoryName = settingsManager.settings.detailCategories[index].category.rawValue
        settingsManager.settings.detailCategories.move(fromOffsets: IndexSet(integer: index), toOffset: settingsManager.settings.detailCategories.count)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(categoryName) to bottom")
    }
    
    private func moveFieldUp(at index: Int) {
        guard index > 0 else { return }
        let fieldName = settingsManager.settings.weatherFields[index].type.rawValue
        let aboveFieldName = settingsManager.settings.weatherFields[index - 1].type.rawValue
        settingsManager.settings.weatherFields.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) above \(aboveFieldName)")
    }
    
    private func moveFieldDown(at index: Int) {
        guard index < settingsManager.settings.weatherFields.count - 1 else { return }
        let fieldName = settingsManager.settings.weatherFields[index].type.rawValue
        let belowFieldName = settingsManager.settings.weatherFields[index + 1].type.rawValue
        settingsManager.settings.weatherFields.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) below \(belowFieldName)")
    }
    
    private func moveHourlyFieldUp(at index: Int) {
        guard index > 0 else { return }
        let fieldName = settingsManager.settings.hourlyFields[index].type.rawValue
        let aboveFieldName = settingsManager.settings.hourlyFields[index - 1].type.rawValue
        settingsManager.settings.hourlyFields.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) above \(aboveFieldName)")
    }
    
    private func moveHourlyFieldDown(at index: Int) {
        guard index < settingsManager.settings.hourlyFields.count - 1 else { return }
        let fieldName = settingsManager.settings.hourlyFields[index].type.rawValue
        let belowFieldName = settingsManager.settings.hourlyFields[index + 1].type.rawValue
        settingsManager.settings.hourlyFields.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) below \(belowFieldName)")
    }
    
    private func moveDailyFieldUp(at index: Int) {
        guard index > 0 else { return }
        let fieldName = settingsManager.settings.dailyFields[index].type.rawValue
        let aboveFieldName = settingsManager.settings.dailyFields[index - 1].type.rawValue
        settingsManager.settings.dailyFields.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) above \(aboveFieldName)")
    }
    
    private func moveDailyFieldDown(at index: Int) {
        guard index < settingsManager.settings.dailyFields.count - 1 else { return }
        let fieldName = settingsManager.settings.dailyFields[index].type.rawValue
        let belowFieldName = settingsManager.settings.dailyFields[index + 1].type.rawValue
        settingsManager.settings.dailyFields.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) below \(belowFieldName)")
    }
    
    private func moveMarineFieldUp(at index: Int) {
        guard index > 0 else { return }
        let fieldName = settingsManager.settings.marineFields[index].type.rawValue
        let aboveFieldName = settingsManager.settings.marineFields[index - 1].type.rawValue
        settingsManager.settings.marineFields.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) above \(aboveFieldName)")
    }
    
    private func moveMarineFieldDown(at index: Int) {
        guard index < settingsManager.settings.marineFields.count - 1 else { return }
        let fieldName = settingsManager.settings.marineFields[index].type.rawValue
        let belowFieldName = settingsManager.settings.marineFields[index + 1].type.rawValue
        settingsManager.settings.marineFields.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) below \(belowFieldName)")
    }
    
    private func moveMyDataFieldUp(at index: Int) {
        guard index > 0 else { return }
        let fieldName = settingsManager.settings.myDataFields[index].parameter.displayName
        let aboveFieldName = settingsManager.settings.myDataFields[index - 1].parameter.displayName
        settingsManager.settings.myDataFields.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) above \(aboveFieldName)")
    }
    
    private func moveMyDataFieldDown(at index: Int) {
        guard index < settingsManager.settings.myDataFields.count - 1 else { return }
        let fieldName = settingsManager.settings.myDataFields[index].parameter.displayName
        let belowFieldName = settingsManager.settings.myDataFields[index + 1].parameter.displayName
        settingsManager.settings.myDataFields.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) below \(belowFieldName)")
    }
    
    private func moveMyDataFieldToTop(at index: Int) {
        guard index > 0 else { return }
        let fieldName = settingsManager.settings.myDataFields[index].parameter.displayName
        settingsManager.settings.myDataFields.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) to top")
    }
    
    private func moveMyDataFieldToBottom(at index: Int) {
        guard index < settingsManager.settings.myDataFields.count - 1 else { return }
        let fieldName = settingsManager.settings.myDataFields[index].parameter.displayName
        settingsManager.settings.myDataFields.move(fromOffsets: IndexSet(integer: index), toOffset: settingsManager.settings.myDataFields.count)
        settingsManager.saveSettings()
        UIAccessibility.post(notification: .announcement, argument: "Moved \(fieldName) to bottom")
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
        .environmentObject(WeatherService())
}

// MARK: - Data Sources & Attribution

/// Lists every external provider Weather Fast relies on, what each one powers,
/// and a link to the provider so users can review terms and give proper credit.
struct DataSourcesView: View {
    var body: some View {
        List {
            Section {
                Text("Weather Fast combines several weather and mapping services to give you the most complete and accurate picture possible. We're grateful to the organizations below and encourage you to visit them.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Weather Data")) {
                DataSourceRow(
                    name: "Open-Meteo",
                    detail: "Current conditions, hourly and daily forecasts, historical weather, marine data, and precipitation nowcasts. Licensed under CC BY 4.0.",
                    urlString: "https://open-meteo.com"
                )
                DataSourceRow(
                    name: "Apple Weather",
                    detail: "Minute-by-minute precipitation nowcasts and observation-informed current conditions in supported regions, via Apple WeatherKit.",
                    urlString: "https://weatherkit.apple.com/legal-attribution.html"
                )
            }

            Section(header: Text("Air Quality")) {
                DataSourceRow(
                    name: "AirNow (U.S. EPA)",
                    detail: "Observed air quality from ground-monitor readings across the United States, from the AirNow program — a partnership led by the U.S. EPA with NOAA, the National Park Service, and state, local, and tribal agencies.",
                    urlString: "https://www.airnow.gov"
                )
                DataSourceRow(
                    name: "Copernicus Atmosphere Monitoring Service (CAMS)",
                    detail: "Modeled air-quality estimates used outside AirNow coverage and as a contrast to observed readings, delivered via the Open-Meteo air-quality API.",
                    urlString: "https://atmosphere.copernicus.eu"
                )
            }

            Section(header: Text("Weather Alerts")) {
                DataSourceRow(
                    name: "National Weather Service (NOAA)",
                    detail: "Official severe-weather alerts for the United States.",
                    urlString: "https://www.weather.gov"
                )
                DataSourceRow(
                    name: "Environment and Climate Change Canada",
                    detail: "Official weather warnings and alerts for Canada.",
                    urlString: "https://weather.gc.ca"
                )
                DataSourceRow(
                    name: "MeteoAlarm (EUMETNET)",
                    detail: "Official weather warnings for European countries, aggregated from national meteorological services.",
                    urlString: "https://meteoalarm.org"
                )
            }

            Section(header: Text("Location & Maps")) {
                DataSourceRow(
                    name: "Apple Maps",
                    detail: "Location search and place names, including points of interest such as airports and universities, via MapKit and Core Location geocoding.",
                    urlString: "https://www.apple.com/legal/internet-services/maps/terms-en.html"
                )
            }
        }
        .navigationTitle("Data Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single attribution row: the provider name, what it powers, and a link to it.
private struct DataSourceRow: View {
    let name: String
    let detail: String
    let urlString: String

    var body: some View {
        Link(destination: URL(string: urlString)!) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .accessibilityHidden(true)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name). \(detail)")
        .accessibilityHint("Opens the \(name) website")
        .accessibilityAddTraits(.isLink)
    }
}

#Preview {
    NavigationView {
        DataSourcesView()
    }
}

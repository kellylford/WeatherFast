//
//  CityDetailView.swift
//  Fast Weather
//
//  Detailed weather view for a city
//

import SwiftUI

struct CityDetailView: View {
    let city: City
    let dateOffset: Int
    let selectedDate: Date
    
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var featureFlags = FeatureFlags.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingHistoricalWeather = false
    @State private var showingRadar = false
    @State private var showingRadarLoop = false
    @State private var showingWeatherAroundMe = false
    @State private var selectedAlert: WeatherAlert?
    @State private var activeAlerts: [WeatherAlert] = []
    @State private var showingRemoveConfirmation = false
    @State private var removalCityName = "" // Captured at trigger time to prevent dialog flashing
    @State private var isRefreshing = false
    @State private var cacheMetadata: CachedWeather?
    /// Change in daylight (seconds) vs. the previous day, for the "N min more/less than
    /// yesterday" note. Fetched separately since the previous day isn't in the forecast array.
    @State private var daylightChangeSeconds: Double?
    
    // Backward compatibility initializer (defaults to today)
    init(city: City, dateOffset: Int = 0, selectedDate: Date = Date()) {
        self.city = city
        self.dateOffset = dateOffset
        self.selectedDate = selectedDate
    }
    
    private var cacheKey: WeatherCacheKey {
        WeatherCacheKey(cityId: city.id, dateOffset: dateOffset)
    }

    private var weather: WeatherData? {
        weatherService.weatherCache[cacheKey]
    }

    /// The most recent full fetch for this city/date failed. Used to surface a retry
    /// banner instead of silently showing truncated (light, 3-day/no-hourly) data.
    private var fetchFailed: Bool {
        weatherService.failedCacheKeys.contains(cacheKey)
    }
    
    private var isSaved: Bool {
        weatherService.savedCities.contains {
            $0.latitude == city.latitude && $0.longitude == city.longitude
        }
    }
    
    private func addCity() {
        weatherService.addCity(city)
        UIAccessibility.post(notification: .announcement, argument: "\(city.displayName) added to My Cities")
    }
    
    private func refreshWeather() async {
        isRefreshing = true
        await weatherService.fetchWeatherForDate(for: city, dateOffset: dateOffset)
        isRefreshing = false
        // Refresh cache metadata
        cacheMetadata = await weatherService.getCacheMetadata(for: cacheKey)
    }

    /// Ensures the detail view has full data (hourly + 16-day) when it appears, and loads
    /// cache metadata. If only light data is cached (hourly missing) it upgrades to a full
    /// fetch — even for a city the list marked failed, so opening the detail acts as a retry.
    private func loadWeather() async {
        let cached = weatherService.weatherCache[cacheKey]
        // Today/future forecasts carry hourly; a nil hourly means we only have light data.
        let needsFull = cached == nil || (dateOffset >= 0 && cached?.hourly == nil)
        if needsFull {
            await weatherService.retryFetch(for: city, dateOffset: dateOffset)
        }
        cacheMetadata = await weatherService.getCacheMetadata(for: cacheKey)
    }

    /// Clears the failure marker and re-attempts a full fetch (the "Try Again" button).
    private func retry() async {
        isRefreshing = true
        await weatherService.retryFetch(for: city, dateOffset: dateOffset)
        isRefreshing = false
        cacheMetadata = await weatherService.getCacheMetadata(for: cacheKey)
    }

    private func loadCacheMetadata() async {
        cacheMetadata = await weatherService.getCacheMetadata(for: cacheKey)
    }
    
    private func isCategoryEnabled(_ category: DetailCategory) -> Bool {
        return settingsManager.settings.detailCategories.first(where: { $0.category == category })?.isEnabled ?? true
    }
    
    @ViewBuilder
    private func detailSection(for category: DetailCategory, weather: WeatherData) -> some View {
        switch category {
        case .todaysForecast:
            if let daily = weather.daily {
                GroupBox(label: Label("Today's Forecast", systemImage: "calendar")) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Weather summary with condition
                        if let weatherCode = daily.weatherCode?.value(at: 0), let code = WeatherCode(rawValue: weatherCode) {
                            let conditionLabel = code.description(precipitationProbability: daily.precipitationProbabilityMax?.value(at: 0))
                            HStack(spacing: 8) {
                                Image(systemName: code.systemImageName)
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .accessibilityHidden(true)
                                Text(conditionLabel)
                                    .font(.headline)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Conditions: \(conditionLabel)")
                        }
                        
                        // Temperature range
                        if !daily.temperature2mMax.isEmpty, let maxTemp = daily.temperature2mMax.value(at: 0),
                           !daily.temperature2mMin.isEmpty, let minTemp = daily.temperature2mMin.value(at: 0) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Temperature Range")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                                HStack {
                                    Text(formatTemperature(minTemp))
                                        .font(.title3)
                                    Text("to")
                                        .foregroundColor(.secondary)
                                        .accessibilityHidden(true)
                                    Text(formatTemperature(maxTemp))
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Temperature: Low \(formatTemperature(minTemp)), High \(formatTemperature(maxTemp))")
                        }
                        
                        // Precipitation alert (only if significant)
                        if settingsManager.settings.showPrecipitationProbabilityInTodaysForecast,
                           let precipProb = daily.precipitationProbabilityMax?.value(at: 0), precipProb > 20 {
                            HStack(spacing: 8) {
                                Image(systemName: "drop.fill")
                                    .foregroundColor(.blue)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(precipProb)% chance of precipitation")
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    // Show snow or rain amount based on which is present (if setting enabled)
                                    if settingsManager.settings.showPrecipitationAmount {
                                        if let snowfall = daily.snowfallSum?.value(at: 0), snowfall > 0 {
                                            Text("\(formatSnowfall(snowfall)) of snow expected")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        } else if let rain = daily.rainSum?.value(at: 0), rain > 0 {
                                            Text("\(formatPrecipitation(rain)) of rain expected")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        } else if let precipSum = daily.precipitationSum?.value(at: 0), precipSum > 0 {
                                            Text("\(formatPrecipitation(precipSum)) expected")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    // Precipitation timing derived from hourly data
                                    if let timingText = precipitationTimingText(from: weather) {
                                        Text(timingText)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel({
                                var label = "\(precipProb) percent chance of precipitation"
                                if settingsManager.settings.showPrecipitationAmount {
                                    if let snowfall = daily.snowfallSum?.value(at: 0), snowfall > 0 {
                                        label += ", \(formatSnowfall(snowfall)) of snow expected"
                                    } else if let rain = daily.rainSum?.value(at: 0), rain > 0 {
                                        label += ", \(formatPrecipitation(rain)) of rain expected"
                                    } else if let precipSum = daily.precipitationSum?.value(at: 0), precipSum > 0 {
                                        label += ", \(formatPrecipitation(precipSum)) expected"
                                    }
                                }
                                if let timingText = precipitationTimingText(from: weather) {
                                    label += ", \(timingText)"
                                }
                                return label
                            }())
                        }
                        
                        // UV warning (only if significant)
                        if settingsManager.settings.showUVIndexInTodaysForecast,
                           let uvMax = daily.uvIndexMax?.value(at: 0), uvMax >= 6 {
                            let category = UVIndexCategory(uvIndex: uvMax)
                            HStack(spacing: 8) {
                                Image(systemName: "sun.max.fill")
                                    .foregroundColor(category.color)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("UV Index: \(Int(uvMax.rounded())) (\(category.category))")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Sun protection recommended")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(8)
                            .background(category.color.opacity(0.1))
                            .cornerRadius(8)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("UV Index: \(Int(uvMax.rounded())) (\(category.category)), Sun protection recommended")
                        }
                        
                        // Wind alert (only if significant)
                        if settingsManager.settings.showWindGustsInTodaysForecast,
                           let windMax = daily.windSpeed10mMax?.value(at: 0), windMax > 25 {
                            HStack(spacing: 8) {
                                Image(systemName: "wind")
                                    .foregroundColor(.orange)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Winds up to \(formatWindSpeed(windMax))")
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let windDir = daily.windDirectionDominant?.value(at: 0) {
                                        Text("From \(degreesToCardinalLong(windDir))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel({
                                var label = "Winds up to \(formatWindSpeed(windMax))"
                                if let windDir = daily.windDirectionDominant?.value(at: 0) {
                                    label += ", From \(degreesToCardinalLong(windDir))"
                                }
                                return label
                            }())
                        }
                        
                        Divider()
                        
                        // Sun times and daylight
                        VStack(spacing: 8) {
                            if let sunriseArray = daily.sunrise, !sunriseArray.isEmpty, let sunrise = sunriseArray[0],
                               let sunsetArray = daily.sunset, !sunsetArray.isEmpty, let sunset = sunsetArray[0] {
                                HStack {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sunrise.fill")
                                            .foregroundColor(.orange)
                                            .accessibilityHidden(true)
                                        Text(formatTime(sunrise))
                                            .font(.subheadline)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Sunrise: \(formatTime(sunrise))")
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "sunset.fill")
                                            .foregroundColor(.orange)
                                            .accessibilityHidden(true)
                                        Text(formatTime(sunset))
                                            .font(.subheadline)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Sunset: \(formatTime(sunset))")
                                }
                            }
                            
                            if settingsManager.settings.showDaylightDuration,
                               let daylight = daily.daylightDuration?.value(at: 0) {
                                let changePhrase = daylightChangeSeconds.flatMap { daylightChangePhrase($0) }
                                VStack(spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sun.max")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .accessibilityHidden(true)
                                        Text("\(formatDuration(daylight)) of daylight")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let changePhrase {
                                        Text(changePhrase)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(changePhrase.map {
                                    "\(formatDuration(daylight)) of daylight, \($0)"
                                } ?? "\(formatDuration(daylight)) of daylight")
                            }
                            
                            if settingsManager.settings.showSunshineDuration,
                               let sunshine = daily.sunshineDuration?.value(at: 0), sunshine > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "sun.and.horizon")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .accessibilityHidden(true)
                                    Text("\(formatDuration(sunshine)) of sunshine")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(formatDuration(sunshine)) of sunshine")
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal)
                .accessibilityElement(children: .contain)
            }
            
        case .currentConditions:
            GroupBox(label: Label("Current Conditions", systemImage: "thermometer")) {
                VStack(spacing: 12) {
                    if let humidity = weather.current.relativeHumidity2m {
                        DetailRow(label: "Humidity", value: "\(humidity)%")
                        Divider()
                    }
                    
                    // Wind Speed with Gusts (if enabled and available)
                    if let windSpeed = weather.current.windSpeed10m {
                        if settingsManager.settings.showWindGustsInCurrentConditions,
                           let windGusts = weather.current.windGusts10m,
                           let windDir = weather.current.windDirection10m {
                            DetailRow(label: "Wind", value: formatWind(speed: windSpeed, direction: windDir, gusts: windGusts, unit: settingsManager.settings.windSpeedUnit.rawValue, degreesToCardinal: degreesToCardinal))
                        } else {
                            DetailRow(label: "Wind Speed", value: formatWindSpeed(windSpeed))
                        }
                        Divider()
                    }
                    
                    if let windDir = weather.current.windDirection10m, weather.current.windSpeed10m == nil {
                        DetailRow(label: "Wind Direction", value: formatWindDirection(windDir))
                        Divider()
                    }
                    
                    // UV Index (if enabled and daytime)
                    if settingsManager.settings.showUVIndexInCurrentConditions,
                       let isDay = weather.current.isDay, isDay == 1,
                       let uvIndex = weather.current.uvIndex {
                        DetailRow(label: "UV Index", value: "\(Int(uvIndex.rounded())) (\(UVIndexCategory(uvIndex: uvIndex).category))")
                        Divider()
                    }
                    
                    // Current precipitation rate (if enabled and > 0)
                    if settingsManager.settings.showCurrentPrecipitationInCurrentConditions {
                        let currentSnow = weather.current.snowfall ?? 0
                        let currentPrecip = weather.current.precipitation ?? 0
                        if currentSnow > 0 {
                            DetailRow(label: "Snowfall", value: formatSnowfall(currentSnow))
                            Divider()
                        } else if currentPrecip > 0 {
                            let rain = weather.current.rain ?? 0
                            DetailRow(label: rain > 0 ? "Rainfall" : "Precipitation", value: formatPrecipitation(currentPrecip))
                            Divider()
                        }
                    }
                    
                    // Dew Point (if enabled)
                    if settingsManager.settings.showDewPoint,
                       let dewPoint = weather.current.dewpoint2m {
                        DetailRow(label: "Dew Point", value: formatDewPoint(dewPoint, isFahrenheit: settingsManager.settings.temperatureUnit == .fahrenheit))
                        Divider()
                    }
                    
                    if let pressure = weather.current.pressureMsl {
                        DetailRow(label: "Pressure", value: formatPressure(pressure))
                        Divider()
                    }
                    if let visibility = weather.current.visibility {
                        DetailRow(label: "Visibility", value: formatVisibility(visibility))
                        Divider()
                    }
                    // Cloud cover is a real observation only for today (dateOffset 0). On future/past
                    // days the synthetic "current" struct fills it with 0, so don't fabricate a
                    // "Cloud Cover 0%" fact for those days (product review #3).
                    if dateOffset == 0 {
                        DetailRow(label: "Cloud Cover", value: "\(weather.current.cloudCover)%")
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            
        case .hourlyForecast:
            if let hourly = weather.hourly,
               let timeArray = hourly.time,
               !timeArray.isEmpty,
               let tempArray = hourly.temperature2m,
               let weatherCodeArray = hourly.weatherCode,
               let precipArray = hourly.precipitation {
                let currentHourIndex = findCurrentHourIndex(in: timeArray)
                let startIndex = currentHourIndex >= 0 ? currentHourIndex : 0
                let endIndex = min(startIndex + 24, timeArray.count)

                if settingsManager.settings.forecastDetailLayout == .headings {
                    GroupBox(label: Label("24-Hour Forecast", systemImage: "clock")) {
                        VStack(spacing: 0) {
                            ForEach(startIndex..<endIndex, id: \.self) { index in
                                HourlyHeadingRow(
                                    hourly: hourly,
                                    index: index,
                                    settingsManager: settingsManager
                                )
                                if index < endIndex - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal)
                } else {
                    GroupBox(label: Label("24-Hour Forecast", systemImage: "clock")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(startIndex..<endIndex, id: \.self) { index in
                                    if let time = timeArray[index] {
                                        HourlyForecastCard(
                                            hourly: hourly,
                                            index: index,
                                            settingsManager: settingsManager
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
        case .dailyForecast:
            if let daily = weather.daily, daily.temperature2mMax.count > 1 {
                if settingsManager.settings.forecastDetailLayout == .headings {
                    GroupBox(label: Label("16-Day Forecast", systemImage: "calendar")) {
                        VStack(spacing: 0) {
                            DailyForecastSummaryView(daily: daily, settingsManager: settingsManager)
                                .padding(.horizontal)
                                .padding(.top, 4)
                                .padding(.bottom, 8)
                            Divider()
                            ForEach(0..<min(16, daily.temperature2mMax.count), id: \.self) { index in
                                DailyHeadingBlock(
                                    city: city,
                                    weather: weather,
                                    daily: daily,
                                    index: index,
                                    settingsManager: settingsManager
                                )
                                if index < min(15, daily.temperature2mMax.count - 1) {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal)
                } else {
                    GroupBox(label: Label("16-Day Forecast", systemImage: "calendar")) {
                        VStack(spacing: 0) {
                            DailyForecastSummaryView(daily: daily, settingsManager: settingsManager)
                                .padding(.horizontal)
                                .padding(.top, 4)
                                .padding(.bottom, 8)
                            Divider()
                            ForEach(0..<min(16, daily.temperature2mMax.count), id: \.self) { index in
                                NavigationLink(destination: DayDetailView(
                                    city: city,
                                    dayIndex: index,
                                    weather: weather,
                                    settingsManager: settingsManager
                                )) {
                                    DailyForecastRow(
                                        daily: daily,
                                        index: index,
                                        settingsManager: settingsManager
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Double tap to see detailed forecast for this day")

                                if index < min(15, daily.temperature2mMax.count - 1) {
                                    Divider()
                                        .padding(.leading)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal)
                }
            }
            
        case .marineForecast:
            MarineForecastSection(city: city, dateOffset: dateOffset)
            
        case .historicalWeather:
            EmptyView() // Historical weather moved to separate screen
            
        case .weatherAlerts:
            // Weather alerts section (US only)
            WeatherAlertsSection(city: city, selectedAlert: $selectedAlert, alerts: $activeAlerts)
                .onAppear {
                    debugLog("🔶 WeatherAlerts category appeared for \(city.name)")
                }

        case .airQuality:
            // Air quality section — observation-first, alert-aware. Feature-flagged.
            // US-only for now: AirNow observed data and NWS air quality alerts are
            // US-only, so the international modeled-only path is gated off until it
            // has region-correct AQI (European AQI) and an international alert source.
            if featureFlags.airQualityEnabled && city.country == "United States" {
                AirQualitySection(city: city, selectedAlert: $selectedAlert)
            }
            
        case .location:
            GroupBox(label: Label("Location", systemImage: "mappin.and.ellipse")) {
                VStack(spacing: 12) {
                    DetailRow(label: "City", value: city.name)
                    if let state = city.state {
                        Divider()
                        DetailRow(label: "State", value: state)
                    }
                    Divider()
                    DetailRow(label: "Country", value: city.country)
                    Divider()
                    DetailRow(label: "Coordinates", value: String(format: "%.4f, %.4f", city.latitude, city.longitude))
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            
        case .myData:
            if featureFlags.myDataEnabled {
                let enabledFields = settingsManager.settings.myDataFields.filter { $0.isEnabled }
                if !enabledFields.isEmpty {
                    GroupBox(label: Label("My Data", systemImage: "chart.bar.doc.horizontal")) {
                        VStack(spacing: 12) {
                            ForEach(Array(enabledFields.enumerated()), id: \.element.id) { index, field in
                                if index > 0 {
                                    Divider()
                                }
                                let value = myDataValue(for: field.parameter, weather: weather)
                                DetailRow(
                                    label: field.parameter.displayName,
                                    value: value
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal)
                    .accessibilityElement(children: .contain)
                } else {
                    GroupBox(label: Label("My Data", systemImage: "chart.bar.doc.horizontal")) {
                        Text("No data points selected. Configure in Settings, then Developer Settings, then My Data.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)
                    }
                    .padding(.horizontal)
                    .accessibilityElement(children: .contain)
                }
            }
            
        case .astronomy:
            GroupBox(label: Label("Astronomy", systemImage: "moon.stars")) {
                VStack(spacing: 12) {
                    let moonPhase = MoonCalculator.phase(for: selectedDate)
                    let phaseName = MoonCalculator.phaseName(for: selectedDate)
                    let illuminationPct = MoonCalculator.illumination(for: selectedDate)
                    let phaseSymbol = MoonCalculator.phaseSymbol(for: selectedDate)

                    // Phase icon + name
                    HStack(spacing: 12) {
                        Image(systemName: phaseSymbol)
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phaseName)
                                .font(.headline)
                            Text("\(Int(illuminationPct.rounded()))% illuminated")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Moon phase: \(phaseName), \(Int(illuminationPct.rounded())) percent illuminated")

                    Divider()

                    // Moonrise / Moonset
                    let moonTimes = MoonCalculator.riseAndSet(
                        for: selectedDate,
                        latitude: city.latitude,
                        longitude: city.longitude
                    )

                    // MoonCalculator returns absolute UTC dates; render them in the CITY's timezone
                    // so moon times match sunrise/sunset (which are city-local). Without this they
                    // rendered in device-local time — wrong for any remote city (product review #5).
                    let timeFormatter: DateFormatter = {
                        let f = DateFormatter()
                        f.dateFormat = "h:mm a"
                        f.timeZone = weather.timeZone
                        return f
                    }()

                    if settingsManager.settings.showMoonriseInAstronomy || settingsManager.settings.showMoonsetInAstronomy {
                        HStack {
                            if settingsManager.settings.showMoonriseInAstronomy {
                                HStack(spacing: 4) {
                                    Image(systemName: "moon.circle")
                                        .foregroundColor(.secondary)
                                        .accessibilityHidden(true)
                                    if let rise = moonTimes.rise {
                                        Text(timeFormatter.string(from: rise))
                                            .font(.subheadline)
                                    } else {
                                        Text("—")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Moonrise: \(moonTimes.rise.map { timeFormatter.string(from: $0) } ?? "not available")")
                            }

                            if settingsManager.settings.showMoonriseInAstronomy && settingsManager.settings.showMoonsetInAstronomy {
                                Spacer()
                            }

                            if settingsManager.settings.showMoonsetInAstronomy {
                                HStack(spacing: 4) {
                                    Image(systemName: "moon.circle.fill")
                                        .foregroundColor(.secondary)
                                        .accessibilityHidden(true)
                                    if let set = moonTimes.set {
                                        Text(timeFormatter.string(from: set))
                                            .font(.subheadline)
                                    } else {
                                        Text("—")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Moonset: \(moonTimes.set.map { timeFormatter.string(from: $0) } ?? "not available")")
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
        }
    }
    
    /// Shown when the full forecast fetch failed. Tells the user the data on screen may
    /// be incomplete and offers a retry, rather than silently presenting truncated data.
    private var forecastErrorBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text("Couldn't load the full forecast")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text("The 16-day and hourly forecast may be incomplete. Check your connection and try again.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await retry() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
            .accessibilityHint("Reloads the full 16-day and hourly forecast")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.orange.opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }

    var body: some View {
        let _ = debugLog("🟢 CityDetailView body called for \(city.name), selectedAlert: \(selectedAlert?.event ?? "nil")")
        ScrollView {
            VStack(spacing: 24) {
                // Full-fetch failure banner — shown whether or not partial (light) data
                // is present, so a truncated forecast is never displayed as if complete.
                if fetchFailed {
                    forecastErrorBanner
                }

                if let weather = weather {
                    // Cache status indicator (if data is stale)
                    if let metadata = cacheMetadata, metadata.isStale {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.orange)
                                .accessibilityHidden(true)
                            Text("Using cached data from \(metadata.ageDescription)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Weather data is \(metadata.ageDescription), tap refresh to update")
                    }
                    
                    // Main weather display
                    VStack(spacing: 16) {
                        if dateOffset == 0 {
                            // Today: a real current temperature — read first after city name.
                            Text(formatTemperature(weather.current.temperature2m))
                                .font(.system(size: 72, weight: .bold))
                                .accessibilityLabel("Current temperature \(formatTemperature(weather.current.temperature2m))")
                        } else {
                            // Future/past day: the synthetic "current" temperature is a min/max
                            // average, not a real reading. Show the day's forecast High and Low
                            // instead of a fabricated "current" (product review #3).
                            let dayHigh = weather.daily?.temperature2mMax.value(at: 0)
                            let dayLow = weather.daily?.temperature2mMin.value(at: 0)
                            VStack(spacing: 4) {
                                if let hi = dayHigh {
                                    Text("High \(formatTemperature(hi))")
                                        .font(.system(size: 56, weight: .bold))
                                }
                                if let lo = dayLow {
                                    Text("Low \(formatTemperature(lo))")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(forecastHighLowLabel(high: dayHigh, low: dayLow))
                        }

                        // Temperature and condition
                        if let weatherCode = weather.current.weatherCodeEnum {
                            Image(systemName: weatherCode.systemImageName(isDay: (weather.current.isDay ?? 1) == 1))
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                                .accessibilityHidden(true)

                            Text(weatherCode.description)
                                .font(.title2)
                                .accessibilityLabel("Conditions: \(weatherCode.description)")
                        }

                        // "Feels like" is a real current reading only for today; on other days it
                        // would be a min/max average of apparent temp, so omit it (product review #3).
                        if dateOffset == 0, let apparentTemp = weather.current.apparentTemperature {
                            Text("Feels like \(formatTemperature(apparentTemp))")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    
                    // Add to My Cities (shown when browsing a city not yet in saved list)
                    if !isSaved {
                        Button(action: addCity) {
                            Label("Add to My Cities", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .accessibilityLabel("Add \(city.displayName) to My Cities")
                    }
                    
                    // Actions Menu
                    Menu {
                        Button(action: {
                            Task {
                                await refreshWeather()
                            }
                        }) {
                            Label("Refresh Weather", systemImage: "arrow.clockwise")
                        }
                        
                        Divider()
                        
                        Button(action: { showingHistoricalWeather = true }) {
                            Label("View Historical Weather", systemImage: "clock.arrow.circlepath")
                        }
                        
                        if featureFlags.radarEnabled {
                            Button(action: { showingRadar = true }) {
                                Label("Expected Precipitation", systemImage: "cloud.rain")
                            }
                        }

                        if featureFlags.radarLoopEnabled {
                            Button(action: { showingRadarLoop = true }) {
                                Label("Radar", systemImage: "antenna.radiowaves.left.and.right")
                            }
                        }
                        
                        if featureFlags.weatherAroundMeEnabled {
                            Button(action: { showingWeatherAroundMe = true }) {
                                Label("Weather Around Me", systemImage: "location.circle")
                            }
                        }
                        
                        if isSaved {
                            Divider()
                            
                            Button(role: .destructive, action: { 
                                removalCityName = city.name
                                showingRemoveConfirmation = true 
                            }) {
                                Label("Remove City", systemImage: "trash")
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                            Text("Actions")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .accessibilityLabel("Actions menu")
                    .accessibilityHint("Opens menu with options to refresh weather, view historical weather, precipitation forecast, weather around me, and remove city")
                    
                    // Dynamically render detail sections based on settings order
                    let _ = debugLog("📊 Detail categories: \(settingsManager.settings.detailCategories.map { "\($0.category)=\($0.isEnabled)" }.joined(separator: ", "))")
                    ForEach(settingsManager.settings.detailCategories) { categoryField in
                        if categoryField.isEnabled {
                            detailSection(for: categoryField.category, weather: weather)
                        }
                    }
                    
                } else if !fetchFailed {
                    ProgressView("Loading weather data...")
                        .padding()
                }
                // When fetchFailed and there's no cached data, the banner above stands alone
                // instead of spinning forever.
            }
            .padding(.vertical)
        }
        .navigationTitle(city.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let text = shareText {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: URL(string: "https://apps.apple.com/us/app/weather-fast/id6757891543")!,
                        subject: Text(shareSubject),
                        message: Text(text)
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share weather forecast")
                }
            }
        }
        .task {
            await loadWeather()
        }
        .task(id: "\(city.id)-\(dateOffset)-daylight") {
            // Reset first so a stale other-city value never flashes while this loads.
            daylightChangeSeconds = nil
            guard settingsManager.settings.showDaylightDuration else { return }
            daylightChangeSeconds = await weatherService.fetchDaylightChangeVsPreviousDay(for: city, dateOffset: dateOffset)
        }
        .refreshable {
            await refreshWeather()
        }
        .sheet(isPresented: $showingHistoricalWeather) {
            NavigationView {
                HistoricalWeatherView(city: city)
                    .navigationTitle("Historical Weather")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingHistoricalWeather = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingRadar) {
            NavigationView {
                RadarView(city: city)
                    .environmentObject(settingsManager)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingRadar = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingRadarLoop) {
            NavigationView {
                RadarLoopView(city: city)
                    .environmentObject(settingsManager)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") {
                                showingRadarLoop = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingWeatherAroundMe) {
            NavigationView {
                WeatherAroundMeView(city: city, defaultDistance: settingsManager.settings.weatherAroundMeDistance)
                    .environmentObject(settingsManager)
                    .environmentObject(weatherService)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingWeatherAroundMe = false
                            }
                        }
                    }
            }
        }
        .sheet(item: $selectedAlert) { alert in
            AlertDetailView(alert: alert)
        }
        .confirmationDialog(
            "Remove \(removalCityName)?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                dismiss()
                // Defer removal until after dismiss animation completes to avoid UICollectionView crash
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    weatherService.removeCity(city)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This city will be removed from your list.")
        }
        .onChange(of: showingRemoveConfirmation) { oldValue, newValue in
            // Flash detection: Alert should never go from true to true
            if oldValue == true && newValue == true {
                debugLog("⚠️ ALERT FLASH DETECTED in CityDetailView confirmation dialog!")
            }
        }
    }
    
    private func formatTemperature(_ celsius: Double) -> String {
        let temp = settingsManager.settings.temperatureUnit.convert(celsius)
        let unit = settingsManager.settings.temperatureUnit == .fahrenheit ? "F" : "C"
        return String(format: "%.0f°%@", temp, unit)
    }

    /// VoiceOver label for the future/past-day forecast High/Low hero (product review #3).
    private func forecastHighLowLabel(high: Double?, low: Double?) -> String {
        switch (high, low) {
        case let (hi?, lo?): return "Forecast high \(formatTemperature(hi)), low \(formatTemperature(lo))"
        case let (hi?, nil): return "Forecast high \(formatTemperature(hi))"
        case let (nil, lo?): return "Forecast low \(formatTemperature(lo))"
        default: return "Forecast temperature unavailable"
        }
    }

    /// "1 minute less than yesterday" / "2 minutes more than today" for the daylight change.
    /// Always compares the displayed day against the day before it; the reference word tracks
    /// the day-navigation offset so it reads naturally both looking back and looking forward:
    /// today→"yesterday", tomorrow→"today", any other day→"the previous day". Returns nil when
    /// the change rounds to under a minute (near the solstices), so we omit the note rather
    /// than showing "0 minutes".
    private func daylightChangePhrase(_ deltaSeconds: Double) -> String? {
        let minutes = Int((abs(deltaSeconds) / 60).rounded())
        guard minutes >= 1 else { return nil }
        let unit = minutes == 1 ? "minute" : "minutes"
        let direction = deltaSeconds >= 0 ? "more" : "less"
        let reference: String
        switch dateOffset {
        case 0: reference = "yesterday"
        case 1: reference = "today"
        default: reference = "the previous day"
        }
        return "\(minutes) \(unit) \(direction) than \(reference)"
    }

    private var shareSubject: String {
        guard let weather = weather else {
            return "Weather Forecast – \(city.displayName)"
        }
        let current = weather.current
        let isFahrenheit = settingsManager.settings.temperatureUnit == .fahrenheit
        let unit = isFahrenheit ? "F" : "C"
        let temp = settingsManager.settings.temperatureUnit.convert(current.temperature2m)
        let tempStr = String(format: "%.0f°%@", temp, unit)
        let condStr = WeatherCode(rawValue: current.weatherCode)?.description ?? ""
        let alertPrefix = activeAlerts.isEmpty ? "" : "⚠️ "
        if condStr.isEmpty {
            return "\(alertPrefix)\(city.displayName) – \(tempStr)"
        }
        return "\(alertPrefix)\(city.displayName) – \(tempStr), \(condStr)"
    }

    private var shareText: String? {
        guard let weather = weather else { return nil }
        let current = weather.current
        let daily = weather.daily

        let isFahrenheit = settingsManager.settings.temperatureUnit == .fahrenheit
        let unit = isFahrenheit ? "F" : "C"

        func fmt(_ celsius: Double) -> String {
            let t = settingsManager.settings.temperatureUnit.convert(celsius)
            return String(format: "%.0f°%@", t, unit)
        }

        // Header line: city + current conditions
        var lines: [String] = []
        var condParts: [String] = [WeatherCode(rawValue: current.weatherCode)?.description ?? ""]
        condParts.append(fmt(current.temperature2m))
        if let feels = current.apparentTemperature {
            condParts.append("(Feels like \(fmt(feels)))")
        }
        lines.append("\(city.displayName) — \(condParts.filter { !$0.isEmpty }.joined(separator: ", "))")

        // Active weather alerts — shown before forecast details
        if !activeAlerts.isEmpty {
            lines.append("")
            lines.append("⚠️ Active Weather Alerts:")
            for alert in activeAlerts {
                lines.append("• \(alert.severity.rawValue): \(alert.event) — \(alert.headline)")
            }
        }

        lines.append("")

        // Up to 3 days from daily forecast
        if let daily = daily {
            let calendar = Calendar.current
            let displayFmt = DateFormatter()
            displayFmt.dateFormat = "EEE, MMM d"
            let shortFmt = DateFormatter()
            shortFmt.dateFormat = "MMM d"

            let count = min(3, daily.temperature2mMax.count)
            for i in 0..<count {
                let date = calendar.date(byAdding: .day, value: i, to: selectedDate) ?? selectedDate
                let label = i == 0 ? "Today, \(shortFmt.string(from: date))" : displayFmt.string(from: date)

                var parts: [String] = []
                if let wc = daily.weatherCode?.value(at: i), let code = WeatherCode(rawValue: wc) {
                    parts.append(code.description)
                }
                if let hi = daily.temperature2mMax.value(at: i) {
                    parts.append("High \(fmt(hi))")
                }
                if let lo = daily.temperature2mMin.value(at: i) {
                    parts.append("Low \(fmt(lo))")
                }
                if let prob = daily.precipitationProbabilityMax?.value(at: i), prob > 0 {
                    parts.append("\(prob)% chance of precipitation")
                }
                lines.append("\(label): \(parts.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatWindSpeed(_ kmh: Double) -> String {
        let speed = settingsManager.settings.windSpeedUnit.convert(kmh)
        return String(format: "%.1f %@", speed, settingsManager.settings.windSpeedUnit.rawValue)
    }
    
    private func formatWindDirection(_ degrees: Int) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(degrees) / 45.0).rounded()) % 8
        return "\(directions[index]) (\(degrees)°)"
    }
    
    private func formatPrecipitation(_ mm: Double) -> String {
        let precip = settingsManager.settings.precipitationUnit.convert(mm)
        return String(format: "%.2f %@", precip, settingsManager.settings.precipitationUnit.rawValue)
    }
    
    private func formatSnowfall(_ cm: Double) -> String {
        // Snow is measured in cm (API) → convert to inches for US, keep cm elsewhere
        switch settingsManager.settings.precipitationUnit {
        case .inches:
            let inches = cm * 0.393701
            return String(format: "%.1f in", inches)
        case .millimeters:
            return String(format: "%.1f cm", cm)
        }
    }
    
    private func formatPressure(_ hPa: Double) -> String {
        let pressure = settingsManager.settings.pressureUnit.convert(hPa)
        let formatString = settingsManager.settings.pressureUnit == .hPa ? "%.0f %@" : "%.2f %@"
        return String(format: formatString, pressure, settingsManager.settings.pressureUnit.rawValue)
    }
    
    private func formatVisibility(_ meters: Double) -> String {
        let km = meters / 1000.0
        let distance = settingsManager.settings.distanceUnit.convert(km)
        return settingsManager.settings.distanceUnit.format(distance, decimals: 1)
    }
    
    private func formatTime(_ isoString: String) -> String {
        FormatHelper.formatTime(isoString)
    }
    
    /// Get the formatted display value for a My Data parameter from weather data
    private func myDataValue(for parameter: MyDataParameter, weather: WeatherData) -> String {
        let current = weather.current
        
        // Check named properties first for already-decoded fields
        let rawValue: Double?
        switch parameter {
        case .temperature2m: rawValue = current.temperature2m
        case .apparentTemperature: rawValue = current.apparentTemperature
        case .relativeHumidity2m: rawValue = current.relativeHumidity2m.map { Double($0) }
        case .dewPoint2m: rawValue = current.dewpoint2m
        case .windSpeed10m: rawValue = current.windSpeed10m
        case .windDirection10m: rawValue = current.windDirection10m.map { Double($0) }
        case .windGusts10m: rawValue = current.windGusts10m
        case .precipitation: rawValue = current.precipitation
        case .rain: rawValue = current.rain
        case .showers: rawValue = current.showers
        case .snowfall: rawValue = current.snowfall
        case .pressureMsl: rawValue = current.pressureMsl
        case .cloudCover: rawValue = Double(current.cloudCover)
        case .visibility: rawValue = current.visibility
        case .weatherCode: rawValue = Double(current.weatherCode)
        case .isDay: rawValue = current.isDay.map { Double($0) }
        case .uvIndex: rawValue = current.uvIndex
        default:
            rawValue = current.myDataValues?[parameter.apiKey]
        }
        
        guard let value = rawValue else { return "N/A" }
        return MyDataFormatHelper.format(parameter: parameter, value: value, settings: settingsManager.settings)
    }
    
    private func precipitationTimingText(from weather: WeatherData) -> String? {
        guard let hourly = weather.hourly,
              let timeArray = hourly.time else { return nil }

        let cityTimeZone = weather.timeZone
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityTimeZone

        let currentIndex = findCurrentHourIndex(in: timeArray)
        let probThreshold = 40       // percent
        let amountThreshold = 1.0    // mm — catches high-amount hours even when PoP is below threshold

        // Collect indices of rainy hours remaining today (in city-local time)
        var rainyIndices: [Int] = []
        for i in currentIndex..<min(currentIndex + 24, timeArray.count) {
            guard let timeStr = timeArray[i],
                  let hourDate = DateParser.parse(timeStr, in: cityTimeZone) else { continue }
            guard cityCalendar.isDateInToday(hourDate) else { break }
            let prob = (hourly.precipitationProbability.flatMap { arr in i < arr.count ? arr[i] : nil } ?? nil) ?? 0
            let amount = (hourly.precipitation.flatMap { arr in i < arr.count ? arr[i] : nil } ?? nil) ?? 0.0
            if prob >= probThreshold || amount >= amountThreshold {
                rainyIndices.append(i)
            }
        }

        guard !rainyIndices.isEmpty else { return nil }

        // Determine precipitation type label for natural VoiceOver reading
        let precipType: String
        if let snow = weather.daily?.snowfallSum?[0], snow > 0 {
            precipType = "Snow"
        } else if let rain = weather.daily?.rainSum?[0], rain > 0 {
            precipType = "Rain"
        } else {
            precipType = "Precipitation"
        }

        if rainyIndices.count >= 8 {
            return "\(precipType) expected throughout the day"
        }

        // Build contiguous windows (allow 1-hour gap to merge nearby showers)
        var windows: [(start: Int, end: Int)] = []
        var windowStart = rainyIndices[0]
        var windowEnd = rainyIndices[0]
        for i in 1..<rainyIndices.count {
            if rainyIndices[i] <= rainyIndices[i - 1] + 2 {
                windowEnd = rainyIndices[i]
            } else {
                windows.append((windowStart, windowEnd))
                windowStart = rainyIndices[i]
                windowEnd = rainyIndices[i]
            }
        }
        windows.append((windowStart, windowEnd))

        func timeLabel(_ index: Int) -> String {
            guard index < timeArray.count, let s = timeArray[index] else { return "" }
            return FormatHelper.formatTimeCompact(s)
        }

        let parts = windows.prefix(2).map { w -> String in
            return w.start == w.end
                ? "around \(timeLabel(w.start))"
                : "\(timeLabel(w.start))–\(timeLabel(w.end))"
        }
        let suffix = windows.count > 2 ? " and later" : ""
        return "\(precipType) most likely " + parts.joined(separator: " and ") + suffix
    }

    private func findCurrentHourIndex(in times: [String?]) -> Int {
        let now = Date()
        let cityTimeZone = weather?.timeZone ?? .current
        for (index, timeString) in times.enumerated() {
            guard let timeString = timeString,
                  let time = DateParser.parse(timeString, in: cityTimeZone) else { continue }
            if time >= now {
                return index
            }
        }
        // All hours are in the past (stale data): fall back to the most recent hour
        // rather than the oldest, so we don't surface long-past hours as "current" — HI-8.
        return max(0, times.count - 1)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        // ViewThatFits tries the inline HStack first. The value Text uses
        // .fixedSize(horizontal: true) so it expresses its full natural width,
        // which lets ViewThatFits correctly detect when label + value exceed
        // the available width and switch to the stacked fallback instead of
        // silently truncating or trailing-wrapping the value.
        ViewThatFits(in: .horizontal) {
            // Preferred: single-row inline layout
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer(minLength: 16)
                Text(value)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            // Fallback: stacked layout when value is too long for inline
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundColor(.secondary)
                Text(value)
                    .fontWeight(.medium)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct HourlyForecastCard: View {
    let hourly: WeatherData.HourlyWeather
    let index: Int
    @ObservedObject var settingsManager: SettingsManager
    
    private var time: String? {
        hourly.time?[index]
    }
    
    private var formattedTime: String {
        guard let time = time else { return "--" }
        return FormatHelper.formatTimeCompact(time)
    }
    
    private var weatherCodeEnum: WeatherCode? {
        guard let code = hourly.weatherCode?[index] else { return nil }
        return WeatherCode(rawValue: code)
    }

    private var isDayTime: Bool {
        guard let t = time,
              let tIdx = t.firstIndex(of: "T") else { return true }
        let hourStr = String(t[t.index(after: tIdx)...].prefix(2))
        let hour = Int(hourStr) ?? 12
        return hour >= 6 && hour < 20
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(formattedTime)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Build content based on enabled fields
            ForEach(settingsManager.settings.hourlyFields.filter { $0.isEnabled }, id: \.id) { field in
                if let content = getFieldContent(for: field.type) {
                    content
                }
            }
        }
        .frame(minWidth: 70)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(createAccessibilityLabel())
    }
    
    private func getFieldContent(for fieldType: HourlyFieldType) -> AnyView? {
        switch fieldType {
        case .temperature:
            if let temp = hourly.temperature2m?[index] {
                return AnyView(Text(formatTemperature(temp))
                    .font(.body)
                    .fontWeight(.semibold))
            }
            
        case .conditions:
            if let weatherCode = weatherCodeEnum {
                return AnyView(Image(systemName: weatherCode.systemImageName(isDay: isDayTime))
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(height: 30))
            }
            
        case .precipitationProbability:
            if let prob = hourly.precipitationProbability?[index], prob > 0 {
                return AnyView(HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("\(prob)%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                })
            }
            
        case .precipitation:
            let snowfallAmt = hourly.snowfall?[index] ?? 0
            if snowfallAmt > 0 {
                return AnyView(HStack(spacing: 2) {
                    Image(systemName: "snowflake")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(formatSnowfall(snowfallAmt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                })
            } else if let precip = hourly.precipitation?[index], precip > 0 {
                return AnyView(HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(formatPrecipitation(precip))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                })
            }
            
        case .snowfall:
            if let snow = hourly.snowfall?[index], snow > 0 {
                return AnyView(HStack(spacing: 2) {
                    Image(systemName: "snowflake")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(formatSnowfall(snow))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                })
            }
            
        case .uvIndex:
            if let uv = hourly.uvIndex?[index], uv > 0 {
                let category = UVIndexCategory(uvIndex: uv)
                return AnyView(Text("\(Int(uv.rounded()))")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(category.color.opacity(0.2))
                    .foregroundColor(category.color)
                    .cornerRadius(4))
            }
            
        case .windSpeed:
            if let windSpeed = hourly.windSpeed10m?[index], windSpeed > 0 {
                return AnyView(HStack(spacing: 2) {
                    Image(systemName: "wind")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatWindSpeed(windSpeed))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                })
            }
            
        case .windGusts:
            if let windGusts = hourly.windGusts10m?[index], windGusts > 0 {
                return AnyView(HStack(spacing: 2) {
                    Image(systemName: "wind")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(formatWindSpeed(windGusts))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                })
            }
            
        case .humidity:
            if let humidity = hourly.relativeHumidity2m?[index] {
                return AnyView(HStack(spacing: 2) {
                    Image(systemName: "humidity")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("\(humidity)%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                })
            }
            
        default:
            break
        }
        return nil
    }
    
    private func createAccessibilityLabel() -> String {
        guard let time = time else { return "No data" }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var hourDescription = formattedTime
        if let date = formatter.date(from: time) {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            let ampm = hour < 12 ? "AM" : "PM"
            let hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            hourDescription = minute > 0 ? "\(hour12):\(String(format: "%02d", minute)) \(ampm)" : "\(hour12) \(ampm)"
        }
        
        var label = hourDescription
        
        // Add enabled fields to label
        for field in settingsManager.settings.hourlyFields.filter({ $0.isEnabled }) {
            if let fieldText = getFieldAccessibilityText(for: field.type) {
                label += ", \(fieldText)"
            }
        }
        
        return label
    }
    
    private func getFieldAccessibilityText(for fieldType: HourlyFieldType) -> String? {
        switch fieldType {
        case .temperature:
            if let temp = hourly.temperature2m?[index] {
                return formatTemperature(temp)
            }
            
        case .conditions:
            return weatherCodeEnum?.description
            
        case .precipitationProbability:
            if let prob = hourly.precipitationProbability?[index], prob > 0 {
                return "\(prob) percent chance of precipitation"
            }
            
        case .precipitation:
            let snowfallAmt = hourly.snowfall?[index] ?? 0
            if snowfallAmt > 0 {
                return "snowfall \(formatSnowfall(snowfallAmt))"
            } else if let precip = hourly.precipitation?[index], precip > 0 {
                return "precipitation \(formatPrecipitation(precip))"
            }
            
        case .snowfall:
            if let snow = hourly.snowfall?[index], snow > 0 {
                return "snowfall \(formatSnowfall(snow))"
            }
            
        case .uvIndex:
            if let uv = hourly.uvIndex?[index], uv > 0 {
                return getUVIndexDescription(uv)
            }
            
        case .windSpeed:
            if let windSpeed = hourly.windSpeed10m?[index], windSpeed > 0 {
                return "wind \(formatWindSpeed(windSpeed))"
            }
            
        case .windGusts:
            if let windGusts = hourly.windGusts10m?[index], windGusts > 0 {
                return "gusts \(formatWindSpeed(windGusts))"
            }
            
        case .humidity:
            if let humidity = hourly.relativeHumidity2m?[index] {
                return "humidity \(humidity) percent"
            }
            
        default:
            return nil
        }
        
        return nil
    }
    
    private func formatTemperature(_ celsius: Double) -> String {
        let temp = settingsManager.settings.temperatureUnit.convert(celsius)
        let unit = settingsManager.settings.temperatureUnit == .fahrenheit ? "F" : "C"
        return String(format: "%.0f°%@", temp, unit)
    }
    
    private func formatPrecipitation(_ mm: Double) -> String {
        let precip = settingsManager.settings.precipitationUnit.convert(mm)
        return String(format: "%.2f %@", precip, settingsManager.settings.precipitationUnit.rawValue)
    }
    
    private func formatSnowfall(_ cm: Double) -> String {
        switch settingsManager.settings.precipitationUnit {
        case .inches:
            return String(format: "%.1f in", cm * 0.393701)
        case .millimeters:
            return String(format: "%.1f cm", cm)
        }
    }
    
    private func formatWindSpeed(_ kmh: Double) -> String {
        let speed = settingsManager.settings.windSpeedUnit.convert(kmh)
        return String(format: "%.0f %@", speed, settingsManager.settings.windSpeedUnit.rawValue)
    }
}

// MARK: - Hourly Heading Row (headings layout mode)

struct HourlyHeadingRow: View {
    let hourly: WeatherData.HourlyWeather
    let index: Int
    @ObservedObject var settingsManager: SettingsManager

    private var formattedTime: String {
        guard let time = hourly.time?[index] else { return "--" }
        return FormatHelper.formatTimeCompact(time)
    }

    private var weatherCodeEnum: WeatherCode? {
        guard let code = hourly.weatherCode?[index] else { return nil }
        return WeatherCode(rawValue: code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(formattedTime)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(formattedTime)

            ForEach(settingsManager.settings.hourlyFields.filter { $0.isEnabled }, id: \.id) { field in
                if let (label, value) = fieldText(for: field.type) {
                    Divider().padding(.leading, 16)
                    DetailRow(label: label, value: value)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private func fieldText(for fieldType: HourlyFieldType) -> (String, String)? {
        switch fieldType {
        case .temperature:
            if let temp = hourly.temperature2m?[index] {
                return ("Temperature", formatTemperature(temp))
            }
        case .conditions:
            if let code = weatherCodeEnum {
                return ("Conditions", code.description)
            }
        case .precipitationProbability:
            if let prob = hourly.precipitationProbability?[index], prob > 0 {
                return ("Precipitation Probability", "\(prob)%")
            }
        case .precipitation:
            if let snow = hourly.snowfall?[index], snow > 0 {
                return ("Snowfall", formatSnowfall(snow))
            } else if let precip = hourly.precipitation?[index], precip > 0 {
                return ("Precipitation", formatPrecipitation(precip))
            }
        case .snowfall:
            if let snow = hourly.snowfall?[index], snow > 0 {
                return ("Snowfall", formatSnowfall(snow))
            }
        case .uvIndex:
            if let uv = hourly.uvIndex?[index], uv > 0 {
                let category = UVIndexCategory(uvIndex: uv)
                return ("UV Index", "\(Int(uv.rounded())) – \(category.category)")
            }
        case .windSpeed:
            if let speed = hourly.windSpeed10m?[index], speed > 0 {
                return ("Wind Speed", formatWindSpeed(speed))
            }
        case .windGusts:
            if let gusts = hourly.windGusts10m?[index], gusts > 0 {
                return ("Wind Gusts", formatWindSpeed(gusts))
            }
        case .humidity:
            if let humidity = hourly.relativeHumidity2m?[index] {
                return ("Humidity", "\(humidity)%")
            }
        case .cloudCover:
            if let cloud = hourly.cloudCover?[index] {
                return ("Cloud Cover", "\(cloud)%")
            }
        case .dewPoint:
            if let dew = hourly.dewPoint2m?[index] {
                return ("Dew Point", formatTemperature(dew))
            }
        default:
            break
        }
        return nil
    }

    private func formatTemperature(_ celsius: Double) -> String {
        let temp = settingsManager.settings.temperatureUnit.convert(celsius)
        let unit = settingsManager.settings.temperatureUnit == .fahrenheit ? "F" : "C"
        return String(format: "%.0f°%@", temp, unit)
    }

    private func formatPrecipitation(_ mm: Double) -> String {
        let precip = settingsManager.settings.precipitationUnit.convert(mm)
        return String(format: "%.2f %@", precip, settingsManager.settings.precipitationUnit.rawValue)
    }

    private func formatSnowfall(_ cm: Double) -> String {
        switch settingsManager.settings.precipitationUnit {
        case .inches: return String(format: "%.1f in", cm * 0.393701)
        case .millimeters: return String(format: "%.1f cm", cm)
        }
    }

    private func formatWindSpeed(_ kmh: Double) -> String {
        let speed = settingsManager.settings.windSpeedUnit.convert(kmh)
        return String(format: "%.0f %@", speed, settingsManager.settings.windSpeedUnit.rawValue)
    }
}

// MARK: - 16-Day Forecast Summary

struct DailyForecastSummaryView: View {
    let daily: WeatherData.DailyWeather
    @ObservedObject var settingsManager: SettingsManager

    private var dayCount: Int {
        min(16, daily.temperature2mMax.count)
    }

    private var isFahrenheit: Bool {
        settingsManager.settings.temperatureUnit == .fahrenheit
    }

    // Returns a natural-language day label with the calendar date included.
    // e.g. "today", "tomorrow", "Thursday, March 5"
    private func dayLabel(for index: Int) -> String {
        guard let sunriseStr = daily.sunrise?.value(at: index), let date = DateParser.parse(sunriseStr) else {
            return "day \(index + 1)"
        }
        if index == 0 { return "today" }
        if index == 1 { return "tomorrow" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: date)
    }

    // Formats a list of day indices as natural English: "March 3", "March 3 and March 5",
    // "March 3, March 5, and March 7". For 4+ items just returns the count phrase.
    private func dateList(indices: [Int], noun: String) -> String {
        guard !indices.isEmpty else { return "" }
        let shortFmt = DateFormatter()
        shortFmt.dateFormat = "MMM d"

        func shortDate(_ index: Int) -> String {
            guard let sunriseStr = daily.sunrise?.value(at: index), let date = DateParser.parse(sunriseStr) else {
                return "day \(index + 1)"
            }
            if index == 0 { return "today" }
            if index == 1 { return "tomorrow" }
            return shortFmt.string(from: date)
        }

        switch indices.count {
        case 1:
            return "\(noun) on \(shortDate(indices[0]))"
        case 2:
            return "\(noun) on \(shortDate(indices[0])) and \(shortDate(indices[1]))"
        case 3:
            return "\(noun) on \(shortDate(indices[0])), \(shortDate(indices[1])), and \(shortDate(indices[2]))"
        default:
            return "\(noun) on \(indices.count) days"
        }
    }

    // Temperature trend: compare first-3-day average high vs last-3-day average high
    private var temperatureTrendText: String? {
        guard dayCount >= 6 else { return nil }
        let highs = (0..<dayCount).compactMap { daily.temperature2mMax.value(at: $0) }
        guard highs.count >= 6 else { return nil }

        let firstAvg = highs.prefix(3).reduce(0, +) / 3.0
        let lastAvg = highs.suffix(3).reduce(0, +) / 3.0
        let threshold = isFahrenheit ? 5.0 : 3.0
        let diff = lastAvg - firstAvg
        guard abs(diff) >= threshold else { return nil }

        let convert = settingsManager.settings.temperatureUnit.convert
        let unit = settingsManager.settings.temperatureUnit.rawValue
        let firstVal = Int(convert(firstAvg).rounded())
        let lastVal = Int(convert(lastAvg).rounded())

        if diff > 0 {
            // Warming trend — mention peak with date if notably above ending average
            if let peakHigh = highs.max(), peakHigh > lastAvg + threshold,
               let peakIndex = (0..<dayCount).first(where: { (daily.temperature2mMax.value(at: $0) ?? 0) == peakHigh }) {
                let peakVal = Int(convert(peakHigh).rounded())
                return "Highs climb from \(firstVal)\(unit) to \(lastVal)\(unit) over the next \(dayCount) days, with a peak of \(peakVal)\(unit) on \(dayLabel(for: peakIndex))."
            } else {
                return "Highs climb from \(firstVal)\(unit) to \(lastVal)\(unit) over the next \(dayCount) days."
            }
        } else {
            // Cooling trend — mention trough with date if notably below ending average
            if let troughLow = highs.min(), troughLow < lastAvg - threshold,
               let troughIndex = (0..<dayCount).first(where: { (daily.temperature2mMax.value(at: $0) ?? 0) == troughLow }) {
                let troughVal = Int(convert(troughLow).rounded())
                return "Highs fall from \(firstVal)\(unit) to \(lastVal)\(unit) over the next \(dayCount) days, with a low of \(troughVal)\(unit) on \(dayLabel(for: troughIndex))."
            } else {
                return "Highs fall from \(firstVal)\(unit) to \(lastVal)\(unit) over the next \(dayCount) days."
            }
        }
    }

    // Precipitation summary: collect specific day indices for snow and rain
    private var precipitationText: String {
        var rainIndices: [Int] = []
        var snowIndices: [Int] = []

        for i in 0..<dayCount {
            let prob = daily.precipitationProbabilityMax?.value(at: i)
            let precip = daily.precipitationSum?.value(at: i)
            let snow = daily.snowfallSum?.value(at: i)

            let isWet: Bool
            if let p = prob {
                isWet = p >= 40
            } else {
                isWet = (precip ?? 0) > 0.5 || (snow ?? 0) > 0.1
            }

            if isWet {
                if (snow ?? 0) > 0.1 {
                    snowIndices.append(i)
                } else {
                    rainIndices.append(i)
                }
            }
        }

        let wetCount = rainIndices.count + snowIndices.count

        switch (wetCount, snowIndices.count) {
        case (0, _):
            return "Dry conditions expected throughout the period."
        case (_, 0):
            // Rain only
            return "\(dateList(indices: rainIndices, noun: "Rain expected").capitalized)."
        case (let w, let s) where s == w:
            // Snow only
            return "\(dateList(indices: snowIndices, noun: "Snow expected").capitalized)."
        default:
            // Mix — lead with snow dates, then mention total rain days
            let snowPart = dateList(indices: snowIndices, noun: "snow")
            let rainCount = rainIndices.count
            let rainPart = rainCount == 1 ? "rain on 1 other day" : "rain on \(rainCount) other days"
            return "Precipitation expected, with \(snowPart) and \(rainPart)."
        }
    }

    // Wind alert: only mention if any day exceeds 56 km/h (~35 mph)
    private var windAlertText: String? {
        let thresholdKmh = 56.0
        guard let windSpeeds = daily.windSpeed10mMax else { return nil }

        var maxSpeed = 0.0
        var maxIndex = 0
        for i in 0..<dayCount {
            let speed = windSpeeds.value(at: i) ?? 0
            if speed > maxSpeed {
                maxSpeed = speed
                maxIndex = i
            }
        }
        guard maxSpeed > thresholdKmh else { return nil }

        let convertedSpeed = Int(settingsManager.settings.windSpeedUnit.convert(maxSpeed).rounded())
        let unit = settingsManager.settings.windSpeedUnit.rawValue
        return "Strong winds up to \(convertedSpeed) \(unit) expected \(dayLabel(for: maxIndex))."
    }

    private var summaryText: String {
        var parts: [String] = []
        if let trend = temperatureTrendText { parts.append(trend) }
        parts.append(precipitationText)
        if let wind = windAlertText { parts.append(wind) }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Text(summaryText)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(summaryText)
    }
}

struct DailyForecastRow: View {
    let daily: WeatherData.DailyWeather
    let index: Int
    @ObservedObject var settingsManager: SettingsManager
    
    private var sunrise: String? {
        daily.sunrise?.value(at: index)
    }
    
    private var high: Double? {
        daily.temperature2mMax.value(at: index)
    }
    
    private var low: Double? {
        daily.temperature2mMin.value(at: index)
    }
    
    private var dayName: String {
        guard let sunrise = sunrise, let date = DateParser.parse(sunrise) else {
            debugLog("⚠️ DailyForecastRow: Failed to parse sunrise '\(sunrise ?? "nil")' for day \(index)")
            return "Unknown Date"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let dateString = dateFormatter.string(from: date)
        
        if index == 0 {
            return "Today, \(dateString)"
        } else if index == 1 {
            return "Tomorrow, \(dateString)"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            let weekdayName = dayFormatter.string(from: date)
            return "\(weekdayName), \(dateString)"
        }
    }
    
    private var weatherCodeEnum: WeatherCode? {
        if let code = daily.weatherCode?.value(at: index) {
            return WeatherCode(rawValue: code)
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            // ── Row 1: Day label (greedy width) + temperatures (pinned right) ──────────
            // Day name gets all remaining space after the temperatures, so it never
            // gets squeezed regardless of screen size or how many other fields are shown.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayName)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                
                // Temperatures are always .fixedSize so they never wrap or clip
                if isFieldEnabled(.temperatureMin) && isFieldEnabled(.temperatureMax),
                   let low = low, let high = high {
                    HStack(spacing: 8) {
                        Text(formatTemperature(low))
                            .foregroundColor(.secondary)
                        Text(formatTemperature(high))
                            .fontWeight(.semibold)
                    }
                    .font(.body)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
                } else if isFieldEnabled(.temperatureMax), let high = high {
                    Text(formatTemperature(high))
                        .font(.body)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityHidden(true)
                } else if isFieldEnabled(.temperatureMin), let low = low {
                    Text(formatTemperature(low))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityHidden(true)
                }
            }
            
            // ── Row 2: Condition icon + description + inline precipitation badges ────
            // This row has the full screen width available, so condition text can use
            // as much space as needed and truncates gracefully only if the user has
            // enabled many inline badges.
            let hasInlineContent: Bool = weatherCodeEnum != nil ||
                settingsManager.settings.dailyFields
                    .filter { $0.isEnabled }
                    .contains { getInlineFieldContent(for: $0.type) != nil }
            
            if hasInlineContent {
                HStack(alignment: .center, spacing: 8) {
                    if let weatherCode = weatherCodeEnum {
                        Image(systemName: weatherCode.systemImageName)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .accessibilityHidden(true)
                        
                        // Show condition description when the conditions field is enabled
                        if isFieldEnabled(.conditions) {
                            Text(weatherCode.description(precipitationProbability: daily.precipitationProbabilityMax?.value(at: index)))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .accessibilityHidden(true)
                        }
                    }
                    
                    Spacer()
                    
                    // Inline precipitation / accumulation badges
                    ForEach(settingsManager.settings.dailyFields.filter { $0.isEnabled }, id: \.id) { field in
                        if let content = getInlineFieldContent(for: field.type) {
                            content
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            
            // ── Row 3: Secondary detail fields (UV, daylight, sunshine, max wind) ────
            if hasAdditionalDetails() {
                HStack(spacing: 12) {
                    ForEach(settingsManager.settings.dailyFields.filter { $0.isEnabled }, id: \.id) { field in
                        if let content = getDetailFieldContent(for: field.type) {
                            content
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(createAccessibilityLabel())
    }
    
    private func getInlineFieldContent(for fieldType: DailyFieldType) -> AnyView? {
        switch fieldType {
        case .precipitationProbability:
            if let prob = daily.precipitationProbabilityMax?.value(at: index), prob > 0 {
                return AnyView(HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(prob)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 50))
            }
            
        case .rainSum:
            if let rain = daily.rainSum?.value(at: index), rain > 0 {
                return AnyView(HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(formatPrecipitation(rain))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 50))
            }
            
        case .snowfallSum:
            if let snow = daily.snowfallSum?.value(at: index), snow > 0 {
                return AnyView(HStack(spacing: 4) {
                    Image(systemName: "snowflake")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(formatSnowfall(snow))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 50))
            }
            
        case .precipitationSum:
            // Prefer snowfall in proper units when snow is expected; fall back to liquid total
            if let snow = daily.snowfallSum?.value(at: index), snow > 0 {
                return AnyView(HStack(spacing: 4) {
                    Image(systemName: "snowflake")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(formatSnowfall(snow))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 50))
            } else if let precip = daily.precipitationSum?.value(at: index), precip > 0 {
                return AnyView(HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(formatPrecipitation(precip))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 50))
            }
            
        default:
            break
        }
        return nil
    }
    
    private func getDetailFieldContent(for fieldType: DailyFieldType) -> AnyView? {
        switch fieldType {
        case .uvIndexMax:
            if let uvMax = daily.uvIndexMax?.value(at: index), uvMax > 0 {
                let category = UVIndexCategory(uvIndex: uvMax)
                return AnyView(HStack(spacing: 4) {
                    Text("UV:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(uvMax.rounded()))")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(category.color.opacity(0.2))
                        .foregroundColor(category.color)
                        .cornerRadius(4)
                })
            }
            
        case .daylightDuration:
            if let daylight = daily.daylightDuration?.value(at: index) {
                return AnyView(HStack(spacing: 4) {
                    Image(systemName: "sun.max")
                        .font(.caption2)
                    Text(formatDuration(daylight))
                        .font(.caption2)
                }
                .foregroundColor(.secondary))
            }
            
        case .sunshineDuration:
            if let sunshine = daily.sunshineDuration?.value(at: index) {
                return AnyView(HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(.caption2)
                    Text(formatDuration(sunshine))
                        .font(.caption2)
                }
                .foregroundColor(.secondary))
            }
            
        case .windSpeedMax:
            if let windMax = daily.windSpeed10mMax?.value(at: index), windMax > 0 {
                return AnyView(HStack(spacing: 4) {
                    Image(systemName: "wind")
                        .font(.caption2)
                    Text(formatWindSpeed(windMax))
                        .font(.caption2)
                }
                .foregroundColor(.secondary))
            }
            
        default:
            break
        }
        return nil
    }
    
    private func hasAdditionalDetails() -> Bool {
        for field in settingsManager.settings.dailyFields.filter({ $0.isEnabled }) {
            switch field.type {
            case .uvIndexMax, .daylightDuration, .sunshineDuration, .windSpeedMax:
                if getDetailFieldContent(for: field.type) != nil {
                    return true
                }
            default:
                continue
            }
        }
        return false
    }
    
    private func isFieldEnabled(_ type: DailyFieldType) -> Bool {
        settingsManager.settings.dailyFields.first(where: { $0.type == type })?.isEnabled ?? false
    }
    
    private func createAccessibilityLabel() -> String {
        var text = dayName
        
        // Add enabled fields to label
        for field in settingsManager.settings.dailyFields.filter({ $0.isEnabled }) {
            if let fieldText = getFieldAccessibilityText(for: field.type) {
                text += ", \(fieldText)"
            }
        }
        
        return text
    }
    
    private func getFieldAccessibilityText(for fieldType: DailyFieldType) -> String? {
        switch fieldType {
        case .conditions:
            return weatherCodeEnum?.description(precipitationProbability: daily.precipitationProbabilityMax?.value(at: index))

        case .temperatureMax:
            if let high = high {
                return "High \(formatTemperature(high))"
            }
            
        case .temperatureMin:
            if let low = low {
                return "Low \(formatTemperature(low))"
            }
            
        case .precipitationProbability:
            if let prob = daily.precipitationProbabilityMax?.value(at: index), prob > 0 {
                return "\(prob) percent chance of precipitation"
            }
            
        case .rainSum:
            if let rain = daily.rainSum?.value(at: index), rain > 0 {
                return "\(formatPrecipitation(rain)) of rain"
            }
            
        case .snowfallSum:
            if let snow = daily.snowfallSum?.value(at: index), snow > 0 {
                return "\(formatSnowfall(snow)) of snow"
            }
            
        case .precipitationSum:
            if let snow = daily.snowfallSum?.value(at: index), snow > 0 {
                return "\(formatSnowfall(snow)) of snow"
            } else if let precip = daily.precipitationSum?.value(at: index), precip > 0 {
                return "precipitation \(formatPrecipitation(precip))"
            }
            
        case .uvIndexMax:
            if let uvMax = daily.uvIndexMax?.value(at: index) {
                return getUVIndexDescription(uvMax)
            }
            
        case .daylightDuration:
            if let daylight = daily.daylightDuration?.value(at: index) {
                return "\(formatDuration(daylight)) of daylight"
            }
            
        case .sunshineDuration:
            if let sunshine = daily.sunshineDuration?.value(at: index) {
                return "\(formatDuration(sunshine)) of sunshine"
            }
            
        case .windSpeedMax:
            if let windMax = daily.windSpeed10mMax?.value(at: index) {
                return "max wind \(formatWindSpeed(windMax))"
            }
            
        case .sunrise:
            if let sunrise = sunrise {
                return "Sunrise \(FormatHelper.formatTime(sunrise))"
            }
            
        case .sunset:
            if let sunset = daily.sunset?.value(at: index) {
                return "Sunset \(FormatHelper.formatTime(sunset))"
            }
            
        default:
            return nil
        }
        
        return nil
    }
    
    private func formatTemperature(_ celsius: Double) -> String {
        let temp = settingsManager.settings.temperatureUnit.convert(celsius)
        let unit = settingsManager.settings.temperatureUnit == .fahrenheit ? "F" : "C"
        return String(format: "%.0f°%@", temp, unit)
    }
    
    private func formatPrecipitation(_ mm: Double) -> String {
        let precip = settingsManager.settings.precipitationUnit.convert(mm)
        return String(format: "%.1f %@", precip, settingsManager.settings.precipitationUnit.rawValue)
    }
    
    private func formatSnowfall(_ cm: Double) -> String {
        switch settingsManager.settings.precipitationUnit {
        case .inches:
            return String(format: "%.1f in", cm * 0.393701)
        case .millimeters:
            return String(format: "%.1f cm", cm)
        }
    }
    
    private func formatWindSpeed(_ kmh: Double) -> String {
        let speed = settingsManager.settings.windSpeedUnit.convert(kmh)
        return String(format: "%.0f %@", speed, settingsManager.settings.windSpeedUnit.rawValue)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)

        if minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(hours)h"
        }
    }
}

// MARK: - Daily Heading Block (headings layout mode)

struct DailyHeadingBlock: View {
    let city: City
    let weather: WeatherData
    let daily: WeatherData.DailyWeather
    let index: Int
    @ObservedObject var settingsManager: SettingsManager

    private var sunrise: String? { daily.sunrise?.value(at: index) }

    private var dayName: String {
        guard let s = sunrise, let date = DateParser.parse(s) else { return "Unknown Date" }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let dateString = dateFormatter.string(from: date)
        if index == 0 { return "Today, \(dateString)" }
        if index == 1 { return "Tomorrow, \(dateString)" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        return "\(dayFormatter.string(from: date)), \(dateString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(destination: DayDetailView(
                city: city,
                dayIndex: index,
                weather: weather,
                settingsManager: settingsManager
            )) {
                HStack {
                    Text(dayName)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Double tap to see detailed forecast for this day")

            ForEach(settingsManager.settings.dailyFields.filter { $0.isEnabled }, id: \.id) { field in
                if let (label, value) = fieldText(for: field.type) {
                    Divider().padding(.leading, 16)
                    DetailRow(label: label, value: value)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private func fieldText(for fieldType: DailyFieldType) -> (String, String)? {
        switch fieldType {
        case .temperatureMax:
            if let high = daily.temperature2mMax.value(at: index) {
                return ("High", formatTemperature(high))
            }
        case .temperatureMin:
            if let low = daily.temperature2mMin.value(at: index) {
                return ("Low", formatTemperature(low))
            }
        case .conditions:
            if let code = daily.weatherCode?.value(at: index), let wc = WeatherCode(rawValue: code) {
                return ("Conditions", wc.description(precipitationProbability: daily.precipitationProbabilityMax?.value(at: index)))
            }
        case .sunrise:
            if let s = sunrise {
                return ("Sunrise", FormatHelper.formatTime(s))
            }
        case .sunset:
            if let s = daily.sunset?.value(at: index) {
                return ("Sunset", FormatHelper.formatTime(s))
            }
        case .precipitationSum:
            if let snow = daily.snowfallSum?.value(at: index), snow > 0 {
                return ("Snowfall", formatSnowfall(snow))
            } else if let precip = daily.precipitationSum?.value(at: index), precip > 0 {
                return ("Precipitation", formatPrecipitation(precip))
            }
        case .precipitationProbability:
            if let prob = daily.precipitationProbabilityMax?.value(at: index), prob > 0 {
                return ("Precipitation Probability", "\(prob)%")
            }
        case .rainSum:
            if let rain = daily.rainSum?.value(at: index), rain > 0 {
                return ("Rain Total", formatPrecipitation(rain))
            }
        case .snowfallSum:
            if let snow = daily.snowfallSum?.value(at: index), snow > 0 {
                return ("Snowfall Total", formatSnowfall(snow))
            }
        case .windSpeedMax:
            if let speed = daily.windSpeed10mMax?.value(at: index), speed > 0 {
                return ("Max Wind Speed", formatWindSpeed(speed))
            }
        case .windDirectionDominant:
            if let degrees = daily.windDirectionDominant?.value(at: index) {
                return ("Wind Direction", formatWindDirection(degrees))
            }
        case .uvIndexMax:
            if let uv = daily.uvIndexMax?.value(at: index), uv > 0 {
                let category = UVIndexCategory(uvIndex: uv)
                return ("UV Index Max", "\(Int(uv.rounded())) – \(category.category)")
            }
        case .daylightDuration:
            if let daylight = daily.daylightDuration?.value(at: index) {
                return ("Daylight Duration", formatDuration(daylight))
            }
        case .sunshineDuration:
            if let sunshine = daily.sunshineDuration?.value(at: index) {
                return ("Sunshine Duration", formatDuration(sunshine))
            }
        default:
            break
        }
        return nil
    }

    private func formatTemperature(_ celsius: Double) -> String {
        let temp = settingsManager.settings.temperatureUnit.convert(celsius)
        let unit = settingsManager.settings.temperatureUnit == .fahrenheit ? "F" : "C"
        return String(format: "%.0f°%@", temp, unit)
    }

    private func formatPrecipitation(_ mm: Double) -> String {
        let precip = settingsManager.settings.precipitationUnit.convert(mm)
        return String(format: "%.1f %@", precip, settingsManager.settings.precipitationUnit.rawValue)
    }

    private func formatSnowfall(_ cm: Double) -> String {
        switch settingsManager.settings.precipitationUnit {
        case .inches: return String(format: "%.1f in", cm * 0.393701)
        case .millimeters: return String(format: "%.1f cm", cm)
        }
    }

    private func formatWindSpeed(_ kmh: Double) -> String {
        let speed = settingsManager.settings.windSpeedUnit.convert(kmh)
        return String(format: "%.0f %@", speed, settingsManager.settings.windSpeedUnit.rawValue)
    }

    private func formatWindDirection(_ degrees: Int) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((Double(degrees) / 45.0).rounded()) % 8
        return "\(directions[idx]) (\(degrees)°)"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}

// MARK: - Weather Alerts Section
struct WeatherAlertsSection: View {
    let city: City
    @Binding var selectedAlert: WeatherAlert?
    @Binding var alerts: [WeatherAlert]
    @EnvironmentObject var weatherService: WeatherService
    @State private var isLoading = true
    @State private var hasLoaded = false  // Prevent re-fetching on every appear
    @State private var loadFailed = false // Distinguish "couldn't check" from "no alerts"

    var body: some View {
        GroupBox(label: Label("Weather Alerts", systemImage: "exclamationmark.triangle.fill")) {
            VStack(spacing: 12) {
                if isLoading {
                    ProgressView("Checking for alerts...")
                        .frame(minHeight: 60)  // Consistent height to prevent layout shift
                        .padding()
                } else if loadFailed {
                    // A fetch failure must never look like "no alerts" for a safety feature.
                    VStack(spacing: 8) {
                        Text("Couldn't check for alerts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Try Again") {
                            Task { await loadAlerts() }
                        }
                        .accessibilityHint("Retries checking for weather alerts")
                    }
                    .frame(minHeight: 60)
                    .padding()
                } else if alerts.isEmpty {
                    Text("No active alerts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(minHeight: 60)  // Match loading height
                        .padding()
                } else {
                    ForEach(alerts) { alert in
                        Button(action: {
                            debugLog("🔔 Alert button tapped: \(alert.event)")
                            selectedAlert = alert
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: alert.severity.iconName)
                                            .foregroundColor(alert.severity.color)
                                        Text(alert.event)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Text(alert.headline)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(alert.severity.rawValue.capitalized) alert: \(alert.event)")
                        .accessibilityHint("Double tap to view alert details")
                        
                        if alert.id != alerts.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: isLoading)  // Smooth transition
        }
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .task(id: city.id) {
            guard !hasLoaded else { return }
            await loadAlerts()
        }
    }

    private func loadAlerts() async {
        isLoading = true
        loadFailed = false
        do {
            let fetchedAlerts = try await weatherService.fetchNWSAlerts(for: city)
            alerts = fetchedAlerts.sorted { $0.severity.sortOrder < $1.severity.sortOrder }
            isLoading = false
            hasLoaded = true
        } catch {
            // Could not determine alert state — show the "couldn't check" state, not "no alerts".
            isLoading = false
            loadFailed = true
            hasLoaded = true
        }
    }
}

// MARK: - Marine Forecast Section

struct MarineForecastSection: View {
    let city: City
    let dateOffset: Int
    
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var isLoading = false
    
    private var marineData: MarineData? {
        let cacheKey = WeatherCacheKey(cityId: city.id, dateOffset: dateOffset)
        return weatherService.marineCache[cacheKey]
    }
    
    private func enabledFields() -> [MarineFieldType] {
        settingsManager.settings.marineFields
            .filter { $0.isEnabled }
            .map { $0.type }
    }
    
    // Find index of current hour (or next available hour) in time array
    private func findCurrentHourIndex(in times: [String?]) -> Int {
        let now = Date()
        let cityTimeZone = weatherService.weatherCache[
            WeatherCacheKey(cityId: city.id, dateOffset: dateOffset)
        ]?.timeZone ?? .current
        for (index, timeString) in times.enumerated() {
            guard let timeString = timeString,
                  let time = DateParser.parse(timeString, in: cityTimeZone) else { continue }
            if time >= now {
                return index
            }
        }
        // All hours are in the past (stale data): fall back to the most recent hour
        // rather than the oldest, so we don't surface long-past hours as "current" — HI-8.
        return max(0, times.count - 1)
    }
    
    var body: some View {
        Group {
            GroupBox(label: Label("Marine Forecast", systemImage: "water.waves")) {
                    if isLoading {
                        ProgressView("Loading marine data...")
                            .frame(minHeight: 100)
                            .padding()
                    } else if dateOffset < 0 {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundColor(.orange)
                            Text("Historical marine data not available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(minHeight: 100)
                        .padding()
                    } else if let marine = marineData, let hourly = marine.hourly {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                // Show next 24 hours starting from current hour (like hourly forecast)
                                if let timeArray = hourly.time, !timeArray.isEmpty {
                                    let currentHourIndex = findCurrentHourIndex(in: timeArray)
                                    let startIndex = currentHourIndex >= 0 ? currentHourIndex : 0
                                    let endIndex = min(startIndex + 24, timeArray.count)
                                    
                                    ForEach(startIndex..<endIndex, id: \.self) { index in
                                        MarineForecastCard(hourly: hourly, index: index, enabledFields: enabledFields())
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal)
        }
        .task(id: "\(city.id)-\(dateOffset)") {
            isLoading = true
            await weatherService.fetchMarineData(for: city, dateOffset: dateOffset)
            isLoading = false
        }
    }
}

// MARK: - Marine Forecast Card

struct MarineForecastCard: View {
    let hourly: MarineData.MarineHourly
    let index: Int
    let enabledFields: [MarineFieldType]
    
    @EnvironmentObject var settingsManager: SettingsManager
    
    private var timeString: String {
        guard let time = hourly.time?[index] else { return "Unknown" }
        return FormatHelper.formatTimeCompact(time)
    }
    
    private func formatWaveHeight(_ meters: Double?) -> String {
        guard let meters = meters else { return "—" }
        // NWS uses feet for wave heights in US waters, meters internationally
        if settingsManager.settings.distanceUnit == .miles {
            let feet = meters * 3.28084
            return String(format: "%.1f ft", feet)
        } else {
            return String(format: "%.1f m", meters)
        }
    }
    
    private func formatDirection(_ degrees: Int?) -> String {
        guard let degrees = degrees else { return "—" }
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(degrees) + 22.5) / 45.0) % 8
        return "\(directions[index]) (\(degrees)°)"
    }
    
    private func formatPeriod(_ seconds: Double?) -> String {
        guard let seconds = seconds else { return "—" }
        return String(format: "%.1f s", seconds)
    }
    
    private func formatTemperature(_ celsius: Double?) -> String {
        guard let celsius = celsius else { return "—" }
        let converted = settingsManager.settings.temperatureUnit.convert(celsius)
        return String(format: "%.1f%@", converted, settingsManager.settings.temperatureUnit.rawValue)
    }
    
    private func formatVelocity(_ kmh: Double?) -> String {
        guard let kmh = kmh else { return "—" }
        // NWS uses knots for marine velocities (1 knot = 1.852 km/h)
        // For consistency with app settings, we use windSpeedUnit but could add knots as option
        let converted = settingsManager.settings.windSpeedUnit.convert(kmh)
        return String(format: "%.1f %@", converted, settingsManager.settings.windSpeedUnit.rawValue)
    }
    
    private func formatSeaLevel(_ meters: Double?) -> String {
        guard let meters = meters else { return "—" }
        // NWS uses feet for sea level/tides in US waters, meters internationally
        if settingsManager.settings.distanceUnit == .miles {
            let feet = meters * 3.28084
            return String(format: "%.2f ft", feet)
        } else {
            return String(format: "%.2f m", meters)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(timeString)
                .font(.headline)
                .foregroundColor(.primary)
            
            ForEach(enabledFields, id: \.self) { field in
                switch field {
                case .waveHeight:
                    if let value = hourly.waveHeight?[index] {
                        MarineDataRow(label: "Wave Height", value: formatWaveHeight(value))
                    }
                case .waveDirection:
                    if let value = hourly.waveDirection?[index] {
                        MarineDataRow(label: "Wave Direction", value: formatDirection(value))
                    }
                case .wavePeriod:
                    if let value = hourly.wavePeriod?[index] {
                        MarineDataRow(label: "Wave Period", value: formatPeriod(value))
                    }
                case .wavePeakPeriod:
                    if let value = hourly.wavePeakPeriod?[index] {
                        MarineDataRow(label: "Peak Period", value: formatPeriod(value))
                    }
                case .windWaveHeight:
                    if let value = hourly.windWaveHeight?[index] {
                        MarineDataRow(label: "Wind Wave", value: formatWaveHeight(value))
                    }
                case .windWaveDirection:
                    if let value = hourly.windWaveDirection?[index] {
                        MarineDataRow(label: "Wind Wave Dir", value: formatDirection(value))
                    }
                case .windWavePeriod:
                    if let value = hourly.windWavePeriod?[index] {
                        MarineDataRow(label: "Wind Wave Period", value: formatPeriod(value))
                    }
                case .swellWaveHeight:
                    if let value = hourly.swellWaveHeight?[index] {
                        MarineDataRow(label: "Swell Height", value: formatWaveHeight(value))
                    }
                case .swellWaveDirection:
                    if let value = hourly.swellWaveDirection?[index] {
                        MarineDataRow(label: "Swell Direction", value: formatDirection(value))
                    }
                case .swellWavePeriod:
                    if let value = hourly.swellWavePeriod?[index] {
                        MarineDataRow(label: "Swell Period", value: formatPeriod(value))
                    }
                case .oceanCurrentVelocity:
                    if let value = hourly.oceanCurrentVelocity?[index] {
                        MarineDataRow(label: "Current Speed", value: formatVelocity(value))
                    }
                case .oceanCurrentDirection:
                    if let value = hourly.oceanCurrentDirection?[index] {
                        MarineDataRow(label: "Current Dir", value: formatDirection(value))
                    }
                case .seaSurfaceTemperature:
                    if let value = hourly.seaSurfaceTemperature?[index] {
                        MarineDataRow(label: "Sea Temp", value: formatTemperature(value))
                    }
                case .seaLevelHeight:
                    if let value = hourly.seaLevelHeight?[index] {
                        MarineDataRow(label: "Sea Level", value: formatSeaLevel(value))
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .frame(width: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(createAccessibilityLabel())
    }
    
    private func createAccessibilityLabel() -> String {
        guard let time = hourly.time?[index] else { return "No data" }
        
        let timeFormatted = FormatHelper.formatTimeCompact(time)
        var label = timeFormatted
        
        for field in enabledFields {
            if let fieldText = getFieldAccessibilityText(for: field) {
                label += ", \(fieldText)"
            }
        }
        
        return label
    }
    
    private func getFieldAccessibilityText(for field: MarineFieldType) -> String? {
        switch field {
        case .waveHeight:
            if let value = hourly.waveHeight?[index] {
                let unit = settingsManager.settings.distanceUnit == .miles ? "feet" : "meters"
                let formatted = formatWaveHeight(value)
                return "Wave height \(formatted)".replacingOccurrences(of: " ft", with: " \(unit)").replacingOccurrences(of: " m", with: " \(unit)")
            }
        case .waveDirection:
            if let value = hourly.waveDirection?[index] {
                let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
                let dirIndex = Int((Double(value) + 22.5) / 45.0) % 8
                return "Wave direction \(directions[dirIndex])"
            }
        case .wavePeriod:
            if let value = hourly.wavePeriod?[index] {
                return "Wave period \(formatPeriod(value))"
            }
        case .wavePeakPeriod:
            if let value = hourly.wavePeakPeriod?[index] {
                return "Peak period \(formatPeriod(value))"
            }
        case .windWaveHeight:
            if let value = hourly.windWaveHeight?[index] {
                let unit = settingsManager.settings.distanceUnit == .miles ? "feet" : "meters"
                let formatted = formatWaveHeight(value)
                return "Wind wave \(formatted)".replacingOccurrences(of: " ft", with: " \(unit)").replacingOccurrences(of: " m", with: " \(unit)")
            }
        case .windWaveDirection:
            if let value = hourly.windWaveDirection?[index] {
                let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
                let dirIndex = Int((Double(value) + 22.5) / 45.0) % 8
                return "Wind wave direction \(directions[dirIndex])"
            }
        case .windWavePeriod:
            if let value = hourly.windWavePeriod?[index] {
                return "Wind wave period \(formatPeriod(value))"
            }
        case .swellWaveHeight:
            if let value = hourly.swellWaveHeight?[index] {
                let unit = settingsManager.settings.distanceUnit == .miles ? "feet" : "meters"
                let formatted = formatWaveHeight(value)
                return "Swell height \(formatted)".replacingOccurrences(of: " ft", with: " \(unit)").replacingOccurrences(of: " m", with: " \(unit)")
            }
        case .swellWaveDirection:
            if let value = hourly.swellWaveDirection?[index] {
                let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
                let dirIndex = Int((Double(value) + 22.5) / 45.0) % 8
                return "Swell direction \(directions[dirIndex])"
            }
        case .swellWavePeriod:
            if let value = hourly.swellWavePeriod?[index] {
                return "Swell period \(formatPeriod(value))"
            }
        case .oceanCurrentVelocity:
            if let value = hourly.oceanCurrentVelocity?[index] {
                return "Current speed \(formatVelocity(value))"
            }
        case .oceanCurrentDirection:
            if let value = hourly.oceanCurrentDirection?[index] {
                let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
                let dirIndex = Int((Double(value) + 22.5) / 45.0) % 8
                return "Current direction \(directions[dirIndex])"
            }
        case .seaSurfaceTemperature:
            if let value = hourly.seaSurfaceTemperature?[index] {
                return "Sea temperature \(formatTemperature(value))"
            }
        case .seaLevelHeight:
            if let value = hourly.seaLevelHeight?[index] {
                let unit = settingsManager.settings.distanceUnit == .miles ? "feet" : "meters"
                let formatted = formatSeaLevel(value)
                return "Sea level \(formatted)".replacingOccurrences(of: " ft", with: " \(unit)").replacingOccurrences(of: " m", with: " \(unit)")
            }
        }
        return nil
    }
}

struct MarineDataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .accessibilityHidden(true)
    }
}

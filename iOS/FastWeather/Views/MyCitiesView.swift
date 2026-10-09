//
//  MyCitiesView.swift
//  Fast Weather
//
//  View for displaying saved cities with three view options: Flat, Table, List
//

import SwiftUI

struct MyCitiesView: View {
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var myLocationService: MyLocationService
    @StateObject private var featureFlags = FeatureFlags.shared
    @ObservedObject private var launchCityService = LaunchCityService.shared
    @State private var showingSettings = false
    @State private var showingAddCity = false
    @State private var selectedCityForHistory: City?
    @State private var selectedCityForDetail: City?
    @State private var hasLoadedInitialWeather = false

    private var showMyLocation: Bool {
        featureFlags.myLocationEnabled && settingsManager.settings.myLocationEnabled
    }
    
    // Date navigation state
    @State private var dateOffset: Int = 0  // 0 = today, +1 = tomorrow, -1 = yesterday
    private let maxDaysForward = 7
    private let maxDaysBack = 7
    
    // Computed properties for date display
    private var selectedDate: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: dateOffset, to: Date()) ?? Date()
    }
    
    private var dateDisplayString: String {
        if dateOffset == 0 {
            return "Today"
        } else if dateOffset == 1 {
            return "Tmrw"  // Abbreviated to prevent truncation confusion with "Today"
        } else if dateOffset == -1 {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: selectedDate)
        }
    }
    
    // Full date string for VoiceOver (not abbreviated)
    private var accessibilityDateString: String {
        if dateOffset == 0 {
            return "Today"
        } else if dateOffset == 1 {
            return "Tomorrow"  // Full word for VoiceOver (visual shows "Tmrw")
        } else if dateOffset == -1 {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"  // Full day/month names for VoiceOver
            return formatter.string(from: selectedDate)
        }
    }
    
    // MARK: - Computed Properties
    
    @ViewBuilder
    private var mainContent: some View {
        if weatherService.savedCities.isEmpty && !showMyLocation {
            EmptyStateView()
        } else {
            switch settingsManager.settings.viewMode {
            case .flat:
                FlatView(
                    selectedCityForHistory: $selectedCityForHistory,
                    selectedCityForDetail: $selectedCityForDetail,
                    dateOffset: dateOffset,
                    selectedDate: selectedDate,
                    showMyLocation: showMyLocation
                )
            case .list:
                ListView(
                    selectedCityForHistory: $selectedCityForHistory,
                    dateOffset: dateOffset,
                    selectedDate: selectedDate,
                    showMyLocation: showMyLocation
                )
            case .table:
                TableView(
                    selectedCityForHistory: $selectedCityForHistory,
                    dateOffset: dateOffset,
                    selectedDate: selectedDate
                )
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Weather Fast")
                .navigationDestination(item: $selectedCityForHistory) { city in
                    HistoricalWeatherView(city: city, autoLoadToday: settingsManager.settings.viewMode == .list)
                        .navigationTitle("Historical Weather")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .navigationDestination(item: $selectedCityForDetail) { city in
                    CityDetailView(city: city)
                    }
                .toolbar {
                    toolbarContent
                }
                .sheet(isPresented: $showingAddCity) {
                    AddCitySearchView(initialSearchText: "")
                }
                .refreshable {
                    await refreshAllCities()
                }
                .onAppear {
                    if showMyLocation {
                        myLocationService.requestPermissionIfNeeded()
                        if myLocationService.locationCity == nil {
                            Task { await myLocationService.refresh() }
                        }
                    }
                }
                .task {
                    // Open the chosen launch city on top of the list; Back returns to the list.
                    if let city = await launchCityService.cityForLaunch(
                        savedCities: weatherService.savedCities,
                        myLocationService: myLocationService,
                        showMyLocation: showMyLocation
                    ) {
                        selectedCityForDetail = city
                    }
                }
                .onChange(of: settingsManager.settings.myLocationEnabled) { _, isEnabled in
                    if isEnabled {
                        myLocationService.requestPermissionIfNeeded()
                        Task { await myLocationService.refreshIfStale() }
                    }
                }
                .onChange(of: dateOffset) { oldValue, newValue in
                    Task {
                        await refreshAllCities()
                    }
                }
                .accessibilityAction(named: "Previous Day") {
                    navigateToPreviousDay()
                }
                .accessibilityAction(named: "Next Day") {
                    navigateToNextDay()
                }
                .accessibilityAction(named: "Return to Today") {
                    navigateToToday()
                }
                .gesture(swipeGesture)
        }
    }
    
    // MARK: - Helper Methods
    
    private func refreshAllCities() async {
        async let locationRefresh: () = showMyLocation ? myLocationService.refresh() : ()
        for city in weatherService.savedCities {
            await weatherService.fetchWeatherForDate(for: city, dateOffset: dateOffset)
        }
        await locationRefresh
    }
    
    private func navigateToPreviousDay() {
        guard dateOffset > -maxDaysBack else { return }
        dateOffset -= 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Viewing weather for \(accessibilityDateString)")
    }
    
    private func navigateToNextDay() {
        guard dateOffset < maxDaysForward else { return }
        dateOffset += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Viewing weather for \(accessibilityDateString)")
    }
    
    private func navigateToToday() {
        dateOffset = 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Returned to today")
    }
    
    // MARK: - Accessors
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { gesture in
                let horizontalSwipe = gesture.translation.width
                let verticalSwipe = abs(gesture.translation.height)
                
                // Only process horizontal swipes
                guard abs(horizontalSwipe) > verticalSwipe else { return }
                
                // iOS timeline convention: swipe LEFT (negative) = see future, swipe RIGHT (positive) = see past
                if horizontalSwipe > 100 && dateOffset > -maxDaysBack {
                    // Swipe RIGHT = go to previous day (back in time)
                    navigateToPreviousDay()
                } else if horizontalSwipe < -100 && dateOffset < maxDaysForward {
                    // Swipe LEFT = go to next day (forward in time)
                    navigateToNextDay()
                }
            }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button(action: navigateToPreviousDay) {
                Label("Previous", systemImage: "arrow.backward")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
            }
            .disabled(dateOffset <= -maxDaysBack)
            .accessibilityLabel("Previous day")
            
            Text(dateDisplayString)
                .font(.subheadline)
                .fontWeight(.semibold)
                .accessibilityLabel("Currently viewing \(accessibilityDateString)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Swipe up for next day, swipe down for previous day")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        // Swipe up = next day
                        navigateToNextDay()
                    case .decrement:
                        // Swipe down = previous day
                        navigateToPreviousDay()
                    @unknown default:
                        break
                    }
                }
            
            Button(action: navigateToNextDay) {
                Label("Next", systemImage: "arrow.forward")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
            }
            .disabled(dateOffset >= maxDaysForward)
            .accessibilityLabel("Next day")
            
            if dateOffset != 0 {
                Button {
                    navigateToToday()
                } label: {
                    Label("Today", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Go to today")
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingAddCity = true
            } label: {
                Label("Add Location", systemImage: "plus")
            }
            .accessibilityLabel("Add Location")
            .accessibilityHint("Opens search to add a new location")
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .accessibilityHidden(true)
            
            Text("No Cities Added")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Browse cities to add your first location")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No cities added. Browse cities to add your first location")
    }
}

#Preview {
    MyCitiesView()
        .environmentObject(WeatherService())
        .environmentObject(SettingsManager())
}

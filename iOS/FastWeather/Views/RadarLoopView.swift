//
//  RadarLoopView.swift
//  Fast Weather
//
//  Animated NWS NEXRAD radar loop with frame-by-frame stepping.
//
//  Two audiences, one screen:
//
//  • Sighted — the loop animates by default, with pinch-zoom, a scrubber and
//    play/pause. Motion is the point of radar; a single still frame cannot
//    show a storm moving.
//
//  • VoiceOver — each frame is a real image element, so VoiceOver's Image
//    Explorer (iOS 27) can describe it. Playback is paused automatically when
//    VoiceOver is running, because an image that changes underneath a
//    description is worse than useless. Previous/Next step through the loop
//    one frame at a time, which is how motion is read non-visually.
//
//  Data: NOAA/NWS NEXRAD base reflectivity, public domain. US coverage only.
//

import SwiftUI
import Combine

/// Where the frames come from. The two sources are genuinely different
/// products, not two routes to the same picture — see IEMRadarService for the
/// full comparison.
enum RadarSource: String, CaseIterable, Identifiable {
    case ridge
    case iem
    case eccc

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .ridge: return "NWS"
        case .iem:   return "Composite"
        case .eccc:  return "Canada"
        }
    }

    /// The two map-drawn sources; the ones with a Map area switch.
    var isMapped: Bool { self != .ridge }

    var summary: String {
        switch self {
        case .ridge: return "10 frames · 2 min apart · 18 minutes · one station"
        case .iem:   return "12 frames · 5 min apart · 55 minutes"
        case .eccc:  return "11 frames · 18 min apart · 3 hours"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .ridge:
            return "National Weather Service station image. Ten frames, two minutes "
                 + "apart, covering eighteen minutes, from a single radar station."
        case .iem:
            return "Multi-radar composite on a map. Twelve frames, five minutes "
                 + "apart, covering fifty-five minutes, centred on your city."
        case .eccc:
            return "Environment and Climate Change Canada composite on a map, "
                 + "covering Canada and the United States. Eleven frames, "
                 + "eighteen minutes apart, covering three hours, centred on your city."
        }
    }
}

struct RadarLoopView: View {
    let city: City
    /// Set when the user picked this radar from the station browser rather
    /// than opening a city. The NWS loop then comes from this exact station
    /// instead of whichever one happens to be nearest.
    var station: RadarStationInfo? = nil

    init(city: City) {
        self.city = city
        self.station = nil
    }

    /// Browsing straight to a station: the composite still needs somewhere to
    /// centre, so the station's own position stands in for a city.
    init(station: RadarStationInfo) {
        self.station = station
        self.city = City(name: station.name,
                         state: station.stateCode.isEmpty ? nil : station.stateCode,
                         country: "United States",
                         latitude: station.latitude,
                         longitude: station.longitude)
    }

    @EnvironmentObject private var settingsManager: SettingsManager

    @State private var source: RadarSource = .ridge
    /// Remembered between visits: someone who wants the wide view usually
    /// wants it every time.
    @AppStorage("radarCompositeArea") private var area: RadarArea = .local
    /// The area of the loop on screen, which lags `area` while a reload runs.
    @State private var loadedArea: RadarArea = .local
    @State private var loop: RadarLoop?
    @State private var index: Int = 0
    @State private var isLoading = true
    @State private var message: String?
    @State private var showingInfo = false

    @State private var isPlaying = false
    @State private var holdTicks = 0
    @State private var voiceOverRunning = UIAccessibility.isVoiceOverRunning

    // Pinch-zoom / pan state for the radar image.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let tick = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            sourcePicker

            if isLoading {
                Spacer()
                ProgressView("Loading radar…")
                    .accessibilityLabel("Loading radar loop")
                Spacer()
            } else if let msg = message {
                Spacer()
                messageView(msg)
                Spacer()
            } else if let loop {
                radarImage(loop)
                controls(loop)
            }
        }
        .navigationTitle(station.map { "\($0.displayName) Radar" } ?? "Radar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { showingInfo = true }) {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About Radar")
                .accessibilityHint("Explains the NWS and Composite radar options, when to choose each, and who provides the radar.")

                Button(action: { Task { await load() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh radar")
                .accessibilityHint("Downloads the latest radar loop.")
            }
        }
        .sheet(isPresented: $showingInfo) {
            RadarInfoView(unit: unit)
        }
        .task { await load() }
        .onChange(of: source) { _, _ in Task { await load() } }
        .onChange(of: area) { _, _ in
            if source.isMapped { Task { await load() } }
        }
        .onReceive(tick) { _ in advanceIfPlaying() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            voiceOverRunning = UIAccessibility.isVoiceOverRunning
            if voiceOverRunning { isPlaying = false }
        }
    }

    // MARK: - Source picker

    private var sourcePicker: some View {
        VStack(spacing: 4) {
            Picker("Radar source", selection: $source) {
                ForEach(RadarSource.allCases) { s in
                    Text(s.shortName).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Radar source")
            .accessibilityHint("Switches between the National Weather Service station image, "
                             + "a United States composite drawn on a map, and Environment "
                             + "and Climate Change Canada's composite, which covers Canada "
                             + "and the United States with three hours of history.")

            if source.isMapped {
                Picker("Map area", selection: $area) {
                    ForEach(RadarArea.allCases) { a in
                        Text(a.name).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Map area")
                .accessibilityHint("Local shows \(RadarArea.local.across(unit)) around your city. "
                                 + "Regional shows \(RadarArea.regional.across(unit)), "
                                 + "to see weather that is farther away.")
            }

            Text(captionText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var unit: DistanceUnit { settingsManager.settings.distanceUnit }

    private var captionText: String {
        switch source {
        case .ridge:
            return source.summary
        case .iem, .eccc:
            return source.summary + "\n" + area.across(unit) + " across, centred on your city"
        }
    }

    private func stationDistance(_ station: RadarLoopStation) -> String? {
        guard let km = station.distanceKm else { return nil }
        let value = Int(unit.convert(km).rounded())
        return "\(value) " + (unit == .miles ? "miles" : "kilometres")
    }

    // MARK: - Image

    private func radarImage(_ loop: RadarLoop) -> some View {
        GeometryReader { geo in
            Image(uiImage: loop.frames[safe: index] ?? loop.frames[0])
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1), 6)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1 { resetZoom() }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
                            }
                            .onEnded { value in
                                // Zoomed in, a drag pans. At normal size it
                                // pages through frames, like Photos.
                                if scale > 1 { lastOffset = offset } else { swipe(value.translation, loop) }
                            }
                    )
                )
                .onTapGesture(count: 2) { resetZoom() }
                // One image element so VoiceOver's Image Explorer can describe it.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(imageLabel(loop))
                .accessibilityHint("Swipe left or right with three fingers to move to the next or previous frame.")
                .accessibilityAddTraits(.isImage)
                // VoiceOver's three-finger swipe pages frames the way it pages
                // photos. The edge is the one being scrolled toward, so a swipe
                // left arrives as .trailing: later in time.
                .accessibilityScrollAction { edge in
                    switch edge {
                    case .trailing: page(1, loop)
                    case .leading:  page(-1, loop)
                    default:        break
                    }
                }
        }
    }

    private func imageLabel(_ loop: RadarLoop) -> String {
        let position = index == loop.frames.count - 1
            ? "frame \(index + 1) of \(loop.frames.count), the most recent"
            : "frame \(index + 1) of \(loop.frames.count)"

        let origin = loop.station.map { "From the \($0.name) radar station. " }
            ?? "A composite of every nearby radar, centred on \(city.name), "
             + "\(loadedArea.across(unit)) across. "

        return "Weather radar near \(city.name), \(position), \(timePhrase(loop)). "
            + origin
            + "Each step is \(intervalPhrase(loop)); the loop covers \(spanPhrase(loop)). "
            + "Use VoiceOver's Intelligent Image Description to hear what this frame shows."
    }

    // MARK: - Time wording

    /// The app formats times as 12-hour "h:mm a" everywhere (FormatHelper);
    /// these frames are Dates rather than ISO strings, so match the format here.
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private func frameTime(_ loop: RadarLoop) -> Date? {
        loop.frameTimes[safe: index]
    }

    /// "at 5:28 PM, 4 minutes ago" — both the clock time and the age, because
    /// on a radar loop the age is the part that actually matters.
    private func timePhrase(_ loop: RadarLoop) -> String {
        guard let t = frameTime(loop) else { return "" }
        let clockTime = Self.clock.string(from: t)
        let minutesAgo = Int((Date().timeIntervalSince(t) / 60).rounded())
        if minutesAgo <= 0 { return "at \(clockTime), just now" }
        if minutesAgo == 1 { return "at \(clockTime), 1 minute ago" }
        return "at \(clockTime), \(minutesAgo) minutes ago"
    }

    private func intervalPhrase(_ loop: RadarLoop) -> String {
        let minutes = Int((loop.interval / 60).rounded())
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    private func spanPhrase(_ loop: RadarLoop) -> String {
        let minutes = Int((loop.span / 60).rounded())
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    // MARK: - Controls

    private func controls(_ loop: RadarLoop) -> some View {
        VStack(spacing: 14) {
            Text(frameCaption(loop))
                .font(.subheadline.weight(.medium))
                .accessibilityHidden(true)

            // Scrubber — the fast way to move through the loop by sight.
            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { index = Int($0.rounded()) }
                ),
                in: 0...Double(max(loop.frames.count - 1, 1)),
                step: 1
            )
            .accessibilityLabel("Radar time")
            .accessibilityValue("Frame \(index + 1) of \(loop.frames.count)")

            HStack(spacing: 28) {
                Button(action: { step(-1, loop) }) {
                    Image(systemName: "backward.frame.fill").font(.title2)
                }
                .disabled(index == 0)
                .accessibilityLabel("Previous frame")
                .accessibilityHint("Steps back one radar frame, earlier in time.")

                Button(action: { togglePlay() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                .accessibilityLabel(isPlaying ? "Pause loop" : "Play loop")
                .accessibilityHint(isPlaying
                    ? "Stops the radar animation."
                    : "Animates the radar frames in order. Paused automatically while VoiceOver is on so the image does not change while you read it.")

                Button(action: { step(1, loop) }) {
                    Image(systemName: "forward.frame.fill").font(.title2)
                }
                .disabled(index >= loop.frames.count - 1)
                .accessibilityLabel("Next frame")
                .accessibilityHint("Steps forward one radar frame, later in time.")
            }

            weatherLink

            VStack(spacing: 3) {
                if let station = loop.station {
                    if let away = stationDistance(station) {
                        Text("\(station.name) station · \(away) away")
                    } else {
                        Text("\(station.name) station · \(station.id)")
                    }
                } else {
                    Text("\(loop.sourceName) · every radar in range · \(loadedArea.name.lowercased()) view")
                }
                Text("Frames \(intervalPhrase(loop)) apart · \(spanPhrase(loop)) of history")
                Text(loop.attribution)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(footerLabel(loop))
        }
        .padding()
    }

    /// The radar answers "what is moving"; this answers "what is it like
    /// there". From the station browser it is the only route to a forecast
    /// for that place, since the station was never a saved city.
    private var weatherLink: some View {
        NavigationLink {
            RadarWeatherDestination(city: city)
        } label: {
            Label(station == nil ? "Weather for \(city.name)" : "Weather for This Station",
                  systemImage: "thermometer.medium")
        }
        .accessibilityHint(station == nil
            ? "Opens the full forecast for \(city.displayName)."
            : "Opens the full forecast for the area around the \(city.displayName) radar station.")
    }

    private func frameCaption(_ loop: RadarLoop) -> String {
        let time = frameTime(loop).map { Self.clock.string(from: $0) } ?? ""
        let base = "Frame \(index + 1) of \(loop.frames.count)"
        guard !time.isEmpty else { return base }
        return index == loop.frames.count - 1
            ? "\(base) · \(time) · most recent"
            : "\(base) · \(time)"
    }

    private func footerLabel(_ loop: RadarLoop) -> String {
        let origin: String
        if let station = loop.station {
            origin = stationDistance(station).map {
                "Source: \(station.name) NEXRAD station, \($0) away."
            } ?? "Source: the \(station.name) NEXRAD station, \(station.id)."
        } else {
            origin = "Source: a composite of every NEXRAD radar in range, "
                   + "\(loadedArea.name.lowercased()) view, \(loadedArea.across(unit)) across."
        }
        return origin
            + " Frames \(intervalPhrase(loop)) apart, covering \(spanPhrase(loop)). "
            + loop.attribution
    }

    private func messageView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(msg)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Try Again") { Task { await load() } }
                .accessibilityHint("Attempts to download the radar loop again.")
        }
        .padding()
    }

    // MARK: - Behaviour

    private func load() async {
        isLoading = true
        message = nil
        resetZoom()
        let requestedArea = area

        let result: RadarLoopResult
        switch source {
        case .ridge:
            if let station {
                result = await RadarLoopService.shared.loadLoop(forStation: station)
            } else {
                result = await RadarLoopService.shared.loadLoop(for: city)
            }
        case .iem:   result = await IEMRadarService.shared.loadLoop(for: city, area: requestedArea)
        case .eccc:  result = await ECCCRadarService.shared.loadLoop(for: city, area: requestedArea)
        }
        switch result {
        case .success(let l):
            loop = l
            loadedArea = requestedArea
            index = max(l.frames.count - 1, 0)   // open on the most recent frame
            // Animate for sighted users; never animate under VoiceOver.
            voiceOverRunning = UIAccessibility.isVoiceOverRunning
            isPlaying = !voiceOverRunning
        case .noCoverage(let m):
            loop = nil
            message = m
        case .failure(let m):
            loop = nil
            message = m
        }
        isLoading = false
    }

    private func togglePlay() {
        isPlaying.toggle()
        if isPlaying, let loop, index >= loop.frames.count - 1 { index = 0 }
    }

    private func step(_ delta: Int, _ loop: RadarLoop) {
        isPlaying = false
        let next = index + delta
        guard next >= 0, next < loop.frames.count else { return }
        index = next
        resetZoom()
        AccessibilityNotification.Announcement(frameCaption(loop)).post()
    }

    /// A clear horizontal swipe on the unzoomed picture: left for the next
    /// (later) frame, right for the previous one.
    private func swipe(_ translation: CGSize, _ loop: RadarLoop) {
        guard abs(translation.width) > 50,
              abs(translation.width) > abs(translation.height) * 1.5 else { return }
        page(translation.width < 0 ? 1 : -1, loop)
    }

    /// Swipe and three-finger-swipe paging. Like the buttons it stops
    /// playback, but it reports with a page-scrolled notification, which is
    /// what VoiceOver speaks after a three-finger swipe, and at either end it
    /// says there is nothing further instead of doing nothing silently.
    private func page(_ delta: Int, _ loop: RadarLoop) {
        isPlaying = false
        let next = index + delta
        guard next >= 0, next < loop.frames.count else {
            let end = delta > 0 ? "No later frames. " : "No earlier frames. "
            UIAccessibility.post(notification: .pageScrolled, argument: end + frameCaption(loop))
            return
        }
        index = next
        resetZoom()
        UIAccessibility.post(notification: .pageScrolled, argument: frameCaption(loop))
    }

    private func advanceIfPlaying() {
        guard isPlaying, let loop, loop.frames.count > 1 else { return }
        if holdTicks > 0 { holdTicks -= 1; return }

        index = (index + 1) % loop.frames.count
        // Hold on the newest frame the way the NWS loop itself does.
        if index == loop.frames.count - 1 { holdTicks = 4 }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

/// Weather for a place reached from the radar. Mirrors the browse path: a
/// city that was never saved has no weather loaded, so fetch it on arrival.
struct RadarWeatherDestination: View {
    let city: City
    @EnvironmentObject private var weatherService: WeatherService

    var body: some View {
        CityDetailView(city: city)
            .task {
                await weatherService.fetchWeatherForDate(for: city, dateOffset: 0)
            }
    }
}

// MARK: - About radar

/// Explains the two radar sources and credits the providers. Lives here for
/// now; the plan is to move this material into the user guide later.
struct RadarInfoView: View {
    let unit: DistanceUnit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Weather Fast can show radar three ways: NWS, Composite and Canada. They show different areas and different amounts of time. Pick one with the switch at the top of the radar screen.")
                    InfoPoints(title: "In short", points: [
                        "NWS is the newest picture, from the one radar station nearest your city.",
                        "Composite has a longer history, is centred on your city, and can widen to show a whole region.",
                        "Canada reaches back three hours and is the only one that works in Canada.",
                    ])
                }

                Section(header: Text("What area you see")) {
                    Text("Every radar picture is a fixed image of one area. Zooming in makes part of it bigger, but you can't scroll to see more of the country. Anything outside the picture isn't part of it, and Intelligent Image Description can only describe what is in the picture.")
                    InfoPoints(title: "NWS", points: [
                        "The area around one radar station.",
                        "The picture is centred on the station, not on your city, so your city may be off to one side.",
                        "How far it reaches depends on the station.",
                    ])
                    InfoPoints(title: "Composite and Canada", points: [
                        "A square centred on your city, with your city marked in the middle.",
                        "Local: \(RadarArea.local.across(unit)) across, \(RadarArea.local.toEachEdge(unit)) from your city to each edge.",
                        "Regional: \(RadarArea.regional.across(unit)) across, \(RadarArea.regional.toEachEdge(unit)) to each edge.",
                        "Choose Local or Regional with the Map area switch, which appears when Composite is selected.",
                    ])
                    Text("Both of those cover far more ground than the square you are shown, so Regional is how to see weather that is farther away, such as a line of storms coming from the next state.")
                    Text("Areas no radar can reach, such as far out over the ocean or deep into Mexico, show no colour. That means there is no radar data, not that the sky is clear. On Canada, those areas are shaded grey so you can tell the difference at a glance.")
                }

                Section(header: Text("NWS")) {
                    Text("The National Weather Service's own radar image, exactly as it publishes it, with its own map, roads, county lines and legend. The NWS calls these RIDGE images.")
                    Text("About 10 frames, a new one every 2 minutes, covering the last 18 minutes. Available in Alaska, Hawaii and Puerto Rico as well as the rest of the United States.")
                    InfoPoints(title: "Choose NWS when", points: [
                        "You want the most recent picture. A new frame every 2 minutes means less lag when a storm is close.",
                        "You want the official National Weather Service image.",
                        "You are in Alaska, Hawaii or Puerto Rico, where Composite has no coverage.",
                    ])
                    InfoPoints(title: "Keep in mind", points: [
                        "One station can only see so far. Weather a long way from the station, or behind mountains, can be missed or look weaker than it is.",
                        "18 minutes is a short window for judging where a storm is heading.",
                    ])
                }

                Section(header: Text("Composite")) {
                    Text("Every NEXRAD radar in the contiguous United States blended into one picture, called a mosaic. The Iowa Environmental Mesonet at Iowa State University builds the mosaic from National Weather Service data. Weather Fast draws your chosen area of it on an Apple map.")
                    Text("12 frames, 5 minutes apart, covering the last 55 minutes.")
                    InfoPoints(title: "Choose Composite when", points: [
                        "You want to see where rain or storms are heading. Nearly an hour of history makes direction and speed much easier to judge.",
                        "Your city sits between radar stations or near the edge of one station's range, where a single station's view is weakest.",
                        "You want your city in the centre of the picture, which also helps VoiceOver's Intelligent Image Description relate what it describes to where you are.",
                        "You want to look farther away. Choose Regional.",
                    ])
                    InfoPoints(title: "Keep in mind", points: [
                        "Frames are 5 minutes apart, so the newest one can be a few minutes older than the NWS image.",
                        "Regional shows more area in less detail. Small showers are easier to see in Local.",
                        "Covers the contiguous United States only. For Alaska, Hawaii and Puerto Rico, use NWS.",
                    ])
                }

                Section(header: Text("Canada")) {
                    Text("Environment and Climate Change Canada blends the Canadian and American radars — up to 180 of them — into one picture, rebuilt every 6 minutes. Weather Fast draws your chosen area of it on an Apple map, the same way it draws Composite.")
                    Text("11 frames, 18 minutes apart, covering the last 3 hours.")
                    InfoPoints(title: "Choose Canada when", points: [
                        "You are in Canada. This is the only source here that covers it.",
                        "You want to see where weather came from, not just where it is. Three hours shows a storm's whole afternoon.",
                        "You want to know where the radar can't see. Areas out of radar range are shaded, rather than just being blank.",
                        "You want snow shown as snow. Rain and snow are drawn separately.",
                    ])
                    InfoPoints(title: "Keep in mind", points: [
                        "Frames are 18 minutes apart, so this is the coarsest view of the three in time, and the newest frame can be a few minutes older than the others.",
                        "It takes longer to load than the others, since each frame is fetched separately.",
                    ])
                }

                Section(header: Text("Radar and VoiceOver")) {
                    Text("Both images work with VoiceOver's Intelligent Image Description feature. While VoiceOver is on, the loop stays paused so the picture does not change while you are reading it. To move through time one frame at a time, swipe left or right on the picture with three fingers, as you would in Photos, or use Previous frame and Next frame.")
                    Text("A description covers only what is in the picture. If it mentions only places near you, that is because the picture shows only the area around your city. For a wider description, choose Composite and then Regional.")
                }

                Section(header: Text("Credits"),
                        footer: Text("Weather Fast is not affiliated with or endorsed by NOAA, the National Weather Service, Iowa State University, or Environment and Climate Change Canada.")) {
                    RadarCreditRow(
                        name: "NOAA National Weather Service",
                        detail: "Radar data from the NEXRAD network, and the NWS radar images. Public domain.",
                        urlString: "https://radar.weather.gov")
                    RadarCreditRow(
                        name: "Iowa Environmental Mesonet, Iowa State University",
                        detail: "The Composite radar mosaic, built from NWS NEXRAD data.",
                        urlString: "https://mesonet.agron.iastate.edu")
                    RadarCreditRow(
                        name: "Environment and Climate Change Canada",
                        detail: "The Canada composite, covering Canada and the United States, from the Meteorological Service of Canada. Contains information licensed under the Open Government Licence – Canada.",
                        urlString: "https://weather.gc.ca")
                    RadarCreditRow(
                        name: "Apple Maps",
                        detail: "The map under the Composite radar.",
                        urlString: "https://www.apple.com/legal/internet-services/maps/terms-en.html")
                }
            }
            .navigationTitle("About Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityHint("Closes About Radar and returns to the radar.")
                }
            }
        }
    }
}

/// A short titled list, read by VoiceOver as one element so the title and its
/// points are heard together rather than as a scatter of fragments.
private struct InfoPoints: View {
    let title: String
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").accessibilityHidden(true)
                    Text(point)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ": " + points.joined(separator: " "))
    }
}

/// One credited provider: name, what it supplies, and a link to it.
private struct RadarCreditRow: View {
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
                        .accessibilityHidden(true)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name). \(detail)")
        .accessibilityAddTraits(.isLink)
        .accessibilityHint("Opens the \(name) website.")
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

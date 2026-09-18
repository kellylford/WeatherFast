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

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .ridge: return "NWS"
        case .iem:   return "Composite"
        }
    }

    var summary: String {
        switch self {
        case .ridge: return "10 frames · 2 min apart · 18 minutes · one station"
        case .iem:   return "12 frames · 5 min apart · 55 minutes · centred on your city"
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
        }
    }
}

struct RadarLoopView: View {
    let city: City

    @State private var source: RadarSource = .ridge
    @State private var loop: RadarLoop?
    @State private var index: Int = 0
    @State private var isLoading = true
    @State private var message: String?

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
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await load() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh radar")
                .accessibilityHint("Downloads the latest radar loop.")
            }
        }
        .task { await load() }
        .onChange(of: source) { _, _ in Task { await load() } }
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
            .accessibilityHint("Switches between the National Weather Service station "
                             + "image and a multi-radar composite drawn on a map.")

            Text(source.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
                            .onEnded { _ in lastOffset = offset }
                    )
                )
                .onTapGesture(count: 2) { resetZoom() }
                // One image element so VoiceOver's Image Explorer can describe it.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(imageLabel(loop))
                .accessibilityAddTraits(.isImage)
        }
    }

    private func imageLabel(_ loop: RadarLoop) -> String {
        let position = index == loop.frames.count - 1
            ? "frame \(index + 1) of \(loop.frames.count), the most recent"
            : "frame \(index + 1) of \(loop.frames.count)"

        let origin = loop.station.map { "From the \($0.name) radar station. " }
            ?? "A composite of every nearby radar, centred on \(city.name). "

        return "Weather radar near \(city.name), \(position), \(timePhrase(loop)). "
            + origin
            + "Each step is \(intervalPhrase(loop)); the loop covers \(spanPhrase(loop)). "
            + "Use VoiceOver's image description to hear what this frame shows."
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

            VStack(spacing: 3) {
                if let station = loop.station {
                    Text("\(station.name) station · \(Int(station.distanceKm.rounded())) km away")
                } else {
                    Text("\(loop.sourceName) · every radar in range")
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
            origin = "Source: \(station.name) NEXRAD station, "
                   + "\(Int(station.distanceKm.rounded())) kilometres away."
        } else {
            origin = "Source: a composite of every NEXRAD radar in range."
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

        let result: RadarLoopResult
        switch source {
        case .ridge: result = await RadarLoopService.shared.loadLoop(for: city)
        case .iem:   result = await IEMRadarService.shared.loadLoop(for: city)
        }
        switch result {
        case .success(let l):
            loop = l
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

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

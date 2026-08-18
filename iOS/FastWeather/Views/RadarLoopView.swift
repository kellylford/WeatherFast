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

struct RadarLoopView: View {
    let city: City

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
        .onReceive(tick) { _ in advanceIfPlaying() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            voiceOverRunning = UIAccessibility.isVoiceOverRunning
            if voiceOverRunning { isPlaying = false }
        }
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
        return "Weather radar near \(city.name), \(position). "
            + "From the \(loop.station.name) radar station. "
            + "Use VoiceOver's image description to hear what this frame shows."
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
                Text("\(loop.station.name) station · \(Int(loop.station.distanceKm.rounded())) km away")
                Text("Radar: NWS NEXRAD (radar.weather.gov)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Source: \(loop.station.name) NEXRAD station, "
                + "\(Int(loop.station.distanceKm.rounded())) kilometres away. "
                + "Radar imagery from the National Weather Service.")
        }
        .padding()
    }

    private func frameCaption(_ loop: RadarLoop) -> String {
        index == loop.frames.count - 1
            ? "Frame \(index + 1) of \(loop.frames.count) — most recent"
            : "Frame \(index + 1) of \(loop.frames.count)"
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

        let result = await RadarLoopService.shared.loadLoop(for: city)
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

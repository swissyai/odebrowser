import SwiftUI

/// What plays in a tab the window is not showing: its artwork with the site's
/// icon, its title and artist, a calm line of how far it has played, and the
/// controls its page offers, in the colors of the Space it sits on. Clicking
/// the artwork or title, or Back to Tab, goes back to the tab that plays.
struct BrowserNowPlayingSidebarWidget: View {
    let instance: BrowserSidebarWidgetInstance
    let session: BrowserMediaSessionSnapshot
    let faviconData: Data?
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void
    let activate: (BrowserTabRuntimeAssignment) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.spaceColorRoles) private var spaceColorRoles
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.browserChromeAppearance) private var chromeAppearance
    @ScaledMetric(relativeTo: .body) private var artworkSize = BrowserSidebarWidgetDeckStyle.artworkSize
    @ScaledMetric(relativeTo: .footnote) private var faviconSize = BrowserSidebarWidgetDeckStyle.faviconSize

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserSidebarWidgetDeckStyle.nowPlayingSectionSpacing) {
            identity
            if let position = session.position {
                BrowserNowPlayingProgress(
                    position: position, isPlaying: session.playbackState == .playing, roles: roles)
            }
            controls
        }
        .overlay(alignment: .topTrailing) { dismissButton }
        .contextMenu {
            Button("Back to Tab", systemImage: "arrow.uturn.backward", action: backToTab)
        }
    }

    // MARK: - Parts

    /// The artwork and what plays, which go back to the tab.
    private var identity: some View {
        Button(action: backToTab) {
            HStack(spacing: OdeSpacing.small) {
                artwork
                VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
                    Text(verbatim: session.mediaDisplayTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(SpaceRoleStyle.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle = session.sourceLine {
                        Text(verbatim: subtitle)
                            .font(.caption)
                            .foregroundStyle(SpaceRoleStyle.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The dismiss control sits over the corner.
                .padding(.trailing, BrowserSidebarWidgetDeckStyle.quietControlDiameter)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Now Playing, \(spokenTitle)"))
        .accessibilityValue(Text(isPlaying ? "Playing" : "Paused"))
        .accessibilityHint(Text("Goes back to the tab that plays"))
        .accessibilityActions { accessibilityControls }
        .help(Text("Back to Tab"))
    }

    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: chromeAppearance.cornerScale.inset, style: .continuous)
        ZStack(alignment: .bottomTrailing) {
            if let artworkData = session.artworkData, let image = BrowserSidebarWidgetArtwork.image(from: artworkData) {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(roles.separator.color, lineWidth: OdeLayout.hairline) }
                // The site's icon at the corner, so where it plays is plain.
                if let faviconImage {
                    siteIcon(faviconImage)
                        .frame(width: faviconSize * 0.72, height: faviconSize * 0.72)
                        .padding(2)
                        .background(roles.selected.color, in: Circle())
                        .offset(x: 4, y: 4)
                }
            } else {
                Group {
                    if let faviconImage {
                        siteIcon(faviconImage)
                    } else {
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(SpaceRoleStyle.secondaryText)
                    }
                }
                .frame(width: faviconSize, height: faviconSize)
                .frame(width: artworkSize, height: artworkSize)
                .background(roles.hover.color, in: shape)
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .accessibilityHidden(true)
    }

    private var faviconImage: Image? {
        faviconData.flatMap(BrowserSidebarWidgetArtwork.image(from:))
    }

    private func siteIcon(_ image: Image) -> some View {
        image.resizable().interpolation(.high).scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: faviconSize * 0.18, style: .continuous))
    }

    /// Back to Tab at the leading edge, the page's own controls in the
    /// middle, and the sound at the trailing edge.
    private var controls: some View {
        HStack(spacing: 0) {
            Button(action: backToTab) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
            .accessibilityLabel(Text("Back to Tab"))
            .help(Text("Back to Tab"))
            Spacer(minLength: 0)
            HStack(spacing: OdeSpacing.extraSmall) {
                transportButton(.previousTrack, symbol: "backward.fill", label: "Previous Track")
                playbackButton
                transportButton(.nextTrack, symbol: "forward.fill", label: "Next Track")
            }
            Spacer(minLength: 0)
            volumeButton
                .frame(width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var dismissButton: some View {
        if instance.availableActions.contains(.dismissMediaSession) {
            Button {
                perform(.dismissMediaSession, instance.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle(alignment: .topTrailing))
            .accessibilityLabel("Hide Now Playing")
            .help("Hide until this tab plays again")
        }
    }

    @ViewBuilder
    private var volumeButton: some View {
        if instance.availableActions.contains(.toggleMute) {
            Button {
                perform(.toggleMute, instance.id)
            } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .contentTransition(symbolTransition)
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
            .accessibilityLabel(session.isMuted ? "Unmute" : "Mute")
            .help(session.isMuted ? "Unmute" : "Mute")
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    /// Play or pause on the Space's solid accent, its glyph in the label
    /// color that keeps its contrast there.
    @ViewBuilder
    private var playbackButton: some View {
        let action = playbackAction
        if instance.availableActions.contains(action) {
            Button {
                perform(action, instance.id)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(roles.labelOnSolid.color)
                    .contentTransition(symbolTransition)
                    .frame(
                        width: BrowserSidebarWidgetDeckStyle.focalControlDiameter,
                        height: BrowserSidebarWidgetDeckStyle.focalControlDiameter
                    )
                    .background(roles.accentSolid.color, in: Circle())
                    .overlay {
                        if contrast == .increased {
                            Circle().strokeBorder(roles.labelOnSolid.color.opacity(0.9), lineWidth: 1.5)
                        }
                    }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                height: BrowserSidebarWidgetDeckStyle.quietControlHitTarget
            )
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .help(isPlaying ? "Pause" : "Play")
        }
    }

    @ViewBuilder
    private func transportButton(
        _ action: BrowserSidebarWidgetAction, symbol: String, label: LocalizedStringKey
    ) -> some View {
        if instance.availableActions.contains(action) {
            Button {
                perform(action, instance.id)
            } label: {
                Image(systemName: symbol)
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle())
            .accessibilityLabel(label)
            .help(label)
        }
    }

    @ViewBuilder
    private var accessibilityControls: some View {
        if instance.availableActions.contains(playbackAction) {
            Button(isPlaying ? "Pause" : "Play") { perform(playbackAction, instance.id) }
        }
        if instance.availableActions.contains(.nextTrack) {
            Button("Next Track") { perform(.nextTrack, instance.id) }
        }
        if instance.availableActions.contains(.previousTrack) {
            Button("Previous Track") { perform(.previousTrack, instance.id) }
        }
        if instance.availableActions.contains(.toggleMute) {
            Button(session.isMuted ? "Unmute" : "Mute") { perform(.toggleMute, instance.id) }
        }
    }

    // MARK: - State

    /// The title and the line under it, as the card is read aloud.
    private var spokenTitle: String {
        [session.mediaDisplayTitle, session.sourceLine].compactMap { $0 }.joined(separator: ", ")
    }

    private var isPlaying: Bool {
        session.playbackState == .playing && instance.availableActions.contains(.pause)
    }

    private var playbackAction: BrowserSidebarWidgetAction { isPlaying ? .pause : .play }

    /// The Space's roles, or a neutral Space's off one.
    private var roles: SpaceColorRoles {
        spaceColorRoles?.applying(in: colorScheme)
            ?? SpaceColorRoles(.graphite, colorScheme: colorScheme, increasedContrast: contrast == .increased)
    }

    /// Glyphs change in place, without a bounce, and without motion when the
    /// person asks for less.
    private var symbolTransition: ContentTransition {
        reduceMotion ? .opacity : .symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating)
    }

    private func backToTab() {
        activate(session.owner)
    }
}

/// How far a session has played, as a 2 pt line in the Space's accent over
/// its separator, moving on with the clock while it plays. It redraws once a
/// second rather than animating, which is the same with Reduce Motion.
private struct BrowserNowPlayingProgress: View {
    let position: BrowserMediaSessionPosition
    let isPlaying: Bool
    let roles: SpaceColorRoles

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = isPlaying ? position.fraction(at: context.date) : position.elapsed / position.duration
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(roles.separator.color)
                    Capsule(style: .continuous)
                        .fill(roles.accentSolid.color)
                        .frame(width: max(2, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 2)
            .accessibilityElement()
            .accessibilityLabel(Text("Progress"))
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        }
    }
}

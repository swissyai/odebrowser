import SwiftUI

/// The card a transient overlay reads a borrowed page inside.
///
/// The page itself is a platform type, so the shell passes its own web view in
/// through `webContent` and answers `pageStatus` for the two states that are
/// not a page: never arrived, and given up under memory pressure.
struct BrowserTransientPageCard<WebContent: View>: View {
    let arrangement: BrowserTransientCardArrangement
    let pageStatus: BrowserTransientPageStatus
    let vocabulary: BrowserTransientOverlayVocabulary
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let restore: () -> Void
    @ViewBuilder let webContent: () -> WebContent
    @State private var isWebContentVisible = false

    var body: some View {
        ZStack {
            pageContent
                // Keep the native page mounted and loading, but hide its
                // unpainted backing surface until content is ready to reveal.
                .opacity(isWebContentVisible ? 1 : 0)
            if let coverLabel = pageStatus.initialLoadingCoverLabel {
                BrowserTransientInitialLoadingCover(
                    accessibilityLabel: coverLabel
                )
            }
        }
        .animation(revealAnimation, value: isWebContentVisible)
        .task(id: coversUnpaintedPage) {
            guard !coversUnpaintedPage else {
                isWebContentVisible = false
                return
            }
            // Give WebKit its first display frames after committing content,
            // without waiting for images or other subresources to finish.
            try? await Task.sleep(for: .milliseconds(34))
            guard !Task.isCancelled else { return }
            isWebContentVisible = true
        }
        .background {
            if reduceTransparency {
                Rectangle().fill(.background)
            } else {
                OdeSurfaceLayer(shape: Rectangle())
            }
        }
        .modifier(
            BrowserTransientPageCardStyle(
                arrangement: arrangement,
                reduceTransparency: reduceTransparency
            )
        )
    }

    @ViewBuilder
    private var pageContent: some View {
        if pageStatus.hasPage {
            webContent()
                .background(.background)
        } else if pageStatus.wasReleasedForMemoryPressure {
            BrowserTransientReleasedPageView(
                vocabulary: vocabulary,
                restore: restore
            )
        } else {
            BrowserTransientLoadingPageView(title: vocabulary.loadingTitle)
        }
    }

    private var coversUnpaintedPage: Bool {
        pageStatus.initialLoadingCoverLabel != nil
    }

    private var revealAnimation: Animation? {
        OdeMotion.contentReveal.unlessReducingMotion(reduceMotion)
    }
}

// MARK: - Standing in for a page

/// Hides a web view that has been handed a URL but has not painted anything
/// yet, so the card never shows a flash of empty page.
private struct BrowserTransientInitialLoadingCover: View {
    let accessibilityLabel: LocalizedStringKey

    var body: some View {
        Color.clear
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

private struct BrowserTransientLoadingPageView: View {
    let title: LocalizedStringKey

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel(title)
    }
}

private struct BrowserTransientReleasedPageView: View {
    let vocabulary: BrowserTransientOverlayVocabulary
    let restore: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(vocabulary.releasedTitle, systemImage: "memorychip")
        } description: {
            Text(vocabulary.releasedDescription)
        } actions: {
            Button(vocabulary.restoreTitle, action: restore)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

// MARK: - Card material

private struct BrowserTransientPageCardStyle: ViewModifier {
    let arrangement: BrowserTransientCardArrangement
    let reduceTransparency: Bool

    @Environment(\.browserChromeAppearance) private var chromeAppearance

    func body(content: Content) -> some View {
        content
            // The page's host clips at the layer too, which reaches what
            // SwiftUI's clip cannot: a platform view and Chromium's layer.
            .environment(\.browserWebContentCornerRadius, cornerRadius)
            .compositingGroup()
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        .white.opacity(arrangement.cardBorderOpacity),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: .black.opacity(
                    reduceTransparency ? 0 : arrangement.cardShadowOpacity
                ),
                radius: arrangement.cardShadowRadius,
                y: arrangement.cardShadowOffsetY
            )
    }

    /// The arrangement's own corner, or a surface's corner of the window the
    /// card floats in, as every floating surface takes.
    private var cornerRadius: CGFloat {
        arrangement.cornerRadius(in: chromeAppearance.cornerScale)
    }
}

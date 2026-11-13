import SwiftUI

struct TabFaviconContent: View {
    let subject: BrowserTabFaviconSubject
    let size: CGFloat
    let requestIdentity: BrowserFaviconTaskIdentity
    let renderedImage: BrowserFaviconRenderedImage?

    var body: some View {
        Group {
            if subject.isStartPage {
                OdeMark()
            } else if let emoji = subject.emoji {
                Text(emoji)
                    .font(.system(size: size * TabFaviconMetrics.emojiSizeRatio))
                    .minimumScaleFactor(TabFaviconMetrics.emojiMinimumScaleFactor)
            } else if subject.nativeContent == .gettingStarted {
                PlatformGettingStartedIcon()
            } else if subject.nativeContent != nil {
                Image(systemName: subject.symbol).symbolRenderingMode(.hierarchical)
            } else if let rendered = renderedImage?.rendered(matching: requestIdentity) {
                BrowserFaviconReadableImage(rendered: rendered, size: size)
            } else {
                Image(systemName: "globe")
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
}

import CoreGraphics
import Foundation

enum BrowserFaviconRenderLoader {
    static func decode(
        _ request: BrowserFaviconRenderRequest,
        fallbackData: @escaping @Sendable (URL, UUID) async -> Data? = {
            pageURL,
            profileID in
            await BrowserFaviconFallbackLoader.shared.data(
                for: pageURL,
                profileID: profileID
            )
        }
    ) async -> CGImage? {
        await decodeAnalyzed(request, fallbackData: fallbackData)?.image
    }

    /// The request's icon with its tone, for drawing it readably on its ground.
    static func decodeAnalyzed(
        _ request: BrowserFaviconRenderRequest,
        fallbackData: @escaping @Sendable (URL, UUID) async -> Data? = {
            pageURL,
            profileID in
            await BrowserFaviconFallbackLoader.shared.data(
                for: pageURL,
                profileID: profileID
            )
        }
    ) async -> BrowserFaviconDecodedImage? {
        var data = request.payload
        if data == nil,
            let pageURL = request.fallbackPageURL,
            let profileID = request.fallbackProfileID
        {
            data = await fallbackData(pageURL, profileID)
        }
        guard !Task.isCancelled, let data else { return nil }
        let decoded = await BrowserFaviconImageDecoder.decodeAnalyzed(
            data,
            maximumPixelSize: request.identity.maximumPixelSize
        )
        guard !Task.isCancelled else { return nil }
        return decoded
    }
}

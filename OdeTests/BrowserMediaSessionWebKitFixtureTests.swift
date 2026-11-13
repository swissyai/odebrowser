import ImageIO
import WebKit
import XCTest

@testable import Ode

@MainActor
final class BrowserMediaSessionWebKitFixtureTests: XCTestCase {
    func testPlayerControlsAndMediaLifetimeDetermineEligibility() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        var events: [BrowserMediaSessionPageEvent] = []
        let proxy = BrowserMediaSessionContentBridge.install(in: configuration.userContentController) {
            if let event = BrowserMediaSessionPageEventDecoder.decode($0.body) { events.append(event) }
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        defer { withExtendedLifetime(proxy) {} }
        webView.loadHTMLString("<main id='player'></main>", baseURL: URL(string: "https://media.crest.test"))
        try await waitUntil("the bridge") { !events.isEmpty }

        func check(_ script: String, active: Bool, _ reason: String) async throws {
            let count = events.count
            try await webView.evaluateJavaScript(script + "; globalThis.__crestMediaSessionBridge.emit(); true")
            try await waitUntil("a fresh report for " + reason) {
                events.count > count && events.last?.hasActiveSession == active
            }
            XCTAssertEqual(events.last?.hasActiveSession, active, reason)
        }
        try await check(
            "navigator.mediaSession.playbackState='playing'", active: false,
            "a playbackState hint alone is not a player")
        try await check(
            "navigator.mediaSession.metadata=new MediaMetadata({title:'Web Audio music'}); navigator.mediaSession.setActionHandler('play',()=>{}); navigator.mediaSession.setActionHandler('pause',()=>{})",
            active: true, "explicit Web Audio music keeps standard transport controls")
        try await check(
            "navigator.mediaSession.playbackState='paused'", active: true, "explicit Web Audio music can pause")
        try await check(
            "navigator.mediaSession.playbackState='none'", active: false, "stopping Web Audio clears its session")
        try await check(
            "navigator.mediaSession.metadata=null; navigator.mediaSession.setActionHandler('play',null); navigator.mediaSession.setActionHandler('pause',null)",
            active: false, "cleared Web Audio stays inactive")
        let mediaSetup = """
            globalThis.player = document.querySelector('#player');
            globalThis.media = document.createElement('video');
            player.append(media);
            for (const [key, value] of Object.entries({ paused:false, ended:false, readyState:4,
              videoWidth:640, videoHeight:360, currentSrc:'https://media.crest.test/one.mp4' })) {
              Object.defineProperty(media, key, { configurable:true, writable:true, value });
            }
            media.style.cssText='width:640px;height:360px';
            media.dispatchEvent(new Event('playing'));
            """
        try await check(mediaSetup, active: false, "audible uncontrolled previews stay excluded")
        try await check("media.controls=true", active: true, "native controlled playback qualifies")
        try await check(
            "media.paused=true; media.dispatchEvent(new Event('pause'))", active: true, "pause retains a current player"
        )
        try await check("media.remove()", active: false, "removal clears a paused player")
        try await check("player.append(media)", active: false, "reinsertion does not restore old qualification")
        try await check(
            "media.paused=false; media.dispatchEvent(new Event('playing'))", active: true, "new playback qualifies")
        try await check(
            "media.currentSrc='https://media.crest.test/two.mp4'; media.paused=true", active: false,
            "a replacement source must play first")
        try await check(
            "media.paused=false; media.dispatchEvent(new Event('playing'))", active: true,
            "replacement playback qualifies")
        try await check(
            "media.ended=true; media.dispatchEvent(new Event('ended'))", active: false, "ended media leaves no card")
        try await check(
            "media.ended=false; media.dispatchEvent(new Event('playing'))", active: true, "replay qualifies")
        try await check(
            "player.hidden=true; history.pushState({},'', '/away')", active: false, "hidden SPA player leaves no card")
        try await check(
            "player.hidden=false; media.controls=false; player.insertAdjacentHTML('beforeend', '<button>Play</button><button>Mute</button><input type=range>')",
            active: true, "custom controls use PiP player recognition")
        try await check("media.muted=true", active: true, "muting a controlled video retains it")
        try await check(
            "player.replaceChildren(); navigator.mediaSession.playbackState='playing'", active: false,
            "stale page playbackState cannot replace removed media")
        try await check(
            "globalThis.chime=document.createElement('audio'); player.append(chime); Object.defineProperty(chime,'paused',{value:false}); chime.dispatchEvent(new Event('playing'))",
            active: false, "incidental audio without controls stays excluded")
        try await check("chime.controls=true", active: true, "ordinary native audio controls remain eligible")
        let beforeReplacement = events.count
        try await webView.evaluateJavaScript("player.replaceChildren(document.createElement('p')); true")
        try await waitUntil("DOM replacement to publish without another media event") {
            events.count > beforeReplacement && events.last?.hasActiveSession == false
        }
        XCTAssertEqual(events.last?.hasActiveSession, false)

    }
}

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserUtilityPresentationState {
    // MARK: - Static Variables

    static let triggerSurfacesDefaultsKey = "browser.utility.trigger-surfaces"
    /// Where earlier releases kept the one list the button last opened, which
    /// still answers for a Space nobody has chosen a list for.
    static let lastSurfaceDefaultsKey = "browser.utility.selected-surface"

    // MARK: - Variables

    private(set) var surface: BrowserUtilitySurface? {
        get { observed(\.surfaceStorage, as: \.surface) }
        set { publish(newValue, into: \.surfaceStorage, as: \.surface) }
    }
    @ObservationIgnored private var surfaceStorage: BrowserUtilitySurface?
    /// The bottom Library control reflects the open list, with no separate expansion step.
    var isSwitcherExpanded: Bool { surface != nil }
    private(set) var isSiteControlPresented: Bool {
        get { observed(\.isSiteControlPresentedStorage, as: \.isSiteControlPresented) }
        set { publish(newValue, into: \.isSiteControlPresentedStorage, as: \.isSiteControlPresented) }
    }
    @ObservationIgnored private var isSiteControlPresentedStorage = false
    private(set) var isSiteControlContextMenuPresented: Bool {
        get { observed(\.isSiteControlContextMenuPresentedStorage, as: \.isSiteControlContextMenuPresented) }
        set {
            publish(newValue, into: \.isSiteControlContextMenuPresentedStorage, as: \.isSiteControlContextMenuPresented)
        }
    }
    @ObservationIgnored private var isSiteControlContextMenuPresentedStorage = false
    private(set) var triggerFrameInGlobal: CGRect?
    private(set) var searchFocusRequest = 0
    @ObservationIgnored private var consumedSearchFocusRequest = 0
    @ObservationIgnored private var searchFocusAssignment: BrowserSpaceRuntimeAssignment?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let persistenceKey: String
    /// The last list opened in each Space, kept across launches on this device.
    private(set) var triggerSurfaces: [UUID: BrowserUtilitySurface] = [:]
    /// What a Space nobody has chosen a list for opens: the list an earlier
    /// release last opened, or the archive.
    @ObservationIgnored private let unchosenSurface: BrowserUtilitySurface

    var isSiteControlInteractionActive: Bool {
        isSiteControlPresented || isSiteControlContextMenuPresented
    }

    var isSidebarInteractionActive: Bool {
        surface != nil || isSiteControlInteractionActive
    }

    /// Defaults saved by another window win over this window's cached choices.
    private var currentTriggerSurfaces: [UUID: BrowserUtilitySurface] {
        triggerSurfaces.merging(storedTriggerSurfaces) { _, stored in stored }
    }

    private var storedTriggerSurfaces: [UUID: BrowserUtilitySurface] {
        guard let stored = defaults?.dictionary(forKey: persistenceKey) as? [String: String] else { return [:] }
        var surfaces: [UUID: BrowserUtilitySurface] = [:]
        for (spaceID, name) in stored {
            guard let spaceID = UUID(uuidString: spaceID), let surface = BrowserUtilitySurface.named(name) else {
                continue
            }
            surfaces[spaceID] = surface
        }
        return surfaces
    }

    // MARK: - Initializers

    init(
        defaults: UserDefaults? = nil,
        persistenceKey: String = triggerSurfacesDefaultsKey
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        unchosenSurface =
            defaults?.string(forKey: Self.lastSurfaceDefaultsKey).flatMap(BrowserUtilitySurface.named) ?? .archive
        triggerSurfaces = storedTriggerSurfaces
    }

    // MARK: - Actions - Chrome

    func recordTriggerFrame(_ frame: CGRect) {
        guard frame != triggerFrameInGlobal else { return }
        triggerFrameInGlobal = frame
    }

    func setSiteControlPresented(_ isPresented: Bool) {
        guard isPresented != isSiteControlPresented else { return }
        isSiteControlPresented = isPresented
    }

    func setSiteControlContextMenuPresented(_ isPresented: Bool) {
        guard isPresented != isSiteControlContextMenuPresented else { return }
        isSiteControlContextMenuPresented = isPresented
    }

    // MARK: - Actions - Navigation

    /// Replaces the utility and cancels focus requests belonging to the previous surface.
    func present(_ surface: BrowserUtilitySurface, for spaceID: UUID? = nil) {
        if self.surface != surface { consumedSearchFocusRequest = searchFocusRequest }
        if let spaceID { chooseTriggerSurface(surface, for: spaceID) }
        self.surface = surface
    }

    /// The list the lists button opens in the Space `spaceID` names.
    func triggerSurface(for spaceID: UUID?) -> BrowserUtilitySurface {
        spaceID.flatMap { currentTriggerSurfaces[$0] } ?? unchosenSurface
    }

    /// Makes `surface` the list the lists button opens in the Space `spaceID`
    /// names, and remembers it.
    ///
    /// Another window's presentation state over the same defaults may have
    /// saved since this one read them, so each save starts from the choices in
    /// effect now rather than from this state's own copy.
    func chooseTriggerSurface(_ surface: BrowserUtilitySurface, for spaceID: UUID) {
        var merged = currentTriggerSurfaces
        guard merged[spaceID] != surface else { return }
        merged[spaceID] = surface
        triggerSurfaces = merged
        var stored: [String: String] = [:]
        for (spaceID, surface) in merged { stored[spaceID.uuidString] = surface.name }
        defaults?.set(stored, forKey: persistenceKey)
    }

    /// Records a request that stays pending until the owning search field can receive it.
    func focusSearch(matching assignment: BrowserSpaceRuntimeAssignment? = nil) {
        guard surface != nil else { return }
        searchFocusAssignment = assignment
        searchFocusRequest &+= 1
    }

    /// A matching mounted toolbar may acknowledge the latest request once; stale fields cannot replay it.
    func consumeSearchFocusRequest(
        _ request: Int,
        for surface: BrowserUtilitySurface,
        matching assignment: BrowserSpaceRuntimeAssignment? = nil
    ) -> Bool {
        guard self.surface == surface, request == searchFocusRequest, request != consumedSearchFocusRequest,
            searchFocusAssignment == nil || searchFocusAssignment == assignment
        else { return false }
        consumedSearchFocusRequest = request
        return true
    }

    /// Stale utility dismissals cannot close a replacement or cancel its pending focus request.
    func dismiss(_ surface: BrowserUtilitySurface) {
        guard self.surface == surface else { return }
        self.surface = nil
        consumedSearchFocusRequest = searchFocusRequest
    }

    /// Closing a utility also discards focus that was requested before its field became available.
    func dismiss() {
        surface = nil
        consumedSearchFocusRequest = searchFocusRequest
    }

    /// Opens the lists for the Space `spaceID` names, or closes them: unseen
    /// finished downloads open Downloads, otherwise the list chosen for that
    /// Space.
    func toggleSwitcher(for spaceID: UUID?, hasNewDownloads: Bool = false) {
        if surface != nil {
            dismiss()
        } else {
            present(hasNewDownloads ? .downloads : triggerSurface(for: spaceID), for: spaceID)
        }
    }

    func handleInteraction(_ interactionSurface: BrowserUtilityInteractionSurface) {
        guard interactionSurface.dismissesUtilities else { return }
        dismiss()
    }
}

extension BrowserUtilityPresentationState: BrowserStoreFirstObservable {}

/// What the welcome offers: to wait while iCloud is checked for an existing
/// setup, to set Ode up, or to open Ode once setup is done. The check
/// never holds the welcome for good: the wait on it offers to set up without
/// iCloud after a few seconds and stops a little later, and a check that
/// failed or found no account offers setup on this device, saying iCloud is
/// unavailable.
struct BrowserOnboardingWelcomeAction: Hashable, Sendable {
    // MARK: - Static Variables

    /// iCloud is being checked; the welcome waits.
    static let checking = BrowserOnboardingWelcomeAction(waitsOnCloud: true)
    /// iCloud has taken a while: the welcome still waits, and offers to set
    /// up this device without it.
    static let stillChecking = BrowserOnboardingWelcomeAction(waitsOnCloud: true, offersSetupWithoutCloud: true)
    /// Setup on this device, once iCloud answered.
    static let setup = BrowserOnboardingWelcomeAction()
    /// Setup on this device without iCloud, which failed, has no account
    /// signed in, or did not answer while the welcome waited.
    static let setupWithoutCloud = BrowserOnboardingWelcomeAction(reportsCloudUnavailable: true)
    /// Setup is done: the welcome opens Ode.
    static let open = BrowserOnboardingWelcomeAction(opensOde: true)

    // MARK: - Variables

    /// Whether the welcome waits on iCloud, offering no setup yet.
    let waitsOnCloud: Bool
    /// Whether the welcome, while it waits, offers to set up without iCloud.
    let offersSetupWithoutCloud: Bool
    /// Whether the welcome says iCloud is unavailable.
    let reportsCloudUnavailable: Bool
    /// Whether the welcome opens Ode rather than setting it up.
    let opensOde: Bool

    // MARK: - Initializers

    /// What the welcome offers for `flow`, as the core published it, while
    /// iCloud sync is in `cloudPhase` and the welcome's wait on it is at
    /// `wait`. A launch that `forcesSetup` always offers setup. The welcome
    /// waits until setup opens, which it does as the welcome appears.
    init(
        flow: SetupFlowState?,
        cloudPhase: CloudSyncPhase,
        wait: BrowserOnboardingCloudWait.Stage,
        forcesSetup: Bool = false
    ) {
        if flow == nil {
            self = .checking
        } else if cloudPhase == .checking && !wait.hasStopped {
            self = wait.offersSetupWithoutCloud ? .stillChecking : .checking
        } else if flow?.opensOdeFromWelcome == true && !forcesSetup {
            self = .open
        } else {
            self = cloudPhase.keepsCloudOutOfReach ? .setupWithoutCloud : .setup
        }
    }

    private init(
        waitsOnCloud: Bool = false,
        offersSetupWithoutCloud: Bool = false,
        reportsCloudUnavailable: Bool = false,
        opensOde: Bool = false
    ) {
        self.waitsOnCloud = waitsOnCloud
        self.offersSetupWithoutCloud = offersSetupWithoutCloud
        self.reportsCloudUnavailable = reportsCloudUnavailable
        self.opensOde = opensOde
    }
}

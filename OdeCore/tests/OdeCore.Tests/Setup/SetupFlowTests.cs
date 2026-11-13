using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// Setup as the core walks a person through it: where each entry opens and
/// where Back and Next lead on each platform, the queue of browsers it imports
/// in turn, finishing, which applies the manual setup and opens the Getting
/// Started guide only in an unlocked first Space, and whether the device has
/// completed setup, which the device store adopts once and keeps.
public sealed partial class BrowserContractsTests {
    /// The setup the last `SetupDraftChanged` among `changes` published.
    private static SetupDraft Drafted(IReadOnlyList<Change> changes) =>
        Assert.IsType<SetupDraftChanged>(changes.Last(change => change is SetupDraftChanged)).Draft!;

    [Fact]
    public void EachEntryOpensOnItsStepAndBackLeadsWhereThePlatformSays() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);

        // Set up by hand from the app, Back closes setup rather than import.
        var manual = device.Send(new StartSetup(device.Workspace, SetupEntry.ManualSetup));
        Assert.Equal((SetupStep.ManualSetup, (SetupStep?)null), (Flowing(manual).Step, Flowing(manual).BackStep));
        Assert.Contains(manual, change => change is SetupDraftChanged { Draft: not null });
        // A Mac offers layout before import; mobile keeps its existing setup.
        var guided = Flowing(device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun)));
        Assert.Equal((SetupStep.Welcome, SetupStep.Layout, (SetupStep?)null), (guided.Step, guided.NextStep, guided.BackStep));
        Assert.Equal(SetupStep.Layout, Flowing(device.Send(new ShowSetupStep(SetupStep.ImportBrowser))).BackStep);
        var skipped = Flowing(device.Send(new ContinueImport()));
        Assert.Equal((SetupStep.ManualSetup, SetupStep.ImportBrowser), (skipped.Step, skipped.BackStep));
        Assert.Null(Flowing(device.Send(new StartSetup(device.Workspace, SetupEntry.ImportBrowser))).BackStep);
        Assert.IsType<PersistentWorkspaceRequired>(Assert.Throws<Rejected>(() =>
            device.Send(new StartSetup(device.Attach(session, WorkspaceKind.Private), SetupEntry.FirstRun))).Rejection);

        // A phone goes from the welcome to setting up Spaces, and back.
        using var phone = new OdeApp(new AppConfiguration(null, DevicePlatform.Mobile));
        var workspace = TestWorkspaces.Open(phone, session);
        Assert.Equal(SetupStep.ManualSetup, Flowing(phone.Send(new StartSetup(workspace, SetupEntry.FirstRun))).NextStep);
        Assert.Equal(SetupStep.Welcome, Flowing(phone.Send(new ShowSetupStep(SetupStep.ManualSetup))).BackStep);
    }

    [Fact]
    public void DesktopPracticeFinishesTheSameSetupWithoutOpeningALearningRecord() {
        var session = SavedSession().Document["session"]!;
        // The legacy fixture is normally a disposable first-launch seed.
        // This contract protects an existing, non-disposable workspace.
        session.AsObject().Remove("disposableSeedMarker");
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun));
        var layout = Flowing(device.Send(new ShowSetupStep(SetupStep.Layout)));
        Assert.Equal((SetupStep.Welcome, SetupStep.ImportBrowser), (layout.BackStep, layout.NextStep));
        device.Send(new ShowSetupStep(SetupStep.ManualSetup));
        var added = Drafted(device.Send(new AddSetupSpace())).Spaces.Last().SpaceId;
        var practice = Flowing(device.Send(new ShowSetupStep(SetupStep.Practice)));
        Assert.Equal((SetupStep.ManualSetup, false), (practice.BackStep, practice.OpensGuide));
        var before = device.Authority.Current.Spaces.ToArray();

        // Normal finishing applies the draft once; practice has no saved progress.
        var changes = device.Send(new FinishSetup(window));
        Assert.Contains(new SetupCompletedChanged(true), changes);
        Assert.Contains(new SetupFinished(device.Workspace, null), changes);
        Assert.Contains(device.Authority.Current.Spaces, space => space.Id == added);
        foreach (var original in before)
            Assert.Equal(original, device.Authority.Current.Spaces.Single(space => space.Id == original.Id));
        Assert.Null(device.Query(new LaunchSetup(LaunchEnvironment.Installed)).Setup);
        Assert.Empty(device.Send(new FinishSetup(window)).OfType<SetupDraftChanged>());
    }

    [Fact]
    public void CompletedDesktopRerunRemainsTraversableAndFinishesWithoutChangingExistingTabs() {
        var session = SavedSession().Document["session"]!;
        session.AsObject().Remove("disposableSeedMarker");
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        device.Send(new AdoptSetupCompletion(Completed: true));
        var rerun = Flowing(device.Send(new StartSetup(device.Workspace, SetupEntry.Rerun)));
        Assert.Equal((SetupStep.Welcome, SetupStep.Layout, false, false),
            (rerun.Step, rerun.NextStep, rerun.OpensOdeFromWelcome, rerun.OpensGuide));
        var originals = device.Authority.Current.Spaces.ToArray();
        device.Send(new ShowSetupStep(SetupStep.ManualSetup));
        var added = Drafted(device.Send(new AddSetupSpace())).Spaces.Last().SpaceId;
        // No lesson action is necessary to finish, but the actual draft is applied.
        var finished = device.Send(new FinishSetup(window));
        Assert.Contains(new SetupFinished(device.Workspace, null), finished);
        Assert.Contains(device.Authority.Current.Spaces, space => space.Id == added);
        foreach (var original in originals)
            Assert.Equal(original, device.Authority.Current.Spaces.Single(space => space.Id == original.Id));
    }

    [Fact]
    public void FinishingWithoutPracticingPreservesTheChosenDraftAndRequiresSpaceAuthorization() {
        var session = GuardedSession();
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var locked = device.Authority.Current.Spaces[0];
        device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun));
        device.Send(new ShowSetupStep(SetupStep.ManualSetup));
        var added = Drafted(device.Send(new AddSetupSpace())).Spaces.Last().SpaceId;
        device.Send(new ShowSetupStep(SetupStep.Practice));
        var before = device.Authority.Current;
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => device.Send(new FinishSetup(window))).Rejection);
        Assert.Same(before, device.Authority.Current);
        Assert.False(device.Query(new LaunchSetup(LaunchEnvironment.Installed)).Setup is null);
        TestGrants.Unlock(device.Send, device.Workspace, locked.Id);
        var finished = device.Send(new FinishSetup(window));
        Assert.Contains(new SetupCompletedChanged(true), finished);
        Assert.Contains(new SetupFinished(device.Workspace, null), finished);
        Assert.Contains(new SetupDraftChanged(null), finished);
        Assert.Contains(device.Authority.Current.Spaces, space => space.Id == added);
        Assert.Null(device.Query(new LaunchSetup(LaunchEnvironment.Installed)).Setup);
    }

    [Fact]
    public void DesktopSkipToEndFromOptionalScreensPreservesTheExistingWorkspaceAndPersistsOnlyNormalCompletion() {
        foreach (var step in new[] { SetupStep.Welcome, SetupStep.Layout, SetupStep.ImportBrowser, SetupStep.ManualSetup }) {
            using var directory = new StorageDirectory();
            var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
            using (var app = new OdeApp(configuration)) {
                var workspace = TestWorkspaces.Open(app, SavedSession().Document["session"]!);
                app.Send(new StartSetup(workspace, SetupEntry.FirstRun));
                app.Send(new ShowSetupStep(step));
                var before = app.Workspace(workspace).Current;
                Assert.Contains(new SetupFinished(workspace, null), app.Send(new SkipSetup()));
                Assert.Same(before, app.Workspace(workspace).Current);
            }
            using var reopened = new OdeApp(configuration);
            Assert.Null(reopened.Query(new LaunchSetup(LaunchEnvironment.Installed)).Setup);
        }
    }

    [Fact]
    public void TheChosenLookDressesEverySpaceSetupMakesAndEachOneAnImportBringsInNew() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var seeded = device.Authority.Current.Spaces[0];
        static (SpaceThemeMode, SpaceIconStyle) Worn(SpaceCustomization customization) =>
            (customization.Branding.ThemeMode, customization.Branding.IconStyle);
        var heraldic = (SpaceThemeMode.Banner, SpaceIconStyle.LayeredEmblem);
        var modern = (SpaceThemeMode.Gradient, SpaceIconStyle.SimpleSymbol);

        // Setup opens in the modern look; a stored heraldic choice still applies.
        Assert.Equal(SetupLook.Modern, Flowing(device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun))).Look);

        // A new Space of the manual setup wears it, and so does the first
        // launch's disposable Space, which the person has not made theirs.
        device.Send(new ShowSetupStep(SetupStep.ImportBrowser));
        var started = Drafted(device.Send(new ContinueImport()));
        Assert.Equal([(seeded.Id, modern)], started.Spaces.Select(space => (space.SpaceId, Worn(space.Customization))));
        var added = Drafted(device.Send(new AddSetupSpace())).Spaces[1];
        Assert.Equal((modern, seeded.Settings.Name), (Worn(added.Customization), started.Spaces[0].ShownName));
        // Choosing another look restyles the setup the device holds: a new
        // Space not yet edited takes the look a new Space gets, the disposable
        // one keeps its colors in the new mode.
        var restyled = Drafted(device.Send(new ChooseSetupLook(SetupLook.Heraldic)));
        Assert.Equal(heraldic, Worn(restyled.Spaces[0].Customization));
        Assert.Equal(SpaceAccent.Orange.House, restyled.Spaces[1].Customization.Branding);

        // A Space an import brings in new wears it; one joining an existing
        // Space takes that Space's look.
        device.Send(new ChooseSetupLook(SetupLook.Modern));
        device.Send(new ShowSetupStep(SetupStep.ImportBrowser));
        // Arc comes chosen.
        device.Send(new OfferImportSources([ImportSource.Arc]));
        device.Send(new ContinueImport());
        var review = Flowing(device.Send(new ReviewImport(ImportSource.Arc,
            ReadSpaces(ImportedSpace("Arc", ImportedTab("https://arc.example/"))), []))).Review!;
        Assert.Equal(modern, Worn(review.Spaces[0].Customization));
    }

    [Fact]
    public void ArcComesChosenWhenFirstOfferedAndStaysAsThePersonLeavesIt() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun));
        Assert.Empty(Flowing(device.Send(new OfferImportSources([ImportSource.Chrome]))).Selected);
        Assert.Equal([ImportSource.Arc], Flowing(device.Send(new OfferImportSources([ImportSource.Chrome, ImportSource.Arc]))).Selected);
        Assert.Empty(Flowing(device.Send(new ToggleImportSource(ImportSource.Arc))).Selected);
        // Offered again, as after a scan, Arc stays as the person left it.
        Assert.Empty(Flowing(device.Send(new OfferImportSources([ImportSource.Chrome, ImportSource.Arc]))).Selected);
        // Setup opened again comes back with Arc chosen.
        Assert.Equal([ImportSource.Arc], Flowing(device.Send(new StartSetup(device.Workspace, SetupEntry.Rerun))).Selected);
    }

    [Fact]
    public void SetupImportsEachChosenBrowserInTurnThenSetsUpSpacesByHand() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun));
        Assert.Equal([ImportSource.Arc], Flowing(device.Send(new OfferImportSources([ImportSource.Arc, ImportSource.Chrome]))).Selected);
        var chosen = Flowing(device.Send(new ToggleImportSource(ImportSource.Chrome)));
        Assert.Equal([ImportSource.Arc, ImportSource.Chrome], chosen.Selected);

        var reading = Flowing(device.Send(new ContinueImport()));
        Assert.Equal((SetupPhase.Reading, ImportSource.Arc), (reading.Phase, reading.Source));
        Assert.IsType<SetupBusy>(Assert.Throws<Rejected>(() => device.Send(new ToggleImportSource(ImportSource.Arc))).Rejection);
        var failed = Flowing(device.Send(new FailImport(ImportSource.Arc, SetupFailureReason.Read, "Unreadable")));
        Assert.Equal((SetupStep.ImportBrowser, SetupPhase.Idle, new SetupFailure(SetupFailureReason.Read, ImportSource.Arc, "Unreadable")),
            (failed.Step, failed.Phase, failed.Failure));

        foreach (var source in new[] { ImportSource.Arc, ImportSource.Chrome }) {
            if (source == ImportSource.Arc) device.Send(new ContinueImport());
            // A read setup no longer waits for changes nothing.
            Assert.Empty(device.Send(new ReviewImport(ImportSource.Safari, [], [])));
            var reviewing = Flowing(device.Send(new ReviewImport(source, ReadSpaces(ImportedSpace(source.Title,
                ImportedTab($"https://{source.Name}.example/"))), [])));
            Assert.Equal((SetupStep.Review, SetupPhase.Reviewing), (reviewing.Step, reviewing.Phase));
            device.Send(new BeginImportCommit());
            device.Send(new ImportReviewedSpaces(device.Workspace, window));
            var next = Flowing(device.Send(new FinishImportCommit(PasswordCount: source == ImportSource.Arc ? 1 : 2, UnsavedPasswordCount: 0)));
            Assert.Equal(source == ImportSource.Arc ? 1 : 2, next.Summary!.TabCount);
            Assert.Equal(source == ImportSource.Arc ? 1 : 3, next.Summary.PasswordCount);
            Assert.Equal(source == ImportSource.Arc ? 1 : 2, next.Summary.SpaceCount);
            // Repeated completion cannot count the same source twice.
            Assert.Empty(device.Send(new FinishImportCommit(PasswordCount: 99, UnsavedPasswordCount: 0)));
            if (source == ImportSource.Arc) {
                Assert.Equal((SetupPhase.Reading, ImportSource.Chrome), (next.Phase, next.Source));
                Assert.Equal([ImportSource.Chrome], next.Selected);
            } else Assert.Equal((SetupStep.ManualSetup, SetupPhase.Idle), (next.Step, next.Phase));
        }
        Assert.Equal(["Arc", "Chrome"], device.Authority.Current.Spaces.Select(space => space.Settings.Name));
    }

    [Fact]
    public void MobileFinishingAppliesTheDraftWithoutAGuideAndStillRequiresSpaceAuthorization() {
        var session = GuardedSession();
        // The embedded example never replaces authorization for the real draft.
        using var device = new TestDevice(session, platform: DevicePlatform.Mobile);
        var window = device.Showing(session);
        var locked = device.Authority.Current.Spaces[0];
        device.Send(new StartSetup(device.Workspace, SetupEntry.Rerun));
        device.Send(new ShowSetupStep(SetupStep.ManualSetup));
        device.Send(new AddSetupSpace());
        // The ready page after the manual setup leads back to it, and finishing from it applies the setup.
        Assert.Equal(SetupStep.ManualSetup, Flowing(device.Send(new ShowSetupStep(SetupStep.Complete))).BackStep);
        var before = device.Authority.Current;

        Assert.Equal(new SpaceLocked(locked.Id), Assert.Throws<Rejected>(() => device.Send(new FinishSetup(window))).Rejection);
        Assert.Same(before, device.Authority.Current);

        TestGrants.Unlock(device.Send, device.Workspace, locked.Id);
        var finished = device.Send(new FinishSetup(window));
        Assert.Contains(new SetupCompletedChanged(true), finished);
        Assert.Contains(new SetupFinished(device.Workspace, null), finished);
        Assert.Contains(new SetupDraftChanged(null), finished);
        Assert.Equal(2, device.Authority.Current.Spaces.Count);
        var complete = Flowing(finished);
        Assert.Equal((SetupStep.Complete, new SetupSummary(IsImport: false, 0, 0, SpaceCount: 1, UnsavedPasswordCount: 0)), (complete.Step, complete.Summary));
    }

    [Fact]
    public void SetupHoldsTheLaunchBackUntilItFinishesOnADeviceThatNeverCompletedItOrWhenForced() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var forced = LaunchEnvironment.Installed with { ForcesDesktopSetup = true };
        SetupEntry? Gate(LaunchEnvironment environment) => device.Query(new LaunchSetup(environment)).Setup;
        StartupBehavior Startup(DevicePlatform platform) =>
            device.Query(new LaunchPlan(device.Workspace, platform, LaunchEnvironment.Installed)).Startup;

        // Setup holds the Mac's first window back, which then shows the tab the
        // person left; on a phone it covers the browser, which opens as chosen.
        Assert.Equal(SetupEntry.FirstRun, Gate(LaunchEnvironment.Installed));
        Assert.Equal(SetupEntry.FirstRun, device.Query(new LaunchWindows(LaunchEnvironment.Installed)).Setup);
        Assert.Equal(StartupBehavior.LastActiveTab, Startup(DevicePlatform.Desktop));
        Assert.Equal(StartupBehavior.ShowStartPage, Startup(DevicePlatform.Mobile));

        // A device that completed setup opens straight away, unless the launch
        // forces setup on its platform.
        device.Send(new AdoptSetupCompletion(Completed: true));
        Assert.Null(Gate(LaunchEnvironment.Installed));
        Assert.Equal(StartupBehavior.ShowStartPage, Startup(DevicePlatform.Desktop));
        Assert.Equal(SetupEntry.FirstRun, Gate(forced));
        Assert.Null(Gate(LaunchEnvironment.Installed with { ForcesMobileSetup = true }));

        // Finishing setup opens the gate for the rest of the run, whatever the launch forced.
        device.Send(new StartSetup(device.Workspace, SetupEntry.FirstRun));
        device.Send(new FinishSetup(window));
        Assert.Null(Gate(forced));
    }

    [Fact]
    public void CompletionIsAdoptedOnceAndKeptInTheDeviceStore() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Mobile);
        using (var app = new OdeApp(configuration)) {
            app.Send(Adoption(document));
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            Assert.Contains(new SetupCompletedChanged(false), app.Send(new AdoptSetupCompletion(Completed: false)));
            var fresh = Flowing(app.Send(new StartSetup(workspace, SetupEntry.FirstRun)));
            Assert.Equal((false, false), (fresh.OpensGuide, fresh.OpensOdeFromWelcome));
            var finished = app.Send(new FinishSetup(Guid.NewGuid()));
            Assert.Contains(new SetupCompletedChanged(true), finished);
            Assert.Contains(new SetupFinished(workspace, null), finished);
        }
        using (var app = new OdeApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            // The store adopted once: what an installed release kept no longer counts.
            Assert.Contains(new SetupCompletedChanged(true), app.Send(new AdoptSetupCompletion(Completed: false)));
            var again = Flowing(app.Send(new StartSetup(workspace, SetupEntry.FirstRun)));
            Assert.Equal((false, true), (again.OpensGuide, again.OpensOdeFromWelcome));
            var rerun = Flowing(app.Send(new StartSetup(workspace, SetupEntry.Rerun)));
            Assert.Equal((false, false, SetupStep.ManualSetup), (rerun.OpensGuide, rerun.OpensOdeFromWelcome, rerun.NextStep));
        }
        using var adopting = new StorageDirectory();
        using (var app = new OdeApp(new AppConfiguration(adopting.Path, DevicePlatform.Desktop))) {
            app.Send(Adoption(document));
            Assert.Contains(new SetupCompletedChanged(true), app.Send(new AdoptSetupCompletion(Completed: true)));
        }
        using var reopened = new OdeApp(new AppConfiguration(adopting.Path, DevicePlatform.Desktop));
        Assert.Contains(new SetupCompletedChanged(true), reopened.Send(new AdoptSetupCompletion(Completed: false)));
    }
}

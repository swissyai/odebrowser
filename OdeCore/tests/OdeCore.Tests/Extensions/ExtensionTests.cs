using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// The extensions of the person's Spaces: the core checks every change and
/// install against its Space before an engine hears of it, never reveals a
/// locked Space's extensions, and lets one consent answer each copy of the
/// same package.
public sealed partial class BrowserContractsTests {
    /// A memory-only app over a two-Space saved session, with Chromium, which
    /// keeps extensions, as its default engine and WebKit, which keeps none.
    private static (OdeApp App, Engine Chromium, RecordingEngine Binding, Guid Workspace, Guid First, Guid Second,
        Guid FirstProfile, Guid SecondProfile) ExtensionHost() {
        var session = TwoSpaceSession();
        var app = new OdeApp();
        var binding = new RecordingEngine();
        var chromium = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium,
            [.. EngineCapability.Required, EngineCapability.Extensions], IsDefault: true), binding.Run);
        app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: false), _ => { });
        var workspace = TestWorkspaces.Open(app, session);
        return (app, chromium, binding, workspace, SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!),
            ProfileId(session["spaces"]![0]!), ProfileId(session["spaces"]![1]!));
    }

    private static InstalledExtension Installed(string id, bool changeable = true) =>
        new(id, Name: id, Version: "1.0", Description: "", Enabled: true, changeable, Permissions: ["Read your history"],
            FromWebStore: true, OptionsUrl: null);

    [Fact]
    public void AnExtensionChangeReachesItsEngineOnlyFromAnUnlockedSpaceOfThePersonsOwnWorkspace() {
        var (app, chromium, binding, workspace, first, _, profile, _) = ExtensionHost();
        using var disposal = app;
        var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
        var privateSpace = app.Workspace(privateWorkspace).Current.Spaces[0].Id;

        app.Send(new ListExtensions(first, EngineKind.Chromium));
        Assert.Equal(new ListEngineExtensions(profile), binding.Commands[^1]);
        app.Report(chromium, new ExtensionsListed(profile, [Installed("managed", changeable: false), Installed("reader")]));
        var listed = Assert.IsType<InstalledExtensionsChanged>(Assert.Single(app.Drain()));
        Assert.Equal((EngineKind.Chromium, profile), (listed.Engine, listed.ProfileId));

        app.Send(new ChangeExtension(first, EngineKind.Chromium, "reader", ExtensionChange.Disable));
        Assert.Equal(new ChangeEngineExtension(profile, "reader", ExtensionChange.Disable), binding.Commands[^1]);
        var issued = binding.Commands.Count;
        Assert.Equal(new ExtensionNotChangeable("managed"),
            Refusal(app, new ChangeExtension(first, EngineKind.Chromium, "managed", ExtensionChange.Remove)));
        Assert.Equal(new UnknownExtension("gone"), Refusal(app, new ChangeExtension(first, EngineKind.Chromium, "gone", ExtensionChange.Pin)));
        Assert.Equal(new EngineLacksCapability(EngineKind.WebKit, EngineCapability.Extensions),
            Refusal(app, new ChangeExtension(first, EngineKind.WebKit, "reader", ExtensionChange.Enable)));
        // A private window runs no extension a person installed.
        Assert.Equal(new SpaceIsPrivate(privateSpace),
            Refusal(app, new InstallExtension(Guid.NewGuid(), privateSpace, EngineKind.Chromium, "reader", [], PreApproved: false)));
        Assert.Equal(new SpaceIsPrivate(privateSpace), Refusal(app, new ListExtensions(privateSpace, EngineKind.Chromium)));

        // A locked Space neither changes nor shows its extensions.
        app.Send(new SetSpaceAccess(workspace, first, SpaceAccessPolicy.DeviceOwnerAuthentication));
        Assert.Equal(new SpaceLocked(first), Refusal(app, new ChangeExtension(first, EngineKind.Chromium, "reader", ExtensionChange.Enable)));
        Assert.Equal(new SpaceLocked(first), Refusal(app, new ListExtensions(first, EngineKind.Chromium)));
        Assert.False(app.Query(new CanChangeExtensions(first, EngineKind.Chromium)).Refusal is null);
        app.Report(chromium, new ExtensionsListed(profile, [Installed("reader")]));
        Assert.DoesNotContain(app.Drain(), change => change is InstalledExtensionsChanged);
        Assert.Equal(issued, binding.Commands.Count);
    }

    [Fact]
    public void AnInstallAsksThePersonOnceAndTheirConsentAnswersEachCopyOfTheSamePackage() {
        var (app, chromium, binding, _, first, second, firstProfile, secondProfile) = ExtensionHost();
        using var disposal = app;
        app.Report(chromium, new ExtensionsListed(firstProfile, []));
        app.Report(chromium, new ExtensionsListed(secondProfile, []));
        app.Drain();
        var install = Guid.NewGuid();
        var question = new ExtensionInstallQuestion("reader", "Reader", "2.1", "", ["Read your history", "Change data on sites"],
            Icon: null, CanWithholdSiteAccess: true, WithholdsSiteAccess: false);

        var destinations = app.Query(new ExtensionCopyDestinations(first, EngineKind.Chromium, "reader"));
        Assert.Equal([second], destinations.SpaceIds);
        Assert.True(destinations.Listed);
        app.Send(new InstallExtension(install, first, EngineKind.Chromium, "reader", [], PreApproved: false));
        Assert.Equal(new DownloadExtension(install, firstProfile, "reader"), binding.Commands[^1]);
        app.Report(chromium, new ExtensionDownloaded(install));
        Assert.Equal(new InstallExtensionPackage(install, firstProfile), binding.Commands[^1]);

        // The person answers the first question, choosing a copy as they do.
        var asked = Guid.NewGuid();
        app.Report(chromium, new ExtensionInstallRequested(asked, install, question));
        Assert.Contains(new ExtensionInstallAsked(asked, install, question), app.Drain());
        app.Send(new AnswerExtensionInstall(asked, Accepted: true, WithholdsSiteAccess: true, [second, first]));
        Assert.Equal(new SettleExtensionInstall(asked, Accepted: true, WithholdsSiteAccess: true), binding.Commands[^1]);
        app.Report(chromium, new ExtensionInstalled(install, firstProfile));
        Assert.Equal(new InstallExtensionPackage(install, secondProfile), binding.Commands[^1]);

        // The copy's question for the same package and access is answered
        // with that consent, and nobody is asked again.
        var copy = Guid.NewGuid();
        app.Report(chromium, new ExtensionInstallRequested(copy, install,
            question with { Permissions = ["Change data on sites", "Read your history"] }));
        Assert.Equal(new SettleExtensionInstall(copy, Accepted: true, WithholdsSiteAccess: true), binding.Commands[^1]);
        Assert.DoesNotContain(app.Drain(), change => change is ExtensionInstallAsked);
        app.Report(chromium, new ExtensionInstalled(install, secondProfile));
        Assert.Equal(new EndExtensionInstall(install), binding.Commands[^1]);
        var installed = Assert.IsType<ExtensionInstallChanged>(app.Drain().Last()).Install;
        Assert.Equal((ExtensionInstallStage.Installed, 2), (installed.Stage, installed.InstalledCount));

        // A question for an install that ended is declined at once.
        var late = Guid.NewGuid();
        app.Report(chromium, new ExtensionInstallRequested(late, install, question));
        Assert.Equal(new SettleExtensionInstall(late, Accepted: false, WithholdsSiteAccess: false), binding.Commands[^1]);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void AnUnavailableCopyEndsItsOperationBeforeALatePromptCanInheritTheNextSpacesConsent(bool deleting) {
        var (app, chromium, binding, workspace, first, second, firstProfile, secondProfile) = ExtensionHost();
        using var disposal = app;
        var window = Guid.NewGuid();
        var third = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, first, [], RestoresTabs: true));
        app.Send(new CreateSpace(workspace, window, third));
        var thirdProfile = app.Workspace(workspace).Current.Spaces.Single(space => space.Id == third).ProfileId;
        foreach (var profile in new[] { firstProfile, secondProfile, thirdProfile })
            app.Report(chromium, new ExtensionsListed(profile, []));
        const string extensionId = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
        var question = new ExtensionInstallQuestion(extensionId, "Reader", "1.0", "", ["Read your history"],
            Icon: null, CanWithholdSiteAccess: true, WithholdsSiteAccess: true);
        var install = Guid.NewGuid();
        app.Send(new InstallExtension(install, first, EngineKind.Chromium, extensionId, [second, third], PreApproved: true));
        app.Report(chromium, new ExtensionDownloaded(install));
        app.Report(chromium, new ExtensionInstallRequested(Guid.NewGuid(), install, question));
        app.Report(chromium, new ExtensionInstalled(install, firstProfile));
        Assert.Equal(new InstallExtensionPackage(install, secondProfile), binding.Commands[^1]);
        app.Drain();
        var issued = binding.Commands.Count;

        var changes = deleting
            ? app.Send(new BeginDeletingSpace(workspace, window, second, Guid.NewGuid()))
            : app.Send(new SetSpaceAccess(workspace, second, SpaceAccessPolicy.DeviceOwnerAuthentication));
        var late = Guid.NewGuid();
        app.Report(chromium, new ExtensionInstallRequested(late, install, question));
        Assert.Equal(new SettleExtensionInstall(late, Accepted: false, WithholdsSiteAccess: false), binding.Commands[^1]);
        Assert.Contains(new EndExtensionInstall(install), binding.Commands.Skip(issued));
        Assert.DoesNotContain(new InstallExtensionPackage(install, thirdProfile), binding.Commands.Skip(issued));
        var ended = Assert.Single(changes.OfType<ExtensionInstallChanged>()).Install;
        Assert.Equal((ExtensionInstallStage.Failed, ExtensionInstallFailure.SpaceUnavailable, 1),
            (ended.Stage, ended.Failure, ended.InstalledCount));
        Assert.Equal([new ExtensionInstallDestination(first, Failure: null),
            new ExtensionInstallDestination(second, ExtensionInstallFailure.SpaceUnavailable)], ended.Destinations);
        app.Report(chromium, new ExtensionInstalled(install, secondProfile));
        Assert.DoesNotContain(app.Drain(), change => change is ExtensionInstallChanged);

        // An unattempted destination can retry under a fresh identity, while
        // another late prompt from the previous operation still cannot borrow it.
        var retry = Guid.NewGuid();
        app.Send(new InstallExtension(retry, third, EngineKind.Chromium, extensionId, [], PreApproved: true));
        app.Report(chromium, new ExtensionDownloaded(retry));
        Assert.Equal(new InstallExtensionPackage(retry, thirdProfile), binding.Commands[^1]);
        var stale = Guid.NewGuid();
        app.Report(chromium, new ExtensionInstallRequested(stale, install, question));
        Assert.Equal(new SettleExtensionInstall(stale, Accepted: false, WithholdsSiteAccess: false), binding.Commands[^1]);
        var fresh = Guid.NewGuid();
        app.Report(chromium, new ExtensionInstallRequested(fresh, retry, question));
        Assert.Equal(new SettleExtensionInstall(fresh, Accepted: true, WithholdsSiteAccess: true), binding.Commands[^1]);
        app.Report(chromium, new ExtensionInstalled(retry, thirdProfile));
        var completed = app.Drain().OfType<ExtensionInstallChanged>().Last().Install;
        Assert.Equal((ExtensionInstallStage.Installed, 1), (completed.Stage, completed.InstalledCount));
        Assert.Equal([new ExtensionInstallDestination(third, Failure: null)], completed.Destinations);
    }

    [Fact]
    public void CancelingAnInstallDiscardsItsPackageAndIgnoresLateAndUnrelatedReports() {
        var (app, chromium, binding, _, first, _, profile, otherProfile) = ExtensionHost();
        using var disposal = app;
        var install = Guid.NewGuid();
        app.Send(new InstallExtension(install, first, EngineKind.Chromium, "reader", [], PreApproved: true));
        app.Report(chromium, new ExtensionInstallFailed(install, otherProfile, ExtensionInstallFailure.DownloadFailed));
        Assert.DoesNotContain(app.Drain(), change => change is ExtensionInstallChanged { Install.Stage.HasEnded: true });
        app.Send(new CancelExtensionInstall(install));
        Assert.Equal(new EndExtensionInstall(install), binding.Commands[^1]);
        var issued = binding.Commands.Count;
        app.Report(chromium, new ExtensionDownloaded(install));
        app.Report(chromium, new ExtensionInstalled(install, profile));
        Assert.Empty(app.Drain());
        Assert.Equal(issued, binding.Commands.Count);
    }

    [Fact]
    public void ACopyCannotReuseConsentForBroaderAccessAndItsFailureIsNotEveryDestinationsFailure() {
        var (app, chromium, binding, _, first, second, profile, copyProfile) = ExtensionHost();
        using var disposal = app;
        var install = Guid.NewGuid();
        var question = new ExtensionInstallQuestion("reader", "Reader", "1.0", "", ["Read your history"],
            Icon: null, CanWithholdSiteAccess: true, WithholdsSiteAccess: true);
        app.Send(new InstallExtension(install, first, EngineKind.Chromium, "reader", [second], PreApproved: true));
        app.Report(chromium, new ExtensionDownloaded(install));
        app.Report(chromium, new ExtensionInstallRequested(Guid.NewGuid(), install, question));
        app.Report(chromium, new ExtensionInstalled(install, profile));
        var prompt = Guid.NewGuid();
        app.Report(chromium, new ExtensionInstallRequested(prompt, install,
            question with { Permissions = ["Read your history", "Change data on sites"] }));
        Assert.Equal(new SettleExtensionInstall(prompt, Accepted: false, WithholdsSiteAccess: true), binding.Commands[^1]);
        app.Report(chromium, new ExtensionInstallFailed(install, copyProfile, ExtensionInstallFailure.Refused));
        var ended = app.Drain().OfType<ExtensionInstallChanged>().Last().Install;
        Assert.Equal((ExtensionInstallStage.Installed, 1), (ended.Stage, ended.InstalledCount));
        Assert.Equal([new ExtensionInstallDestination(first, Failure: null),
            new ExtensionInstallDestination(second, ExtensionInstallFailure.Refused)], ended.Destinations);
    }

}

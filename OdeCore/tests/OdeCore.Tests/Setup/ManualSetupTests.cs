using System.Text;
using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// The manual setup the device holds: how it starts, grows and follows the
/// workspace while it waits, where it waits for the next launch, and the
/// unfinished setup an installed release kept, which the device store adopts.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void AManualSetupGrowsWithinTheLimitAndFollowsTheWorkspaceWhileItWaits() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var existing = device.Authority.Current.Spaces[0];

        var started = Drafted(device.Send(new StartSetup(device.Workspace, SetupEntry.ManualSetup)));
        Assert.Equal([(existing.Id, existing.ProfileId, false, "Reading")],
            started.Spaces.Select(space => (space.SpaceId, space.ProfileId, space.IsNew, space.ShownName)));
        // A new Space is named for its place and wears the next accent.
        var added = Drafted(device.Send(new AddSetupSpace())).Spaces[1];
        Assert.Equal((true, "Space 2", SetupDraft.NewSpaceSymbol, SpaceAccent.Orange),
            (added.IsNew, added.ShownName, added.Customization.Symbol, added.Customization.Accent));
        // A blank name stays blank while it is typed and shows as untitled.
        var blank = Drafted(device.Send(new CustomizeSetupSpace(added.SpaceId, added.Customization with { Name = "  " }))).Spaces[1];
        Assert.Equal(("  ", SpaceCustomization.UntitledName), (blank.Customization.Name, blank.ShownName));
        // An existing Space never leaves a setup; a Space created elsewhere joins it.
        Assert.Empty(device.Send(new RemoveSetupSpace(existing.Id)).OfType<SetupDraftChanged>());
        var created = Guid.NewGuid();
        var followed = Drafted(device.Send(new CreateSpace(device.Workspace, window, created)));
        Assert.Equal([existing.Id, added.SpaceId, created], followed.Spaces.Select(space => space.SpaceId));
        // Showing the step again keeps the setup; opening setup again on a Mac does not.
        Assert.Equal(followed, Drafted(device.Send(new ShowSetupStep(SetupStep.ManualSetup))));
        Assert.Equal([existing.Id, created],
            Drafted(device.Send(new StartSetup(device.Workspace, SetupEntry.ManualSetup))).Spaces.Select(space => space.SpaceId));

        for (int count = 2; count < SessionState.MaximumSpaces; count++) device.Send(new AddSetupSpace());
        Assert.Equal(new SpaceLimitReached(SessionState.MaximumSpaces),
            Assert.Throws<Rejected>(() => device.Send(new AddSetupSpace())).Rejection);

        // Setup opened again from the start ends the manual setup.
        Assert.Contains(new SetupDraftChanged(null), device.Send(new StartSetup(device.Workspace, SetupEntry.Rerun)));
        Assert.IsType<NoManualSetup>(Assert.Throws<Rejected>(() => device.Send(new AddSetupSpace())).Rejection);
        var borrowed = device.Attach(session, WorkspaceKind.Private);
        Assert.IsType<PersistentWorkspaceRequired>(
            Assert.Throws<Rejected>(() => device.Send(new StartSetup(borrowed, SetupEntry.ManualSetup))).Rejection);
    }

    [Fact]
    public void RemovingANewSetupSpaceLeavesTheWorkspaceUntouchedAndOnlyAppliesTheKeptDraft() {
        var session = SavedSession().Document["session"]!;
        session.AsObject().Remove("disposableSeedMarker");
        using var device = new TestDevice(session, platform: DevicePlatform.Mobile);
        var window = device.Showing(session);
        var before = device.Authority.Current;
        var existing = before.Spaces[0];
        device.Send(new StartSetup(device.Workspace, SetupEntry.ManualSetup));
        var kept = Drafted(device.Send(new AddSetupSpace())).Spaces[^1];
        var removed = Drafted(device.Send(new AddSetupSpace())).Spaces[^1];

        var revised = Drafted(device.Send(new RemoveSetupSpace(removed.SpaceId)));
        Assert.Equal([existing.Id, kept.SpaceId], revised.Spaces.Select(space => space.SpaceId));
        Assert.Same(before, device.Authority.Current);

        Assert.Contains(new SetupDraftChanged(null), device.Send(new FinishSetup(window)));
        Assert.Equal([existing.Id, kept.SpaceId], device.Authority.Current.Spaces.Select(space => space.Id));
        Assert.Equal(existing, device.Authority.Current.Spaces[0]);
    }

    [Theory]
    [InlineData("mobile", true)]
    [InlineData("desktop", false)]
    public void AnUnfinishedSetupWaitsForTheNextLaunchOnlyWhereThePlatformKeepsIt(string platform, bool resumes) {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Named(platform)!);
        Guid created;
        using (var app = new OdeApp(configuration)) {
            app.Send(Adoption(document));
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            app.Send(new StartSetup(workspace, SetupEntry.ManualSetup));
            var added = Drafted(app.Send(new AddSetupSpace())).Spaces[^1];
            created = added.SpaceId;
            app.Send(new CustomizeSetupSpace(created, added.Customization with { Name = "Kept" }));
        }
        using (var app = new OdeApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            var resumed = Drafted(app.Send(new StartSetup(workspace, SetupEntry.ManualSetup)));
            Assert.Equal(resumes, resumed.Spaces.Any(space => space.SpaceId == created && space.ShownName == "Kept"));
            app.Send(new StartSetup(workspace, SetupEntry.Rerun));
            Assert.DoesNotContain(Drafted(app.Send(new ShowSetupStep(SetupStep.ManualSetup))).Spaces, space => space.IsNew);
        }
        // Starting over is what the next launch finds.
        using (var app = new OdeApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            Assert.DoesNotContain(Drafted(app.Send(new StartSetup(workspace, SetupEntry.ManualSetup))).Spaces, space => space.IsNew);
        }
    }

    [Fact]
    public void TheSetupAnInstalledReleaseKeptIsAdoptedOnceAndResumes() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        var stored = document["spaces"]![0]!;
        Guid existing = SpaceId(stored), created = Guid.NewGuid();
        JsonObject Legacy(Guid id, JsonNode profile, bool isNew, string name) => new() {
            ["id"] = SwiftId(id),
            ["profile"] = new JsonObject { ["id"] = profile.DeepClone() },
            ["isNew"] = isNew,
            ["existingPinnedTabCount"] = 0,
            ["customization"] = new JsonObject {
                ["name"] = name,
                ["symbol"] = "airplane",
                ["accent"] = "teal",
                ["branding"] = JsonNode.Parse(SavedBranding)
            },
            ["addedTabs"] = new JsonArray()
        };
        byte[] Saved(params JsonObject[] spaces) => Encoding.UTF8.GetBytes(new JsonObject {
            ["spaces"] = new JsonArray([.. spaces]),
            ["spaceOrderWasEdited"] = true
        }.ToJsonString());
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Mobile);
        using (var app = new OdeApp(configuration)) {
            app.Send(Adoption(document));
            TestWorkspaces.OpenStored(app);
            app.Send(new AdoptSetupDraft(Saved(Legacy(created, Guid.NewGuid().ToString(), true, "Trips"),
                Legacy(existing, stored["profile"]!["id"]!, false, "Reading room"))));
            // Adopted once: a later launch's document changes nothing.
            app.Send(new AdoptSetupDraft(Saved(Legacy(Guid.NewGuid(), Guid.NewGuid().ToString(), true, "Later"))));
        }
        using (var app = new OdeApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            var resumed = Drafted(app.Send(new StartSetup(workspace, SetupEntry.ManualSetup)));
            Assert.Equal([(created, true, "Trips"), (existing, false, "Reading room")],
                resumed.Spaces.Select(space => (space.SpaceId, space.IsNew, space.ShownName)));
            Assert.True(resumed.OrderWasEdited);
            Assert.Equal(SpaceAccent.Teal, resumed.Spaces[0].Customization.Accent);
        }
    }

    [Fact]
    public void AnEarlierReleasesDraftIsAdoptedWholeOrNotAtAll() {
        Guid space = Guid.NewGuid(), profile = Guid.NewGuid();
        JsonObject Space() => new() {
            ["id"] = new JsonObject { ["rawValue"] = space.ToString().ToUpperInvariant() },
            ["profile"] = new JsonObject { ["id"] = profile.ToString() },
            ["isNew"] = true,
            ["customization"] = new JsonObject { ["name"] = "Trips", ["symbol"] = "airplane", ["accent"] = "teal" }
        };
        byte[] Saved(params JsonNode?[] spaces) => Encoding.UTF8.GetBytes(new JsonObject { ["spaces"] = new JsonArray(spaces) }.ToJsonString());
        byte[] Edited(Action<JsonObject> edit) {
            var edited = Space();
            edit(edited);
            return Saved(Space(), edited);
        }

        var draft = LegacySetupDraftDocument.Read(Saved(Space()))!;
        var read = Assert.Single(draft.Spaces);
        Assert.False(draft.OrderWasEdited);
        Assert.Equal((space, profile, true), (read.SpaceId, read.ProfileId, read.IsNew));
        Assert.Equal(("Trips", "airplane", SpaceAccent.Teal), (read.Customization.Name, read.Customization.Symbol, read.Customization.Accent));
        // Without branding of its own, a Space wears its accent's house look.
        Assert.Equal(SpaceBranding.Normalized(SpaceAccent.Teal.House), read.Customization.Branding);

        // One Space that does not read drops the draft, as the release that saved it did.
        byte[]?[] dropped = [
            null, [], Encoding.UTF8.GetBytes("{"), Encoding.UTF8.GetBytes("{}"), Saved(),
            Saved(Space(), null),
            Edited(edited => edited.Remove("profile")),
            Edited(edited => edited.Remove("customization")),
            Edited(edited => edited["isNew"] = "yes"),
            Edited(edited => edited["customization"]!.AsObject().Remove("name")),
            Edited(edited => edited["customization"]!.AsObject().Remove("symbol")),
            Edited(edited => edited["customization"]!["accent"] = "unknown"),
            Edited(edited => edited["id"] = "space"),
            Edited(edited => edited["customization"]!["branding"] = new JsonObject { ["bannerStrength"] = "strong" })
        ];
        Assert.All(dropped, document => Assert.Null(LegacySetupDraftDocument.Read(document)));
    }
}

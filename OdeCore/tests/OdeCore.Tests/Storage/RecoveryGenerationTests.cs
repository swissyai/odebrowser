using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

/// The dated copies of the session file: what each launch keeps, what the
/// rotation removes, the copy a launch holds back when the session lost more
/// than half of what it held, and the restores that return to a copy.
public sealed partial class BrowserContractsTests {
    private static string CheckpointsOf(StorageDirectory directory) => Path.Combine(directory.Path, RecoveryGenerations.DirectoryName);

    /// Writes a session file holding one Space with `tabs` tabs, in place of
    /// whatever the file and its sidecars held, as a damaged or wrong write
    /// that still decodes would leave it.
    private static void WriteSessionWithTabs(string file, int tabs) {
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        var list = document["spaces"]![0]!["tabs"]!.AsArray();
        var template = list[0]!.AsObject();
        template.Remove("splitGroupID");
        for (int index = 1; index < tabs; index++) {
            var copy = template.DeepClone().AsObject();
            copy["id"] = SwiftId(Guid.NewGuid());
            list.Add(copy);
        }
        foreach (var path in new[] { file, file + "-wal", file + "-shm" }) File.Delete(path);
        WriteStoredFile(file, document, JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid())));
    }

    private static void Launch(StorageDirectory directory) {
        using var app = new OdeApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
    }

    private static int StoredTabs(StorageDirectory directory) {
        using var app = new OdeApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        return StoredDocument(app)["spaces"]![0]!["tabs"]!.AsArray().Count;
    }

    [Fact]
    public void EachLaunchKeepsADatedCopyNamedForWhatItHeld() {
        using var directory = new StorageDirectory();
        WriteSessionWithTabs(directory.File, 6);
        Launch(directory);
        Launch(directory);

        var generations = OdeApp.ListRecoveryGenerations(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        Assert.Equal(2, generations.Count);
        Assert.All(generations, generation => Assert.Equal((1, 6, false), (generation.Spaces, generation.Tabs, generation.Held)));
        Assert.True(generations[0].TakenAt >= generations[1].TakenAt);
        // The newest copy is also the standalone checkpoint a restore returns to.
        AssertSameParts(StoredParts(Path.Combine(CheckpointsOf(directory), generations[0].Name)), StoredParts(directory.Recovery));
    }

    [Fact]
    public void ASessionThatLostMoreThanHalfHoldsTheFullCopyBackAcrossLaunches() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 6);
        Launch(directory);
        var full = Assert.Single(OdeApp.ListRecoveryGenerations(configuration));
        var fullParts = StoredParts(directory.Recovery);

        // A write that still decodes but holds one tab of six, then many launches.
        WriteSessionWithTabs(directory.File, 1);
        for (int launch = 0; launch < RecoveryGenerations.LaunchesKept + 3; launch++) Launch(directory);

        var generations = OdeApp.ListRecoveryGenerations(configuration);
        var held = Assert.Single(generations, generation => generation.Held);
        Assert.Equal(full.Name, held.Name);
        Assert.Equal(6, held.Tabs);
        AssertSameParts(fullParts, StoredParts(directory.Recovery));

        // The default restore returns to the copy held back, and lets it rotate again.
        OdeApp.RestoreRecoveryCheckpoint(configuration);
        Assert.Equal(6, StoredTabs(directory));
        Assert.DoesNotContain(OdeApp.ListRecoveryGenerations(configuration), generation => generation.Held);
    }

    [Fact]
    public void WhatThePersonRemovedExplainsASmallerSession() {
        using var directory = new StorageDirectory();
        WriteSessionWithTabs(directory.File, 6);
        using (var storage = SessionStorage.Open(directory.Path, _ => { }, out var loaded)) {
            var session = loaded.Session!;
            storage.SaveRecoveryCheckpoint(session, DateTimeOffset.UtcNow);
            var space = session.Spaces[0];
            storage.NoteRemovedByPerson(session, session with { Spaces = [space with { Tabs = [space.Tabs[0]] }] });
        }
        WriteSessionWithTabs(directory.File, 1);
        using (var storage = SessionStorage.Open(directory.Path, _ => { }, out var loaded))
            storage.SaveRecoveryCheckpoint(loaded.Session!, DateTimeOffset.UtcNow);

        Assert.Equal(2, RecoveryGenerations.List(directory.Path).Count);
        Assert.DoesNotContain(RecoveryGenerations.List(directory.Path), generation => generation.Held);
    }

    [Fact]
    public void KeepingTheCurrentSessionLetsTheHeldCopyRotateOut() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 6);
        Launch(directory);
        WriteSessionWithTabs(directory.File, 1);
        Launch(directory);
        Assert.Contains(OdeApp.ListRecoveryGenerations(configuration), generation => generation.Held);

        OdeApp.KeepCurrentSession(configuration);
        for (int launch = 0; launch < RecoveryGenerations.LaunchesKept; launch++) Launch(directory);
        Assert.All(OdeApp.ListRecoveryGenerations(configuration), generation => Assert.Equal(1, generation.Tabs));
    }

    [Fact]
    public void ARestoreCanReturnToAChosenCopy() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 6);
        Launch(directory);
        var six = Assert.Single(OdeApp.ListRecoveryGenerations(configuration));
        WriteSessionWithTabs(directory.File, 3);
        Launch(directory);
        Assert.DoesNotContain(OdeApp.ListRecoveryGenerations(configuration), generation => generation.Held);

        OdeApp.RestoreRecoveryCheckpoint(configuration, six.Name);
        Assert.Equal(6, StoredTabs(directory));
        Assert.IsType<RecoveryCheckpointUnusable>(
            Assert.Throws<Rejected>(() => OdeApp.RestoreRecoveryCheckpoint(configuration, "session-missing.sqlite")).Rejection);
    }

    [Fact]
    public void ARestorePassesOverDamagedCopiesToTheNewestThatDecodes() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 6);
        Launch(directory);
        WriteSessionWithTabs(directory.File, 4);
        Launch(directory);
        var newest = OdeApp.ListRecoveryGenerations(configuration)[0];
        Assert.Equal(4, newest.Tabs);

        File.WriteAllBytes(directory.Recovery, "damaged"u8.ToArray());
        File.WriteAllBytes(Path.Combine(CheckpointsOf(directory), newest.Name), "damaged"u8.ToArray());
        OdeApp.RestoreRecoveryCheckpoint(configuration);
        Assert.Equal(6, StoredTabs(directory));
    }

    [Fact]
    public void TheRotationKeepsRecentLaunchesAndOneCopyPerDayWithinItsCaps() {
        using var directory = new StorageDirectory();
        string folder = CheckpointsOf(directory);
        Directory.CreateDirectory(folder);
        var now = new DateTimeOffset(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);
        var names = new List<string>();
        for (int day = 9; day >= 0; day--) {
            foreach (int hour in new[] { 1, 2, 3 }) {
                string name = RecoveryGenerations.NameFor(now.Date.AddDays(-day).AddHours(hour), new(1, 10));
                File.WriteAllBytes(Path.Combine(folder, name), new byte[100]);
                names.Add(name);
            }
        }
        string oldest = names[0];
        RecoveryGenerations.Hold(directory.Path, oldest);

        RecoveryGenerations.Prune(directory.Path, now);
        var kept = RecoveryGenerations.List(directory.Path).Select(generation => generation.Name).ToHashSet();
        // Today's three, yesterday's two newest, the newest of each of the five days before, and the held copy.
        Assert.Equal(11, kept.Count);
        Assert.Contains(oldest, kept);
        foreach (int day in Enumerable.Range(0, RecoveryGenerations.DaysKept))
            Assert.Contains(RecoveryGenerations.NameFor(now.Date.AddDays(-day).AddHours(3), new(1, 10)), kept);
        Assert.DoesNotContain(RecoveryGenerations.NameFor(now.Date.AddDays(-2).AddHours(1), new(1, 10)), kept);

        // Over the size cap, the oldest kept copies go first; the newest and the held copy stay.
        RecoveryGenerations.Prune(directory.Path, now, mostBytes: 350);
        var capped = RecoveryGenerations.List(directory.Path);
        Assert.Equal(3, capped.Count);
        Assert.Equal(names[^1], capped[0].Name);
        Assert.Contains(capped, generation => generation.Name == oldest && generation.Held);
    }

    [Fact]
    public void ACopyKeptBeforeAnUpdateIsNamedForTheVersionAndRestoresTheSessionFromBeforeIt() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 6);
        using (var app = new OdeApp(configuration)) app.Send(new KeepCopyBeforeUpdate("0.9.4"));

        var update = Assert.Single(OdeApp.ListRecoveryGenerations(configuration), generation => generation.UpdateTo is not null);
        Assert.Equal(("0.9.4", 1, 6), (update.UpdateTo, update.Spaces, update.Tabs));

        // The update's first launch finds a damaged session; the copy from before it restores.
        WriteSessionWithTabs(directory.File, 1);
        OdeApp.RestoreRecoveryCheckpoint(configuration, update.Name);
        Assert.Equal(6, StoredTabs(directory));
    }

    [Fact]
    public void CopiesKeptBeforeUpdatesKeepOnePerVersionForTheNewestVersionsOutsideTheLaunchRotation() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 3);
        using (var app = new OdeApp(configuration)) {
            foreach (var version in new[] { "0.9.1", "0.9.2", "0.9.2", "0.9.3", "0.9.4" }) app.Send(new KeepCopyBeforeUpdate(version));
        }
        for (int launch = 0; launch < RecoveryGenerations.LaunchesKept + 3; launch++) Launch(directory);

        var generations = OdeApp.ListRecoveryGenerations(configuration);
        Assert.Equal(["0.9.4", "0.9.3", "0.9.2"],
            generations.Where(generation => generation.UpdateTo is not null).Select(generation => generation.UpdateTo));
        Assert.Equal(RecoveryGenerations.LaunchesKept, generations.Count(generation => generation.UpdateTo is null));
    }

    [Fact]
    public void ACopyBeforeAnUpdateRefusesAVersionItCannotBeNamedFor() {
        using var directory = new StorageDirectory();
        WriteSessionWithTabs(directory.File, 2);
        using var app = new OdeApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        Assert.IsType<InvalidUpdateVersion>(Assert.Throws<Rejected>(() => app.Send(new KeepCopyBeforeUpdate("../0.9"))).Rejection);
        Assert.IsType<InvalidUpdateVersion>(Assert.Throws<Rejected>(() => app.Send(new KeepCopyBeforeUpdate(""))).Rejection);
    }

    [Fact]
    public void ARestoreKeepsTheSessionItReplacedAsACopyThatRestoresBack() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 6);
        Launch(directory);
        var six = Assert.Single(OdeApp.ListRecoveryGenerations(configuration));
        WriteSessionWithTabs(directory.File, 3);

        OdeApp.RestoreRecoveryCheckpoint(configuration, six.Name);
        Assert.Equal(6, StoredTabs(directory));
        var before = Assert.Single(OdeApp.ListRecoveryGenerations(configuration), generation => generation.BeforeRestore);
        Assert.Equal((1, 3, false), (before.Spaces, before.Tabs, before.Held));

        // Undoing the restore returns to the session it replaced.
        OdeApp.RestoreRecoveryCheckpoint(configuration, before.Name);
        Assert.Equal(3, StoredTabs(directory));
    }

    [Fact]
    public void TheDefaultRestoreNeverChoosesACopyKeptBeforeARestore() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 6);
        Launch(directory);
        var six = Assert.Single(OdeApp.ListRecoveryGenerations(configuration));
        WriteSessionWithTabs(directory.File, 2);
        OdeApp.RestoreRecoveryCheckpoint(configuration, six.Name);

        // The standalone checkpoint is gone; the newest copy is the session
        // the first restore replaced, which the default restore passes over.
        File.Delete(directory.Recovery);
        OdeApp.RestoreRecoveryCheckpoint(configuration);
        Assert.Equal(6, StoredTabs(directory));
    }

    [Fact]
    public void CopiesKeptBeforeRestoresKeepTheNewestFewOutsideTheLaunchRotation() {
        using var directory = new StorageDirectory();
        string folder = CheckpointsOf(directory);
        Directory.CreateDirectory(folder);
        var now = new DateTimeOffset(2026, 10, 29, 12, 0, 0, TimeSpan.Zero);
        for (int hour = 1; hour <= 5; hour++) {
            File.WriteAllBytes(Path.Combine(folder, RecoveryGenerations.NameFor(now.AddHours(-hour), new(1, 2), beforeRestore: true)), new byte[10]);
            File.WriteAllBytes(Path.Combine(folder, RecoveryGenerations.NameFor(now.AddHours(-hour).AddMinutes(1), new(1, 2))), new byte[10]);
        }

        RecoveryGenerations.Prune(directory.Path, now);
        var listed = RecoveryGenerations.List(directory.Path);
        Assert.Equal(RecoveryGenerations.RestoreCopiesKept, listed.Count(generation => generation.BeforeRestore));
        Assert.Equal(RecoveryGenerations.LaunchesKept, listed.Count(generation => !generation.BeforeRestore));
        Assert.Equal(now.AddHours(-1), listed.First(generation => generation.BeforeRestore).TakenAt);
    }

    [Fact]
    public void TheCopiesAreListedWithoutAnAppAndTheHeldCopyIsKeptOnRequest() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        WriteSessionWithTabs(directory.File, 6);
        Launch(directory);
        WriteSessionWithTabs(directory.File, 1);
        Launch(directory);

        var copies = new StandaloneAnswers().Query(new RecoveryCopiesIn(directory.Path)).Copies;
        Assert.Equal(2, copies.Count);
        var held = Assert.Single(copies, copy => copy.Held);
        Assert.Equal((1, 6, null, false), (held.Spaces, held.Tabs, held.UpdateTo, held.BeforeRestore));
        Assert.Empty(new StandaloneAnswers().Query(new RecoveryCopiesIn(Path.Combine(directory.Path, "missing"))).Copies);

        // The person answers that nothing is missing: the copy is no longer held.
        using (var app = new OdeApp(configuration)) app.Send(new KeepCurrentSession());
        Assert.DoesNotContain(new StandaloneAnswers().Query(new RecoveryCopiesIn(directory.Path)).Copies, copy => copy.Held);
    }

    [Fact]
    public void OnlyALossOfMoreThanHalfThePersonDidNotMakeHoldsACopyBack() {
        var newest = new RecoveryGenerations.Counts(4, 40);
        Assert.False(RecoveryGenerations.LostMoreThanHalf(newest, new(4, 20), default));
        Assert.True(RecoveryGenerations.LostMoreThanHalf(newest, new(4, 19), default));
        Assert.True(RecoveryGenerations.LostMoreThanHalf(newest, new(1, 40), default));
        Assert.False(RecoveryGenerations.LostMoreThanHalf(newest, new(1, 5), new(3, 35)));
        // A loss of one is never one, however small the session.
        Assert.False(RecoveryGenerations.LostMoreThanHalf(new(1, 1), new(1, 0), default));
    }
}

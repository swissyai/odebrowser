using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;

using Xunit;

namespace OdeCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void ImportAttemptsAndPerDestinationExtensionResultsSurviveRelaunchAndSetupRestart() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        var document = SavedSession().Document["session"]!.AsObject();
        var firstId = Guid.NewGuid();
        var secondId = Guid.NewGuid();
        var interruptedId = Guid.NewGuid();
        Guid importedSpace;
        const string extension = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
        using (var app = new OdeApp(configuration)) {
            app.Send(Adoption(document));
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            app.Send(new StartSetup(workspace, SetupEntry.ImportBrowser));
            app.Send(new OfferImportSources([ImportSource.Arc]));
            app.Send(new ContinueImport());
            var review = Flowing(app.Send(new ReviewImport(ImportSource.Arc,
                ReadSpaces(ImportedSpace("Arc", ImportedTab("https://arc.example/"))), []))).Review!;
            importedSpace = review.Spaces[0].Source.Id;
            var started = new SetupImportOutcome(firstId, "Arc", SetupImportOutcomeStatus.Started, 1, 1, 0, 0,
                ["One history database was unreadable"], 0, 0, 0, 0,
                [new(extension, "Blocker", importedSpace, SetupImportExtensionStatus.Pending)]);
            app.Send(new RecordSetupImportOutcome(started));
            app.Send(new BeginImportCommit());
            app.Send(new ImportReviewedSpaces(workspace, Guid.NewGuid()));
            app.Send(new FinishImportCommit(0, 0, started with { Status = SetupImportOutcomeStatus.Imported, DroppedCookieCount = 2 }));
            app.Send(new RecordSetupImportOutcome(started with { Id = secondId, SourceTitle = "Chrome", Status = SetupImportOutcomeStatus.Failed }));
            app.Send(new RecordSetupImportOutcome(started with { Id = interruptedId, SourceTitle = "Retry" }));
        }
        using (var app = new OdeApp(configuration)) {
            var receipts = app.Query(new GetSetupImportOutcomes()).Items;
            Assert.Equal(3, receipts.Count);
            Assert.Equal(SetupImportOutcomeStatus.Imported, receipts[0].Status);
            Assert.Equal(2, receipts[0].DroppedCookieCount);
            Assert.Single(receipts[0].Omissions);
            Assert.Equal(SetupImportExtensionStatus.Pending, Assert.Single(receipts[0].Extensions).Status);
            Assert.Equal(SetupImportOutcomeStatus.Failed, receipts[1].Status);
            Assert.Equal(SetupImportOutcomeStatus.Started, receipts[2].Status);
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            app.Send(new StartSetup(workspace, SetupEntry.ImportBrowser));
            Assert.Equal(3, app.Query(new GetSetupImportOutcomes()).Items.Count);
            // Unapproved destinations and a stale started receipt cannot undo a result.
            app.Send(new SetSetupImportExtensionOutcome(firstId, extension, Guid.NewGuid(), SetupImportExtensionStatus.Installed));
            app.Send(new RecordSetupImportOutcome(receipts[0] with { Status = SetupImportOutcomeStatus.Started }));
            Assert.Equal(SetupImportExtensionStatus.Pending, Assert.Single(app.Query(new GetSetupImportOutcomes()).Items[0].Extensions).Status);
            app.Send(new SetSetupImportExtensionOutcome(firstId, extension, importedSpace, SetupImportExtensionStatus.Installed));
        }
        using var reopened = new OdeApp(configuration);
        var installed = Assert.Single(reopened.Query(new GetSetupImportOutcomes()).Items[0].Extensions);
        Assert.Equal(SetupImportExtensionStatus.Installed, installed.Status);
    }

    [Fact]
    public void ARefusedReceiptWriteDoesNotPublishAnAttemptAndCanBeRetriedAfterTheActualLockIsReleased() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        using var app = new OdeApp(configuration);
        var outcome = new SetupImportOutcome(Guid.NewGuid(), "Synthetic", SetupImportOutcomeStatus.Started,
            0, 0, 0, 0, [], 0, 0, 0, 0, []);
        using (var holder = SqliteConnection.Open(directory.File, Sqlite.OpenReadWrite)) {
            holder.Execute("BEGIN IMMEDIATE");
            Assert.IsType<SaveFailed>(Assert.Throws<Rejected>(() => app.Send(new RecordSetupImportOutcome(outcome))).Rejection);
            Assert.Empty(app.Query(new GetSetupImportOutcomes()).Items);
            holder.Execute("ROLLBACK");
        }
        app.Send(new RecordSetupImportOutcome(outcome));
        Assert.Equal(outcome.Id, Assert.Single(app.Query(new GetSetupImportOutcomes()).Items).Id);

        var destination = Guid.NewGuid();
        const string extension = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
        app.Send(new RecordSetupImportOutcome(outcome with {
            Status = SetupImportOutcomeStatus.Imported,
            Extensions = [new(extension, "Blocker", destination, SetupImportExtensionStatus.Pending)]
        }));
        using (var holder = SqliteConnection.Open(directory.File, Sqlite.OpenReadWrite)) {
            holder.Execute("BEGIN IMMEDIATE");
            Assert.IsType<SaveFailed>(Assert.Throws<Rejected>(() => app.Send(
                new SetSetupImportExtensionOutcome(outcome.Id, extension, destination, SetupImportExtensionStatus.Installed))).Rejection);
            Assert.Equal(SetupImportExtensionStatus.Pending,
                Assert.Single(Assert.Single(app.Query(new GetSetupImportOutcomes()).Items).Extensions).Status);
            holder.Execute("ROLLBACK");
        }
        app.Send(new SetSetupImportExtensionOutcome(outcome.Id, extension, destination, SetupImportExtensionStatus.Installed));
        var removed = Guid.NewGuid();
        var removedReceipt = outcome with {
            Id = Guid.NewGuid(),
            Status = SetupImportOutcomeStatus.Imported,
            Extensions = [new(extension, "Blocker", removed, SetupImportExtensionStatus.Pending)]
        };
        app.Send(new RecordSetupImportOutcome(removedReceipt));
        app.Send(new SetSetupImportExtensionOutcome(removedReceipt.Id, extension, removed, SetupImportExtensionStatus.Removed));
        using var reopened = new OdeApp(configuration);
        Assert.Equal(SetupImportExtensionStatus.Removed,
            reopened.Query(new GetSetupImportOutcomes()).Items[1].Extensions[0].Status);
        Assert.Equal(SetupImportExtensionStatus.Installed,
            Assert.Single(reopened.Query(new GetSetupImportOutcomes()).Items[0].Extensions).Status);
    }

    [Fact]
    public void ReceiptUpdatesPreserveUnknownDocumentAndDestinationFieldsAcrossSqlUpdateAndReopen() {
        using var directory = new StorageDirectory();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        var firstSpace = Guid.Parse("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
        var secondSpace = Guid.Parse("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");
        const string extension = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
        var receipt = new SetupImportOutcome(Guid.Parse("cccccccc-cccc-4ccc-8ccc-cccccccccccc"), "Synthetic", SetupImportOutcomeStatus.Imported,
            1, 1, 0, 1, ["Passwords left out"], 2, 3, 4, 1,
            [new(extension, "Blocker", firstSpace, SetupImportExtensionStatus.Pending),
             new(extension, "Blocker", secondSpace, SetupImportExtensionStatus.Pending)]);
        using (var app = new OdeApp(configuration)) app.Send(new RecordSetupImportOutcome(receipt));
        using (var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadWrite)) {
            using var read = connection.Prepare("SELECT document FROM device_import_outcome WHERE id = ?");
            // SQLite TEXT keys are case-sensitive; the store's GUID keys are uppercase.
            Assert.Null(read.Bind(1, receipt.Id.ToString("D")).First<string?>(row => row.Text(0), null));
            var stored = read.Bind(1, receipt.Id.ToString("D").ToUpperInvariant()).First<string?>(row => row.Text(0), null);
            Assert.NotNull(stored);
            var document = JsonNode.Parse(stored)!.AsObject();
            document["future"] = new JsonObject { ["kept"] = true };
            document["extensions"]![0]!["futureDestination"] = new JsonObject { ["token"] = "first" };
            document["extensions"]![0]!["space"] = firstSpace.ToString("D").ToUpperInvariant();
            document["extensions"]![1]!["futureDestination"] = new JsonObject { ["token"] = "second" };
            using var update = connection.Prepare("UPDATE device_import_outcome SET document = ? WHERE id = ?");
            Assert.Equal(1, update.Bind(1, document.ToJsonString()).Bind(2, receipt.Id.ToString("D").ToUpperInvariant()).Run());
        }
        using (var app = new OdeApp(configuration)) {
            app.Send(new SetSetupImportExtensionOutcome(receipt.Id, extension, firstSpace, SetupImportExtensionStatus.Installed));
            app.Send(new SetSetupImportExtensionOutcome(receipt.Id, extension, secondSpace, SetupImportExtensionStatus.Failed));
        }
        using (var app = new OdeApp(configuration)) {
            var extensions = Assert.Single(app.Query(new GetSetupImportOutcomes()).Items).Extensions;
            Assert.Equal(SetupImportExtensionStatus.Installed, extensions[0].Status);
            Assert.Equal(SetupImportExtensionStatus.Failed, extensions[1].Status);
            // A late observation cannot rewrite an already settled destination.
            app.Send(new SetSetupImportExtensionOutcome(receipt.Id, extension, secondSpace, SetupImportExtensionStatus.Installed));
            Assert.Equal(SetupImportExtensionStatus.Failed,
                app.Query(new GetSetupImportOutcomes()).Items[0].Extensions[1].Status);
        }
        using (var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadWrite)) {
            using var read = connection.Prepare("SELECT document FROM device_import_outcome WHERE id = ?");
            var document = JsonNode.Parse(read.Bind(1, receipt.Id.ToString("D").ToUpperInvariant()).First(row => row.Text(0), ""))!;
            Assert.True(document["future"]!["kept"]!.GetValue<bool>());
            Assert.NotNull(document["extensions"]![0]!["futureDestination"]);
            Assert.Equal("first", document["extensions"]![0]!["futureDestination"]!["token"]!.GetValue<string>());
            Assert.Equal("second", document["extensions"]![1]!["futureDestination"]!["token"]!.GetValue<string>());
            document["status"] = -1;
            Assert.Null(SetupImportOutcomeDocument.Read(document.ToJsonString()));
            document["status"] = (int)SetupImportOutcomeStatus.Imported;
            document["extensions"]![0]!["status"] = -1;
            Assert.Null(SetupImportOutcomeDocument.Read(document.ToJsonString()));
        }
    }

    [Fact]
    public void AReceiptDocumentReadsBackWholeOrNotAtAll() {
        var space = Guid.Parse("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
        var receipt = new SetupImportOutcome(Guid.Parse("cccccccc-cccc-4ccc-8ccc-cccccccccccc"), "Synthetic", SetupImportOutcomeStatus.Imported,
            3, 2, 5, 1, ["History left out"], 7, 2, 1, 1,
            [new("cjpalhdlnbpafiamejdnhcphjbkeiagm", "Blocker", space, SetupImportExtensionStatus.Installed)]);
        string written = SetupImportOutcomeDocument.Write(receipt);
        string Edited(Action<JsonObject> edit) {
            var document = JsonNode.Parse(written)!.AsObject();
            edit(document);
            return document.ToJsonString();
        }

        var read = SetupImportOutcomeDocument.Read(written)!;
        Assert.Equal(receipt.Omissions, read.Omissions);
        Assert.Equal(receipt.Extensions, read.Extensions);
        Assert.Equal(receipt, read with { Omissions = receipt.Omissions, Extensions = receipt.Extensions });

        // Missing counts and lists read as none, and a negative count as zero.
        var sparse = SetupImportOutcomeDocument.Read(Edited(document => {
            document.Remove("tabs");
            document.Remove("omissions");
            document.Remove("extensions");
            document["cookies"] = -4;
        }))!;
        Assert.Equal((0, 0), (sparse.TabCount, sparse.CookieCount));
        Assert.Empty(sparse.Omissions);
        Assert.Empty(sparse.Extensions);

        // A document that does not read whole is no receipt.
        string?[] unreadable = [
            null, "", "[]", "{",
            Edited(document => document.Remove("id")),
            Edited(document => document["id"] = "receipt"),
            Edited(document => document.Remove("title")),
            Edited(document => document.Remove("status")),
            Edited(document => document["status"] = 9),
            Edited(document => document["tabs"] = "three"),
            Edited(document => document["omissions"] = new JsonArray(JsonValue.Create(1))),
            Edited(document => document["extensions"]![0]!.AsObject().Remove("name")),
            Edited(document => document["extensions"]![0]!["space"] = "space"),
            Edited(document => document["extensions"]![0]!["status"] = 9)
        ];
        Assert.All(unreadable, document => Assert.Null(SetupImportOutcomeDocument.Read(document)));

        // A rewrite keeps what a newer build added to the receipt and to the
        // entry for the same extension and Space, and drops other entries.
        var rewritten = JsonNode.Parse(SetupImportOutcomeDocument.Write(receipt with { Status = SetupImportOutcomeStatus.Failed }, Edited(document => {
            document["future"] = 1;
            document["extensions"]![0]!["space"] = space.ToString("D").ToUpperInvariant();
            document["extensions"]![0]!["token"] = "kept";
            document["extensions"]!.AsArray().Add(new JsonObject { ["id"] = "other", ["space"] = space.ToString("D"), ["token"] = "dropped" });
        })))!;
        Assert.Equal(1, rewritten["future"]!.GetValue<int>());
        Assert.Equal((int)SetupImportOutcomeStatus.Failed, rewritten["status"]!.GetValue<int>());
        var extension = Assert.Single(rewritten["extensions"]!.AsArray())!;
        Assert.Equal("kept", extension["token"]!.GetValue<string>());
        Assert.Equal(space.ToString("D"), extension["space"]!.GetValue<string>());
    }
}

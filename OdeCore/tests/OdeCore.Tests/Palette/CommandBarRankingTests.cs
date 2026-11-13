using System.Globalization;
using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;
using Xunit.Abstractions;

namespace OdeCore.Tests;

/// How the palette ranks a labelled set of queries over a synthetic workspace
/// of kept tabs, folders and history, read from the fixtures beside this test:
/// how many of the expected rows land first and within the first three rows.
/// The two counts are the contract; a change to ranking that moves either
/// must say so by updating them.
public sealed class CommandBarRankingTests(ITestOutputHelper output) {
    #region Static Variables

    /// How many of the labelled queries put the expected row first.
    private const int ExpectedFirst = 50;

    /// How many of the labelled queries put the expected row in the first three.
    private const int ExpectedTopThree = 50;

    /// The moment every query is asked at; the fixture's dates precede it.
    private static readonly DateTimeOffset Now = new(2026, 11, 8, 12, 0, 0, TimeSpan.Zero);

    #endregion

    #region Actions - Ranking

    [Fact]
    public void TheLabelledQueriesLandWhereExpected() {
        var workspace = RankingWorkspace.Load();
        int first = 0, topThree = 0;
        foreach (var query in RankingQuery.Load()) {
            int position = workspace.Position(query, Now);
            if (position == 1) first++;
            if (position is >= 1 and <= 3) topThree++;
            output.WriteLine($"{query.Id,2} {query.Text,-18} {(position == 0 ? "absent" : $"#{position}"),-7} {query.Rule}");
        }
        output.WriteLine($"first {first}/50, top three {topThree}/50");

        Assert.Equal((ExpectedFirst, ExpectedTopThree), (first, topThree));
    }

    #endregion
}

/// One labelled query: what is typed, the Space it is typed in, and what the
/// first row should be. `Expected` is the address of a tab or history row,
/// `space:` and a Space's name, `folder:` and a folder's title, `intent:` and
/// the address the text itself opens, `card` for a calculator card, or
/// `search` for the search row. `Setup` names picks to remember first.
internal sealed record RankingQuery(int Id, string Text, string Space, string Expected, string Rule, string Setup) {
    #region Actions - Loading

    public static IReadOnlyList<RankingQuery> Load() =>
        [.. RankingFixture.Rows("CommandBarRankingQueries.tsv").Select(cells =>
            new RankingQuery(int.Parse(cells[0], CultureInfo.InvariantCulture), cells[1], cells[2], cells[3], cells[4], cells[5]))];

    #endregion

    #region Actions - Matching

    /// Whether `row`, shown in `space`, is the expected row.
    public bool Matches(PaletteRow row, SpaceState space) {
        if (Expected.StartsWith("space:", StringComparison.Ordinal)) return row.Kind == PaletteRowKind.Space && row.Title == Expected[6..];
        if (Expected.StartsWith("folder:", StringComparison.Ordinal)) return row.Kind == PaletteRowKind.Folder && row.Title == Expected[7..];
        if (Expected.StartsWith("intent:", StringComparison.Ordinal))
            return row.Kind == PaletteRowKind.OpenAddress && SamePlace(row.Address, Expected[7..]);
        if (row.TabId is { } tab)
            return space.Tabs.FirstOrDefault(candidate => candidate.Id == tab) is { } found && SamePlace(found.SavedAddress ?? found.Url, Expected);
        return row.Kind == PaletteRowKind.History && SamePlace(row.Address, Expected);
    }

    private static bool SamePlace(string? address, string expected) =>
        address is not null && PaletteMemory.Place(address) is { } place && place == PaletteMemory.Place(expected);

    #endregion
}

/// The synthetic workspace the labelled queries run against: one Space per
/// name in the items fixture, each with its kept tabs, folders and history.
internal sealed class RankingWorkspace {
    #region Variables

    private readonly IReadOnlyDictionary<string, SpaceState> spaces;

    #endregion

    #region Constructors

    private RankingWorkspace(IReadOnlyDictionary<string, SpaceState> spaces) => this.spaces = spaces;

    public static RankingWorkspace Load() {
        var items = RankingFixture.Rows("CommandBarRankingItems.tsv")
            .Select(cells => new Item(cells[0], cells[1], cells[2], cells[3], cells[4], cells[5], cells[6])).ToList();
        var spaces = new Dictionary<string, SpaceState>(StringComparer.Ordinal);
        foreach (var group in items.GroupBy(item => item.Space)) spaces[group.Key] = Space(group.Key, [.. group]);
        return new(spaces);
    }

    #endregion

    #region Actions - Ranking

    /// Where the expected row lands for `query` at `now`, counted from one
    /// across every group, or zero when it is absent. A card or a search is
    /// first only when no Top Hit shows above it.
    public int Position(RankingQuery query, DateTimeOffset now) {
        var space = spaces[query.Space == "any" ? "Studio" : query.Space];
        var others = spaces.Values.Where(other => other.Id != space.Id).ToList();
        var memory = Remembered(query, now);
        var palette = new Palette(space, shownTabId: null, isPrivate: false, allowsInternalPages: true, AppPreferences.Default,
            SearchCatalog.Starting(language: null, region: null), memory, others, now);
        var answer = palette.Answer(new PaletteSuggestions(Guid.NewGuid(), query.Text, [], [], [], Provider: null, Scope: null,
            AllowsCompletion: true, Pasteboard: null));
        var rows = answer.Groups.SelectMany(group => group.Rows).ToList();
        bool leads = answer.Groups.Any(group => group.Section == PaletteSection.TopHit);
        if (query.Expected == "card")
            return !leads && answer.Groups.Any(group => group.Section == PaletteSection.Card) && rows[0].Kind == PaletteRowKind.Search ? 1 : 0;
        if (query.Expected == "search") return !leads && rows.Count > 0 && rows[0].Kind == PaletteRowKind.Search ? 1 : 0;
        int index = rows.FindIndex(row => query.Matches(row, space));
        return index + 1;
    }

    /// A memory that began before every date in the fixture, with the picks
    /// `query` sets up remembered an hour before `now`.
    private static PaletteMemory Remembered(RankingQuery query, DateTimeOffset now) {
        var memory = PaletteMemory.Starting(new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero));
        if (query.Setup.Length == 0) return memory;
        var parts = query.Setup.Split('|');
        for (int pick = 0; pick < int.Parse(parts[3], CultureInfo.InvariantCulture); pick++)
            memory = memory.Chose(parts[2], PaletteDestination.Address(parts[1])!, parts[1], before: null, now.AddHours(-1), learns: true);
        return memory;
    }

    #endregion

    #region Actions - Building

    /// The Space named `name` holding `items`, decoded as a stored Space is:
    /// saved and pinned items become kept tabs at their address, a folder
    /// named by an item holds it, and history items become entries, newest
    /// first, each first visited a day before its last visit.
    private static SpaceState Space(string name, IReadOnlyList<Item> items) {
        var folders = new Dictionary<string, Guid>(StringComparer.Ordinal);
        JsonArray tabs = [];
        foreach (var item in items.Where(item => item.Kind != "history")) {
            var tab = new JsonObject {
                ["id"] = Identity(Guid.NewGuid()),
                ["title"] = item.Title,
                ["url"] = item.Url,
                ["savedURL"] = item.Url,
                ["placement"] = item.Kind,
                ["symbol"] = "globe"
            };
            if (item.LastActiveAt is { } active) tab["lastActivatedAt"] = StoredSessionCodec.Seconds(active);
            if (item.Folder.Length > 0) {
                if (!folders.TryGetValue(item.Folder, out var folder)) folders[item.Folder] = folder = Guid.NewGuid();
                tab["folderID"] = Identity(folder);
            }
            tabs.Add(tab);
        }
        var history = items.Where(item => item.Kind == "history").OrderByDescending(item => item.LastActiveAt).Select(item => (JsonNode)new JsonObject {
            ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(),
            ["url"] = item.Url,
            ["title"] = item.Title,
            ["firstVisitedAt"] = StoredSessionCodec.Seconds(item.LastActiveAt!.Value.AddDays(-1)),
            ["lastVisitedAt"] = StoredSessionCodec.Seconds(item.LastActiveAt.Value),
            ["visitCount"] = int.Parse(item.Visits, CultureInfo.InvariantCulture)
        });
        return StoredSessionCodec.DecodeSpace(new JsonObject {
            ["id"] = Identity(Guid.NewGuid()),
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant() },
            ["name"] = name,
            ["symbol"] = "square.stack",
            ["accent"] = "indigo",
            ["accessPolicy"] = "open",
            ["tabs"] = tabs,
            ["folders"] = new JsonArray([.. folders.Select(folder => (JsonNode)new JsonObject {
                ["id"] = Identity(folder.Value), ["title"] = folder.Key, ["location"] = "saved"
            })]),
            ["splitGroups"] = new JsonArray(),
            ["archivedTabs"] = new JsonArray(),
            ["history"] = new JsonArray([.. history])
        });
    }

    private static JsonObject Identity(Guid id) => new() { ["rawValue"] = id.ToString("D").ToUpperInvariant() };

    #endregion

    #region Types

    /// One fixture row: a kept tab or a history entry of a Space.
    private sealed record Item(string Space, string Kind, string Folder, string Title, string Url, string LastActive, string Visits) {
        public DateTimeOffset? LastActiveAt => LastActive.Length == 0 ? null
            : DateTimeOffset.Parse(LastActive, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal);
    }

    #endregion
}

/// Reads a tab-separated fixture beside the palette tests, skipping its header.
internal static class RankingFixture {
    #region Actions - Reading

    public static IEnumerable<string[]> Rows(string name) =>
        File.ReadLines(Path.Combine(AppContext.BaseDirectory, "Palette", "Fixtures", name)).Skip(1)
            .Where(line => line.Length > 0).Select(line => line.Split('\t'));

    #endregion
}

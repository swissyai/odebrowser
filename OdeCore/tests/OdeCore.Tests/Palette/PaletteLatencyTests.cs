using System.Diagnostics;
using System.Text.Json.Nodes;

using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;
using Xunit.Abstractions;

namespace OdeCore.Tests;

/// How long the palette takes to answer one keystroke over a Space at the
/// size the ranking is built for: 500 open tabs, 480 kept tabs in 20
/// folders, 1,500 history entries, 280 commands, 20 settings pages and 20
/// other Spaces. The answer must stay within four milliseconds at the median
/// and eight at the 95th percentile, so results never lag the caret. The
/// test runs apart from the parallel suites so their work is not timed.
[Collection(PaletteLatencyCollection.Name)]
public sealed class PaletteLatencyTests(ITestOutputHelper output) {
    #region Static Variables

    private const double MedianBudgetMilliseconds = 4;
    private const double TailBudgetMilliseconds = 8;
    private const int Rounds = 9;
    private static readonly DateTimeOffset Now = new(2026, 11, 8, 12, 0, 0, TimeSpan.Zero);
    private static readonly string[] Words = [
        "alpha", "beacon", "cobalt", "delta", "ember", "falcon", "garden", "harbor", "indigo", "jasper", "kestrel", "lantern", "meadow",
        "nectar", "orchid", "pioneer", "quartz", "river", "saffron", "timber", "umber", "velvet", "willow", "xenon", "yarrow", "zephyr",
        "anchor", "bridge", "canyon", "dune", "estuary", "fjord", "glacier", "heath", "island", "jungle", "knoll", "lagoon", "mesa",
        "notes", "report", "plan", "review", "draft", "guide", "board", "studio", "atlas", "ledger", "signal", "vector", "matrix", "module"
    ];
    private static readonly string[] Queries = [
        "al", "alp", "alpha", "bea", "beacon", "co", "cob", "delta", "em", "ember", "fal", "garden", "har", "harbor", "ind", "jas", "kes",
        "lan", "mea", "nec", "orc", "pio", "qua", "riv", "saf", "tim", "umb", "vel", "wil", "xen", "yar", "zep", "report", "plan", "rev",
        "draft", "guide", "board", "ledger notes", "river plan", "alpha report", "site12", "site3", "quartz atlas", "module", "matrix"
    ];

    #endregion

    #region Actions - Timing

    [Fact]
    public void AKeystrokeIsAnsweredWithinTheBudget() {
        var (space, others) = Workspace();
        var commands = Enumerable.Range(0, 280).Select(n => new PaletteCommand(ShortcutCommand.All[n % ShortcutCommand.All.Count],
            $"{Word(n * 7)} {Word(n * 11 + 3)}", Word(n % 5))).ToList();
        var pages = Enumerable.Range(0, 20).Select(n => new PaletteSettingsPage($"page{n}", Word(n * 3), $"{Word(n * 5)} {Word(n * 9)}")).ToList();
        var memory = PaletteMemory.Starting(Now.AddDays(1));
        var catalog = SearchCatalog.Starting(language: null, region: null);
        PaletteAnswer Answer(string text) => new Palette(space, shownTabId: null, isPrivate: false, allowsInternalPages: true, AppPreferences.Default,
            catalog, memory, others, Now).Answer(new PaletteSuggestions(Guid.NewGuid(), text, commands, pages, [], Provider: null, Scope: null,
            AllowsCompletion: true, Pasteboard: null));

        foreach (var text in Queries) Answer(text);
        // Each query's time is the best of its rounds, so another process
        // taking the CPU mid-answer does not stand in for the ranking's cost.
        var samples = new double[Queries.Length];
        Array.Fill(samples, double.MaxValue);
        for (int round = 0; round < Rounds; round++)
            for (int index = 0; index < Queries.Length; index++) {
                long started = Stopwatch.GetTimestamp();
                Answer(Queries[index]);
                samples[index] = Math.Min(samples[index], Stopwatch.GetElapsedTime(started).TotalMilliseconds);
            }
        Array.Sort(samples);
        double median = samples[samples.Length / 2];
        double tail = samples[(int)Math.Ceiling(samples.Length * 0.95) - 1];
        output.WriteLine($"{samples.Length} queries, best of {Rounds} rounds, over {space.Tabs.Count} tabs, {space.History.Count} history entries, "
            + $"{commands.Count} commands: median {median:F2} ms, p95 {tail:F2} ms, max {samples[^1]:F2} ms");

        Assert.True(median <= MedianBudgetMilliseconds, $"median {median:F2} ms exceeds {MedianBudgetMilliseconds} ms");
        Assert.True(tail <= TailBudgetMilliseconds, $"p95 {tail:F2} ms exceeds {TailBudgetMilliseconds} ms");
    }

    #endregion

    #region Actions - Building

    /// A Space of 500 open tabs, 480 saved tabs in 20 folders and 1,500
    /// history entries over 60 hosts, with 20 other Spaces beside it.
    private static (SpaceState Space, IReadOnlyList<SpaceState> Others) Workspace() {
        var folders = Enumerable.Range(0, 20).Select(_ => Guid.NewGuid()).ToList();
        JsonArray tabs = [];
        for (int n = 0; n < 500; n++) tabs.Add(Tab(n, "current", null));
        for (int n = 500; n < 980; n++) tabs.Add(Tab(n, "saved", folders[n % folders.Count]));
        var history = Enumerable.Range(0, 1_500).Select(n => (JsonNode)new JsonObject {
            ["id"] = Guid.NewGuid().ToString("D"),
            ["url"] = Url(n + 2_000),
            ["title"] = Title(n + 2_000),
            ["firstVisitedAt"] = StoredSessionCodec.Seconds(Now.AddDays(-(n % 400) - 1)),
            ["lastVisitedAt"] = StoredSessionCodec.Seconds(Now.AddDays(-(n % 400))),
            ["visitCount"] = 1 + n % 7
        });
        var space = StoredSessionCodec.DecodeSpace(new JsonObject {
            ["id"] = new JsonObject { ["rawValue"] = Guid.NewGuid().ToString("D") },
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString("D") },
            ["name"] = "Studio",
            ["tabs"] = tabs,
            ["folders"] = new JsonArray([.. folders.Select((folder, index) => (JsonNode)new JsonObject {
                ["id"] = new JsonObject { ["rawValue"] = folder.ToString("D") },
                ["title"] = $"{Word(index * 13)} {Word(index * 17 + 1)}",
                ["location"] = "saved"
            })]),
            ["history"] = new JsonArray([.. history])
        });
        var others = Enumerable.Range(0, 20).Select(n => StoredSessionCodec.DecodeSpace(new JsonObject {
            ["id"] = new JsonObject { ["rawValue"] = Guid.NewGuid().ToString("D") },
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString("D") },
            ["name"] = Word(n * 19 + 2)
        })).ToList();
        return (space, others);
    }

    private static JsonObject Tab(int n, string placement, Guid? folder) {
        var tab = new JsonObject {
            ["id"] = new JsonObject { ["rawValue"] = Guid.NewGuid().ToString("D") },
            ["title"] = Title(n),
            ["url"] = Url(n),
            ["savedURL"] = Url(n),
            ["placement"] = placement,
            ["symbol"] = "globe",
            ["lastActivatedAt"] = StoredSessionCodec.Seconds(Now.AddHours(-(n % 300)))
        };
        if (folder is { } held) tab["folderID"] = new JsonObject { ["rawValue"] = held.ToString("D") };
        return tab;
    }

    /// A title of three to six words, some behind an unread badge or before a site name.
    private static string Title(int n) {
        string words = string.Join(' ', Enumerable.Range(0, 3 + n % 4).Select(index => Word(n * 7 + index * 31)));
        return n % 9 == 0 ? $"({n % 50 + 1}) {words}" : n % 4 == 0 ? $"{words} - {Word(n * 3)}" : words;
    }

    /// An address on one of 60 hosts with up to three path segments and sometimes a query.
    private static string Url(int n) {
        string host = n % 5 == 0 ? $"www.site{n % 60}.example" : $"{Word(n % Words.Length)}.site{n % 60}.example";
        string path = string.Join('/', Enumerable.Range(0, n % 4).Select(index => $"{Word(n * 5 + index * 13)}-{n + index}"));
        string query = n % 6 == 0 ? $"?tab={Word(n * 3)}&id={n}" : "";
        return $"https://{host}/{path}{query}";
    }

    private static string Word(int n) => Words[Math.Abs(n) % Words.Length];

    #endregion
}

/// The collection the latency test runs in, alone.
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class PaletteLatencyCollection {
    #region Static Variables

    public const string Name = "Palette latency";

    #endregion
}

using System.Reflection;
using System.Text.Json;

using OdeCore.Contracts;

namespace OdeCore.Domain;

#region Types

/// One live answer with the words that find it: its card, then its title,
/// the questions people ask for it, its other names, loose keywords, its
/// steps, its note and the words of its default keys.
internal sealed record AnswerEntry(AnswerCard Card, string Title, IReadOnlyList<string> Questions, IReadOnlyList<string> Aliases,
    IReadOnlyList<string> Keywords, IReadOnlyList<string> Steps, string Note, string KeyWords);

#endregion

/// The written answers Ode ships, read once from the answers file the core
/// embeds: every live card with the words that find it, the groups of words
/// ranking treats as one, the cards offered before anything is asked, and the
/// index that ranks them. A card the file marks pending, waiting for its
/// feature, is left out. An answer that names a command Ode does not have,
/// or a kind or field the file does not define, fails the read.
internal sealed class AnswerCatalog {
    #region Static Variables

    private const string ResourceName = "OdeCore.Answers.json";

    /// The words a key symbol is spoken as, so "cmd shift t" finds ⇧⌘T.
    private static readonly Dictionary<char, string> KeyNames = new() {
        ['⌘'] = "cmd command",
        ['⇧'] = "shift",
        ['⌥'] = "option opt alt",
        ['⌃'] = "ctrl control",
        ['⇥'] = "tab",
        ['←'] = "left",
        ['→'] = "right",
        ['↑'] = "up",
        ['↓'] = "down",
        ['↩'] = "return enter",
        ['⌫'] = "delete"
    };

    private static readonly Lazy<AnswerCatalog> shipped = new(() => {
        using var stream = typeof(AnswerCatalog).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException($"The core does not embed {ResourceName}.");
        return Read(stream);
    });

    /// The answers Ode ships.
    public static AnswerCatalog Shipped => shipped.Value;

    #endregion

    #region Variables

    public IReadOnlyList<AnswerEntry> Entries { get; }

    /// Each word's group of words ranking treats as the same, by stem.
    public IReadOnlyDictionary<string, IReadOnlyList<string>> Synonyms { get; }

    /// The cards offered before anything is asked, in order.
    public IReadOnlyList<AnswerCard> Suggested { get; }

    public AnswerIndex Index { get; }

    #endregion

    #region Constructors

    private AnswerCatalog(IReadOnlyList<AnswerEntry> entries, IReadOnlyDictionary<string, IReadOnlyList<string>> synonyms,
        IReadOnlyList<AnswerCard> suggested) {
        Entries = entries;
        Synonyms = synonyms;
        Suggested = suggested;
        Index = new AnswerIndex(this);
    }

    #endregion

    #region Actions - Reading

    /// The live answers in an answers file.
    public static AnswerCatalog Read(Stream stream) {
        ArgumentNullException.ThrowIfNull(stream);
        using var document = JsonDocument.Parse(stream);
        var root = document.RootElement;
        if (root.GetProperty("schemaVersion").GetInt32() != 1)
            throw new InvalidDataException("This answers file is not schema version 1.");
        string guides = Text(root.GetProperty("helpBase")).TrimEnd('/');
        List<AnswerEntry> entries = [];
        foreach (var card in root.GetProperty("cards").EnumerateArray()) {
            var entry = Entry(card, guides);
            if (card.GetProperty("status").GetString() == "live") entries.Add(entry);
            else if (card.GetProperty("status").GetString() != "pending")
                throw new InvalidDataException($"{entry.Card.Id}: an answer is live or pending.");
        }
        if (entries.Select(entry => entry.Card.Id).Distinct(StringComparer.Ordinal).Count() != entries.Count)
            throw new InvalidDataException("Two answers share an id.");
        Dictionary<string, IReadOnlyList<string>> synonyms = new(StringComparer.Ordinal);
        foreach (var group in root.GetProperty("synonyms").EnumerateArray()) {
            List<string> stems = [.. group.EnumerateArray().SelectMany(word => AnswerText.Of(Text(word)).Words).Distinct()];
            foreach (var stem in stems)
                synonyms[stem] = [.. (synonyms.TryGetValue(stem, out var known) ? known : []).Concat(stems).Distinct()];
        }
        var byId = entries.ToDictionary(entry => entry.Card.Id, entry => entry.Card, StringComparer.Ordinal);
        List<AnswerCard> suggested = [.. Strings(root, "suggested").Select(id => byId.TryGetValue(id, out var card)
            ? card : throw new InvalidDataException($"The suggested answer {id} is not a live answer."))];
        return new(entries, synonyms, suggested);
    }

    private static AnswerEntry Entry(JsonElement card, string guides) {
        string id = Text(card.GetProperty("id"));
        var kind = AnswerKind.Named(card.GetProperty("kind").GetString())
            ?? throw new InvalidDataException($"{id}: unknown kind.");
        string? keys = Optional(card, "keys");
        var answer = new AnswerCard(id, kind, Text(card.GetProperty("title")), Strings(card, "steps"), keys, Optional(card, "note"),
            card.TryGetProperty("action", out var action) ? Action(id, action) : null, guides + card.GetProperty("help").GetString());
        return new(answer, answer.Title, Strings(card, "questions"), Strings(card, "aliases"), Strings(card, "keywords"), answer.Steps,
            answer.Note ?? "", keys is null ? "" : string.Join(' ', keys.Select(key => KeyNames.TryGetValue(key, out var name)
                ? name : key.ToString().ToLowerInvariant())));
    }

    private static AnswerAction Action(string id, JsonElement action) {
        var named = action.EnumerateObject().ToList();
        if (named.Count != 1) throw new InvalidDataException($"{id}: an action names exactly one thing to run.");
        string target = Text(named[0].Value);
        return named[0].Name switch {
            "command" => new(ShortcutCommand.Named(target) ?? throw new InvalidDataException($"{id}: Ode has no command {target}."),
                null, null, null),
            "settings" => new(null, target, null, null),
            "space" => new(null, null, target, null),
            "app" => new(null, null, null, target),
            _ => throw new InvalidDataException($"{id}: unknown action {named[0].Name}.")
        };
    }

    private static IReadOnlyList<string> Strings(JsonElement element, string name) =>
        element.TryGetProperty(name, out var values) ? [.. values.EnumerateArray().Select(Text)] : [];

    private static string Text(JsonElement value) =>
        value.GetString() ?? throw new InvalidDataException("An answers file holds a null where text belongs.");

    private static string? Optional(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) ? value.GetString() : null;

    #endregion
}

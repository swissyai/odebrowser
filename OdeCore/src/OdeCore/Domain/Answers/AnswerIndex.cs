using OdeCore.Contracts;

namespace OdeCore.Domain;

#region Types

/// A card that matched a question, how strongly, whether the question is,
/// word for word, one of the card's own titles, names or questions, and the
/// share of the words asked that the card is about.
internal sealed record AnswerMatch(AnswerCard Card, double Score, bool Exact, double Coverage);

/// How ranking weighs what it reads: how much a word counts in each field,
/// in the order title, names, questions, keywords, steps, note and keys; BM25's
/// saturation and length normalization; what a synonym, two joined words and a
/// typo count for; what a card that holds none of the words asked keeps of
/// its score; and the bonuses for a phrase the card holds exactly, after a
/// typo fix, or inside a longer one, for a name of the card the text holds
/// whole, and for title words.
internal sealed record AnswerWeights(IReadOnlyList<double> Fields, double Saturation, double LengthNormalization, double Synonym, double Split,
    double Typo, double UncoveredShare, double Exact, double CorrectedExact, double Contained, double Named, double Title) {
    /// The weights tuned on four fifths of the golden questions.
    public static AnswerWeights Tuned { get; } = new([2.6, 2.3, 1.9, 2.35, 0.32, 0.35, 1.9], Saturation: 0.85, LengthNormalization: 0.8,
        Synonym: 0.57, Split: 0.9, Typo: 0.63, UncoveredShare: 0.49, Exact: 4.2, CorrectedExact: 3.4, Contained: 0.86, Named: 2.84,
        Title: 2.54);
}

#endregion

/// Ranks the written answers for what a person typed, by the words they
/// share and nothing else: BM25 over each card's fields, weighted so a word
/// in the title or another name for the feature counts most and a word in the
/// steps least; words a group of synonyms treats as one; a typo fixed against
/// the words the answers hold; two words typed as one, as in "splitview";
/// more for a card that holds every word asked, and most for a card whose
/// title, name or question the text is. It also decides whether one answer
/// should lead the palette: when the text names a card exactly, or reads as a
/// question the best card is about and answers clearly, or names one card far
/// better than any other. Text that looks like an address never leads with
/// one.
internal sealed class AnswerIndex {
    #region Static Variables

    /// The score a question's best card must reach to lead.
    private const double QuestionFloor = 6;

    /// The share of a question's words its best card must be about to lead,
    /// unless it scores `StrongFloor`: a card about one word of a question
    /// on something else, as "side" in "the side effects of ibuprofen", does
    /// not answer it.
    private const double QuestionCoverage = 0.5;

    /// The score, and the lead over the next card, with which a card leads
    /// text that does not read as a question.
    private const double StrongFloor = 10;
    private const double StrongMargin = 1.6;

    #endregion

    #region Variables

    private readonly AnswerWeights weights;
    private readonly IReadOnlyList<Document> documents;
    private readonly IReadOnlyDictionary<string, IReadOnlyList<string>> synonyms;
    private readonly Dictionary<string, double> idf = new(StringComparer.Ordinal);
    private readonly double[] averages = new double[Fields];

    /// The fields a card is read in.
    private const int Fields = 7;

    /// The fields that show a card is about a word, rather than mentioning it.
    private static readonly bool[] Strong = [true, true, true, false, false, false, true];

    #endregion

    #region Constructors

    public AnswerIndex(AnswerCatalog catalog, AnswerWeights? weights = null) {
        ArgumentNullException.ThrowIfNull(catalog);
        this.weights = weights ?? AnswerWeights.Tuned;
        synonyms = catalog.Synonyms;
        documents = [.. catalog.Entries.Select(entry => Document.Of(entry, Canonical))];
        Dictionary<string, int> frequency = new(StringComparer.Ordinal);
        foreach (var document in documents) {
            for (int field = 0; field < Fields; field++) averages[field] += document.Lengths[field];
            foreach (var term in document.Terms) frequency[term] = frequency.GetValueOrDefault(term) + 1;
        }
        for (int field = 0; field < Fields; field++) averages[field] = Math.Max(1, averages[field] / Math.Max(1, documents.Count));
        foreach (var (term, count) in frequency)
            idf[term] = Math.Log(1 + (documents.Count - count + 0.5) / (count + 0.5));
    }

    #endregion

    #region Actions - Ranking

    /// Every card that matches `text`, best first.
    public IReadOnlyList<AnswerMatch> Rank(string text) {
        ArgumentNullException.ThrowIfNull(text);
        var asked = AnswerText.Of(text);
        if (asked.Terms.Count == 0) return [];
        var expansions = asked.Terms.Distinct(StringComparer.Ordinal).Select(Expand).ToList();
        double rarity = expansions.Sum(expansion => expansion.Count == 0 ? 0 : expansion.Keys.Max(Rarity));
        string phrase = Canonical(asked.Words);
        string corrected = Canonical(asked.Words.Select(word => Corrected(word) ?? word));
        List<AnswerMatch> matches = [];
        foreach (var document in documents) {
            // Each word asked counts once, through whichever of the words it
            // stands for the card holds best, so a card that holds a word and
            // its synonyms does not count it twice.
            double score = expansions.Sum(expansion => expansion.Count == 0 ? 0
                : expansion.Max(term => term.Value * Relevance(document, term.Key)));
            if (score <= 0) continue;
            int covered = expansions.Count(expansion => expansion.Keys.Any(document.StrongTerms.Contains));
            score *= weights.UncoveredShare + (1 - weights.UncoveredShare) * covered / expansions.Count;
            if (rarity > 0)
                score += weights.Title * expansions.Sum(expansion => expansion.Keys.Where(document.TitleTerms.Contains).Select(Rarity)
                    .DefaultIfEmpty(0).Max()) / rarity;
            bool exact = document.Phrases.Contains(phrase);
            if (exact) score += weights.Exact;
            // A correction that only finishes what is being typed, as "engi"
            // toward Engines, is not a typo, and so is not an exact match.
            else if (corrected != phrase && document.Phrases.Contains(corrected)
                && !document.Phrases.Any(known => known.StartsWith(phrase, StringComparison.Ordinal))) {
                score += weights.CorrectedExact;
                exact = true;
            } else if (phrase.Length >= 6 && document.Phrases.Any(known => $" {known} ".Contains($" {phrase} ", StringComparison.Ordinal)))
                score += weights.Contained;
            if (!exact && document.Names.Any(name => $" {phrase} ".Contains($" {name} ", StringComparison.Ordinal)
                || $" {corrected} ".Contains($" {name} ", StringComparison.Ordinal)))
                score += weights.Named;
            matches.Add(new(document.Card, score, exact, (double)covered / expansions.Count));
        }
        return [.. matches.OrderByDescending(match => match.Score).ThenBy(match => match.Card.Id, StringComparer.Ordinal)];
    }

    /// How much `term` says about `document`: BM25 over its fields.
    private double Relevance(Document document, string term) {
        if (!idf.TryGetValue(term, out double rarity)) return 0;
        double frequency = 0;
        for (int field = 0; field < Fields; field++) {
            if (document.Counts[field].GetValueOrDefault(term) is not (> 0 and var count)) continue;
            frequency += weights.Fields[field] * count / (1 - weights.LengthNormalization + weights.LengthNormalization * document.Lengths[field] / averages[field]);
        }
        return rarity * frequency * (weights.Saturation + 1) / (frequency + weights.Saturation);
    }

    /// How rare `term` is among the answers, or nothing for a word none holds.
    private double Rarity(string term) => idf.GetValueOrDefault(term);

    /// The card that should lead the palette for `text`, or null.
    public AnswerCard? Lead(string text) {
        ArgumentNullException.ThrowIfNull(text);
        if (LooksLikeAddress(text)) return null;
        var matches = Rank(text);
        if (matches.Count == 0) return null;
        var best = matches[0];
        if (best.Exact) return best.Card;
        var asked = AnswerText.Of(text);
        // Small words alone, as the start of "what is the", ask nothing yet.
        if (!asked.HasContent) return null;
        if (asked.ReadsAsQuestion && best.Score >= QuestionFloor && (best.Coverage > QuestionCoverage || best.Score >= StrongFloor))
            return best.Card;
        double next = matches.Count > 1 ? matches[1].Score : 0;
        return asked.Words.Count >= 2 && best.Score >= StrongFloor && best.Score >= StrongMargin * next ? best.Card : null;
    }

    /// The words `term` stands for, each with how much it counts: itself when
    /// the answers hold it, the words its synonym group holds, and, for a
    /// word no answer holds, the two words it joins or the words one typo
    /// away from it.
    private Dictionary<string, double> Expand(string term) {
        Dictionary<string, double> expansion = new(StringComparer.Ordinal);
        bool known = idf.ContainsKey(term);
        if (known) expansion[term] = 1;
        if (synonyms.TryGetValue(term, out var group))
            foreach (var synonym in group.Where(synonym => synonym != term && idf.ContainsKey(synonym)))
                expansion[synonym] = weights.Synonym;
        if (known || expansion.Count > 0) return expansion;
        if (Split(term) is { } split) {
            expansion[split.First] = weights.Split;
            expansion[split.Second] = weights.Split;
            return expansion;
        }
        foreach (var near in Near(term)) expansion[near] = weights.Typo;
        return expansion;
    }

    /// `words` as one phrase, each word spelled as the first of its synonym
    /// group, so "ctrl tab" and "control tab" compare equal.
    private string Canonical(IEnumerable<string> words) =>
        string.Join(' ', words.Select(word => synonyms.TryGetValue(word, out var group) ? group[0] : word));

    /// What `word` most likely meant, when the answers do not hold it: the
    /// two words it joins, or the one word it is a typo of; null for a word
    /// they hold, a short one, or one with no single nearest word.
    private string? Corrected(string word) {
        if (idf.ContainsKey(word) || synonyms.ContainsKey(word)) return null;
        if (Split(word) is { } split) return $"{split.First} {split.Second}";
        var near = Near(word).ToList();
        return near.Count == 1 ? near[0] : null;
    }

    /// Two words the answers hold that `term` joins, as "splitview" joins
    /// "split" and "view", or null.
    private (string First, string Second)? Split(string term) {
        if (term.Length < 6) return null;
        for (int cut = 3; cut <= term.Length - 3; cut++) {
            string first = AnswerText.Stem(term[..cut]), second = AnswerText.Stem(term[cut..]);
            if (idf.ContainsKey(first) && idf.ContainsKey(second)) return (first, second);
        }
        return null;
    }

    /// The words the answers hold within one edit of `term`, or two for a
    /// long word; none for a word shorter than four letters.
    private IEnumerable<string> Near(string term) {
        if (term.Length < 4) yield break;
        int allowed = term.Length <= 7 ? 1 : 2;
        foreach (var candidate in idf.Keys)
            if (Math.Abs(candidate.Length - term.Length) <= allowed && Distance(term, candidate, allowed) <= allowed)
                yield return candidate;
    }

    /// Edits, counting a swap of two neighbours as one, from `first` to
    /// `second`, or more than `limit` once it is sure to exceed it.
    private static int Distance(string first, string second, int limit) {
        var costs = new int[first.Length + 1, second.Length + 1];
        for (int row = 0; row <= first.Length; row++) costs[row, 0] = row;
        for (int column = 0; column <= second.Length; column++) costs[0, column] = column;
        for (int row = 1; row <= first.Length; row++) {
            int smallest = int.MaxValue;
            for (int column = 1; column <= second.Length; column++) {
                int cost = first[row - 1] == second[column - 1] ? 0 : 1;
                int value = Math.Min(Math.Min(costs[row - 1, column] + 1, costs[row, column - 1] + 1), costs[row - 1, column - 1] + cost);
                if (row > 1 && column > 1 && first[row - 1] == second[column - 2] && first[row - 2] == second[column - 1])
                    value = Math.Min(value, costs[row - 2, column - 2] + 1);
                costs[row, column] = value;
                smallest = Math.Min(smallest, value);
            }
            if (smallest > limit) return limit + 1;
        }
        return costs[first.Length, second.Length];
    }

    /// Whether `text` looks like an address someone means to open: a scheme,
    /// or one word with a dot inside it.
    private static bool LooksLikeAddress(string text) {
        string trimmed = text.Trim();
        if (trimmed.Contains("://", StringComparison.Ordinal)) return true;
        int dot = trimmed.IndexOf('.', StringComparison.Ordinal);
        return !trimmed.Any(char.IsWhiteSpace) && dot > 0 && dot < trimmed.Length - 1;
    }

    #endregion

    #region Types

    /// One card as ranking reads it: which stems appear in each of its
    /// fields, each field's length, the stems in its strong fields, its title,
    /// names and questions as whole phrases, and its names of two words or
    /// more.
    private sealed record Document(AnswerCard Card, IReadOnlyList<Dictionary<string, int>> Counts, int[] Lengths,
        HashSet<string> StrongTerms, HashSet<string> Phrases, HashSet<string> Names, HashSet<string> TitleTerms) {
        public IEnumerable<string> Terms => Counts.SelectMany(counts => counts.Keys).Distinct(StringComparer.Ordinal);

        public static Document Of(AnswerEntry entry, Func<IEnumerable<string>, string> canonical) {
            IReadOnlyList<string>[] fields = [[entry.Title], entry.Aliases, entry.Questions, entry.Keywords, entry.Steps, [entry.Note],
                [entry.KeyWords]];
            List<Dictionary<string, int>> counts = [];
            var lengths = new int[fields.Length];
            HashSet<string> strong = new(StringComparer.Ordinal);
            for (int field = 0; field < fields.Length; field++) {
                Dictionary<string, int> count = new(StringComparer.Ordinal);
                // A word counts once in a field however often the field repeats
                // it, so a card with many names for one feature does not
                // outrank the card that is about it.
                foreach (var term in fields[field].SelectMany(text => AnswerText.Of(text).Terms)) {
                    count[term] = 1;
                    lengths[field]++;
                    if (Strong[field]) strong.Add(term);
                }
                counts.Add(count);
            }
            HashSet<string> phrases = new(StringComparer.Ordinal);
            foreach (var text in entry.Aliases.Concat(entry.Questions).Append(entry.Title))
                phrases.Add(canonical(AnswerText.Of(text).Words));
            HashSet<string> names = new(StringComparer.Ordinal);
            foreach (var alias in entry.Aliases)
                if (AnswerText.Of(alias).Words is { Count: >= 2 } words) names.Add(canonical(words));
            HashSet<string> title = [.. AnswerText.Of(entry.Title).Terms];
            return new(entry.Card, counts, lengths, strong, phrases, names, title);
        }
    }

    #endregion
}

using System.Globalization;
using System.Text;

using OdeCore.Contracts;

namespace OdeCore.Application;

#region Types

/// One place of a Space's history with the time of every visit it holds,
/// oldest first, as an export writes it.
internal sealed record HistoryVisits(HistoryPlace Place, IReadOnlyList<DateTimeOffset> Visits);

#endregion

internal sealed partial class HistoryStore {
    #region Static Variables

    /// How much the search ranks a word in a title, an address and a page's
    /// text, in that order.
    private const string Weights = "10.0, 4.0, 1.0";

    #endregion

    #region Actions - Places

    /// The places of `space` last visited before `before`, or every place
    /// with none, newest first, `limit` at most, and whether more follow.
    /// `beforeUrl` continues within addresses sharing the cursor's visit time.
    public HistoryPlaces Places(Guid space, DateTimeOffset? before, int limit, string? beforeUrl = null) {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(limit);
        string spaceId = Spelling(space);
        long until = before?.ToUnixTimeMilliseconds() ?? long.MaxValue;
        return Read(statement => {
            List<HistoryPlace> places = [];
            statement("SELECT url, title, first_visit, last_visit, visit_count FROM place WHERE space = ?1 "
                    + "AND (last_visit < ?2 OR (last_visit = ?2 AND url < ?4)) "
                    + "ORDER BY last_visit DESC, url DESC LIMIT ?3")
                .Bind(1, spaceId).Bind(2, until).Bind(3, limit + 1).Bind(4, beforeUrl ?? "").Rows(row => places.Add(Place(row)));
            bool more = places.Count > limit;
            return new HistoryPlaces(more ? places[..limit] : places, more);
        });
    }

    /// The places of `space` whose title or address holds every word of
    /// `text`, the last as a word's start, best first, `limit` at most. Text
    /// of one letter, which starts too many words, finds the newest places
    /// whose title or address holds it anywhere.
    public IReadOnlyList<HistoryPlace> Matching(Guid space, string text, int limit) {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(limit);
        string spaceId = Spelling(space);
        if (MatchExpression(text) is not { } match) {
            string pattern = "%" + Escaped(text.Trim()) + "%";
            if (pattern == "%%") return [];
            return Read<IReadOnlyList<HistoryPlace>>(statement => {
                List<HistoryPlace> places = [];
                statement("SELECT url, title, first_visit, last_visit, visit_count FROM place WHERE space = ?1 "
                        + "AND (title LIKE ?2 ESCAPE '\\' OR url LIKE ?2 ESCAPE '\\') ORDER BY last_visit DESC, id DESC LIMIT ?3")
                    .Bind(1, spaceId).Bind(2, pattern).Bind(3, limit).Rows(row => places.Add(Place(row)));
                return places;
            });
        }
        return Read<IReadOnlyList<HistoryPlace>>(statement => {
            List<HistoryPlace> places = [];
            statement("SELECT p.url, p.title, p.first_visit, p.last_visit, p.visit_count FROM page_search s "
                    + "JOIN place p ON p.id = s.rowid WHERE page_search MATCH ? AND p.space = ? "
                    + $"ORDER BY bm25(page_search, {Weights}) LIMIT ?")
                .Bind(1, match).Bind(2, spaceId).Bind(3, limit).Rows(row => places.Add(Place(row)));
            return places;
        });
    }

    /// Every place of `space`, newest first, each with its visits, for an
    /// export to write as it reads them.
    public void EachWithVisits(Guid space, Action<HistoryVisits> each) {
        ArgumentNullException.ThrowIfNull(each);
        string spaceId = Spelling(space);
        Read(statement => {
            long current = 0;
            HistoryPlace? place = null;
            List<DateTimeOffset> visits = [];
            statement("SELECT p.id, p.url, p.title, p.first_visit, p.last_visit, p.visit_count, v.at FROM place p "
                    + "JOIN visit v ON v.place = p.id WHERE p.space = ? ORDER BY p.last_visit DESC, p.id DESC, v.at")
                .Bind(1, spaceId).Rows(row => {
                    long id = row.Long(0);
                    if (id != current) {
                        if (place is not null) each(new HistoryVisits(place, [.. visits]));
                        current = id;
                        place = new HistoryPlace(row.Text(1), row.Text(2), Time(row.Long(3)), Time(row.Long(4)), Count(row.Long(5)));
                        visits.Clear();
                    }
                    visits.Add(Time(row.Long(6)));
                });
            if (place is not null) each(new HistoryVisits(place, [.. visits]));
            return true;
        });
    }

    /// How many places and visits `space` keeps here.
    public (long Places, long Visits) Counts(Guid space) {
        string spaceId = Spelling(space);
        return Read(statement => (
            statement("SELECT count(*) FROM place WHERE space = ?").Bind(1, spaceId).First(row => row.Long(0), 0L),
            statement("SELECT count(*) FROM visit v JOIN place p ON p.id = v.place WHERE p.space = ?").Bind(1, spaceId)
                .First(row => row.Long(0), 0L)));
    }

    private static HistoryPlace Place(SqliteStatement row) =>
        new(row.Text(0), row.Text(1), Time(row.Long(2)), Time(row.Long(3)), Count(row.Long(4)));

    private static DateTimeOffset Time(long milliseconds) => DateTimeOffset.FromUnixTimeMilliseconds(milliseconds);

    private static int Count(long visits) => (int)Math.Clamp(visits, 1, int.MaxValue);

    #endregion

    #region Actions - Search text

    /// The full-text expression for `text`: each of its words in quotes, all
    /// required, the last also matching words it starts. Null when it holds
    /// no word, or only one letter, which would match most of the index.
    internal static string? MatchExpression(string text) {
        ArgumentNullException.ThrowIfNull(text);
        var words = Words(text);
        if (words.Count == 0 || words.Count == 1 && words[0].Length < 2) return null;
        var expression = new StringBuilder();
        for (int index = 0; index < words.Count; index++) {
            if (index > 0) expression.Append(' ');
            expression.Append('"').Append(words[index]).Append('"');
            if (index == words.Count - 1 && words[index].Length >= 2) expression.Append('*');
        }
        return expression.ToString();
    }

    /// The words of `text` as the index splits them: runs of letters and digits.
    internal static IReadOnlyList<string> Words(string text) {
        List<string> words = [];
        var word = new StringBuilder();
        foreach (var element in text.EnumerateRunes()) {
            if (Rune.IsLetterOrDigit(element) || Rune.GetUnicodeCategory(element) is UnicodeCategory.NonSpacingMark
                    or UnicodeCategory.SpacingCombiningMark) {
                word.Append(element.ToString());
                continue;
            }
            if (word.Length > 0) words.Add(word.ToString());
            word.Clear();
        }
        if (word.Length > 0) words.Add(word.ToString());
        return words;
    }

    #endregion
}

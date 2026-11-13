using System.Text;

using OdeCore.Contracts;

namespace OdeCore.Application;

#region Types

/// One address another browser's history held, with the times of the visits
/// it kept: those a browser prunes are only counted in `VisitCount`.
internal sealed record ImportedPlace(string Url, string Title, DateTimeOffset FirstVisitedAt, DateTimeOffset LastVisitedAt, long VisitCount,
    IReadOnlyList<DateTimeOffset> Visits);

#endregion

internal sealed partial class HistoryStore {
    #region Static Variables

    /// How many imported places one queued write takes in.
    private const int ImportChunk = 1_000;

    /// The most UTF-8 bytes of a page's text the store keeps for search.
    public const int MaximumTextBytes = 2_048;

    /// The tables that hold rows of a place, by the column naming it.
    private static readonly (string Table, string Column)[] PlaceRows = [("visit", "place"), ("page_search", "rowid"),
        ("page_text", "place")];

    #endregion

    #region Actions - Visits

    /// A visit at `at` to `entry`'s address, as the session's history records
    /// it in `space`: the place takes the entry's title and one more visit.
    public void Visit(Guid space, HistoryEntryState entry, DateTimeOffset at) {
        ArgumentNullException.ThrowIfNull(entry);
        string spaceId = Spelling(space), url = entry.Url, title = entry.Title;
        long time = at.ToUnixTimeMilliseconds();
        Enqueue(() => {
            var held = Writing("SELECT id, title FROM place WHERE space = ? AND url = ?").Bind(1, spaceId).Bind(2, url)
                .First(row => (Id: row.Long(0), Title: row.Text(1)), ((long Id, string Title)?)null);
            long place;
            if (held is { } existing) {
                place = existing.Id;
                Writing("UPDATE place SET title = ?, last_visit = max(last_visit, ?2), first_visit = min(first_visit, ?2), "
                    + "visit_count = visit_count + 1 WHERE id = ?3").Bind(1, title).Bind(2, time).Bind(3, place).Run();
            } else {
                place = Writing("INSERT INTO place(space, url, host, title, first_visit, last_visit, visit_count) VALUES(?,?,?,?,?,?,1) "
                        + "RETURNING id")
                    .Bind(1, spaceId).Bind(2, url).Bind(3, Site(url)).Bind(4, title).Bind(5, time).Bind(6, time)
                    .First(row => row.Long(0), 0L);
            }
            Writing("INSERT OR IGNORE INTO visit(place, at) VALUES(?,?)").Bind(1, place).Bind(2, time).Run();
            if (held?.Title != title) Index(place, url, title);
        });
    }

    /// The place for `url` in `space` titled `title`, without another visit.
    public void Retitle(Guid space, string url, string title) {
        string spaceId = Spelling(space);
        Enqueue(() => {
            long place = Writing("UPDATE place SET title = ? WHERE space = ? AND url = ? AND title <> ? RETURNING id")
                .Bind(1, title).Bind(2, spaceId).Bind(3, url).Bind(4, title).First(row => row.Long(0), 0L);
            if (place != 0) Index(place, url, title);
        });
    }

    #endregion

    #region Actions - Removal

    /// Removes the place for `url` from `space`, with its visits.
    public void Remove(Guid space, string url) {
        string spaceId = Spelling(space);
        Enqueue(() => RemovePlaces("space = ?1 AND url = ?2", statement => statement.Bind(1, spaceId).Bind(2, url)));
    }

    /// Removes every place of `site`, or of a host within it, from `space`.
    public void RemoveSite(Guid space, string site) {
        string spaceId = Spelling(space), host = Site(site);
        Enqueue(() => RemovePlaces("space = ?1 AND (host = ?2 OR host LIKE ?3 ESCAPE '\\')",
            statement => statement.Bind(1, spaceId).Bind(2, host).Bind(3, "%." + Escaped(host))));
    }

    /// Removes the visits `space` made from `start` up to, but not
    /// including, `end`, and every place left without a visit.
    public void RemoveVisits(Guid space, DateTimeOffset start, DateTimeOffset end) {
        string spaceId = Spelling(space);
        long from = start.ToUnixTimeMilliseconds(), until = end.ToUnixTimeMilliseconds();
        Enqueue(() => RemoveVisits(spaceId, from, until));
    }

    /// Removes the visits `space` made before `cutoff`, as its retention asks.
    public void Expire(Guid space, DateTimeOffset cutoff) {
        string spaceId = Spelling(space);
        long until = cutoff.ToUnixTimeMilliseconds();
        Enqueue(() => RemoveVisits(spaceId, long.MinValue, until));
    }

    /// Removes everything `space` keeps here, as clearing its history or
    /// deleting the Space does.
    public void Clear(Guid space) {
        string spaceId = Spelling(space);
        Enqueue(() => {
            RemovePlaces("space = ?1", statement => statement.Bind(1, spaceId));
            Writing("DELETE FROM adopted WHERE space = ?").Bind(1, spaceId).Run();
        });
    }

    /// The visits of `spaceId` in [`from`, `until`), and every place they
    /// leave without one; each place that keeps others dates and counts what
    /// is left. A count that includes visits the store has no time for keeps
    /// those. Runs on the worker.
    private void RemoveVisits(string spaceId, long from, long until) {
        writer.Execute("CREATE TEMP TABLE IF NOT EXISTS removed_visits (place INTEGER PRIMARY KEY, removed INTEGER NOT NULL)");
        Writing("DELETE FROM removed_visits").Run();
        Writing("INSERT INTO removed_visits SELECT v.place, count(*) FROM visit v JOIN place p ON p.id = v.place "
            + "WHERE p.space = ? AND v.at >= ? AND v.at < ? GROUP BY v.place").Bind(1, spaceId).Bind(2, from).Bind(3, until).Run();
        Writing("DELETE FROM visit WHERE at >= ? AND at < ? AND place IN (SELECT place FROM removed_visits)")
            .Bind(1, from).Bind(2, until).Run();
        RemovePlaces("id IN (SELECT place FROM removed_visits) AND NOT EXISTS (SELECT 1 FROM visit WHERE visit.place = place.id)", _ => { });
        Writing("UPDATE place SET first_visit = (SELECT min(at) FROM visit WHERE visit.place = place.id), "
            + "last_visit = (SELECT max(at) FROM visit WHERE visit.place = place.id), "
            + "visit_count = max((SELECT count(*) FROM visit WHERE visit.place = place.id), "
            + "visit_count - (SELECT removed FROM removed_visits r WHERE r.place = place.id)) "
            + "WHERE id IN (SELECT place FROM removed_visits)").Run();
        ForgetText(spaceId, from, until);
    }

    /// Removes the places `condition` names, which `bind` gives its values,
    /// with every row that belongs to them. Runs on the worker.
    private void RemovePlaces(string condition, Action<SqliteStatement> bind) {
        foreach (var (table, column) in PlaceRows) {
            var statement = Writing($"DELETE FROM {table} WHERE {column} IN (SELECT id FROM place WHERE {condition})");
            bind(statement);
            statement.Run();
        }
        var places = Writing($"DELETE FROM place WHERE {condition}");
        bind(places);
        places.Run();
    }

    #endregion

    #region Actions - Following the session

    /// Follows the session from `previous` to `next`: a Space the session no
    /// longer holds leaves nothing here, and, when `takesEntries`, each
    /// history entry `next` holds that `previous` did not, such as one another
    /// device synced or an import brought, joins its Space here without a
    /// visit of its own.
    public void Follow(SessionState previous, SessionState next, bool takesEntries) {
        ArgumentNullException.ThrowIfNull(previous);
        ArgumentNullException.ThrowIfNull(next);
        if (ReferenceEquals(previous.Spaces, next.Spaces)) return;
        foreach (var gone in previous.Spaces.Where(space => next.Spaces.All(kept => kept.Id != space.Id))) Clear(gone.Id);
        if (!takesEntries) return;
        foreach (var space in next.Spaces) {
            var before = previous.Spaces.FirstOrDefault(candidate => candidate.Id == space.Id);
            if (before is not null && ReferenceEquals(before.History, space.History)) continue;
            var held = before?.History.ToHashSet() ?? [];
            var arrived = space.History.Where(entry => !held.Contains(entry)).ToArray();
            if (arrived.Length == 0) continue;
            string spaceId = Spelling(space.Id);
            Enqueue(() => {
                foreach (var entry in arrived)
                    Take(spaceId, new ImportedPlace(entry.Url, entry.Title, entry.FirstVisitedAt, entry.LastVisitedAt, entry.VisitCount, []));
            });
        }
    }

    #endregion

    #region Actions - Bringing history in

    /// Takes in the history the session kept for each of `spaces` before
    /// this store did, once per Space: each address with a visit at its first
    /// and latest visit. A Space already taken in, or one whose address the
    /// store holds already, keeps what the store holds. Nothing is announced:
    /// the session shows these addresses already.
    public void Adopt(IEnumerable<SpaceState> spaces) {
        ArgumentNullException.ThrowIfNull(spaces);
        foreach (var space in spaces) {
            string spaceId = Spelling(space.Id);
            var entries = space.History;
            Enqueue(() => {
                if (Writing("SELECT 1 FROM adopted WHERE space = ?").Bind(1, spaceId).First(_ => true, false)) return;
                foreach (var entry in entries)
                    Take(spaceId, new ImportedPlace(entry.Url, entry.Title, entry.FirstVisitedAt, entry.LastVisitedAt, entry.VisitCount, []));
                Writing("INSERT OR IGNORE INTO adopted(space) VALUES(?)").Bind(1, spaceId).Run();
            }, announces: false);
        }
    }

    /// Takes in `places` another browser kept, into `space`, a thousand to a
    /// write so reads go on between them. An address the store holds keeps
    /// its title unless the import visited it later, and gains the visits it
    /// did not hold; taking the same import in twice adds nothing.
    public void Import(Guid space, IReadOnlyList<ImportedPlace> places) {
        ArgumentNullException.ThrowIfNull(places);
        string spaceId = Spelling(space);
        for (int start = 0; start < places.Count; start += ImportChunk) {
            var chunk = new ImportedPlace[Math.Min(ImportChunk, places.Count - start)];
            for (int index = 0; index < chunk.Length; index++) chunk[index] = places[start + index];
            Enqueue(() => {
                foreach (var place in chunk) Take(spaceId, place);
            });
        }
    }

    /// Takes in one place. A new place counts its visits, or the import's
    /// count where that is more, and holds a visit at its first and latest
    /// visit when the import brought no times. A place the store holds gains
    /// the visits it lacked and counts the larger of the two counts, so
    /// taking in what the store already holds, or the same import twice,
    /// counts nothing twice. Runs on the worker.
    private void Take(string spaceId, ImportedPlace place) {
        IReadOnlyList<DateTimeOffset> visits = place.Visits.Count > 0 ? place.Visits
            : place.FirstVisitedAt == place.LastVisitedAt ? [place.LastVisitedAt] : [place.FirstVisitedAt, place.LastVisitedAt];
        long first = Math.Min(visits.Min().ToUnixTimeMilliseconds(), place.FirstVisitedAt.ToUnixTimeMilliseconds());
        long last = Math.Max(visits.Max().ToUnixTimeMilliseconds(), place.LastVisitedAt.ToUnixTimeMilliseconds());
        long count = Math.Clamp(Math.Max(place.VisitCount, visits.Count), 1, BrowserDataHistoryEntry.MaximumVisitCount);
        var held = Writing("SELECT id, last_visit FROM place WHERE space = ? AND url = ?").Bind(1, spaceId).Bind(2, place.Url)
            .First(row => (Id: row.Long(0), Last: row.Long(1)), ((long Id, long Last)?)null);
        if (held is not { } existing) {
            long id = Writing("INSERT INTO place(space, url, host, title, first_visit, last_visit, visit_count) VALUES(?,?,?,?,?,?,?) "
                    + "RETURNING id")
                .Bind(1, spaceId).Bind(2, place.Url).Bind(3, Site(place.Url)).Bind(4, place.Title).Bind(5, first).Bind(6, last)
                .Bind(7, count).First(row => row.Long(0), 0L);
            AddVisits(id, visits);
            Index(id, place.Url, place.Title);
            return;
        }
        AddVisits(existing.Id, visits);
        bool later = last > existing.Last;
        Writing("UPDATE place SET title = CASE WHEN ?1 THEN ?2 ELSE title END, first_visit = min(first_visit, ?3), "
                + "last_visit = max(last_visit, ?4), visit_count = max(visit_count, ?5, "
                + "(SELECT count(*) FROM visit WHERE visit.place = ?6)) WHERE id = ?6")
            .Bind(1, later ? 1 : 0).Bind(2, place.Title).Bind(3, first).Bind(4, last).Bind(5, count).Bind(6, existing.Id).Run();
        if (later) Index(existing.Id, place.Url, place.Title);
    }

    /// Adds each visit `place` does not hold yet.
    private void AddVisits(long place, IReadOnlyList<DateTimeOffset> visits) {
        var insert = Writing("INSERT OR IGNORE INTO visit(place, at) VALUES(?,?)");
        foreach (var visit in visits) insert.Bind(1, place).Bind(2, visit.ToUnixTimeMilliseconds()).Run();
    }

    #endregion

    #region Actions - Page text

    /// Keeps `text`, the start of the readable text the page at `url` showed
    /// in `space` at `at`, for search, in place of what it kept for the page
    /// before: at most `MaximumTextBytes` UTF-8 bytes, cut at a word. An
    /// address the store holds no visit to keeps nothing. Empty text removes
    /// any earlier capture, and an older capture cannot replace a newer one.
    public void RememberText(Guid space, string url, string text, DateTimeOffset at) {
        ArgumentNullException.ThrowIfNull(text);
        string spaceId = Spelling(space), kept = Capped(text);
        byte[] compressed = kept.Length == 0 ? [] : Compressed(kept);
        long time = at.ToUnixTimeMilliseconds();
        Enqueue(() => {
            var held = Writing("SELECT id, title FROM place WHERE space = ? AND url = ?").Bind(1, spaceId).Bind(2, url)
                .First(row => (Id: row.Long(0), Title: row.Text(1)), ((long Id, string Title)?)null);
            if (held is not { } place) return;
            var before = Writing("SELECT captured_at, text FROM page_text WHERE place = ?").Bind(1, place.Id)
                .First(row => (At: row.Long(0), Text: row.Blob(1)), ((long At, byte[] Text)?)null);
            if (before is { } previous) {
                if (previous.At > time) return;
                if (previous.Text.AsSpan().SequenceEqual(compressed)) {
                    Writing("UPDATE page_text SET captured_at = ? WHERE place = ?").Bind(1, time).Bind(2, place.Id).Run();
                    return;
                }
            }
            if (compressed.Length == 0) Writing("DELETE FROM page_text WHERE place = ?").Bind(1, place.Id).Run();
            else Writing("INSERT OR REPLACE INTO page_text(place, captured_at, text) VALUES(?,?,?)").Bind(1, place.Id).Bind(2, time)
                    .Bind(3, compressed).Run();
            Index(place.Id, url, place.Title);
        });
    }

    /// Forgets the page text `space` keeps here, as turning off remembering
    /// it asks; titles and addresses stay searchable, and other Spaces keep theirs.
    public void ForgetText(Guid space) {
        string spaceId = Spelling(space);
        Enqueue(() => ForgetText(spaceId, long.MinValue, long.MaxValue));
    }

    /// Forgets captures in the removed range, including those belonging to a
    /// place whose earlier visits remain. Runs on the worker.
    private void ForgetText(string spaceId, long from, long until) {
        List<(long Id, string Url, string Title)> texted = [];
        Writing("SELECT p.id, p.url, p.title FROM place p JOIN page_text t ON t.place = p.id "
                + "WHERE p.space = ? AND t.captured_at >= ? AND t.captured_at < ?")
            .Bind(1, spaceId).Bind(2, from).Bind(3, until).Rows(row => texted.Add((row.Long(0), row.Text(1), row.Text(2))));
        foreach (var (id, url, title) in texted) {
            Writing("DELETE FROM page_text WHERE place = ?").Bind(1, id).Run();
            Index(id, url, title);
        }
    }

    /// Collapses white space within a bounded UTF-8 budget without splitting
    /// a Unicode scalar, preferring a word boundary in the latter half.
    internal static string Capped(string text) {
        var kept = new StringBuilder();
        int bytes = 0, boundary = 0, boundaryBytes = 0;
        bool space = false;
        foreach (var rune in text.EnumerateRunes()) {
            if (Rune.IsWhiteSpace(rune)) {
                space = kept.Length > 0;
                continue;
            }
            int needed = rune.Utf8SequenceLength + (space ? 1 : 0);
            if (bytes + needed > MaximumTextBytes) {
                if (!space && boundaryBytes > MaximumTextBytes / 2) kept.Length = boundary;
                break;
            }
            if (space) {
                (boundary, boundaryBytes) = (kept.Length, bytes);
                kept.Append(' ');
                bytes++;
                space = false;
            }
            kept.Append(rune.ToString());
            bytes += rune.Utf8SequenceLength;
        }
        return kept.ToString();
    }

    private static byte[] Compressed(string text) {
        using var buffer = new MemoryStream();
        using (var zlib = new System.IO.Compression.ZLibStream(buffer, System.IO.Compression.CompressionLevel.Optimal, leaveOpen: true))
            zlib.Write(System.Text.Encoding.UTF8.GetBytes(text));
        return buffer.ToArray();
    }

    /// The text `compressed` holds, or none when it does not read.
    private string Decompressed(byte[] compressed) {
        if (compressed.Length == 0) return "";
        try {
            using var zlib = new System.IO.Compression.ZLibStream(new MemoryStream(compressed), System.IO.Compression.CompressionMode.Decompress);
            using var reader = new StreamReader(zlib, Encoding.UTF8);
            var text = new char[MaximumTextBytes];
            int length = 0, read;
            while (length < text.Length && (read = reader.Read(text, length, text.Length - length)) > 0) length += read;
            if (length > 0 && char.IsHighSurrogate(text[length - 1])) length--;
            return Capped(new string(text, 0, length));
        } catch (InvalidDataException) {
            announce(new HistoryStorageFailed(HistoryStorageOperation.PageText, StorageFailure.Damaged, 0));
            return "";
        }
    }

    #endregion

    #region Actions - Search index

    /// Indexes the place's title, address and the page text it keeps,
    /// replacing what was indexed for it. Runs on the worker.
    private void Index(long place, string url, string title) {
        string text = Decompressed(Writing("SELECT text FROM page_text WHERE place = ?").Bind(1, place).First(row => row.Blob(0), []));
        Writing("DELETE FROM page_search WHERE rowid = ?").Bind(1, place).Run();
        Writing("INSERT INTO page_search(rowid, title, address, text) VALUES(?,?,?,?)").Bind(1, place).Bind(2, title)
            .Bind(3, Address(url)).Bind(4, text).Run();
    }

    #endregion

    #region Actions - Spelling

    /// A Space's identity as the store spells it.
    private static string Spelling(Guid id) => id.ToString("D").ToUpperInvariant();

    /// The site `url` belongs to, as the store groups and removes places by
    /// it: its host in lower case without a leading `www.`; a host alone is
    /// read as itself.
    internal static string Site(string url) {
        string host = Uri.TryCreate(url, UriKind.Absolute, out var parsed) && parsed.Host.Length > 0 ? parsed.Host : url;
        host = host.ToLowerInvariant();
        return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
    }

    /// The words of an address the search index reads: everything after its
    /// scheme.
    private static string Address(string url) {
        int scheme = url.IndexOf("://", StringComparison.Ordinal);
        return scheme < 0 ? url : url[(scheme + 3)..];
    }

    /// `text` with the characters `LIKE` reads as patterns escaped by a backslash.
    private static string Escaped(string text) => text.Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("%", "\\%", StringComparison.Ordinal).Replace("_", "\\_", StringComparison.Ordinal);

    #endregion
}

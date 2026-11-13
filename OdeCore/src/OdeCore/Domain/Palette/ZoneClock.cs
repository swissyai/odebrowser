using System.Globalization;
using System.Text.RegularExpressions;

namespace OdeCore.Domain;

/// The time a person asked about somewhere else, worked out on the device:
/// the time now in a place, as "time in tokyo" or "what time is it in
/// london" asks, or a time of day in one place as it falls in another, as
/// "3pm new york in tokyo" or "9:30 pst to cet" asks. Places are cities,
/// countries with one time zone and the abbreviations people use for them.
internal sealed partial class ZoneClock {
    #region Static Variables

    /// The longest text read as a question about time.
    private const int MaximumLength = 80;

    /// The places a person names, as they type them, and the time zone each
    /// keeps. A zone's own city, such as Tokyo for Asia/Tokyo, is here too.
    private static readonly Dictionary<string, (string Zone, string Place)> Places = Build(
        ("Pacific/Honolulu", "Honolulu", ["honolulu", "hawaii", "hst"]),
        ("America/Anchorage", "Anchorage", ["anchorage", "alaska", "akst"]),
        ("America/Los_Angeles", "Los Angeles", ["los angeles", "la", "san francisco", "sf", "seattle", "portland", "san diego",
            "las vegas", "vancouver", "california", "pacific", "pst", "pdt", "pt"]),
        ("America/Denver", "Denver", ["denver", "salt lake city", "calgary", "mountain", "mst", "mdt", "mt"]),
        ("America/Phoenix", "Phoenix", ["phoenix", "arizona"]),
        ("America/Chicago", "Chicago", ["chicago", "dallas", "houston", "austin", "minneapolis", "new orleans", "central", "cst", "cdt",
            "ct"]),
        ("America/New_York", "New York", ["new york", "nyc", "ny", "boston", "miami", "atlanta", "washington", "washington dc", "dc",
            "philadelphia", "detroit", "eastern", "est", "edt", "et"]),
        ("America/Toronto", "Toronto", ["toronto", "montreal", "ottawa"]),
        ("America/Mexico_City", "Mexico City", ["mexico city", "mexico"]),
        ("America/Bogota", "Bogotá", ["bogota", "bogotá", "colombia"]),
        ("America/Lima", "Lima", ["lima", "peru"]),
        ("America/Santiago", "Santiago", ["santiago", "chile"]),
        ("America/Argentina/Buenos_Aires", "Buenos Aires", ["buenos aires", "argentina"]),
        ("America/Sao_Paulo", "São Paulo", ["sao paulo", "são paulo", "rio", "rio de janeiro", "brazil", "brasil"]),
        ("Atlantic/Reykjavik", "Reykjavík", ["reykjavik", "reykjavík", "iceland"]),
        ("Europe/London", "London", ["london", "uk", "united kingdom", "england", "scotland", "edinburgh", "manchester", "gmt", "bst"]),
        ("Europe/Dublin", "Dublin", ["dublin", "ireland"]),
        ("Europe/Lisbon", "Lisbon", ["lisbon", "portugal", "porto"]),
        ("Europe/Madrid", "Madrid", ["madrid", "barcelona", "spain"]),
        ("Europe/Paris", "Paris", ["paris", "france", "lyon", "cet", "cest"]),
        ("Europe/Brussels", "Brussels", ["brussels", "belgium"]),
        ("Europe/Amsterdam", "Amsterdam", ["amsterdam", "netherlands", "holland"]),
        ("Europe/Berlin", "Berlin", ["berlin", "germany", "munich", "frankfurt", "hamburg"]),
        ("Europe/Zurich", "Zurich", ["zurich", "zürich", "geneva", "switzerland"]),
        ("Europe/Rome", "Rome", ["rome", "milan", "italy"]),
        ("Europe/Vienna", "Vienna", ["vienna", "austria"]),
        ("Europe/Copenhagen", "Copenhagen", ["copenhagen", "denmark"]),
        ("Europe/Oslo", "Oslo", ["oslo", "norway"]),
        ("Europe/Stockholm", "Stockholm", ["stockholm", "sweden"]),
        ("Europe/Warsaw", "Warsaw", ["warsaw", "poland"]),
        ("Europe/Prague", "Prague", ["prague", "czechia", "czech republic"]),
        ("Europe/Budapest", "Budapest", ["budapest", "hungary"]),
        ("Europe/Athens", "Athens", ["athens", "greece", "eet", "eest"]),
        ("Europe/Helsinki", "Helsinki", ["helsinki", "finland"]),
        ("Europe/Kyiv", "Kyiv", ["kyiv", "kiev", "ukraine"]),
        ("Europe/Istanbul", "Istanbul", ["istanbul", "ankara", "turkey", "türkiye"]),
        ("Europe/Moscow", "Moscow", ["moscow", "msk"]),
        ("Africa/Cairo", "Cairo", ["cairo", "egypt"]),
        ("Africa/Lagos", "Lagos", ["lagos", "nigeria"]),
        ("Africa/Nairobi", "Nairobi", ["nairobi", "kenya"]),
        ("Africa/Johannesburg", "Johannesburg", ["johannesburg", "cape town", "south africa"]),
        ("Asia/Jerusalem", "Jerusalem", ["jerusalem", "tel aviv", "israel"]),
        ("Asia/Riyadh", "Riyadh", ["riyadh", "saudi arabia"]),
        ("Asia/Dubai", "Dubai", ["dubai", "abu dhabi", "uae"]),
        ("Asia/Tehran", "Tehran", ["tehran", "iran"]),
        ("Asia/Karachi", "Karachi", ["karachi", "pakistan"]),
        ("Asia/Kolkata", "India", ["india", "delhi", "new delhi", "mumbai", "bangalore", "bengaluru", "kolkata", "chennai",
            "hyderabad", "ist"]),
        ("Asia/Kathmandu", "Kathmandu", ["kathmandu", "nepal"]),
        ("Asia/Dhaka", "Dhaka", ["dhaka", "bangladesh"]),
        ("Asia/Bangkok", "Bangkok", ["bangkok", "thailand"]),
        ("Asia/Ho_Chi_Minh", "Ho Chi Minh City", ["ho chi minh", "ho chi minh city", "saigon", "hanoi", "vietnam"]),
        ("Asia/Jakarta", "Jakarta", ["jakarta", "indonesia"]),
        ("Asia/Singapore", "Singapore", ["singapore", "sgt"]),
        ("Asia/Kuala_Lumpur", "Kuala Lumpur", ["kuala lumpur", "malaysia"]),
        ("Asia/Manila", "Manila", ["manila", "philippines"]),
        ("Asia/Hong_Kong", "Hong Kong", ["hong kong", "hk"]),
        ("Asia/Shanghai", "China", ["china", "beijing", "shanghai", "shenzhen", "guangzhou"]),
        ("Asia/Taipei", "Taipei", ["taipei", "taiwan"]),
        ("Asia/Seoul", "Seoul", ["seoul", "korea", "south korea", "kst"]),
        ("Asia/Tokyo", "Tokyo", ["tokyo", "osaka", "kyoto", "japan", "jst"]),
        ("Australia/Perth", "Perth", ["perth"]),
        ("Australia/Adelaide", "Adelaide", ["adelaide"]),
        ("Australia/Brisbane", "Brisbane", ["brisbane"]),
        ("Australia/Sydney", "Sydney", ["sydney", "canberra", "aest", "aedt"]),
        ("Australia/Melbourne", "Melbourne", ["melbourne"]),
        ("Pacific/Auckland", "Auckland", ["auckland", "wellington", "new zealand", "nz"]),
        ("Etc/UTC", "UTC", ["utc", "coordinated universal time", "zulu"]));

    #endregion

    #region Variables

    /// The moment the answer is about.
    public DateTimeOffset Instant { get; }

    /// The time zone the answer tells the time in, by its IANA name.
    public string Zone { get; }

    /// The place the answer tells the time in, as people know it.
    public string Place { get; }

    /// The zone and place the person gave a time of day in, or null when
    /// they asked for the time now.
    public string? FromZone { get; }
    public string? FromPlace { get; }

    /// How many minutes `Zone` is ahead of the zone it is compared with:
    /// `FromZone`, or this device's own; negative when it is behind.
    public int MinutesAhead { get; }

    /// How the answer compares the two zones, such as "14 hours ahead",
    /// "5 hours 30 minutes behind" or "Same time".
    public string Difference => MinutesAhead == 0 ? "Same time" : $"{Span(Math.Abs(MinutesAhead))} {(MinutesAhead > 0 ? "ahead" : "behind")}";

    #endregion

    #region Constructors

    private ZoneClock(DateTimeOffset instant, string zone, string place, string? fromZone, string? fromPlace, int minutesAhead) {
        Instant = instant;
        Zone = zone;
        Place = place;
        FromZone = fromZone;
        FromPlace = fromPlace;
        MinutesAhead = minutesAhead;
    }

    #endregion

    #region Actions - Reading

    /// What `typed` asks about time, at `now` on a device in `local`, or null
    /// when it asks nothing this reads or names a place it does not know.
    public static ZoneClock? Of(string typed, DateTimeOffset now, TimeZoneInfo local) {
        ArgumentNullException.ThrowIfNull(typed);
        ArgumentNullException.ThrowIfNull(local);
        string text = typed.Trim().ToLowerInvariant().TrimEnd('?').Trim();
        if (text.Length is 0 or > MaximumLength) return null;
        if (Now().Match(text) is { Success: true } asked) return Current(asked.Groups["place"].Value, now, local);
        if (Converting().Match(text) is { Success: true } converting) return Converted(converting, now, local);
        return null;
    }

    /// The time now in `name`.
    private static ZoneClock? Current(string name, DateTimeOffset now, TimeZoneInfo local) {
        if (Lookup(name) is not { } place || Named(place.Zone) is not { } zone) return null;
        int ahead = (int)Math.Round((zone.GetUtcOffset(now) - local.GetUtcOffset(now)).TotalMinutes);
        return new(now, place.Zone, place.Place, null, null, ahead);
    }

    /// A time of day in one place, today there, as it falls in another.
    private static ZoneClock? Converted(Match match, DateTimeOffset now, TimeZoneInfo local) {
        if (Lookup(match.Groups["from"].Value) is not { } from || Lookup(match.Groups["to"].Value) is not { } to
            || Named(from.Zone) is not { } fromZone || Named(to.Zone) is not { } toZone || from.Zone == to.Zone
            || TimeOfDay(match) is not { } time)
            return null;
        var today = TimeZoneInfo.ConvertTime(now, fromZone).Date;
        var wall = today + time;
        if (fromZone.IsInvalidTime(wall)) return null;
        var instant = new DateTimeOffset(wall, fromZone.GetUtcOffset(wall));
        int ahead = (int)Math.Round((toZone.GetUtcOffset(instant) - fromZone.GetUtcOffset(instant)).TotalMinutes);
        return new(instant, to.Zone, to.Place, from.Zone, from.Place, ahead);
    }

    /// The time of day a match names, as "3pm", "3:30 pm", "15:00", "noon"
    /// or "midnight", or null for one that is no time.
    private static TimeSpan? TimeOfDay(Match match) {
        string word = match.Groups["word"].Value;
        if (word == "noon") return TimeSpan.FromHours(12);
        if (word == "midnight") return TimeSpan.Zero;
        if (!int.TryParse(match.Groups["hour"].Value, CultureInfo.InvariantCulture, out int hour)) return null;
        int minute = match.Groups["minute"].Success ? int.Parse(match.Groups["minute"].Value, CultureInfo.InvariantCulture) : 0;
        string meridiem = match.Groups["meridiem"].Value.Replace(".", "", StringComparison.Ordinal);
        if (meridiem.Length > 0) {
            if (hour is < 1 or > 12) return null;
            hour = hour % 12 + (meridiem.StartsWith('p') ? 12 : 0);
        } else if (!match.Groups["minute"].Success) {
            return null;
        }
        return hour is >= 0 and < 24 && minute is >= 0 and < 60 ? new TimeSpan(hour, minute, 0) : null;
    }

    private static (string Zone, string Place)? Lookup(string name) {
        string trimmed = name.Trim();
        if (trimmed.EndsWith(" time", StringComparison.Ordinal)) trimmed = trimmed[..^" time".Length].TrimEnd();
        return Places.TryGetValue(trimmed, out var place) ? place : null;
    }

    private static TimeZoneInfo? Named(string id) {
        try {
            return TimeZoneInfo.FindSystemTimeZoneById(id);
        } catch (TimeZoneNotFoundException) {
            return null;
        } catch (InvalidTimeZoneException) {
            return null;
        }
    }

    /// `minutes` as hours and minutes, as "14 hours" or "5 hours 30 minutes".
    private static string Span(int minutes) {
        int hours = minutes / 60, rest = minutes % 60;
        string hourPart = hours == 1 ? "1 hour" : $"{hours} hours";
        string minutePart = rest == 1 ? "1 minute" : $"{rest} minutes";
        return hours == 0 ? minutePart : rest == 0 ? hourPart : $"{hourPart} {minutePart}";
    }

    private static Dictionary<string, (string Zone, string Place)> Build(params (string Zone, string Place, string[] Names)[] zones) {
        var places = new Dictionary<string, (string Zone, string Place)>(StringComparer.Ordinal);
        foreach (var (zone, place, names) in zones)
            foreach (string name in names) places.TryAdd(name, (zone, place));
        return places;
    }

    [GeneratedRegex(@"^(?:what\s+time\s+is\s+it\s+(?:in|at)\s+|what\s+is\s+the\s+time\s+in\s+|what's\s+the\s+time\s+in\s+|(?:current\s+|local\s+)?time\s+(?:in|at)\s+|time\s+)(?<place>[a-z .'áãéíóúüç]+)$|^(?<place>[a-z .'áãéíóúüç]+?)\s+(?:local\s+)?time(?:\s+now)?$",
        RegexOptions.CultureInvariant)]
    private static partial Regex Now();

    [GeneratedRegex(@"^(?:(?<word>noon|midnight)|(?<hour>\d{1,2})(?::(?<minute>\d{2}))?\s*(?<meridiem>a\.?m\.?|p\.?m\.?)?)\s+(?:in\s+)?(?<from>[a-z .'áãéíóúüç]+?)\s+(?:in|to|into)\s+(?<to>[a-z .'áãéíóúüç]+?)$",
        RegexOptions.CultureInvariant)]
    private static partial Regex Converting();

    #endregion
}

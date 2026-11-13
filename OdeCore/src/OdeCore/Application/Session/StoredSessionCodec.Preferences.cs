using System.Text.Json;
using System.Text.Json.Nodes;

using OdeCore.Contracts;
using OdeCore.Domain;

namespace OdeCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    /// What a Space that stored no browsing preferences searches and keeps.
    internal static BrowsingPreferences DefaultBrowsingPreferences { get; } = new(BuiltInSearchProvider.Google, null, [], false,
        FollowsDefaultSearch: true, FollowsDefaultSuggestions: true, CurrentTabCleanup.After12Hours, ContentBlockingPolicy.Balanced,
        new(DataRetention.Forever, DataRetention.Forever, DataRetention.Forever));

    /// What a Space that stored no credential preferences offers.
    internal static CredentialPreferences DefaultCredentialPreferences { get; } = new(true, true, false);

    #endregion

    #region Actions - Browsing preferences

    /// A Space's browsing preferences. The selection falls back to the legacy
    /// provider member, a custom engine without a readable identity is left out,
    /// a Space an older release stored searches and suggests as it chose rather
    /// than following the default, a missing cleanup policy is twelve hours and
    /// an unknown one never cleans.
    internal static BrowsingPreferences DecodeBrowsingPreferences(JsonNode? node) {
        var value = Object(node);
        var retention = value[Key.DataRetention] as JsonObject;
        DataRetention Kept(string key) => DataRetention.Named(TolerantText(retention?[key])) ?? DataRetention.Forever;
        var cleanup = value[Key.CurrentTabCleanupPolicy] is { } stored
            ? CurrentTabCleanup.Named(TolerantText(stored)) ?? CurrentTabCleanup.Never : CurrentTabCleanup.After12Hours;
        var (builtIn, custom) = SearchSelection(TolerantText(value[Key.SelectedSearchProviderId])
            ?? TolerantText(value[Key.LegacySearchProvider]));
        return new(builtIn, custom,
            [.. Items(value[Key.CustomSearchProviders]).OfType<JsonObject>().Select(CustomSearchProvider).OfType<CustomSearchProvider>()],
            TolerantFlag(value[Key.SearchSuggestionsEnabled]) ?? false, TolerantFlag(value[Key.SearchFollowsDefault]) ?? false,
            TolerantFlag(value[Key.SuggestionsFollowDefault]) ?? false, cleanup,
            ContentBlockingPolicy.Named(TolerantText(value[Key.ContentBlockingPolicy])) ?? ContentBlockingPolicy.Balanced,
            new(Kept(Key.History), Kept(Key.Archive), Kept(Key.Downloads)));
    }

    /// The engine a stored selection names: a built-in's spelling, or `custom:`
    /// and a custom engine's identity. One this build cannot read selects Google.
    internal static (BuiltInSearchProvider? BuiltIn, Guid? Custom) SearchSelection(string? spelling) =>
        spelling is not null && spelling.StartsWith(SearchProvider.CustomPrefix, StringComparison.Ordinal)
            && Guid.TryParseExact(spelling[SearchProvider.CustomPrefix.Length..], "D", out var custom)
            ? (null, custom) : (BuiltInSearchProvider.Named(spelling) ?? BuiltInSearchProvider.Google, null);

    /// A selection in its stored spelling.
    internal static string SearchSelection(BrowsingPreferences preferences) =>
        preferences.SelectedCustomEngineId is { } custom ? SearchProvider.CustomName(custom)
            : (preferences.SelectedBuiltInEngine ?? BuiltInSearchProvider.Google).Name;

    /// Older builds read only the legacy provider member, so a custom selection
    /// keeps Google there as their safe fallback. Following the default is
    /// written only where a Space follows it.
    internal static JsonObject Encode(BrowsingPreferences preferences) {
        var encoded = EncodeSelection(preferences);
        if (preferences.FollowsDefaultSearch) encoded[Key.SearchFollowsDefault] = true;
        if (preferences.FollowsDefaultSuggestions) encoded[Key.SuggestionsFollowDefault] = true;
        return encoded;
    }

    private static JsonObject EncodeSelection(BrowsingPreferences preferences) => new() {
        [Key.LegacySearchProvider] = preferences.SelectedCustomEngineId is null
            ? (preferences.SelectedBuiltInEngine ?? BuiltInSearchProvider.Google).Name : BuiltInSearchProvider.Google.Name,
        [Key.SelectedSearchProviderId] = SearchSelection(preferences),
        [Key.CustomSearchProviders] = new JsonArray(preferences.CustomSearchProviders.Select(provider => {
            var value = new JsonObject {
                [Key.Id] = BareIdentity(provider.Id),
                [Key.Name] = provider.Name,
                [Key.SearchUrlTemplate] = provider.SearchUrlTemplate
            };
            Put(value, Key.SuggestionUrlTemplate, provider.SuggestionUrlTemplate);
            return (JsonNode?)value;
        }).ToArray()),
        [Key.SearchSuggestionsEnabled] = preferences.SearchSuggestionsEnabled,
        [Key.CurrentTabCleanupPolicy] = preferences.CurrentTabCleanup.Name,
        [Key.ContentBlockingPolicy] = preferences.ContentBlocking.Name,
        [Key.DataRetention] = new JsonObject {
            [Key.History] = preferences.DataRetention.History.Name,
            [Key.Archive] = preferences.DataRetention.Archive.Name,
            [Key.Downloads] = preferences.DataRetention.Downloads.Name
        }
    };

    private static CustomSearchProvider? CustomSearchProvider(JsonObject value) =>
        Guid.TryParse(TolerantText(value[Key.Id]), out var id)
            ? Contracts.CustomSearchProvider.Carried(id, TolerantText(value[Key.Name]) ?? "", TolerantText(value[Key.SearchUrlTemplate]) ?? "",
                TolerantText(value[Key.SuggestionUrlTemplate]))
            : null;

    #endregion

    #region Actions - Credential preferences

    internal static CredentialPreferences DecodeCredentialPreferences(JsonNode? node) {
        var value = Object(node);
        return new(Flag(value[Key.IsEnabled]) ?? DefaultCredentialPreferences.IsEnabled,
            Flag(value[Key.SyncsOdePasswordsWithICloud]) ?? DefaultCredentialPreferences.SyncsOdePasswordsWithICloud,
            Flag(value[Key.AlsoOffersSaveToSystemPasswords]) ?? DefaultCredentialPreferences.AlsoOffersSaveToSystemPasswords);
    }

    internal static JsonObject Encode(CredentialPreferences preferences) => new() {
        [Key.IsEnabled] = preferences.IsEnabled,
        [Key.SyncsOdePasswordsWithICloud] = preferences.SyncsOdePasswordsWithICloud,
        [Key.AlsoOffersSaveToSystemPasswords] = preferences.AlsoOffersSaveToSystemPasswords
    };

    #endregion

    #region Actions - App preferences

    /// The app-wide preferences. A value this build cannot read keeps its default,
    /// and translation rules that no longer validate read as none, which never
    /// translates.
    internal static AppPreferences DecodeAppPreferences(JsonNode? node) {
        var value = Object(node);
        var defaults = AppPreferences.Default;
        return new(StartupBehavior.Named(TolerantText(value[Key.StartupBehavior])) ?? defaults.Startup,
            TolerantFlag(value[Key.OffersTranslation]) ?? defaults.OffersTranslation,
            TolerantFlag(value[Key.AutomaticallyTranslates]) ?? defaults.AutomaticallyTranslates,
            TranslationRules(value[Key.TranslationRules]),
            TolerantFlag(value[Key.ChecksSpelling]) ?? defaults.ChecksSpelling,
            TolerantFlag(value[Key.AutomaticallyEntersPictureInPicture]) ?? defaults.AutomaticallyEntersPictureInPicture,
            SavedTabClosePolicy.Named(TolerantText(value[Key.SavedTabClosePolicy])) ?? defaults.SavedTabClose,
            TolerantFlag(value[Key.SavedTabFaviconReturnsToSavedUrl]) ?? defaults.SavedTabFaviconReturnsToSavedUrl,
            TolerantFlag(value[Key.SplitFocusFollowsMouse]) ?? defaults.SplitFocusFollowsMouse,
            TolerantFlag(value[Key.AutomaticallyShowsDeveloperToolbar]) ?? defaults.AutomaticallyShowsDeveloperToolbar,
            TolerantFlag(value[Key.ShowsRecentTabs]) ?? defaults.ShowsRecentTabs,
            DecodePalettePreferences(value[Key.Palette]), DecodeTabPreviewPreferences(value[Key.TabPreviews]),
            TolerantFlag(value[Key.NestsTabsOpenedFromPages]) ?? defaults.NestsTabsOpenedFromPages,
            DecodeFocusPreferences(value[Key.Focus]));
    }

    /// The app-wide preferences. The palette's, the previews' and nesting are
    /// written only once they differ from the defaults, so a release that never
    /// stored them reads its own document back unchanged.
    internal static JsonObject Encode(AppPreferences preferences) {
        var value = new JsonObject {
            [Key.StartupBehavior] = preferences.Startup.Name,
            [Key.OffersTranslation] = preferences.OffersTranslation,
            [Key.AutomaticallyTranslates] = preferences.AutomaticallyTranslates,
            [Key.TranslationRules] = EncodeTranslationRules(preferences.TranslationRules),
            [Key.ChecksSpelling] = preferences.ChecksSpelling,
            [Key.AutomaticallyEntersPictureInPicture] = preferences.AutomaticallyEntersPictureInPicture,
            [Key.SavedTabClosePolicy] = preferences.SavedTabClose.Name,
            [Key.SavedTabFaviconReturnsToSavedUrl] = preferences.SavedTabFaviconReturnsToSavedUrl,
            [Key.SplitFocusFollowsMouse] = preferences.SplitFocusFollowsMouse,
            [Key.AutomaticallyShowsDeveloperToolbar] = preferences.AutomaticallyShowsDeveloperToolbar,
            [Key.ShowsRecentTabs] = preferences.ShowsRecentTabs
        };
        if (!preferences.Palette.Equals(PalettePreferences.Default)) value[Key.Palette] = Encode(preferences.Palette);
        if (!preferences.TabPreviews.Equals(TabPreviewPreferences.Default)) value[Key.TabPreviews] = Encode(preferences.TabPreviews);
        if (preferences.NestsTabsOpenedFromPages) value[Key.NestsTabsOpenedFromPages] = true;
        if (preferences.Focus is { } focus && !focus.Equals(FocusPreferences.Default)) value[Key.Focus] = Encode(focus);
        return value;
    }

    /// The Focus preferences, or null for a document that holds none. A value
    /// this build cannot read keeps its default, and a limit without a site or
    /// whole minutes is left out.
    internal static FocusPreferences? DecodeFocusPreferences(JsonNode? node) {
        if (node is not JsonObject value) return null;
        List<SiteTimeLimit> limits = [];
        foreach (var item in (value[Key.Limits] as JsonArray ?? []).OfType<JsonObject>())
            if (TolerantText(item[Key.Site]) is { } site && item[Key.MinutesPerDay] is JsonValue minutes
                && minutes.TryGetValue<int>(out int perDay))
                limits.Add(new(site, perDay));
        return new FocusPreferences(TolerantFlag(value[Key.HidesFeeds]) ?? FocusPreferences.Default.HidesFeeds, limits).Restored();
    }

    internal static JsonObject Encode(FocusPreferences preferences) => new() {
        [Key.HidesFeeds] = preferences.HidesFeeds,
        [Key.Limits] = new JsonArray([.. preferences.Limits.Select(limit => (JsonNode)new JsonObject {
            [Key.Site] = limit.Site,
            [Key.MinutesPerDay] = limit.MinutesPerDay
        })])
    };

    /// The tab preview preferences. A value this build cannot read keeps its
    /// default, and a site that is not text, or spells no site, is left out.
    internal static TabPreviewPreferences DecodeTabPreviewPreferences(JsonNode? node) {
        var value = node as JsonObject ?? [];
        return new TabPreviewPreferences(TolerantFlag(value[Key.ShowsPreviews]) ?? TabPreviewPreferences.Default.ShowsPreviews,
            [.. (value[Key.SitesWithoutPreviews] as JsonArray ?? []).Select(TolerantText).OfType<string>()]).Restored();
    }

    internal static JsonObject Encode(TabPreviewPreferences preferences) => new() {
        [Key.ShowsPreviews] = preferences.ShowsPreviews,
        [Key.SitesWithoutPreviews] = new JsonArray([.. preferences.SitesWithoutPreviews.Select(site => (JsonNode?)site)])
    };

    /// The palette preferences. A value this build cannot read keeps its
    /// default, a kind of result it cannot name is left out, and a number of
    /// rows it cannot read is the kind's own. A record from before the Space
    /// trigger existed keeps the Space entry its Tab setting gave it.
    internal static PalettePreferences DecodePalettePreferences(JsonNode? node) {
        var value = node as JsonObject ?? [];
        var defaults = PalettePreferences.Default;
        bool Flag(string key, bool fallback) => TolerantFlag(value[key]) ?? fallback;
        List<PaletteSourceChoice> sources = [];
        foreach (var item in (value[Key.Sources] as JsonArray ?? []).OfType<JsonObject>())
            if (DecodePaletteSourceChoice(item) is { } choice) sources.Add(choice);
        return new PalettePreferences(PaletteLayout.Named(TolerantText(value[Key.Layout])) ?? defaults.Layout, sources,
            Flag(Key.ShowsTopHit, defaults.ShowsTopHit), Flag(Key.PrefersOpenTabs, defaults.PrefersOpenTabs),
            Flag(Key.CompletesInline, defaults.CompletesInline), Flag(Key.LearnsChoices, defaults.LearnsChoices),
            Flag(Key.SearchesSitesWithTab, defaults.SearchesSitesWithTab), Flag(Key.ShowsReasons, defaults.ShowsReasons),
            DecodeProviderSpaceTrigger(value, defaults)).Restored();
    }

    /// One kind of result and its choices, or null for a kind this build cannot name.
    private static PaletteSourceChoice? DecodePaletteSourceChoice(JsonObject item) =>
        PaletteSource.Named(TolerantText(item[Key.Source])) is { } source
            ? new(source, TolerantFlag(item[Key.IsEnabled]) ?? source.IsEnabledByDefault,
                item[Key.Limit] is JsonValue limit && limit.TryGetValue<int>(out int rows) ? rows : null)
            : null;

    /// The stored Space trigger; a record from before it existed takes the
    /// one its Tab setting gave it.
    private static SearchProviderSpaceTrigger DecodeProviderSpaceTrigger(JsonObject value, PalettePreferences defaults) {
        if (value.ContainsKey(Key.ProviderSpaceTrigger))
            return SearchProviderSpaceTrigger.Named(TolerantText(value[Key.ProviderSpaceTrigger])) ?? defaults.ProviderSpaceTrigger;
        return (TolerantFlag(value[Key.SearchesSitesWithTab]) ?? defaults.SearchesSitesWithTab)
            ? SearchProviderSpaceTrigger.PrefixedShortcut : SearchProviderSpaceTrigger.Off;
    }

    private static JsonNode Encode(PaletteSourceChoice choice) {
        var value = new JsonObject { [Key.Source] = choice.Source.Name, [Key.IsEnabled] = choice.IsEnabled };
        if (choice.Limit is { } limit) value[Key.Limit] = limit;
        return value;
    }

    internal static JsonObject Encode(PalettePreferences preferences) => new() {
        [Key.Layout] = preferences.Layout.Name,
        [Key.Sources] = new JsonArray([.. preferences.Sources.Select(Encode)]),
        [Key.ShowsTopHit] = preferences.ShowsTopHit,
        [Key.PrefersOpenTabs] = preferences.PrefersOpenTabs,
        [Key.CompletesInline] = preferences.CompletesInline,
        [Key.LearnsChoices] = preferences.LearnsChoices,
        [Key.SearchesSitesWithTab] = preferences.SearchesSitesWithTab,
        [Key.ProviderSpaceTrigger] = preferences.ProviderSpaceTrigger.Name,
        [Key.ShowsReasons] = preferences.ShowsReasons
    };

    /// The values the native settings stored before the core owned them, each
    /// under its stored name and null when never saved. Translation rules arrive
    /// as the raw JSON text the native setting stored. A value this build cannot
    /// read keeps its default rather than failing the whole import.
    /// The preferences an older release's settings stored, read as the stored
    /// record is: each value saved in its stored spelling, anything missing
    /// or unreadable the default.
    internal static AppPreferences ImportAppPreferences(LegacyAppPreferences legacy) {
        ArgumentNullException.ThrowIfNull(legacy);
        var stored = new JsonObject();
        Put(stored, Key.StartupBehavior, legacy.StartupBehavior);
        Put(stored, Key.OffersTranslation, legacy.OffersTranslation);
        Put(stored, Key.AutomaticallyTranslates, legacy.AutomaticallyTranslates);
        stored[Key.TranslationRules] = RawTranslationRules(legacy.TranslationRules);
        Put(stored, Key.ChecksSpelling, legacy.ChecksSpelling);
        Put(stored, Key.AutomaticallyEntersPictureInPicture, legacy.AutomaticallyEntersPictureInPicture);
        Put(stored, Key.SavedTabClosePolicy, legacy.SavedTabClosePolicy);
        Put(stored, Key.SavedTabFaviconReturnsToSavedUrl, legacy.SavedTabFaviconReturnsToSavedUrl);
        Put(stored, Key.SplitFocusFollowsMouse, legacy.SplitFocusFollowsMouse);
        return DecodeAppPreferences(stored);
    }

    private static JsonNode? RawTranslationRules(string? text) {
        if (text is null) return null;
        try {
            return JsonNode.Parse(text, documentOptions: new() { MaxDepth = 8 });
        } catch (JsonException) {
            return null;
        }
    }

    /// Rules in their stored shape, `{"sources":{"es":{"targetID":"en","isEnabled":true}}}`.
    internal static IReadOnlyList<TranslationRule> TranslationRules(JsonNode? value) {
        if (value?[Key.Sources] is not JsonObject sources) return AutomaticTranslationRules.Empty.Rules;
        try {
            return AutomaticTranslationRules.Restore(sources.Select(member => new TranslationRule(member.Key,
                TolerantText(member.Value?[Key.TargetId]) ?? "", TolerantFlag(member.Value?[Key.IsEnabled]) ?? false))).Rules;
        } catch (Rejected) {
            return AutomaticTranslationRules.Empty.Rules;
        }
    }

    private static JsonObject EncodeTranslationRules(IReadOnlyList<TranslationRule> rules) {
        var sources = new JsonObject();
        foreach (var rule in rules)
            sources[rule.SourceLanguage] = new JsonObject { [Key.TargetId] = rule.TargetId, [Key.IsEnabled] = rule.IsEnabled };
        return new() { [Key.Sources] = sources };
    }

    /// A startup or saved-tab close choice in its stored spelling, which settings
    /// commands and the launch plan also use; null when this build cannot name it.
    internal static StartupBehavior? ParseStartupBehavior(JsonNode? node) => StartupBehavior.Named(TolerantText(node));

    internal static SavedTabClosePolicy? ParseSavedTabClosePolicy(JsonNode? node) => SavedTabClosePolicy.Named(TolerantText(node));

    #endregion
}

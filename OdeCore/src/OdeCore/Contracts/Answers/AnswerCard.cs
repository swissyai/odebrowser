namespace OdeCore.Contracts;

#region Types

/// What an answer's "Do it" runs, exactly one of: a command; a settings page
/// by the name the platform's settings give it; a page of the current Space's
/// settings by its name; or an action of the platform's application menus by
/// its name, such as restoring an earlier copy.
public sealed record AnswerAction(ShortcutCommand? Command, string? SettingsPage, string? SpacePage, string? ApplicationAction);

#endregion

/// A written answer to a question about Ode, which the palette shows above
/// its results: its stable `Id`, what it is, its title in a person's words,
/// one to three steps, the default keys in Mac symbols, an optional caveat,
/// what "Do it" runs, if anything, and the address of the guide section that
/// explains the same thing. Answers are written and checked by hand; nothing
/// composes or rewrites their text.
public sealed record AnswerCard(string Id, AnswerKind Kind, string Title, IReadOnlyList<string> Steps, string? Keys, string? Note,
    AnswerAction? Action, string Guide) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<string> Steps {
        get;
        init => field = [.. value];
    } = [.. Steps];

    #endregion

    #region Actions - Equality

    public bool Equals(AnswerCard? other) => other is not null
        && Id == other.Id
        && Kind == other.Kind
        && Title == other.Title
        && Steps.SequenceEqual(other.Steps)
        && Keys == other.Keys
        && Note == other.Note
        && Action == other.Action
        && Guide == other.Guide;

    public override int GetHashCode() => HashCode.Combine(Id, Kind, Title, Steps.Count);

    #endregion
}

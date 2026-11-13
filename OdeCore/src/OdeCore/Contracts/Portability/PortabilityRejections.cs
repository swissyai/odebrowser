namespace OdeCore.Contracts;

#region Archives

/// The Ode browser-data file holds something Ode would not keep. Nothing was imported.
public sealed record ArchiveInvalid : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This file does not contain valid Ode browser data.";

    #endregion
}

/// The Ode browser-data file is larger than an import reads. Nothing was imported.
public sealed record ArchiveTooLarge : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This file is larger than Ode’s 50 MB import limit.";

    #endregion
}

/// The file is not Ode browser data. Nothing was imported.
public sealed record NotAnArchive : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This is not an Ode browser-data file.";

    #endregion
}

/// The Ode browser-data file is of `Version`, a format this build cannot read.
public sealed record UnsupportedArchiveVersion(int Version) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Version))]
    public string Message => "This Ode browser-data version (%lld) is not supported.";

    #endregion
}

#endregion

#region Bookmarks

/// The browser's bookmarks hold no web page Ode can open. Nothing was imported.
public sealed record BookmarksHaveNoLinks : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This file does not contain any HTTP or HTTPS bookmarks Ode can import.";

    #endregion
}

/// The browser's bookmarks hold more folders, nesting, tabs or Spaces than Ode keeps. Nothing was imported.
public sealed record BookmarksOverLimits : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This bookmark file exceeds Ode’s folder, depth, tab, or Space limits.";

    #endregion
}

/// The browser's bookmark file is larger than an import reads. Nothing was imported.
public sealed record BookmarksTooLarge : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This bookmark file is larger than Ode’s 50 MB import limit.";

    #endregion
}

/// The browser's bookmark file holds nothing Ode recognizes as bookmarks. Nothing was imported.
public sealed record BookmarksUnrecognized : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Ode could not recognize this browser’s bookmark data.";

    #endregion
}

#endregion

#region Files

/// The file could not be read. Nothing was imported.
public sealed record FileUnreadable : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Ode could not read this file.";

    #endregion
}

/// The export folder could not be created or written. Nothing was exported,
/// and the exports already there were kept.
public sealed record ExportFolderUnwritable : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Ode could not write to the export folder.";

    #endregion
}

#endregion

#region History

/// At least one further valid address could not fit. Read data is retained.
public sealed record HistoryAddressesOverLimit : Rejection {
    #region Variables

    [Localized]
    public string Message => "Some history was left out: the profile exceeds the 500,000-address import limit.";

    #endregion
}

/// At least one further visit time could not fit. Read data is retained.
public sealed record HistoryVisitsOverLimit : Rejection {
    #region Variables

    [Localized]
    public string Message => "Some visit times were left out: the profile exceeds the 4,000,000-visit import limit.";

    #endregion
}

/// Copying, opening, preparing or stepping the history database failed.
public sealed record HistoryReadFailed : Rejection {
    #region Variables

    [Localized]
    public string Message => "Some history could not be read. Successfully read history is still included.";

    #endregion
}

/// Unsupported or invalid addresses are distinct from capacity/read failures.
public sealed record HistoryAddressesUnsupported(int Count) : Rejection {
    #region Variables

    [Localized(Argument = nameof(Count))]
    public string Message => "%lld history addresses were not valid HTTP or HTTPS addresses.";

    #endregion
}

#endregion

#region Sessions

/// The Chromium session is encrypted with its profile's key, which only that browser holds. Nothing was imported.
public sealed record SessionEncrypted : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This Chromium session is profile-encrypted and cannot be safely imported outside its source browser.";

    #endregion
}

/// The browser's session holds no web page Ode can open. Nothing was imported.
public sealed record SessionHasNoTabs : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This session has no HTTP or HTTPS tabs Ode can import.";

    #endregion
}

/// The browser's session holds more Spaces, tabs, folders or text than a Space keeps. Nothing was imported.
public sealed record SessionOverLimits : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This session exceeds Ode’s Space, tab, folder, or text limits.";

    #endregion
}

/// The browser's session file is larger than an import reads. Nothing was imported.
public sealed record SessionTooLarge : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This session file is larger than Ode’s 512 MB import limit.";

    #endregion
}

/// The import read was canceled, exhausted, or belongs to a closed core.
public sealed record ImportReadUnavailable : Rejection {
    #region Variables

    [Localized]
    public string Message => "This import review is no longer available. Read the browser data again.";

    #endregion
}

/// No accepted import read is evicted to admit another one.
public sealed record ImportReadLimitReached : Rejection {
    #region Variables

    [Localized]
    public string Message => "Ode cannot hold more import data for review. Finish or cancel pending imports, or select fewer profiles.";

    #endregion
}

/// The browser's session file holds nothing Ode recognizes as its tabs. Nothing was imported.
public sealed record SessionUnrecognized : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Ode could not recognize this browser’s tab-session data.";

    #endregion
}

#endregion

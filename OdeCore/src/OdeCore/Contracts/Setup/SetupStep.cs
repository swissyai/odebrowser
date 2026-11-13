namespace OdeCore.Contracts;

/// A step of setup: what the person sees, where Back and Next lead from it,
/// and how far along setup it is. Back from a step the entry did not pass
/// through closes setup instead. A step travels as its index in `All`, so
/// `All` is append-only.
public sealed class SetupStep {
    #region Types

    /// Each platform shows a step with its own page, so the one place that
    /// builds a step's page switches over the kind.
    public enum Kinds { Welcome, FeatureSpaces, FeatureTabs, FeatureSync, ImportBrowser, Review, ManualSetup, Complete, Look, Layout, Practice }

    #endregion

    #region Static Variables

    /// Where setup opens for a person new to Ode, or who asked to see it again.
    public static readonly SetupStep Welcome = new(Kinds.Welcome, name: "welcome", progressPosition: 0,
        next: (platform, _) => platform.OffersSetupPractice ? Layout : platform.ChoosesLook ? Look : platform.ImportsBrowsers ? ImportBrowser : ManualSetup,
        back: (_, _) => null);
    /// The tour of Spaces, tabs and sync, one page each.
    public static readonly SetupStep FeatureSpaces = new(Kinds.FeatureSpaces, name: "featureSpaces", progressPosition: 0,
        next: (_, _) => FeatureTabs, back: (_, _) => null);
    public static readonly SetupStep FeatureTabs = new(Kinds.FeatureTabs, name: "featureTabs", progressPosition: 0,
        next: (_, _) => FeatureSync, back: (_, _) => null);
    public static readonly SetupStep FeatureSync = new(Kinds.FeatureSync, name: "featureSync", progressPosition: 0,
        next: (_, _) => ManualSetup, back: (_, _) => null);
    /// Choosing the browsers to import from, and reading them.
    public static readonly SetupStep ImportBrowser = new(Kinds.ImportBrowser, name: "importBrowser", progressPosition: 1,
        next: (_, _) => null, back: (entry, platform) => !entry.IsGuided ? null : platform.OffersSetupPractice ? Layout : platform.ChoosesLook ? Look : Welcome);
    /// Reviewing what one browser brings, and importing it.
    public static readonly SetupStep Review = new(Kinds.Review, name: "review", progressPosition: 2, next: (_, _) => null,
        back: (_, _) => ImportBrowser);
    /// Setting up Spaces by hand.
    public static readonly SetupStep ManualSetup = new(Kinds.ManualSetup, name: "manualSetup", progressPosition: 3,
        next: (platform, entry) => platform.OffersSetupPractice && entry.IsGuided ? Practice : Complete,
        back: (entry, platform) => !entry.IsGuided ? null
            : platform.ImportsBrowsers ? ImportBrowser
            : platform.ChoosesLook ? Look
            : Welcome);
    /// What setup is about to do, or did, before Ode opens. Setup that
    /// walks the person through Ode reaches it from the manual setup, which
    /// finishing then applies, and Back returns there.
    public static readonly SetupStep Complete = new(Kinds.Complete, name: "complete", progressPosition: 4, next: (_, _) => null,
        back: (entry, _) => entry.IsGuided ? ManualSetup : null);
    /// Choosing the look the Spaces setup makes wear, on a platform that offers it.
    /// No platform offers it: every Space wears the modern look. It keeps its
    /// place in `All`, which is append-only.
    public static readonly SetupStep Look = new(Kinds.Look, name: "look", progressPosition: 1,
        next: (platform, _) => platform.ImportsBrowsers ? ImportBrowser : ManualSetup, back: (_, _) => Welcome);

    /// Previewing a layout changes no preferences until the person confirms it.
    public static readonly SetupStep Layout = new(Kinds.Layout, name: "layout", progressPosition: 1,
        next: (_, _) => ImportBrowser, back: (_, _) => Welcome);
    /// Optional real controls in a disposable workspace. No attempts or results are kept.
    public static readonly SetupStep Practice = new(Kinds.Practice, name: "practice", progressPosition: 4,
        next: (_, _) => null, back: (_, _) => ManualSetup);

    public static IReadOnlyList<SetupStep> All { get; } =
        [Welcome, FeatureSpaces, FeatureTabs, FeatureSync, ImportBrowser, Review, ManualSetup, Complete, Look, Layout, Practice];

    #endregion

    #region Variables

    public Kinds Kind { get; }

    public string Name { get; }

    /// How far along setup the step stands, counting from zero, of `ProgressCount`.
    public int ProgressPosition { get; }

    /// How many positions setup walks through on a platform that offers every step.
    public const int ProgressCount = 5;

    /// Whether finishing setup from this step applies the manual setup the
    /// device holds: from the manual setup itself, or the page after it.
    internal bool AppliesManualSetup => Kind is Kinds.ManualSetup or Kinds.Complete or Kinds.Practice;

    private readonly Func<DevicePlatform, SetupEntry, SetupStep?> next;
    private readonly Func<SetupEntry, DevicePlatform, SetupStep?> back;

    #endregion

    #region Constructors

    private SetupStep(Kinds kind, string name, int progressPosition, Func<DevicePlatform, SetupEntry, SetupStep?> next,
        Func<SetupEntry, DevicePlatform, SetupStep?> back) {
        Kind = kind;
        Name = name;
        ProgressPosition = progressPosition;
        this.next = next;
        this.back = back;
    }

    #endregion

    #region Actions - Lookup

    public static SetupStep? Named(string? name) => All.FirstOrDefault(step => step.Name == name);

    #endregion

    #region Actions - Navigation

    /// The step Continue leads to on `platform`, or null when something the
    /// step does decides it.
    public SetupStep? Next(DevicePlatform platform, SetupEntry entry) {
        ArgumentNullException.ThrowIfNull(platform);
        ArgumentNullException.ThrowIfNull(entry);
        return next(platform, entry);
    }

    /// The step Back leads to for a setup `entry` opened on `platform`, or
    /// null when Back closes setup.
    public SetupStep? Back(SetupEntry entry, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(entry);
        ArgumentNullException.ThrowIfNull(platform);
        return back(entry, platform);
    }

    #endregion
}

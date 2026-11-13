namespace OdeCore.Contracts;

/// What a written answer is: the steps of a task, an explanation of how
/// something behaves, or a plain statement that Ode does not have something,
/// with what comes closest. A task's steps read as a numbered procedure; the
/// others' read as one paragraph. A kind travels as its index in `All`, so
/// `All` is append-only.
public sealed class AnswerKind {
    #region Static Variables

    public static readonly AnswerKind Task = new(name: "task", numbersSteps: true);
    public static readonly AnswerKind Explain = new(name: "explain", numbersSteps: false);
    public static readonly AnswerKind Missing = new(name: "missing", numbersSteps: false);

    public static IReadOnlyList<AnswerKind> All { get; } = [Task, Explain, Missing];

    #endregion

    #region Variables

    /// How the answers file spells the kind.
    public string Name { get; }

    /// The steps are a procedure, read in order and numbered.
    public bool NumbersSteps { get; }

    #endregion

    #region Constructors

    private AnswerKind(string name, bool numbersSteps) {
        Name = name;
        NumbersSteps = numbersSteps;
    }

    #endregion

    #region Actions - Lookup

    public static AnswerKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}

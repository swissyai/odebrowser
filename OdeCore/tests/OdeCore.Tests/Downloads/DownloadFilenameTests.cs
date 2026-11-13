using OdeCore.Application;
using OdeCore.Contracts;
using OdeCore.Domain;

using Xunit;

namespace OdeCore.Tests;

/// The name a download is saved and shown under, for a fixed set of names an
/// engine or a page may suggest, as the core's rule and the query the platform
/// asks answer it. The platform's tests pin the same table through the query.
public sealed class DownloadFilenameTests {
    public static TheoryData<string, string> Names => new() {
        { "report.pdf", "report.pdf" },
        { "..\\..\\.pay\0load.txt. ", "payload.txt" },
        { "../..", "download" },
        { "", "download" },
        { "folder/in\u202Eexe.pdf", "inexe.pdf" },
        { "C:\\Users\\someone\\file.txt", "file.txt" },
        { "a:b.txt", "a_b.txt" },
        { "  .hidden. ", "hidden" },
        { "e\u0301te\u0301.txt", "\u00E9t\u00E9.txt" },
        { "invoice.pdf\u202Eppa", "invoice.pdfppa" },
        { "\uFEFF\u200B", "download" },
        { "tab\there\u0085.txt", "tabhere.txt" },
        { "\u00A0name\u00A0.txt\u00A0", "name\u00A0.txt" },
        { "archive.tar.gz", "archive.tar.gz" },
        { new string('a', 300) + ".txt", new string('a', 236) + ".txt" },
        { string.Concat(Enumerable.Repeat("\u00E9", 200)) + ".pdf", string.Concat(Enumerable.Repeat("\u00E9", 118)) + ".pdf" },
        { new string('a', 250) + "." + new string('b', 40), new string('a', 240) },
        { string.Concat(Enumerable.Repeat("\U0001F468\u200D\U0001F469", 40)) + ".png",
            string.Concat(Enumerable.Repeat("\U0001F468\U0001F469", 29)) + "\U0001F468.png" },
    };

    [Theory]
    [MemberData(nameof(Names))]
    public void ASuggestedNameIsSavedUnderItsSafeName(string suggested, string expected) {
        Assert.Equal(expected, DownloadFilename.Safe(suggested));
        Assert.Equal(expected, new StandaloneAnswers().Query(new SanitizeDownloadFilename(suggested)).Filename);
    }
}

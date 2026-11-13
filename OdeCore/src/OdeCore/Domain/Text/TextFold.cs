using System.Globalization;
using System.Text;

namespace OdeCore.Domain;

/// How the core reads text it compares: `Normalized` puts it in canonical
/// composed form, and `Folded` also drops case and diacritics, so "Café",
/// "CAFE" and a decomposed "Café" all fold to "cafe". Normalization
/// rejects malformed UTF-16 and U+FFFE, so those become U+FFFD in the copy
/// that is compared; the text a person sees keeps them. The palette's term
/// matching folds each character the same way, one at a time, so it can
/// report where in a title a match lands (`PaletteQuery`).
internal static class TextFold {
    #region Actions - Folding

    /// `text` in canonical composed form (NFC).
    public static string Normalized(string text) => Normalized(text, NormalizationForm.FormC);

    /// `text` without case or diacritics: decomposed, without its nonspacing
    /// marks, recomposed and lowercased as the invariant culture lowers it.
    public static string Folded(string text) {
        var decomposed = Normalized(text, NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (char character in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark) builder.Append(character);
        return builder.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    private static string Normalized(string text, NormalizationForm form) {
        try {
            return text.Normalize(form);
        } catch (ArgumentException) {
            var valid = new StringBuilder(text.Length);
            foreach (var rune in text.EnumerateRunes())
                valid.Append((rune.Value == 0xFFFE ? Rune.ReplacementChar : rune).ToString());
            return valid.ToString().Normalize(form);
        }
    }

    #endregion
}

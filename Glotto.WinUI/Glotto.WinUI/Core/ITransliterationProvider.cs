// ITransliterationProvider.cs
// Port of TransliterationProvider protocol in TransliterationProvider.swift

using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Glotto.WinUI.Core;

/// <summary>
/// Everything that can generate transliteration candidates must implement this interface.
/// In Phase 1: GoogleTransliterationProvider and LocalRuleTransliterationProvider.
/// In Phase 2: additional offline engines slot in here without touching any call site.
/// </summary>
public interface ITransliterationProvider
{
    /// <summary>
    /// Fetch ranked candidates for a single word-in-progress.
    /// <paramref name="text"/> is the raw Latin buffer being composed — not yet committed to the target app.
    /// Candidates are ordered best-first (rank 0 = most likely).
    /// Implementors should never throw out of this method — return an empty list on any failure.
    /// </summary>
    Task<IReadOnlyList<TransliterationCandidate>> GetCandidatesAsync(
        string text,
        LanguageProfile profile,
        CancellationToken cancellationToken);
}

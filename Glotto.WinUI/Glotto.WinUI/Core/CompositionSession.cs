// CompositionSession.cs
// Port of CompositionSession struct from CompositionController.swift.
// Value type: mutations are cheap, copying is trivial.
// One controller owns it; all observers react to it.

using System.Collections.Generic;

namespace Glotto.WinUI.Core;

/// <summary>
/// The single source of truth for what's happening in a composition session.
/// This is a mutable struct — CompositionController owns one and replaces it on each mutation.
/// </summary>
public struct CompositionSession
{
    /// <summary>Raw Latin characters the user has typed since the last commit or cancel.</summary>
    public string Buffer { get; private set; } = string.Empty;

    /// <summary>The currently active language profile.</summary>
    public LanguageProfile Profile { get; set; }

    /// <summary>The ranked candidates from the most recent transliteration lookup.</summary>
    public IReadOnlyList<TransliterationCandidate> Candidates { get; set; } = [];

    /// <summary>Index into <see cref="Candidates"/> currently highlighted in the overlay panel.</summary>
    public int SelectionIndex { get; set; } = 0;

    /// <summary>Whether a network request is currently in flight.</summary>
    public bool IsLoading { get; set; } = false;

    /// <summary>Whether the last lookup attempt failed (used to show "unavailable" UI).</summary>
    public bool LookupFailed { get; set; } = false;

    public bool IsEmpty => string.IsNullOrEmpty(Buffer);

    public TransliterationCandidate? SelectedCandidate =>
        Candidates.Count > 0 && SelectionIndex < Candidates.Count
            ? Candidates[SelectionIndex]
            : null;

    public CompositionSession(LanguageProfile profile)
    {
        Profile = profile;
    }

    /// <summary>Append a character to the buffer.</summary>
    public void Append(char character)
    {
        Buffer += character;
        // Reset selection when the buffer changes — don't preserve stale index.
        SelectionIndex = 0;
        LookupFailed = false;
    }

    /// <summary>Remove the last character (backspace handling).</summary>
    public void DeleteBack()
    {
        if (string.IsNullOrEmpty(Buffer)) return;
        Buffer = Buffer[..^1];
        SelectionIndex = 0;
        Candidates = [];
        LookupFailed = false;
    }

    public void Reset()
    {
        Buffer = string.Empty;
        Candidates = [];
        SelectionIndex = 0;
        IsLoading = false;
        LookupFailed = false;
    }
}

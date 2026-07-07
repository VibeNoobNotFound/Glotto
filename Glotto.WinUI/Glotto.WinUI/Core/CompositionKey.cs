// CompositionKey.cs
// Port of CompositionKey enum from CompositionController.swift.
// Keys that CompositionController understands while a session is active.

namespace Glotto.WinUI.Core;

/// <summary>
/// Discriminated union of keys CompositionController handles while composing.
/// NumberSelect carries the candidate number (1–5).
/// </summary>
public abstract record CompositionKey
{
    private CompositionKey() { }  // closed hierarchy

    public sealed record ArrowUp : CompositionKey;
    public sealed record ArrowDown : CompositionKey;
    public sealed record Commit : CompositionKey;      // Enter/Return
    public sealed record Space : CompositionKey;
    public sealed record Escape : CompositionKey;
    public sealed record NumberSelect(int Number) : CompositionKey;  // 1–5 for direct candidate selection
}

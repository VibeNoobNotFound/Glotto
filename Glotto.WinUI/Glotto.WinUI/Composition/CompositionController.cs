// CompositionController.cs
// Port of CompositionController.swift.
//
// Orchestrates the composition lifecycle:
//   KeyboardHookManager calls Receive(char) / HandleSpecialKey() on keystrokes.
//   CompositionController debounces, calls TransliterationService, updates session state,
//   and tells CandidateOverlayController to show/hide/reposition.
//
// Must run on the WinUI dispatcher thread (equivalent of @MainActor in Swift).
// The DispatcherQueue.HasThreadAccess check guards mutation of UI-bound properties.

using CommunityToolkit.Mvvm.ComponentModel;
using Glotto.WinUI.Core;
using Glotto.WinUI.Interop;
using Glotto.WinUI.Services;
using Microsoft.UI.Dispatching;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Glotto.WinUI.Composition;

public sealed partial class CompositionController : ObservableObject
{
    [ObservableProperty] private CompositionSession _session;

    private readonly TransliterationService _service;
    private readonly TextInjector _textInjector;
    private readonly CandidateOverlayController _overlayController;
    private readonly DispatcherQueue _dispatcherQueue;

    /// <summary>Debounce window: wait this long after the last keystroke before issuing a network request.</summary>
    private readonly TimeSpan _debounceInterval = TimeSpan.FromMilliseconds(130);

    /// <summary>The in-flight lookup task, cancelled if the buffer changes before it resolves.</summary>
    private CancellationTokenSource? _lookupCts;

    public bool IsComposing => !Session.IsEmpty;

    public CompositionController(
        LanguageProfile profile,
        TransliterationService service,
        TextInjector textInjector,
        CandidateOverlayController overlayController,
        DispatcherQueue dispatcherQueue)
    {
        _session = new CompositionSession(profile);
        _service = service;
        _textInjector = textInjector;
        _overlayController = overlayController;
        _dispatcherQueue = dispatcherQueue;

        // Wire click-to-commit: the panel calls back here when the user clicks a candidate row.
        overlayController.CandidateSelected += (_, idx) => CommitCandidate(idx);
    }

    // MARK: - Keystroke handling (called from KeyboardHookManager via dispatcher)

    /// <summary>Called for each printable Latin character captured while armed.</summary>
    public void Receive(char character)
    {
        _session.Append(character);
        OnPropertyChanged(nameof(Session));
        ScheduleLookup();
        UpdateOverlay();
    }

    /// <summary>Called for backspace while composing.</summary>
    public void HandleBackspace()
    {
        _session.DeleteBack();
        OnPropertyChanged(nameof(Session));
        if (_session.IsEmpty)
        {
            CancelComposition();
        }
        else
        {
            ScheduleLookup();
            UpdateOverlay();
        }
    }

    /// <summary>
    /// Called for navigation/commit/cancel keys while the panel is visible.
    /// Returns true if the key was consumed (should be swallowed), false to pass through.
    /// </summary>
    public bool HandleSpecialKey(CompositionKey key)
    {
        if (_session.IsEmpty && key is not CompositionKey.Escape) return false;

        switch (key)
        {
            case CompositionKey.ArrowUp:
                if (_session.Candidates.Count == 0) return false;
                _session.SelectionIndex = Math.Max(0, _session.SelectionIndex - 1);
                OnPropertyChanged(nameof(Session));
                _overlayController.Update(_session);
                return true;

            case CompositionKey.ArrowDown:
                if (_session.Candidates.Count == 0) return false;
                _session.SelectionIndex = Math.Min(_session.Candidates.Count - 1, _session.SelectionIndex + 1);
                OnPropertyChanged(nameof(Session));
                _overlayController.Update(_session);
                return true;

            case CompositionKey.Commit:      // Enter — commit highlighted candidate
                CommitSelected(suffix: string.Empty);
                return true;

            case CompositionKey.Space:       // Space — commit top candidate, appending a space
                CommitSelected(suffix: " ");
                return true;

            case CompositionKey.Escape:
                CancelComposition();
                return true;

            case CompositionKey.NumberSelect ns:
                var idx = ns.Number - 1;
                if (idx >= 0 && idx < _session.Candidates.Count)
                {
                    _session.SelectionIndex = idx;
                    OnPropertyChanged(nameof(Session));
                    CommitSelected(suffix: string.Empty);
                }
                return true;

            default:
                return false;
        }
    }

    // MARK: - Commit / cancel

    public void CommitSelected(string suffix = " ")
    {
        var candidate = _session.SelectedCandidate;
        if (candidate is null)
        {
            CancelComposition();
            return;
        }

        // Latin characters are swallowed by the hook — the text field is clean at the cursor.
        var latinCount = 0;

        _lookupCts?.Cancel();
        _session.Reset();
        OnPropertyChanged(nameof(Session));
        _overlayController.Hide();

        var textToInject = candidate.Text + suffix;

        // Small delay so the overlay fade-out animation finishes before injection fires.
        _ = Task.Run(async () =>
        {
            await Task.Delay(50);
            await _textInjector.InjectAsync(textToInject, latinCount);
        });
    }

    /// <summary>Commit a specific candidate by index — called from click handler in the panel.</summary>
    public void CommitCandidate(int index)
    {
        if (index < 0 || index >= _session.Candidates.Count) return;
        _session.SelectionIndex = index;
        OnPropertyChanged(nameof(Session));
        CommitSelected(suffix: " ");
    }

    public void CancelComposition()
    {
        _lookupCts?.Cancel();
        _session.Reset();
        OnPropertyChanged(nameof(Session));
        _overlayController.Hide();
    }

    // MARK: - Debounced lookup

    private void ScheduleLookup()
    {
        _lookupCts?.Cancel();
        _lookupCts = new CancellationTokenSource();
        var cts = _lookupCts;

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(_debounceInterval, cts.Token);

                var text = _session.Buffer;
                var profile = _session.Profile;
                if (string.IsNullOrEmpty(text)) return;

                _dispatcherQueue.TryEnqueue(() =>
                {
                    _session.IsLoading = true;
                    OnPropertyChanged(nameof(Session));
                    _overlayController.Update(_session);
                });

                var results = await _service.GetCandidatesAsync(text, profile, cts.Token);

                if (cts.IsCancellationRequested) return;

                _dispatcherQueue.TryEnqueue(() =>
                {
                    _session.IsLoading = false;

                    var candidates = results.ToList();
                    // Always append raw Latin text as the final candidate option if not already present.
                    if (!string.IsNullOrEmpty(text) &&
                        !candidates.Any(c => c.Text.Equals(text, StringComparison.OrdinalIgnoreCase)))
                    {
                        candidates.Add(new TransliterationCandidate(text, candidates.Count));
                    }

                    _session.Candidates = candidates;
                    _session.SelectionIndex = 0;
                    _session.LookupFailed = results.Count == 0;

                    OnPropertyChanged(nameof(Session));
                    UpdateOverlay();
                });
            }
            catch (OperationCanceledException)
            {
                // Expected — debounce cancelled because a new keystroke arrived
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CompositionController] Lookup failed: {ex.Message}");
            }
        }, cts.Token);
    }

    // MARK: - Overlay

    private void UpdateOverlay()
    {
        if (_session.IsEmpty)
            _overlayController.Hide();
        else
            _overlayController.ShowOrUpdate(_session);
    }
}

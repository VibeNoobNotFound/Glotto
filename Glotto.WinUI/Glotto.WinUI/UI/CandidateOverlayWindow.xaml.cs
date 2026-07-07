// CandidateOverlayWindow.xaml.cs
// Port of CandidatePanelView.swift + CandidateOverlayController.swift (window half).
//
// A secondary WinUI 3 Window that hosts the floating candidate panel.
//
// Non-activating setup (§8 of the Windows implementation plan):
//   - WS_EX_NOACTIVATE + WS_EX_TOOLWINDOW applied to remove from taskbar and prevent focus steal.
//   - Shown via SetWindowPos(SWP_NOACTIVATE | SWP_SHOWWINDOW) — NOT window.Activate().
//   - Always-on-top via OverlappedPresenter.IsAlwaysOnTop.
//
// DO NOT call window.Activate() — it will steal focus from the target application.
// The candidate panel must NEVER take keyboard focus; the hook intercepts keys globally.

using Glotto.WinUI.Core;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using WinRT.Interop;
using Windows.Graphics;
using static Glotto.WinUI.Interop.NativeMethods;
using System;
using Microsoft.UI.Xaml;

namespace Glotto.WinUI.UI;

public sealed partial class CandidateOverlayWindow : Microsoft.UI.Xaml.Window
{
    private readonly DispatcherQueue _dispatcherQueue;
    private IntPtr _hwnd;
    private AppWindow? _appWindow;
    private OverlappedPresenter? _presenter;

    /// <summary>Raised when the user clicks a candidate row. Argument is the candidate index.</summary>
    public event EventHandler<int>? CandidateClicked;

    public CandidateOverlayWindow(DispatcherQueue dispatcherQueue)
    {
        _dispatcherQueue = dispatcherQueue;
        InitializeComponent();

        // Set up after InitializeComponent so the HWND is available
        _hwnd = WindowNative.GetWindowHandle(this);
        _appWindow = AppWindow.GetFromWindowId(Microsoft.UI.Win32Interop.GetWindowIdFromWindow(_hwnd));

        // Apply always-on-top via OverlappedPresenter
        _presenter = OverlappedPresenter.Create();
        _presenter.IsAlwaysOnTop = true;
        _presenter.IsMinimizable = false;
        _presenter.IsMaximizable = false;
        _presenter.IsResizable = false;
        _presenter.SetBorderAndTitleBar(false, false);
        _appWindow?.SetPresenter(_presenter);

        // Apply non-activating window styles
        ApplyNonActivatingStyle();

        // Make the window background transparent
        if (_appWindow is not null)
        {
            _appWindow.IsShownInSwitchers = false;
        }
    }

    // MARK: - Non-activating setup

    private void ApplyNonActivatingStyle()
    {
        var exStyle = (uint)GetWindowLongPtr(_hwnd, GWL_EXSTYLE).ToInt64();

        // Remove WS_EX_APPWINDOW (prevents appearing in taskbar/alt-tab)
        // Add WS_EX_NOACTIVATE (prevents focus grab) and WS_EX_TOOLWINDOW
        exStyle = (exStyle & ~WS_EX_APPWINDOW) | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
        SetWindowLongPtr(_hwnd, GWL_EXSTYLE, (IntPtr)exStyle);
    }

    // MARK: - Show / hide without activating

    public void ShowNonActivating()
    {
        SetWindowPos(
            _hwnd,
            HWND_TOPMOST,
            0, 0, 0, 0,     // position and size set separately via MoveAndResize
            SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOMOVE | SWP_NOSIZE
        );
    }

    public void HideWindow()
    {
        SetWindowPos(
            _hwnd,
            HWND_TOPMOST,
            0, 0, 0, 0,
            SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | 0x0080 /* SWP_HIDEWINDOW */
        );
    }

    public IntPtr GetHwnd() => _hwnd;

    public void MoveAndResize(int x, int y, int width, int height)
    {
        // AppWindow.MoveAndResize takes physical pixels (RectInt32)
        _appWindow?.MoveAndResize(new RectInt32(x, y, width, height));
    }

    // MARK: - Content update

    /// <summary>
    /// Update the panel content based on the current composition session.
    /// Called from CandidateOverlayController whenever the session changes.
    /// </summary>
    public void UpdateSession(CompositionSession session, bool isPresented)
    {
        _dispatcherQueue.TryEnqueue(() => RenderSession(session, isPresented));
    }

    private void RenderSession(CompositionSession session, bool isPresented)
    {
        // Header
        if (!string.IsNullOrEmpty(session.Buffer))
        {
            BufferText.Text = $"› {session.Buffer}";
            BufferBadge.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
        }
        else
        {
            BufferBadge.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
        }

        LookupFailedIcon.Visibility = session.LookupFailed
            ? Microsoft.UI.Xaml.Visibility.Visible
            : Microsoft.UI.Xaml.Visibility.Collapsed;

        ProfileNameText.Text = session.Profile.DisplayName;

        // Content area
        LoadingPanel.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
        EmptyText.Visibility    = Microsoft.UI.Xaml.Visibility.Collapsed;
        CandidatesPanel.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;

        if (session.IsLoading)
        {
            LoadingText.Text = $"Looking up \"{session.Buffer}\"…";
            LoadingPanel.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
        }
        else if (session.Candidates.Count == 0)
        {
            EmptyText.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
        }
        else
        {
            BuildCandidateRows(session);
            CandidatesPanel.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
        }
    }

    private void BuildCandidateRows(CompositionSession session)
    {
        CandidatesPanel.Children.Clear();

        for (var i = 0; i < session.Candidates.Count; i++)
        {
            var candidate = session.Candidates[i];
            var isSelected = i == session.SelectionIndex;
            var rowIndex = i;  // capture for closure

            var row = BuildCandidateRow(candidate, i, isSelected);
            row.Tapped += (_, _) => CandidateClicked?.Invoke(this, rowIndex);

            CandidatesPanel.Children.Add(row);

            // Divider between rows
            if (i < session.Candidates.Count - 1)
            {
                CandidatesPanel.Children.Add(new Microsoft.UI.Xaml.Controls.Border
                {
                    Height = 1,
                    Margin = new Microsoft.UI.Xaml.Thickness(36, 0, 0, 0),
                    Opacity = 0.3,
                    Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["DividerStrokeColorDefaultBrush"]
                });
            }
        }
    }

    private static Microsoft.UI.Xaml.Controls.Border BuildCandidateRow(
        TransliterationCandidate candidate,
        int rank,
        bool isSelected)
    {
        var accentBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentFillColorDefaultBrush"];

        // Rank badge
        var rankBadge = new Microsoft.UI.Xaml.Controls.Border
        {
            Width = 18, Height = 18,
            CornerRadius = new Microsoft.UI.Xaml.CornerRadius(9),
            Background = isSelected ? accentBrush
                : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["ControlFillColorDefaultBrush"],
            Child = new Microsoft.UI.Xaml.Controls.TextBlock
            {
                Text = (rank + 1).ToString(),
                FontSize = 10,
                FontWeight = Microsoft.UI.Text.FontWeights.Medium,
                HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Center,
                VerticalAlignment = Microsoft.UI.Xaml.VerticalAlignment.Center,
                Foreground = isSelected
                    ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White)
                    : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
            }
        };

        // Script text (large, for readability of non-Latin script)
        var scriptText = new Microsoft.UI.Xaml.Controls.TextBlock
        {
            Text = candidate.Text,
            FontSize = 18,
            FontWeight = isSelected ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
            VerticalAlignment = Microsoft.UI.Xaml.VerticalAlignment.Center,
            Margin = new Microsoft.UI.Xaml.Thickness(10, 0, 0, 0)
        };

        // Keyboard hint (↵ for selected)
        Microsoft.UI.Xaml.FrameworkElement? hint = null;
        if (isSelected)
        {
            hint = new Microsoft.UI.Xaml.Controls.Border
            {
                Padding = new Microsoft.UI.Xaml.Thickness(5, 2, 5, 2),
                CornerRadius = new Microsoft.UI.Xaml.CornerRadius(4),
                Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["ControlFillColorDefaultBrush"],
                Child = new Microsoft.UI.Xaml.Controls.TextBlock
                {
                    Text = "↵",
                    FontSize = 10,
                    Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
                }
            };
        }

        // Row grid
        var grid = new Microsoft.UI.Xaml.Controls.Grid
        {
            Padding = new Microsoft.UI.Xaml.Thickness(12, 9, 12, 9)
        };
        grid.ColumnDefinitions.Add(new Microsoft.UI.Xaml.Controls.ColumnDefinition { Width = Microsoft.UI.Xaml.GridLength.Auto });
        grid.ColumnDefinitions.Add(new Microsoft.UI.Xaml.Controls.ColumnDefinition { Width = new Microsoft.UI.Xaml.GridLength(1, Microsoft.UI.Xaml.GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new Microsoft.UI.Xaml.Controls.ColumnDefinition { Width = Microsoft.UI.Xaml.GridLength.Auto });

        Microsoft.UI.Xaml.Controls.Grid.SetColumn(rankBadge, 0);
        Microsoft.UI.Xaml.Controls.Grid.SetColumn(scriptText, 1);
        grid.Children.Add(rankBadge);
        grid.Children.Add(scriptText);
        if (hint is not null)
        {
            Microsoft.UI.Xaml.Controls.Grid.SetColumn(hint, 2);
            grid.Children.Add(hint);
        }

        // Row border (provides selection highlight background)
        var rowBorder = new Microsoft.UI.Xaml.Controls.Border
        {
            CornerRadius = new Microsoft.UI.Xaml.CornerRadius(8),
            Margin = new Microsoft.UI.Xaml.Thickness(4, 0, 4, 0),
            Background = isSelected
                ? new Microsoft.UI.Xaml.Media.SolidColorBrush(
                    Microsoft.UI.ColorHelper.FromArgb(38, 0, 120, 212))  // accent ~15% opacity
                : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent),
            Child = grid
        };

        return rowBorder;
    }
}

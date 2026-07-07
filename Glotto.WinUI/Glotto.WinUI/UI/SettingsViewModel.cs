using System.Collections.Generic;
using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Glotto.WinUI.Core;
using Glotto.WinUI.Providers;
using Windows.Storage;

namespace Glotto.WinUI.UI;

public sealed partial class ProviderItemViewModel : ObservableObject
{
    public string Id { get; }
    public string DisplayName { get; }
    public string Subtitle { get; }
    public string Icon { get; }

    [ObservableProperty] private int _priority;

    public ProviderItemViewModel(ProviderEntry entry, int priority)
    {
        Id = entry.Id;
        DisplayName = entry.DisplayName;
        Subtitle = entry.Subtitle;
        Icon = entry.Icon;
        _priority = priority;
    }
}

public sealed partial class SettingsViewModel : ObservableObject
{
    private const string ProviderOrderKey = "providerOrder";
    private const string ActiveProfileIdKey = "activeProfileID";

    [ObservableProperty] private string _activeProfileId = LanguageProfile.Sinhala.Id;
    [ObservableProperty] private string _hotkeyText = "Ctrl + Shift + Space";

    public ObservableCollection<ProviderItemViewModel> Providers { get; } = [];

    public IReadOnlyList<LanguageProfile> LanguageProfiles => LanguageProfile.BuiltIn;

    public SettingsViewModel()
    {
        LoadSettings();
    }

    private void LoadSettings()
    {
        // Load active profile
        _activeProfileId = SettingsStorage.GetString(ActiveProfileIdKey, LanguageProfile.Sinhala.Id)!;

        // Load providers order
        var rawOrder = SettingsStorage.GetString(ProviderOrderKey, ProviderRegistry.DefaultOrder)!;
        var entries = ProviderRegistry.OrderedEntries(rawOrder);
        
        Providers.Clear();
        for (int i = 0; i < entries.Count; i++)
        {
            Providers.Add(new ProviderItemViewModel(entries[i], i + 1));
        }
    }

    [RelayCommand]
    private void MoveUp(ProviderItemViewModel item)
    {
        int index = Providers.IndexOf(item);
        if (index <= 0) return;

        Providers.RemoveAt(index);
        Providers.Insert(index - 1, item);
        UpdatePrioritiesAndSave();
    }

    [RelayCommand]
    private void MoveDown(ProviderItemViewModel item)
    {
        int index = Providers.IndexOf(item);
        if (index < 0 || index >= Providers.Count - 1) return;

        Providers.RemoveAt(index);
        Providers.Insert(index + 1, item);
        UpdatePrioritiesAndSave();
    }

    private void UpdatePrioritiesAndSave()
    {
        var ids = new List<string>();
        for (int i = 0; i < Providers.Count; i++)
        {
            Providers[i].Priority = i + 1;
            ids.Add(Providers[i].Id);
        }

        var rawOrder = string.Join(",", ids);
        SettingsStorage.SetString(ProviderOrderKey, rawOrder);
    }

    partial void OnActiveProfileIdChanged(string value)
    {
        if (value is not null)
        {
            SettingsStorage.SetString(ActiveProfileIdKey, value);
        }
    }
}

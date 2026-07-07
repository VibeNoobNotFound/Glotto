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

public sealed class SoundItem
{
    public string Id { get; }
    public string DisplayName { get; }
    public SoundItem(string id, string displayName)
    {
        Id = id;
        DisplayName = displayName;
    }
}

public sealed partial class SettingsViewModel : ObservableObject
{
    private const string ProviderOrderKey = "providerOrder";
    private const string ActiveProfileIdKey = "activeProfileID";
    private const string SoundEnabledKey = "soundEnabled";

    [ObservableProperty] private string _activeProfileId = LanguageProfile.Sinhala.Id;
    [ObservableProperty] private string _hotkeyText = "Ctrl + Shift + Space";
    [ObservableProperty] private bool _soundEnabled = true;
    [ObservableProperty] private string _selectedSoundOnId = "Asterisk";
    [ObservableProperty] private string _selectedSoundOffId = "Beep";

    public ObservableCollection<ProviderItemViewModel> Providers { get; } = [];

    public IReadOnlyList<LanguageProfile> LanguageProfiles => LanguageProfile.BuiltIn;

    public List<SoundItem> AvailableSounds { get; } = new()
    {
        new SoundItem("None", "None (Silent)"),
        new SoundItem("Asterisk", "Default Beep"),
        new SoundItem("Beep", "Beep"),
        new SoundItem("Exclamation", "Exclamation"),
        new SoundItem("Hand", "Critical Stop"),
        new SoundItem("Question", "Question")
    };

    public SettingsViewModel()
    {
        LoadSettings();
    }

    private void LoadSettings()
    {
        // Load active profile
        _activeProfileId = SettingsStorage.GetString(ActiveProfileIdKey, LanguageProfile.Sinhala.Id)!;

        // Load sound settings
        _soundEnabled = SettingsStorage.GetString(SoundEnabledKey, "true") == "true";
        _selectedSoundOnId = SettingsStorage.GetString(SoundPlayer.SelectedSoundOnIdKey, "Asterisk")!;
        _selectedSoundOffId = SettingsStorage.GetString(SoundPlayer.SelectedSoundOffIdKey, "Beep")!;

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

    public void UpdatePrioritiesAndSave()
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

    partial void OnSoundEnabledChanged(bool value)
    {
        SettingsStorage.SetString(SoundEnabledKey, value ? "true" : "false");
    }

    partial void OnSelectedSoundOnIdChanged(string value)
    {
        if (value is not null)
        {
            SettingsStorage.SetString(SoundPlayer.SelectedSoundOnIdKey, value);
            // Play immediately for visual feedback (armed state)
            try
            {
                SoundPlayer.PlayToggleSound(armed: true);
            }
            catch {}
        }
    }

    partial void OnSelectedSoundOffIdChanged(string value)
    {
        if (value is not null)
        {
            SettingsStorage.SetString(SoundPlayer.SelectedSoundOffIdKey, value);
            // Play immediately for visual feedback (disarmed state)
            try
            {
                SoundPlayer.PlayToggleSound(armed: false);
            }
            catch {}
        }
    }
}

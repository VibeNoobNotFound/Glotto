using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Windows.Storage;

namespace Glotto.WinUI.Core;

public static class SettingsStorage
{
    private static readonly bool _isPackaged;
    private static readonly string _fallbackPath;
    private static Dictionary<string, string> _fallbackCache = new();

    static SettingsStorage()
    {
        try
        {
            // If this doesn't throw, we have a package identity
            _ = ApplicationData.Current.LocalSettings;
            _isPackaged = true;
        }
        catch
        {
            _isPackaged = false;
        }

        var localFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Glotto");
        Directory.CreateDirectory(localFolder);
        _fallbackPath = Path.Combine(localFolder, "settings.json");

        if (!_isPackaged && File.Exists(_fallbackPath))
        {
            try
            {
                var json = File.ReadAllText(_fallbackPath);
                _fallbackCache = JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new();
            }
            catch
            {
                _fallbackCache = new();
            }
        }
    }

    public static string? GetString(string key, string? defaultValue = null)
    {
        if (_isPackaged)
        {
            return ApplicationData.Current.LocalSettings.Values[key] as string ?? defaultValue;
        }
        else
        {
            return _fallbackCache.TryGetValue(key, out var val) ? val : defaultValue;
        }
    }

    public static void SetString(string key, string value)
    {
        if (_isPackaged)
        {
            ApplicationData.Current.LocalSettings.Values[key] = value;
        }
        else
        {
            _fallbackCache[key] = value;
            try
            {
                var json = JsonSerializer.Serialize(_fallbackCache);
                File.WriteAllText(_fallbackPath, json);
            }
            catch
            {
                // Ignored
            }
        }
    }
}

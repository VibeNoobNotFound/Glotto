using System;
using Glotto.WinUI.Core;

namespace Glotto.WinUI.Core;

public static class SoundPlayer
{
    private const string SoundEnabledKey = "soundEnabled";
    public const string SelectedSoundOnIdKey = "selectedSoundOnId";
    public const string SelectedSoundOffIdKey = "selectedSoundOffId";

    public static void PlayToggleSound(bool armed)
    {
        var soundEnabled = SettingsStorage.GetString(SoundEnabledKey, "true") == "true";
        if (!soundEnabled) return;

        var key = armed ? SelectedSoundOnIdKey : SelectedSoundOffIdKey;
        var defaultSound = armed ? "Asterisk" : "Beep";
        var soundId = SettingsStorage.GetString(key, defaultSound);

        if (soundId == "None" || string.IsNullOrEmpty(soundId)) return;

        try
        {
            switch (soundId)
            {
                case "Asterisk":
                    System.Media.SystemSounds.Asterisk.Play();
                    break;
                case "Beep":
                    System.Media.SystemSounds.Beep.Play();
                    break;
                case "Exclamation":
                    System.Media.SystemSounds.Exclamation.Play();
                    break;
                case "Hand":
                    System.Media.SystemSounds.Hand.Play();
                    break;
                case "Question":
                    System.Media.SystemSounds.Question.Play();
                    break;
                default:
                    System.Media.SystemSounds.Asterisk.Play();
                    break;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[SoundPlayer] Failed to play sound: {ex.Message}");
        }
    }
}

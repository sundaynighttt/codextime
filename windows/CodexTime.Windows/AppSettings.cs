using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace CodexTime.WinApp;

public sealed class AppSettings
{
    public DisplayMode DisplayMode { get; set; } = DisplayMode.TaskbarLabel;
    public int? FloatingLeftPx { get; set; }
    public int? FloatingTopPx { get; set; }
    public bool ShowResetTime { get; set; }
    public bool HasCompletedSetup { get; set; }
    public Dictionary<UsageProviderID, ProviderPreferences> Providers { get; set; } = new();

    public ProviderPreferences Preferences(UsageProviderID id)
    {
        Providers ??= new();
        if (!Providers.TryGetValue(id, out var preferences) || preferences is null)
            Providers[id] = preferences = new ProviderPreferences();
        return preferences;
    }
}

public sealed class ProviderPreferences
{
    public bool Enabled { get; set; } = true;
    public bool UsageConsent { get; set; }
    public bool GrokWebVerified { get; set; }
}

public static class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private static string SettingsPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CodexTime",
        "settings.json");

    public static AppSettings Load()
    {
        try
        {
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath), JsonOptions)
                   ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static void Save(AppSettings settings)
    {
        var directory = Path.GetDirectoryName(SettingsPath)!;
        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(directory, $"settings-{Guid.NewGuid():N}.tmp");
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(settings, JsonOptions));
        File.Move(temporaryPath, SettingsPath, overwrite: true);
    }
}

public static class StartupManager
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "CodexTime";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            return key?.GetValue(ValueName) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (value)
            {
                key.SetValue(ValueName, $"\"{Environment.ProcessPath}\"");
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
        }
    }
}

public static class AppLog
{
    private static readonly object Gate = new();

    // Exception text can contain CLI output, account information or request data.
    public static void Write(Exception exception) => Write("operation_failed");

    public static void Write(string message)
    {
        try
        {
            var directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CodexTime");
            Directory.CreateDirectory(directory);
            lock (Gate)
            {
                File.AppendAllText(
                    Path.Combine(directory, "codextime.log"),
                    $"[{DateTimeOffset.Now:O}] {message}{Environment.NewLine}");
            }
        }
        catch
        {
            // Logging must never terminate the monitor.
        }
    }
}

using System.Diagnostics;
using System.IO;

namespace CodexTime.WinApp;

// Interactive, user-requested login only. The OS opens the installed executable
// or npm command wrapper with fixed arguments; no composed command text, package
// installation, model calls, output capture or browser credential access.
public static class ProviderLoginService
{
    public static void Login(UsageProviderID provider)
    {
        string? executable = provider switch
        {
            UsageProviderID.Codex => FindCodex(),
            UsageProviderID.Claude => FindClaude(),
            UsageProviderID.Grok => FindCursor(),
            _ => null
        };
        if (executable is null)
        {
            OpenOfficialDownload(provider);
            return;
        }
        Process.Start(CreateLoginStartInfo(provider, executable))?.Dispose();
    }

    internal static ProcessStartInfo CreateLoginStartInfo(UsageProviderID provider, string executable)
    {
        var start = new ProcessStartInfo(executable)
        {
            UseShellExecute = true,
            WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            WindowStyle = ProcessWindowStyle.Normal
        };
        if (provider == UsageProviderID.Codex) start.ArgumentList.Add("login");
        else if (provider == UsageProviderID.Claude)
        {
            start.ArgumentList.Add("auth");
            start.ArgumentList.Add("login");
        }
        return start;
    }

    public static void OpenUsage(UsageProviderID provider) => Open(provider switch
    {
        UsageProviderID.Codex => "https://chatgpt.com/codex/settings/usage",
        UsageProviderID.Grok => "https://grok.com/?_s=usage",
        UsageProviderID.Claude => "https://claude.ai/settings/usage",
        _ => throw new ArgumentOutOfRangeException(nameof(provider))
    });

    private static void OpenOfficialDownload(UsageProviderID provider) => Open(provider switch
    {
        UsageProviderID.Codex => "https://developers.openai.com/codex/cli/",
        UsageProviderID.Claude => "https://code.claude.com/docs/en/setup",
        UsageProviderID.Grok => "https://cursor.com/downloads",
        _ => throw new ArgumentOutOfRangeException(nameof(provider))
    });

    private static void Open(string fixedUrl) => Process.Start(new ProcessStartInfo(fixedUrl)
    {
        UseShellExecute = true
    })?.Dispose();

    private static string? FindCodex()
    {
        try
        {
            var path = CodexAppServerClient.ResolveCodexPath();
            return InstalledCli(path);
        }
        catch { return null; }
    }

    private static string? FindClaude()
    {
        var known = NativeExecutable(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin", "claude.exe"));
        if (known is not null) return known;
        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            try
            {
                foreach (var name in new[] { "claude.exe", "claude.cmd", "claude.bat" })
                {
                    var candidate = InstalledCli(Path.Combine(directory.Trim('"'), name));
                    if (candidate is not null) return candidate;
                }
            }
            catch { /* Malformed PATH entries do not expand the search. */ }
        }
        return null;
    }

    private static string? FindCursor()
    {
        foreach (var candidate in new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "cursor", "Cursor.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Cursor", "Cursor.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Cursor", "Cursor.exe")
        })
        {
            var executable = NativeExecutable(candidate);
            if (executable is not null) return executable;
        }
        return null;
    }

    private static string? NativeExecutable(string path)
    {
        if (!Path.IsPathFullyQualified(path) || !string.Equals(Path.GetExtension(path), ".exe", StringComparison.OrdinalIgnoreCase)
            || !File.Exists(path)) return null;
        return Path.GetFullPath(path);
    }

    private static string? InstalledCli(string path)
    {
        if (!Path.IsPathFullyQualified(path) || !File.Exists(path)) return null;
        var extension = Path.GetExtension(path);
        if (!new[] { ".exe", ".cmd", ".bat" }.Contains(extension, StringComparer.OrdinalIgnoreCase)) return null;
        return Path.GetFullPath(path);
    }
}

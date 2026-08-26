using System.Diagnostics;
using System.IO;

namespace CodexTime.WinApp;

public sealed class CodexAppServerClient
{
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(12);

    public async Task<RateLimitReport> FetchAsync(CancellationToken cancellationToken = default)
    {
        var startInfo = CreateStartInfo(ResolveCodexPath());
        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException("Codex app-server를 시작하지 못했습니다.");
        }

        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        try
        {
            await process.StandardInput.WriteLineAsync(
                "{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"codextime-windows\",\"version\":\"0.2.0\"}}}");
            await process.StandardInput.WriteLineAsync("{\"method\":\"initialized\"}");
            await process.StandardInput.WriteLineAsync("{\"id\":2,\"method\":\"account/rateLimits/read\"}");
            await process.StandardInput.FlushAsync();

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(RequestTimeout);
            while (true)
            {
                string? line;
                try
                {
                    line = await process.StandardOutput.ReadLineAsync(timeout.Token);
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    throw new TimeoutException("Codex 사용량 조회 시간이 초과됐습니다.");
                }

                if (line is null)
                {
                    var error = await stderrTask;
                    throw new InvalidOperationException(
                        string.IsNullOrWhiteSpace(error)
                            ? "Codex app-server가 응답 없이 종료됐습니다."
                            : error.Trim());
                }

                var report = RateLimitParser.ParseResponseLine(line);
                if (report is not null)
                {
                    return report;
                }
            }
        }
        finally
        {
            if (!process.HasExited)
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync(CancellationToken.None);
                }
                catch
                {
                    // The short-lived app-server may exit between the checks above.
                }
            }
        }
    }

    private static ProcessStartInfo CreateStartInfo(string path)
    {
        var extension = Path.GetExtension(path).ToLowerInvariant();
        var startInfo = new ProcessStartInfo
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        switch (extension)
        {
            case ".cmd":
            case ".bat":
                startInfo.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
                startInfo.ArgumentList.Add("/d");
                startInfo.ArgumentList.Add("/s");
                startInfo.ArgumentList.Add("/c");
                startInfo.ArgumentList.Add($"\"{path}\" app-server");
                break;
            case ".ps1":
                startInfo.FileName = "powershell.exe";
                startInfo.ArgumentList.Add("-NoProfile");
                startInfo.ArgumentList.Add("-ExecutionPolicy");
                startInfo.ArgumentList.Add("Bypass");
                startInfo.ArgumentList.Add("-File");
                startInfo.ArgumentList.Add(path);
                startInfo.ArgumentList.Add("app-server");
                break;
            default:
                startInfo.FileName = path;
                startInfo.ArgumentList.Add("app-server");
                break;
        }

        return startInfo;
    }

    private static string ResolveCodexPath()
    {
        var explicitPath = Environment.GetEnvironmentVariable("CODEX_CLI_PATH");
        if (!string.IsNullOrWhiteSpace(explicitPath) && File.Exists(explicitPath))
        {
            return Path.GetFullPath(explicitPath);
        }

        var names = new[] { "codex.exe", "codex.cmd", "codex.bat", "codex.ps1" };
        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
                     .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            foreach (var name in names)
            {
                try
                {
                    var candidate = Path.Combine(directory.Trim('"'), name);
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
                catch
                {
                    // Ignore malformed PATH entries and continue searching.
                }
            }
        }

        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var codexBin = Path.Combine(localAppData, "OpenAI", "Codex", "bin");
        if (Directory.Exists(codexBin))
        {
            var appCodex = Directory.EnumerateDirectories(codexBin)
                .Select(directory => Path.Combine(directory, "codex.exe"))
                .Where(File.Exists)
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault();
            if (appCodex is not null)
            {
                return appCodex;
            }
        }

        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        foreach (var candidate in new[]
                 {
                     Path.Combine(appData, "npm", "codex.cmd"),
                     Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin", "codex.exe")
                 })
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new FileNotFoundException(
            "Codex CLI를 찾지 못했습니다. Codex를 설치하고 로그인한 뒤 다시 실행하세요.");
    }
}

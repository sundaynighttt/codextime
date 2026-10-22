using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace CodexTime.WinApp;

// Synthetic inputs only: no installed CLI, credentials, network or existing logs.
public static class ResourceSafetySelfTests
{
    private const string FixtureDirectoryVariable = "CODEXTIME_RESOURCE_FIXTURE_DIRECTORY";
    private const string DirectoryPrefix = "codextime-resource-tests-";
    private const string PrivateMarker = "synthetic-private-stderr-marker";
    private const string Response = "{\"id\":2,\"result\":{\"rateLimits\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":31}}}}";

    public static async Task RunAsync()
    {
        await BoundedLinesAsync();
        await ChildProcessesAsync();
        await RollingLogsAsync();
    }

    private static async Task BoundedLinesAsync()
    {
        const int maximum = 262_144;
        using (var source = new GeneratedTextReader(1_048_576))
        {
            var reader = new BoundedLineReader(source, maximum);
            await ExpectAsync<InvalidDataException>(() => reader.ReadLineAsync(default));
            Require(source.ReadCount <= maximum + 16_384,
                "oversized unterminated stdout must be rejected before consuming the whole input");
        }

        var boundary = new string('x', maximum);
        using (var source = new StringReader(boundary + "\n" + boundary + "\r\n" + boundary))
        {
            var reader = new BoundedLineReader(source, maximum);
            Require(await reader.ReadLineAsync(default) == boundary, "exact limit with LF");
            Require(await reader.ReadLineAsync(default) == boundary, "exact limit with CRLF");
            Require(await reader.ReadLineAsync(default) == boundary, "exact limit at EOF");
            Require(await reader.ReadLineAsync(default) is null, "EOF after final unterminated line");
        }

        foreach (var ending in new[] { "\n", "\r\n", string.Empty })
        {
            using var source = new StringReader(new string('x', maximum + 1) + ending);
            var reader = new BoundedLineReader(source, maximum);
            await ExpectAsync<InvalidDataException>(() => reader.ReadLineAsync(default));
        }

        using (var source = new StringReader("\n\r\n{\"method\":\"notification\"}\n" + Response + "\n"))
        {
            var reader = new BoundedLineReader(source, maximum);
            Require(await reader.ReadLineAsync(default) == string.Empty, "empty LF line");
            Require(await reader.ReadLineAsync(default) == string.Empty, "empty CRLF line");
            Require(RateLimitParser.ParseResponseLine((await reader.ReadLineAsync(default))!) is null,
                "notification remains separate from following response");
            var report = RateLimitParser.ParseResponseLine((await reader.ReadLineAsync(default))!);
            Require(report?.Main.Primary.RemainingPercent == 69, "response after notification");
            Require(await reader.ReadLineAsync(default) is null, "EOF after LF");
        }

        using (var source = new StringReader(string.Empty))
            Require(await new BoundedLineReader(source, maximum).ReadLineAsync(default) is null, "empty stream EOF");

        using (var cancelled = new CancellationTokenSource())
        using (var source = new StringReader("ready\n"))
        {
            cancelled.Cancel();
            await ExpectAsync<OperationCanceledException>(() => new BoundedLineReader(source, maximum).ReadLineAsync(cancelled.Token));
        }
        using (var source = new WaitingTextReader())
        using (var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(50)))
        {
            await ExpectAsync<OperationCanceledException>(() => new BoundedLineReader(source, maximum)
                .ReadLineAsync(cancellation.Token).WaitAsync(TimeSpan.FromSeconds(3)));
            Require(source.ObservedCancellation, "active cancellation reaches the owned read");
        }
    }

    private static async Task ChildProcessesAsync()
    {
        await WithFixtureAsync("stderr-flood", async (start, directory) =>
        {
            var report = await new CodexAppServerClient().FetchAsync(start, TimeSpan.FromSeconds(8))
                .WaitAsync(TimeSpan.FromSeconds(11));
            Require(report.Main.Primary.RemainingPercent == 69, "stderr flood does not block valid response");
            await AssertFixtureExitedAsync(directory, descendantRequired: false);
        });

        await WithFixtureAsync("oversized-stdout", async (start, directory) =>
        {
            await ExpectProviderFailureAsync(() => new CodexAppServerClient()
                .FetchAsync(start, TimeSpan.FromSeconds(8)).WaitAsync(TimeSpan.FromSeconds(11)), ProviderFailure.InvalidResponse);
            await AssertFixtureExitedAsync(directory, descendantRequired: false);
        });

        await WithFixtureAsync("stdout-eof", async (start, directory) =>
        {
            await ExpectProviderFailureAsync(() => new CodexAppServerClient()
                .FetchAsync(start, TimeSpan.FromSeconds(8)).WaitAsync(TimeSpan.FromSeconds(4)), ProviderFailure.QueryFailed);
            await AssertFixtureExitedAsync(directory, descendantRequired: false);
        });

        await WithFixtureAsync("stall", async (start, directory) =>
        {
            await ExpectTimeoutAsync(() => new CodexAppServerClient()
                .FetchAsync(start, TimeSpan.FromSeconds(3)).WaitAsync(TimeSpan.FromSeconds(6)));
            await AssertFixtureExitedAsync(directory, descendantRequired: true);
        });

        await WithFixtureAsync("stall", async (start, directory) =>
        {
            using var cancellation = new CancellationTokenSource();
            var fetch = new CodexAppServerClient().FetchAsync(start, TimeSpan.FromSeconds(12), cancellation.Token);
            await WaitForRecordAsync(directory, "descendant.pid");
            cancellation.Cancel();
            await ExpectAsync<OperationCanceledException>(() => fetch.WaitAsync(TimeSpan.FromSeconds(4)));
            await AssertFixtureExitedAsync(directory, descendantRequired: true);
        });
    }

    private static async Task RollingLogsAsync()
    {
        string directory = NewDirectory();
        try
        {
            const int maximumBytes = 4096;
            string path = Path.Combine(directory, "rolling.log");
            var log = new RollingFileLog(path, maxFileBytes: maximumBytes, maxMessageChars: 128);
            log.Write("synthetic-first-message");
            Require(ReadSmallLog(path, maximumBytes).Contains("synthetic-first-message"), "initial log write");
            for (int index = 0; index < 160; index++) log.Write($"synthetic-rotation-{index:D3}-" + new string('a', 96));
            log.Write("synthetic-latest-message");
            Require(File.Exists(path + ".1"), "log rotation retains one backup");
            AssertLogBounds(path, maximumBytes);
            Require(ReadSmallLog(path, maximumBytes).Contains("synthetic-latest-message"), "rotation retains latest message");
            Require(Directory.EnumerateFiles(directory, "rolling.log*").Count() <= 2, "only one rotated backup");

            string limitedPath = Path.Combine(directory, "entry.log");
            new RollingFileLog(limitedPath, maxFileBytes: maximumBytes, maxMessageChars: 64)
                .Write(new string('p', 10_000) + "synthetic-tail-must-be-truncated");
            var limited = ReadSmallLog(limitedPath, maximumBytes);
            Require(limited.Length < 1024 && !limited.Contains("synthetic-tail-must-be-truncated"),
                "individual message length is bounded");

            string unicodePath = Path.Combine(directory, "unicode.log");
            var unicodeLog = new RollingFileLog(unicodePath, maxFileBytes: 1024, maxMessageChars: 2048);
            for (int index = 0; index < 12; index++) unicodeLog.Write(string.Concat(Enumerable.Repeat("한글😀", 1024)));
            AssertLogBounds(unicodePath, 1024);
            Require(ReadSmallLog(unicodePath, 1024).Length > 0, "multibyte entry is written within byte cap");

            // The logical 3 GiB file is sparse: this writes metadata, never GiB of data.
            string oversizedPath = Path.Combine(directory, "oversized.log");
            MakeSparseFile(oversizedPath, 3L * 1024 * 1024 * 1024);
            MakeSparseFile(oversizedPath + ".1", 3L * 1024 * 1024 * 1024);
            new RollingFileLog(oversizedPath, maxFileBytes: maximumBytes, maxMessageChars: 128)
                .Write("synthetic-recovered-message");
            AssertLogBounds(oversizedPath, maximumBytes);
            Require(ReadSmallLog(oversizedPath, maximumBytes).Contains("synthetic-recovered-message"),
                "existing oversized log is recovered without reading or retaining giant content");

            string concurrentPath = Path.Combine(directory, "concurrent.log");
            var concurrentLog = new RollingFileLog(concurrentPath, maxFileBytes: maximumBytes, maxMessageChars: 128);
            await Task.WhenAll(Enumerable.Range(0, 8).Select(writer => Task.Run(() =>
            {
                for (int index = 0; index < 100; index++) concurrentLog.Write($"synthetic-worker-{writer}-{index}-한글😀");
            })));
            concurrentLog.Write("synthetic-after-concurrent-writers");
            AssertLogBounds(concurrentPath, maximumBytes);
            Require(ReadSmallLog(concurrentPath, maximumBytes).Contains("synthetic-after-concurrent-writers"),
                "logging remains usable after concurrent rotation");
        }
        finally { DeleteDirectory(directory); }
    }

    public static async Task RunFixtureAsync(string mode)
    {
        if (mode is not ("stderr-flood" or "oversized-stdout" or "stdout-eof" or "stall" or "descendant"))
            throw new InvalidOperationException("Invalid resource fixture mode");
        string directory = Environment.GetEnvironmentVariable(FixtureDirectoryVariable)
            ?? throw new InvalidOperationException("Missing synthetic fixture directory");
        CheckDirectory(directory);
        using (var self = Process.GetCurrentProcess())
            await File.WriteAllTextAsync(Path.Combine(directory, mode == "descendant" ? "descendant.pid" : "fixture.pid"),
                $"{self.Id}:{self.StartTime.ToUniversalTime().Ticks}");

        if (mode == "stderr-flood")
        {
            await Console.Error.WriteLineAsync(PrivateMarker);
            var block = new string('e', 4096);
            for (int index = 0; index < 1024; index++) await Console.Error.WriteAsync(block);
            await Console.Error.FlushAsync();
            await Console.Out.WriteLineAsync(Response);
            await Console.Out.FlushAsync();
        }
        else if (mode == "oversized-stdout")
        {
            var block = new string('x', 4096);
            for (int index = 0; index < 256; index++) await Console.Out.WriteAsync(block);
            await Console.Out.FlushAsync();
        }
        else if (mode == "stdout-eof")
        {
            await Console.Error.WriteLineAsync(PrivateMarker);
            await Console.Error.FlushAsync();
            // Close the real pipe handle; disposing Console.Out can leave the OS handle open.
            if (!CloseHandle(GetStdHandle(-11))) throw new InvalidOperationException("Synthetic stdout close failed");
        }
        else if (mode == "stall")
        {
            using var descendant = Process.Start(CreateFixtureStartInfo("descendant", directory))
                ?? throw new InvalidOperationException("Synthetic descendant did not start");
            await WaitForRecordAsync(directory, "descendant.pid");
            await Task.Delay(TimeSpan.FromSeconds(30));
            return;
        }
        await Task.Delay(TimeSpan.FromSeconds(30));
    }

    private static ProcessStartInfo CreateFixtureStartInfo(string mode, string directory)
    {
        var start = new ProcessStartInfo(Environment.ProcessPath!)
        {
            UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
            start.ArgumentList.Add(Path.Combine(AppContext.BaseDirectory,
                typeof(ResourceSafetySelfTests).Assembly.GetName().Name + ".dll"));
        start.ArgumentList.Add("--resource-fixture");
        start.ArgumentList.Add(mode);
        start.Environment[FixtureDirectoryVariable] = directory;
        return start;
    }

    private static async Task WithFixtureAsync(string mode, Func<ProcessStartInfo, string, Task> action)
    {
        string directory = NewDirectory();
        try { await action(CreateFixtureStartInfo(mode, directory), directory); }
        finally
        {
            // A failed assertion must still leave only these recorded synthetic processes stopped.
            foreach (var name in new[] { "fixture.pid", "descendant.pid" })
            {
                using var process = FindRecordedProcess(directory, name);
                if (process is not null) { try { process.Kill(entireProcessTree: true); await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3)); } catch { } }
            }
            DeleteDirectory(directory);
        }
    }

    private static async Task AssertFixtureExitedAsync(string directory, bool descendantRequired)
    {
        await WaitForRecordAsync(directory, "fixture.pid");
        if (descendantRequired) await WaitForRecordAsync(directory, "descendant.pid");
        foreach (var name in new[] { "fixture.pid", "descendant.pid" })
        {
            using var process = FindRecordedProcess(directory, name);
            if (process is null) continue;
            await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3));
            Require(process.HasExited, "owned synthetic child remains after request cleanup");
        }
    }

    private static Process? FindRecordedProcess(string directory, string name)
    {
        CheckDirectory(directory);
        string path = Path.Combine(directory, name);
        if (!File.Exists(path)) return null;
        var parts = File.ReadAllText(path).Split(':');
        Require(parts.Length == 2 && int.TryParse(parts[0], out _) && long.TryParse(parts[1], out _), "synthetic PID record");
        try
        {
            var process = Process.GetProcessById(int.Parse(parts[0]));
            if (process.StartTime.ToUniversalTime().Ticks == long.Parse(parts[1]) && !process.HasExited) return process;
            process.Dispose();
        }
        catch (ArgumentException) { }
        catch (InvalidOperationException) { }
        return null;
    }

    private static async Task WaitForRecordAsync(string directory, string name)
    {
        CheckDirectory(directory);
        var deadline = Stopwatch.StartNew();
        string path = Path.Combine(directory, name);
        while (!File.Exists(path) || new FileInfo(path).Length == 0)
        {
            if (deadline.Elapsed > TimeSpan.FromSeconds(5)) throw new InvalidOperationException("Synthetic fixture did not become ready");
            await Task.Delay(20);
        }
    }

    private static string NewDirectory()
    {
        string directory = Path.Combine(Path.GetTempPath(), DirectoryPrefix + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        CheckDirectory(directory);
        return directory;
    }

    private static void CheckDirectory(string directory)
    {
        string full = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string temporary = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        Require(Path.GetFileName(full).StartsWith(DirectoryPrefix, StringComparison.Ordinal)
            && string.Equals(Path.GetDirectoryName(full), temporary, StringComparison.OrdinalIgnoreCase)
            && Directory.Exists(full) && (File.GetAttributes(full) & FileAttributes.ReparsePoint) == 0,
            "fixture stays in its own synthetic temporary directory");
    }

    private static void DeleteDirectory(string directory)
    {
        CheckDirectory(directory);
        Directory.Delete(Path.GetFullPath(directory), recursive: true);
    }

    private static string ReadSmallLog(string path, int maximumBytes)
    {
        Require(File.Exists(path) && new FileInfo(path).Length <= maximumBytes, "log byte limit before reading");
        return File.ReadAllText(path, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true));
    }

    private static void AssertLogBounds(string path, int maximumBytes)
    {
        Require(File.Exists(path), "active log exists");
        foreach (var file in new[] { path, path + ".1" })
            if (File.Exists(file)) _ = ReadSmallLog(file, maximumBytes);
        Require(!File.Exists(path + ".2"), "only one log backup");
    }

    private static void MakeSparseFile(string path, long length)
    {
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None);
        const uint fsctlSetSparse = 0x000900C4;
        Require(DeviceIoControl(stream.SafeFileHandle, fsctlSetSparse, IntPtr.Zero, 0, IntPtr.Zero, 0, out _, IntPtr.Zero),
            "sparse fixture must be supported before assigning a large logical length");
        stream.SetLength(length);
    }

    private static async Task ExpectAsync<T>(Func<Task> action) where T : Exception
    {
        try { await action(); }
        catch (T error)
        {
            Require(!error.ToString().Contains(PrivateMarker, StringComparison.Ordinal), "raw synthetic stderr must not escape");
            return;
        }
        throw new InvalidOperationException($"Expected synthetic failure {typeof(T).Name}");
    }

    private static async Task ExpectTimeoutAsync(Func<Task> action)
    {
        try { await action(); }
        catch (TimeoutException) { return; }
        catch (ProviderQueryException error) when (error.Failure == ProviderFailure.Timeout) { return; }
        throw new InvalidOperationException("Expected bounded synthetic request timeout");
    }

    private static async Task ExpectProviderFailureAsync(Func<Task> action, ProviderFailure expected)
    {
        try { await action(); }
        catch (ProviderQueryException error) when (error.Failure == expected)
        {
            Require(!error.ToString().Contains(PrivateMarker, StringComparison.Ordinal), "raw synthetic stderr must not escape");
            return;
        }
        throw new InvalidOperationException("Expected synthetic provider failure " + expected);
    }

    private static void Require(bool condition, string name)
    {
        if (!condition) throw new InvalidOperationException("Resource safety self test failed: " + name);
    }

    private sealed class GeneratedTextReader(int length) : TextReader
    {
        public int ReadCount { get; private set; }
        public override int Read(char[] buffer, int index, int count) => Fill(buffer.AsSpan(index, count));
        public override int Read(Span<char> buffer) => Fill(buffer);
        public override ValueTask<int> ReadAsync(Memory<char> buffer, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(Fill(buffer.Span));
        }
        private int Fill(Span<char> buffer)
        {
            int count = Math.Min(buffer.Length, length - ReadCount);
            buffer[..count].Fill('x');
            ReadCount += count;
            return count;
        }
    }

    private sealed class WaitingTextReader : TextReader
    {
        public bool ObservedCancellation { get; private set; }
        public override async ValueTask<int> ReadAsync(Memory<char> buffer, CancellationToken cancellationToken = default)
        {
            try { await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken); }
            catch (OperationCanceledException) { ObservedCancellation = cancellationToken.IsCancellationRequested; throw; }
            return 0;
        }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeviceIoControl(SafeFileHandle handle, uint code, IntPtr input, int inputSize,
        IntPtr output, int outputSize, out int returned, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
}

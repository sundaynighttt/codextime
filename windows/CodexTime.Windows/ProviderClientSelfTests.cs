using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace CodexTime.WinApp;

// Every credential and database below is synthetic and isolated under a fresh
// temporary directory. No production constructor, login or network is used.
public static class ProviderClientSelfTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1800000000);
    private static string Token(long expiry = 4102444800) => "fixture." + Convert.ToBase64String(
        Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { exp = expiry }))).TrimEnd('=')
        .Replace('+', '-').Replace('/', '_') + ".synthetic";

    public static async Task RunAsync()
    {
        CredentialAndQuotaParsers();
        await HttpContractsAsync();
        await WindowsStorageAsync();
    }

    private static void CredentialAndQuotaParsers()
    {
        byte[] Credential(object expires, string[] scopes, string token = "synthetic-access") => JsonSerializer.SerializeToUtf8Bytes(
            new { claudeAiOauth = new { accessToken = token, expiresAt = expires, scopes } });
        var valid = WindowsClaudeCredentialSource.Parse(Credential(Now.AddHours(1).ToUnixTimeMilliseconds(), ["user:profile"]), Now);
        Require(valid.AccessToken == "synthetic-access" && !valid.ToString().Contains("synthetic-access"));
        ExpectFailure(() => WindowsClaudeCredentialSource.Parse(Credential(Now.ToUnixTimeMilliseconds(), ["user:profile"]), Now), ProviderFailure.AuthenticationRequired);
        ExpectFailure(() => WindowsClaudeCredentialSource.Parse(Credential(true, ["user:profile"]), Now), ProviderFailure.AuthenticationRequired);
        ExpectFailure(() => WindowsClaudeCredentialSource.Parse(Credential(Now.AddHours(1).ToUnixTimeMilliseconds(), ["inference"]), Now), ProviderFailure.Unsupported);
        ExpectFailure(() => WindowsClaudeCredentialSource.Parse(Credential(Now.AddHours(1).ToUnixTimeMilliseconds(), ["user:profile"], "bad\nvalue"), Now), ProviderFailure.AuthenticationRequired);
        ExpectFailure(() => WindowsClaudeCredentialSource.Parse(new byte[65537], Now), ProviderFailure.AuthenticationRequired);
        Require(WindowsCursorCredentialSource.ParseToken(Token(), Now).ExpiresAt.Year == 2100);
        ExpectFailure(() => WindowsCursorCredentialSource.ParseToken(Token(Now.ToUnixTimeSeconds()), Now), ProviderFailure.AuthenticationRequired);
        ExpectFailure(() => WindowsCursorCredentialSource.ParseToken("not-a-token", Now), ProviderFailure.AuthenticationRequired);

        var claude = ClaudeUsageProviderClient.Parse(Encoding.UTF8.GetBytes("""
            {"five_hour":{"utilization":10.1,"resets_at":"2026-10-20T12:00:00Z"},
             "seven_day":{"utilization":80},"seven_day_sonnet":{"utilization":100},
             "identity":"ignored","credits":{"balance":0}}
            """));
        Require(claude.DisplayRemainingPercent == 20 && claude.Windows[0].DisplayRemainingPercent == 89
            && claude.Windows.Count == 3 && claude.Windows[0].ResetsAt.HasValue);
        var unknown = ClaudeUsageProviderClient.Parse(Encoding.UTF8.GetBytes("{\"five_hour\":{\"utilization\":true}}"));
        Require(unknown.DisplayRemainingPercent is null);
        ExpectFailure(() => ClaudeUsageProviderClient.Parse(Encoding.UTF8.GetBytes("{\"credits\":100}")), ProviderFailure.InvalidResponse);
        var grok = GrokUsageProviderClient.Parse(Encoding.UTF8.GetBytes("{\"usagePercent\":40.1,\"isUnified\":true,\"nextResetTimestampUtc\":\"2026-10-21T01:00:00Z\"}"));
        Require(grok.DisplayRemainingPercent == 59 && grok.DisplayWindow!.Label == "공유 주간 한도");
        ExpectFailure(() => GrokUsageProviderClient.Parse(Encoding.UTF8.GetBytes("{\"usagePercent\":-1}")), ProviderFailure.InvalidResponse);
        ExpectFailure(() => GrokUsageProviderClient.Parse(Encoding.UTF8.GetBytes("{\"usagePercent\":1,\"isUnified\":\"yes\"}")), ProviderFailure.InvalidResponse);
        ExpectFailure(() => GrokUsageProviderClient.Parse(Encoding.UTF8.GetBytes("{\"usagePercent\":1,\"usesPooledEnterpriseAllowance\":true}")), ProviderFailure.Unsupported);
        ExpectFailure(() => GrokUsageProviderClient.Parse(Encoding.UTF8.GetBytes("{\"balance\":10}")), ProviderFailure.InvalidResponse);
    }

    private static async Task HttpContractsAsync()
    {
        int calls = 0;
        var credential = new SyntheticCredentials();
        var claudeTransport = new UsageHttpTransport(() => new SyntheticHandler(async (request, token) =>
        {
            calls++;
            Require(request.RequestUri == ClaudeUsageProviderClient.Endpoint && request.Method == HttpMethod.Get
                && request.Content is null && request.Headers.Authorization?.Scheme == "Bearer");
            Require(request.Headers.GetValues("anthropic-beta").Single() == "oauth-2025-04-20");
            await Task.Yield();
            return new(HttpStatusCode.OK) { Content = new StringContent("{\"seven_day\":{\"utilization\":22}}") };
        }));
        Require((await new ClaudeUsageProviderClient(credential, claudeTransport).FetchAsync()).DisplayRemainingPercent == 78);
        var grokTransport = new UsageHttpTransport(() => new SyntheticHandler(async (request, token) =>
        {
            calls++;
            Require(request.RequestUri == GrokUsageProviderClient.Endpoint && request.Method == HttpMethod.Post
                && await request.Content!.ReadAsStringAsync(token) == "{}"
                && request.Headers.GetValues("Connect-Protocol-Version").Single() == "1");
            return new(HttpStatusCode.OK) { Content = new StringContent("{\"usagePercent\":3}") };
        }));
        Require((await new GrokUsageProviderClient(credential, grokTransport).FetchAsync()).DisplayRemainingPercent == 97 && calls == 2);
        foreach (var (status, expected) in new[] { (HttpStatusCode.Unauthorized, ProviderFailure.AuthenticationRequired),
            (HttpStatusCode.Forbidden, ProviderFailure.AuthenticationRequired), (HttpStatusCode.TemporaryRedirect, ProviderFailure.QueryFailed),
            (HttpStatusCode.TooManyRequests, ProviderFailure.QueryFailed), (HttpStatusCode.GatewayTimeout, ProviderFailure.Timeout) })
        {
            var transport = new UsageHttpTransport(() => new SyntheticHandler((_, _) => Task.FromResult(new HttpResponseMessage(status)
                { Content = new ThrowIfReadContent() })));
            await ExpectFailureAsync(() => new ClaudeUsageProviderClient(credential, transport).FetchAsync(), expected);
        }
        var oversized = new UsageHttpTransport(() => new SyntheticHandler((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            { Content = new ByteArrayContent(new byte[262145]) })));
        await ExpectFailureAsync(() => new ClaudeUsageProviderClient(credential, oversized).FetchAsync(), ProviderFailure.InvalidResponse);
        var streaming = new UsageHttpTransport(() => new SyntheticHandler((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            { Content = new StreamContent(new MemoryStream(new byte[262145])) })));
        await ExpectFailureAsync(() => new ClaudeUsageProviderClient(credential, streaming).FetchAsync(), ProviderFailure.InvalidResponse);
        var waiting = new UsageHttpTransport(() => new SyntheticHandler(async (_, token) =>
        { await Task.Delay(Timeout.InfiniteTimeSpan, token); return new(HttpStatusCode.OK); }));
        using (var request = new HttpRequestMessage(HttpMethod.Get, ClaudeUsageProviderClient.Endpoint))
            await ExpectFailureAsync(() => waiting.SendAsync(request, 1024, TimeSpan.FromMilliseconds(30), CancellationToken.None), ProviderFailure.Timeout);
        using (var activeCancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(30)))
        using (var request = new HttpRequestMessage(HttpMethod.Get, ClaudeUsageProviderClient.Endpoint))
        {
            try
            {
                await waiting.SendAsync(request, 1024, TimeSpan.FromSeconds(2), activeCancellation.Token);
                throw new InvalidOperationException("Active cancellation not propagated");
            }
            catch (OperationCanceledException) when (activeCancellation.IsCancellationRequested) { }
        }
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try { await new GrokUsageProviderClient(credential, grokTransport).FetchAsync(cancelled.Token); throw new InvalidOperationException("Cancellation not propagated"); }
        catch (OperationCanceledException) { }
        using var badDestination = new HttpRequestMessage(HttpMethod.Get, "https://example.invalid/");
        await ExpectFailureAsync(() => claudeTransport.SendAsync(badDestination, 1024, TimeSpan.FromSeconds(1), default), ProviderFailure.Unsupported);
    }

    private static async Task WindowsStorageAsync()
    {
        if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("Native Windows storage tests must run on Windows");
        string directory = Path.Combine(Path.GetTempPath(), "codextime-provider-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        Process? writer = null;
        try
        {
            foreach (var (provider, extension, expected) in new[]
            {
                (UsageProviderID.Codex, ".cmd", "login"),
                (UsageProviderID.Claude, ".bat", "auth login")
            })
            {
                // Exercise the Windows OS association and argument delivery with
                // our own inert script. Never invoke an installed login client.
                string script = Path.Combine(directory, "synthetic-login" + extension);
                string received = Path.Combine(directory, "received-arguments.txt");
                await File.WriteAllTextAsync(script, "@echo off\r\necho %1 %2>\"%~dp0received-arguments.txt\"\r\n");
                var launch = ProviderLoginService.CreateLoginStartInfo(provider, script);
                launch.WindowStyle = ProcessWindowStyle.Hidden;
                using var process = Process.Start(launch) ?? throw new InvalidOperationException("Synthetic shell launch failed");
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                try { await process.WaitForExitAsync(timeout.Token); }
                catch { try { process.Kill(entireProcessTree: true); } catch { } throw; }
                Require(process.ExitCode == 0 && (await File.ReadAllTextAsync(received)).Trim() == expected);
                File.Delete(received);
            }
            string claudePath = Path.Combine(directory, "synthetic-credentials.json");
            await File.WriteAllBytesAsync(claudePath, JsonSerializer.SerializeToUtf8Bytes(new { claudeAiOauth = new
                { accessToken = "synthetic-access", expiresAt = DateTimeOffset.UtcNow.AddHours(1).ToUnixTimeMilliseconds(), scopes = new[] { "user:profile" } } }));
            Require((await new WindowsClaudeCredentialSource(claudePath).LoadAsync(DateTimeOffset.UtcNow, default)).AccessToken == "synthetic-access");
            string absent = Path.Combine(directory, "missing.vscdb");
            await ExpectFailureAsync(() => new WindowsCursorCredentialSource(absent).LoadAsync(Now, default), ProviderFailure.AuthenticationRequired);
            Require(!File.Exists(absent));
            string partial = Path.Combine(directory, "partial.vscdb");
            await File.WriteAllBytesAsync(partial, Encoding.ASCII.GetBytes("synthetic database marker"));
            await File.WriteAllBytesAsync(partial + "-wal", Encoding.ASCII.GetBytes("synthetic WAL marker"));
            var partialHashes = HashFiles(partial, partial + "-wal");
            await ExpectFailureAsync(() => new WindowsCursorCredentialSource(partial).LoadAsync(Now, default), ProviderFailure.Unsupported);
            Require(!File.Exists(partial + "-shm") && partialHashes.SequenceEqual(HashFiles(partial, partial + "-wal")));
            string rollback = Path.Combine(directory, "rollback.vscdb");
            using (var connection = new SqliteConnection($"Data Source={rollback};Pooling=False"))
            { connection.Open(); using var command = connection.CreateCommand(); command.CommandText = "CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT)"; command.ExecuteNonQuery(); }
            await ExpectFailureAsync(() => new WindowsCursorCredentialSource(rollback).LoadAsync(Now, default), ProviderFailure.Unsupported);
            Require(!File.Exists(rollback + "-shm") && !File.Exists(rollback + "-wal"));

            var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
            start.ArgumentList.Add("--provider-wal-fixture"); start.ArgumentList.Add(directory);
            writer = Process.Start(start) ?? throw new InvalidOperationException("Fixture process failed");
            using var readyTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(25));
            Require(await writer.StandardOutput.ReadLineAsync(readyTimeout.Token) == "fixture-ready");
            string database = Path.Combine(directory, "state.vscdb");
            var before = HashFiles(database, database + "-wal", database + "-shm");
            var result = await new WindowsCursorCredentialSource(database).LoadAsync(Now, default);
            Require(result.AccessToken == Token() && before.SequenceEqual(HashFiles(database, database + "-wal", database + "-shm")));
            await writer.StandardInput.WriteLineAsync("view"); await writer.StandardInput.FlushAsync();
            Require(await writer.StandardOutput.ReadLineAsync(readyTimeout.Token) == "fixture-view-ready");
            before = HashFiles(database, database + "-wal", database + "-shm");
            await ExpectFailureAsync(() => new WindowsCursorCredentialSource(database).LoadAsync(Now, default), ProviderFailure.InvalidResponse);
            Require(before.SequenceEqual(HashFiles(database, database + "-wal", database + "-shm")));
            // A real directory junction is a reparse point and must be rejected,
            // even when it ultimately points back into our synthetic directory.
            string junction = Path.Combine(directory, "junction");
            var junctionStart = new ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true };
            junctionStart.ArgumentList.Add("/d"); junctionStart.ArgumentList.Add("/c");
            junctionStart.ArgumentList.Add("mklink"); junctionStart.ArgumentList.Add("/J");
            junctionStart.ArgumentList.Add(junction); junctionStart.ArgumentList.Add(directory);
            using (var command = Process.Start(junctionStart)!) { await command.WaitForExitAsync(); Require(command.ExitCode == 0); }
            try { await ExpectFailureAsync(() => new WindowsCursorCredentialSource(Path.Combine(junction, "state.vscdb")).LoadAsync(Now, default), ProviderFailure.Unsupported); }
            finally { Directory.Delete(junction); }
        }
        finally
        {
            if (writer is not null)
            {
                writer.StandardInput.Close();
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                try { await writer.WaitForExitAsync(timeout.Token); }
                catch { try { writer.Kill(entireProcessTree: true); } catch { } }
                writer.Dispose();
            }
            Directory.Delete(directory, recursive: true);
        }
    }

    public static async Task RunWalFixtureAsync(string directory)
    {
        var full = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar);
        if (!Path.GetFileName(full).StartsWith("codextime-provider-tests-", StringComparison.Ordinal)
            || !string.Equals(Path.GetDirectoryName(full)?.TrimEnd('\\'), Path.GetFullPath(Path.GetTempPath()).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)
            || !Directory.Exists(full) || (File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidOperationException("Invalid synthetic fixture directory");
        string database = Path.Combine(full, "state.vscdb");
        if (File.Exists(database)) throw new InvalidOperationException("Fixture must be new");
        using var connection = new SqliteConnection($"Data Source={database};Pooling=False");
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = "CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT); INSERT INTO ItemTable VALUES('cursorAuth/accessToken','old-synthetic-value'); PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;";
        command.ExecuteNonQuery();
        command.CommandText = "UPDATE ItemTable SET value=$token WHERE key='cursorAuth/accessToken'; INSERT INTO ItemTable VALUES('privateOtherKey','not-an-authorization');";
        command.Parameters.AddWithValue("$token", Token()); command.ExecuteNonQuery();
        Console.WriteLine("fixture-ready"); Console.Out.Flush();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        while (await Console.In.ReadLineAsync(deadline.Token) is { } instruction)
        {
            if (instruction != "view") throw new InvalidOperationException("Invalid synthetic fixture instruction");
            command.Parameters.Clear();
            command.CommandText = "DROP TABLE ItemTable; CREATE TABLE OtherTable(key TEXT, value TEXT); INSERT INTO OtherTable VALUES('cursorAuth/accessToken','private-other-value'); CREATE VIEW ItemTable AS SELECT key,value FROM OtherTable;";
            command.ExecuteNonQuery();
            Console.WriteLine("fixture-view-ready"); Console.Out.Flush();
        }
    }

    private static string[] HashFiles(params string[] paths) => paths.Select(path =>
    {
        // SQLite's separate writer already owns writable handles. The hash
        // observer must share those handles without requesting write access.
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        return Convert.ToHexString(SHA256.HashData(stream));
    }).ToArray();
    private static void Require(bool condition) { if (!condition) throw new InvalidOperationException("Synthetic provider assertion failed"); }
    private static void ExpectFailure(Action action, ProviderFailure expected)
    { try { action(); } catch (ProviderQueryException exception) when (exception.Failure == expected) { return; } throw new InvalidOperationException("Expected fixed provider failure"); }
    private static async Task ExpectFailureAsync(Func<Task> action, ProviderFailure expected)
    { try { await action(); } catch (ProviderQueryException exception) when (exception.Failure == expected) { return; } throw new InvalidOperationException("Expected fixed provider failure"); }
    private sealed class SyntheticCredentials : IUsageCredentialSource
    { public Task<UsageAuthorization> LoadAsync(DateTimeOffset now, CancellationToken cancellationToken) => Task.FromResult(new UsageAuthorization("synthetic-only", now.AddHours(1))); }
    private sealed class SyntheticHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> action) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => action(request, cancellationToken); }
    private sealed class ThrowIfReadContent : HttpContent
    {
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => throw new InvalidOperationException("Error body was read");
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
    }
}

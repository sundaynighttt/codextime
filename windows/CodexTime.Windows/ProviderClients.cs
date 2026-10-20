using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace CodexTime.WinApp;

public static class ProductionUsageProviders
{
    public static IUsageProviderClient Create(UsageProviderID id) => id switch
    {
        UsageProviderID.Codex => new CodexUsageProviderClient(),
        UsageProviderID.Grok => new GrokUsageProviderClient(),
        UsageProviderID.Claude => new ClaudeUsageProviderClient(),
        _ => throw new ProviderQueryException(ProviderFailure.Unsupported)
    };
}

public sealed class CodexUsageProviderClient : IUsageProviderClient
{
    public UsageProviderID Id => UsageProviderID.Codex;
    public async Task<ProviderUsageSnapshot> FetchAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var report = await new CodexAppServerClient().FetchAsync(cancellationToken);
            var windows = new List<ProviderUsageWindow>
            { new("primary", "기본 한도", report.Main.Primary.RemainingPercent, report.Main.Primary.ResetsAt) };
            if (report.Main.Secondary is { } secondary)
                windows.Add(new("secondary", "추가 한도", secondary.RemainingPercent, secondary.ResetsAt));
            return new(Id, windows);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (OperationCanceledException) { throw new ProviderQueryException(ProviderFailure.Timeout); }
        catch (ProviderQueryException) { throw; }
        catch (FileNotFoundException) { throw new ProviderQueryException(ProviderFailure.NotInstalled); }
        catch (TimeoutException) { throw new ProviderQueryException(ProviderFailure.Timeout); }
        catch { throw new ProviderQueryException(ProviderFailure.QueryFailed); }
    }
}

internal sealed class UsageAuthorization
{
    internal string AccessToken { get; }
    internal DateTimeOffset ExpiresAt { get; }
    internal UsageAuthorization(string accessToken, DateTimeOffset expiresAt)
    { AccessToken = accessToken; ExpiresAt = expiresAt; }
    public override string ToString() => "UsageAuthorization(redacted)";
}

internal interface IUsageCredentialSource
{
    Task<UsageAuthorization> LoadAsync(DateTimeOffset now, CancellationToken cancellationToken);
}

// This seam is used only for synthetic self tests. Production owns the handler;
// it never inherits browser cookies, a proxy credential, redirects or OS login.
internal interface IUsageHttpTransport
{
    Task<byte[]> SendAsync(HttpRequestMessage request, int maximumBytes, TimeSpan timeout,
        CancellationToken cancellationToken);
}

internal sealed class UsageHttpTransport : IUsageHttpTransport
{
    private readonly Func<HttpMessageHandler> _createHandler;
    internal UsageHttpTransport(Func<HttpMessageHandler>? syntheticHandler = null)
    {
        _createHandler = syntheticHandler ?? (() => new HttpClientHandler
        {
            AllowAutoRedirect = false, UseCookies = false, UseProxy = false,
            UseDefaultCredentials = false, Credentials = null, PreAuthenticate = false,
            AutomaticDecompression = DecompressionMethods.None
        });
    }
    public async Task<byte[]> SendAsync(HttpRequestMessage request, int maximumBytes, TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        if (request.RequestUri != ClaudeUsageProviderClient.Endpoint && request.RequestUri != GrokUsageProviderClient.Endpoint)
            throw new ProviderQueryException(ProviderFailure.Unsupported);
        using var handler = _createHandler();
        using var client = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(timeout);
        try
        {
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            // Never read error bodies. Authentication and all failures are fixed codes.
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                throw new ProviderQueryException(ProviderFailure.AuthenticationRequired);
            if (response.StatusCode is HttpStatusCode.RequestTimeout or HttpStatusCode.GatewayTimeout)
                throw new ProviderQueryException(ProviderFailure.Timeout);
            if (response.StatusCode != HttpStatusCode.OK)
                throw new ProviderQueryException(ProviderFailure.QueryFailed);
            if (response.Content.Headers.ContentLength is long size && size > maximumBytes)
                throw new ProviderQueryException(ProviderFailure.InvalidResponse);
            await using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var data = new MemoryStream();
            var buffer = new byte[4096];
            while (true)
            {
                int count = await stream.ReadAsync(buffer, deadline.Token);
                if (count == 0) break;
                if (data.Length + count > maximumBytes)
                    throw new ProviderQueryException(ProviderFailure.InvalidResponse);
                data.Write(buffer, 0, count);
            }
            return data.ToArray();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (OperationCanceledException) { throw new ProviderQueryException(ProviderFailure.Timeout); }
        catch (ProviderQueryException) { throw; }
        catch { throw new ProviderQueryException(ProviderFailure.QueryFailed); }
    }
}

public sealed class ClaudeUsageProviderClient : IUsageProviderClient
{
    internal static readonly Uri Endpoint = new("https://api.anthropic.com/api/oauth/usage");
    private readonly IUsageCredentialSource _credentials;
    private readonly IUsageHttpTransport _transport;
    public UsageProviderID Id => UsageProviderID.Claude;
    public ClaudeUsageProviderClient() : this(new WindowsClaudeCredentialSource(), new UsageHttpTransport()) { }
    internal ClaudeUsageProviderClient(IUsageCredentialSource credentials, IUsageHttpTransport transport)
    { _credentials = credentials; _transport = transport; }

    public async Task<ProviderUsageSnapshot> FetchAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var authorization = await _credentials.LoadAsync(DateTimeOffset.UtcNow, cancellationToken);
            if (authorization.ExpiresAt <= DateTimeOffset.UtcNow.AddSeconds(15))
                throw new ProviderQueryException(ProviderFailure.AuthenticationRequired);
            using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authorization.AccessToken);
            request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            var data = await _transport.SendAsync(request, 262144, TimeSpan.FromSeconds(8), cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            return Parse(data);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (ProviderQueryException) { throw; }
        catch { throw new ProviderQueryException(ProviderFailure.QueryFailed); }
    }

    internal static ProviderUsageSnapshot Parse(byte[] data)
    {
        try
        {
            if (data.Length > 262144) throw new JsonException();
            using var document = JsonDocument.Parse(data, new JsonDocumentOptions { MaxDepth = 32 });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new JsonException();
            var windows = new List<ProviderUsageWindow>();
            foreach (var (key, label, shared) in new[] { ("five_hour", "단기 한도", true),
                ("seven_day", "주간 한도", true), ("seven_day_sonnet", "Sonnet 주간 한도", false),
                ("seven_day_opus", "Opus 주간 한도", false) })
            {
                if (!root.TryGetProperty(key, out var value) || value.ValueKind != JsonValueKind.Object) continue;
                double? remaining = value.TryGetProperty("utilization", out var usage) && TryPercent(usage, out var used)
                    ? 100 - used : null;
                var reset = value.TryGetProperty("resets_at", out var time) ? ParseDate(time) : null;
                windows.Add(new(key, label, remaining, reset, shared));
            }
            if (windows.Count == 0) throw new JsonException();
            return new(UsageProviderID.Claude, windows);
        }
        catch { throw new ProviderQueryException(ProviderFailure.InvalidResponse); }
    }

    internal static bool TryPercent(JsonElement value, out double number)
    {
        number = 0;
        return value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out number)
            && double.IsFinite(number) && number is >= 0 and <= 100;
    }
    internal static DateTimeOffset? ParseDate(JsonElement value) => value.ValueKind == JsonValueKind.String
        && DateTimeOffset.TryParse(value.GetString(), CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var time) ? time : null;
}

public sealed class GrokUsageProviderClient : IUsageProviderClient
{
    internal static readonly Uri Endpoint = new("https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus");
    private readonly IUsageCredentialSource _credentials;
    private readonly IUsageHttpTransport _transport;
    public UsageProviderID Id => UsageProviderID.Grok;
    public GrokUsageProviderClient() : this(new WindowsCursorCredentialSource(), new UsageHttpTransport()) { }
    internal GrokUsageProviderClient(IUsageCredentialSource credentials, IUsageHttpTransport transport)
    { _credentials = credentials; _transport = transport; }

    public async Task<ProviderUsageSnapshot> FetchAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var authorization = await _credentials.LoadAsync(DateTimeOffset.UtcNow, cancellationToken);
            if (authorization.ExpiresAt <= DateTimeOffset.UtcNow.AddSeconds(30))
                throw new ProviderQueryException(ProviderFailure.AuthenticationRequired);
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
            request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authorization.AccessToken);
            request.Headers.TryAddWithoutValidation("Connect-Protocol-Version", "1");
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            var data = await _transport.SendAsync(request, 65536, TimeSpan.FromSeconds(10), cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            return Parse(data);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (ProviderQueryException) { throw; }
        catch { throw new ProviderQueryException(ProviderFailure.QueryFailed); }
    }

    internal static ProviderUsageSnapshot Parse(byte[] data)
    {
        try
        {
            if (data.Length > 65536) throw new JsonException();
            using var document = JsonDocument.Parse(data, new JsonDocumentOptions { MaxDepth = 16 });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new JsonException();
            foreach (var flag in new[] { "usesPooledEnterpriseAllowance", "isUnified" })
                if (root.TryGetProperty(flag, out var boolean) && boolean.ValueKind is not
                    (JsonValueKind.True or JsonValueKind.False or JsonValueKind.Null)) throw new JsonException();
            if (root.TryGetProperty("nextResetTimestampUtc", out var resetField) && resetField.ValueKind is not
                (JsonValueKind.String or JsonValueKind.Null)) throw new JsonException();
            if (root.TryGetProperty("usesPooledEnterpriseAllowance", out var pooled) && pooled.ValueKind == JsonValueKind.True)
                throw new ProviderQueryException(ProviderFailure.Unsupported);
            if (!root.TryGetProperty("usagePercent", out var usage) || !ClaudeUsageProviderClient.TryPercent(usage, out var used))
                throw new JsonException();
            var reset = root.TryGetProperty("nextResetTimestampUtc", out var time) ? ClaudeUsageProviderClient.ParseDate(time) : null;
            bool unified = root.TryGetProperty("isUnified", out var shared) && shared.ValueKind == JsonValueKind.True;
            return new(UsageProviderID.Grok, [new("weekly", unified ? "공유 주간 한도" : "Grok Bot 주간 한도", 100 - used, reset)]);
        }
        catch (ProviderQueryException) { throw; }
        catch { throw new ProviderQueryException(ProviderFailure.InvalidResponse); }
    }
}

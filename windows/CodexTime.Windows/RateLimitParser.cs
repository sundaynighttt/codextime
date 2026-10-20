using System.Text.Json;

namespace CodexTime.WinApp;

public static class RateLimitParser
{
    public static RateLimitReport? ParseResponseLine(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        if (root.TryGetProperty("error", out var error) && error.ValueKind != JsonValueKind.Null)
        {
            throw new ProviderQueryException(ProviderFailure.QueryFailed);
        }

        if (!root.TryGetProperty("result", out var result) || result.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        if (!result.TryGetProperty("rateLimits", out var fallback) || fallback.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var snapshots = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        if (result.TryGetProperty("rateLimitsByLimitId", out var byLimit) &&
            byLimit.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in byLimit.EnumerateObject())
            {
                snapshots[property.Name] = property.Value.Clone();
            }
        }

        var fallbackId = GetOptionalString(fallback, "limitId") ?? "codex";
        snapshots.TryAdd(fallbackId, fallback.Clone());

        var buckets = snapshots
            .Select(entry => ParseBucket(entry.Key, entry.Value))
            .Where(bucket => bucket is not null)
            .Cast<RateLimitBucket>()
            .OrderBy(bucket => bucket.Id.Equals("codex", StringComparison.OrdinalIgnoreCase) ? 0 : 1)
            .ThenBy(bucket => bucket.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (buckets.Length == 0)
        {
            throw new InvalidOperationException("Codex 사용량 응답에 표시할 한도가 없습니다.");
        }

        var main = buckets.FirstOrDefault(bucket =>
            bucket.Id.Equals("codex", StringComparison.OrdinalIgnoreCase)) ?? buckets[0];
        return new RateLimitReport(main, buckets);
    }

    private static RateLimitBucket? ParseBucket(string entryId, JsonElement snapshot)
    {
        if (snapshot.ValueKind != JsonValueKind.Object ||
            !snapshot.TryGetProperty("primary", out var primaryElement) ||
            primaryElement.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var id = GetOptionalString(snapshot, "limitId") ?? entryId;
        var name = id.Equals("codex", StringComparison.OrdinalIgnoreCase)
            ? "Codex"
            : GetOptionalString(snapshot, "limitName") ?? id;

        var primary = ParseWindow(primaryElement);
        LimitWindow? secondary = null;
        if (snapshot.TryGetProperty("secondary", out var secondaryElement) &&
            secondaryElement.ValueKind == JsonValueKind.Object)
        {
            secondary = ParseWindow(secondaryElement);
        }

        return new RateLimitBucket(id, name, primary, secondary);
    }

    private static LimitWindow ParseWindow(JsonElement window)
    {
        if (!window.TryGetProperty("usedPercent", out var used) || used.ValueKind != JsonValueKind.Number
            || !used.TryGetDouble(out var usedPercent) || !double.IsFinite(usedPercent)
            || usedPercent is < 0 or > 100)
            throw new ProviderQueryException(ProviderFailure.InvalidResponse);
        var remaining = (int)Math.Floor(100d - usedPercent);

        DateTimeOffset? resetsAt = null;
        if (window.TryGetProperty("resetsAt", out var reset) && reset.TryGetInt64(out var unixSeconds))
        {
            try { resetsAt = DateTimeOffset.FromUnixTimeSeconds(unixSeconds).ToLocalTime(); }
            catch (ArgumentOutOfRangeException) { throw new ProviderQueryException(ProviderFailure.InvalidResponse); }
        }

        return new LimitWindow(remaining, resetsAt);
    }

    private static string? GetOptionalString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
}

public static class RateLimitParserSelfTest
{
    public static void Run()
    {
        const string sample = """
            {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":6,"resetsAt":1788312070},"secondary":{"usedPercent":41,"resetsAt":1787792400}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":6,"resetsAt":1788312070},"secondary":{"usedPercent":41,"resetsAt":1787792400}},"spark":{"limitId":"spark","limitName":"GPT Spark","primary":{"usedPercent":0}}}}}
            """;

        var report = RateLimitParser.ParseResponseLine(sample)
            ?? throw new InvalidOperationException("Parser returned no report.");
        if (report.Main.Primary.RemainingPercent != 94 || report.Main.Secondary?.RemainingPercent != 59)
        {
            throw new InvalidOperationException("Parser percentage conversion failed.");
        }
        if (report.Buckets.Count != 2 || report.Buckets[1].Name != "GPT Spark")
        {
            throw new InvalidOperationException("Parser bucket ordering failed.");
        }
        if (RateLimitParser.ParseResponseLine("{\"method\":\"account/rateLimits/updated\"}") is not null)
        {
            throw new InvalidOperationException("Parser accepted a notification without a result.");
        }

        foreach (var invalid in new[] { "{}", "{\"usedPercent\":true}", "{\"usedPercent\":\"2\"}",
            "{\"usedPercent\":-1}", "{\"usedPercent\":101}" })
        {
            var rejected = false;
            try { RateLimitParser.ParseResponseLine("{\"id\":2,\"result\":{\"rateLimits\":{\"primary\":" + invalid + "}}}"); }
            catch (ProviderQueryException error) when (error.Failure == ProviderFailure.InvalidResponse) { rejected = true; }
            if (!rejected) throw new InvalidOperationException("Parser accepted an invalid percentage.");
        }
        var fractional = RateLimitParser.ParseResponseLine("{\"id\":2,\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":6.2}}}}")!;
        if (fractional.Main.Primary.RemainingPercent != 93)
            throw new InvalidOperationException("Parser overstated a fractional remaining quota.");
    }
}

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
            var message = error.TryGetProperty("message", out var errorMessage)
                ? errorMessage.GetString()
                : error.GetRawText();
            throw new InvalidOperationException($"Codex 응답 오류: {message}");
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
        var usedPercent = window.TryGetProperty("usedPercent", out var used) && used.TryGetDouble(out var value)
            ? value
            : 0d;
        var remaining = (int)Math.Round(Math.Clamp(100d - usedPercent, 0d, 100d));

        DateTimeOffset? resetsAt = null;
        if (window.TryGetProperty("resetsAt", out var reset) && reset.TryGetInt64(out var unixSeconds))
        {
            resetsAt = DateTimeOffset.FromUnixTimeSeconds(unixSeconds).ToLocalTime();
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
    }
}

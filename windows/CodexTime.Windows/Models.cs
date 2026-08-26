namespace CodexTime.WinApp;

public sealed record LimitWindow(int RemainingPercent, DateTimeOffset? ResetsAt);

public sealed record RateLimitBucket(
    string Id,
    string Name,
    LimitWindow Primary,
    LimitWindow? Secondary);

public sealed record RateLimitReport(
    RateLimitBucket Main,
    IReadOnlyList<RateLimitBucket> Buckets);

public enum DisplayMode
{
    TaskbarLabel,
    FloatingPill
}

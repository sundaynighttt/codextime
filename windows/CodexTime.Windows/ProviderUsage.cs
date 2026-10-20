namespace CodexTime.WinApp;

public enum UsageProviderID { Codex, Grok, Claude }

public static class UsageProviders
{
    public static readonly UsageProviderID[] All = [UsageProviderID.Codex, UsageProviderID.Grok, UsageProviderID.Claude];
    public static string Name(this UsageProviderID id) => id.ToString();
}

public sealed record ProviderUsageWindow(string Id, string Label, double? RemainingPercent,
    DateTimeOffset? ResetsAt = null, bool CountsTowardSummary = true)
{
    public int? DisplayRemainingPercent => RemainingPercent is double number && double.IsFinite(number)
        && number is >= 0 and <= 100 ? (int)Math.Floor(number) : null;
}

public sealed record ProviderUsageSnapshot(UsageProviderID Provider, IReadOnlyList<ProviderUsageWindow> Windows)
{
    public ProviderUsageWindow? DisplayWindow => Windows.Where(window => window.CountsTowardSummary
        && window.DisplayRemainingPercent.HasValue).OrderBy(window => window.RemainingPercent).FirstOrDefault();
    public int? DisplayRemainingPercent => DisplayWindow?.DisplayRemainingPercent;
}

public enum ProviderFailure { NotInstalled, NotConnected, AuthenticationRequired, PermissionRequired,
    Unsupported, Timeout, InvalidResponse, QueryFailed }

public static class ProviderFailures
{
    public static string Message(this ProviderFailure failure) => failure switch
    {
        ProviderFailure.NotInstalled => "공식 앱 또는 CLI를 설치해 주세요.",
        ProviderFailure.NotConnected => "간편 설정에서 계정을 연결해 주세요.",
        ProviderFailure.AuthenticationRequired => "공식 앱 또는 CLI에 다시 로그인해 주세요.",
        ProviderFailure.PermissionRequired => "사용량 조회 권한을 확인해 주세요.",
        ProviderFailure.Unsupported => "현재 로그인 또는 저장소 형식을 지원하지 않습니다.",
        ProviderFailure.Timeout => "사용량 조회 시간이 초과됐습니다.",
        ProviderFailure.InvalidResponse => "잔여 한도 응답을 확인하지 못했습니다.",
        _ => "사용량을 조회하지 못했습니다. 다시 시도해 주세요."
    };
}

public sealed class ProviderQueryException(ProviderFailure failure) : Exception(failure.Message())
{
    public ProviderFailure Failure { get; } = failure;
}

public sealed class ProviderUsageState(UsageProviderID id)
{
    public UsageProviderID Id { get; } = id;
    public ProviderUsageSnapshot? Snapshot { get; set; }
    public DateTimeOffset? LastSuccess { get; set; }
    public DateTimeOffset? LastAttempt { get; set; }
    public ProviderFailure? Failure { get; set; } = ProviderFailure.NotConnected;
    public bool IsRefreshing { get; set; }
    public bool AwaitingVerification { get; set; }
    public string? Error => Failure?.Message();
    public int? DisplayRemainingPercent => Snapshot?.DisplayRemainingPercent;
    public bool IsStale => LastSuccess is not null && (Failure is not null
        || DateTimeOffset.UtcNow - LastSuccess > TimeSpan.FromMinutes(20));
}

public interface IUsageProviderClient
{
    UsageProviderID Id { get; }
    Task<ProviderUsageSnapshot> FetchAsync(CancellationToken cancellationToken = default);
}

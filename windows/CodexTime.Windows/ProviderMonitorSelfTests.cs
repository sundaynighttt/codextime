namespace CodexTime.WinApp;

// No files, credentials, network, browser or real CLI are touched by these tests.
public static class ProviderMonitorSelfTests
{
    public static async Task RunAsync()
    {
        await ConsentAndDefaults();
        await IndependentProvidersAndFailureRetention();
        await SingleFlight();
        await HiddenWorkerCannotPublishOrOverlap();
        await DisconnectRevokesAndRejectsLateResult();
        await GrokRequiresExplicitWebVerification();
        await GrokRejectsMissingResetAndChangedCandidate();
    }

    private static async Task ConsentAndDefaults()
    {
        var settings = new AppSettings();
        var calls = new Counter();
        using var monitor = new ProviderMonitor(settings, id =>
        {
            calls.Add(id);
            return new ImmediateClient(id, Snapshot(id, 71));
        }, () => { });
        Check(UsageProviders.All.All(id => settings.Preferences(id).Enabled), "three providers visible by default");
        Check(!settings.ShowResetTime, "reset hidden by default");
        Check(new ProviderUsageState(UsageProviderID.Claude) { LastSuccess = DateTimeOffset.UtcNow.AddMinutes(-21) }.IsStale,
            "values older than twenty minutes are stale");
        await monitor.RefreshAllAsync();
        await monitor.RefreshAsync(UsageProviderID.Claude, interactive: true);
        await monitor.RefreshAsync(UsageProviderID.Grok, interactive: true);
        Check(calls.Get(UsageProviderID.Codex) == 1, "legacy Codex auto query");
        Check(calls.Get(UsageProviderID.Claude) == 0 && calls.Get(UsageProviderID.Grok) == 0,
            "no provider construction before consent, even interactive refresh");
        Check(monitor.States.Single(state => state.Id == UsageProviderID.Claude).Failure == ProviderFailure.NotConnected,
            "disconnected state retained");
    }

    private static async Task IndependentProvidersAndFailureRetention()
    {
        var settings = Connected();
        var blocked = new ControlledClient(UsageProviderID.Codex);
        var claudeCalls = 0;
        using var monitor = new ProviderMonitor(settings, id => id switch
        {
            UsageProviderID.Codex => blocked,
            UsageProviderID.Claude when Interlocked.Increment(ref claudeCalls) == 1 => new ImmediateClient(id, Snapshot(id, 81)),
            UsageProviderID.Claude => new FailureClient(id),
            _ => new ImmediateClient(id, Snapshot(id, 62))
        }, () => { });
        var slow = monitor.RefreshAsync(UsageProviderID.Codex);
        await blocked.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await monitor.RefreshAsync(UsageProviderID.Claude).WaitAsync(TimeSpan.FromSeconds(3));
        Check(!slow.IsCompleted, "Claude does not wait for slow Codex");
        var first = monitor.States.Single(state => state.Id == UsageProviderID.Claude);
        Check(first.DisplayRemainingPercent == 81 && first.LastSuccess is not null, "independent successful snapshot");
        await monitor.RefreshAsync(UsageProviderID.Claude);
        var failed = monitor.States.Single(state => state.Id == UsageProviderID.Claude);
        Check(failed.DisplayRemainingPercent == 81 && failed.LastSuccess == first.LastSuccess,
            "failure retains last confirmed values and time");
        Check(failed.Failure == ProviderFailure.QueryFailed && failed.IsStale
            && !failed.Error!.Contains("sensitive synthetic error"), "fixed failure, old value is stale");
        blocked.Complete(54);
        await slow;
    }

    private static async Task SingleFlight()
    {
        var settings = Connected();
        var client = new ControlledClient(UsageProviderID.Claude);
        int created = 0;
        using var monitor = new ProviderMonitor(settings, id =>
        {
            Interlocked.Increment(ref created);
            return client;
        }, () => { });
        var one = monitor.RefreshAsync(UsageProviderID.Claude);
        await client.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var two = monitor.RefreshAsync(UsageProviderID.Claude);
        Check(ReferenceEquals(one, two) && created == 1, "single flight per provider");
        client.Complete(42);
        await Task.WhenAll(one, two);
    }

    private static async Task HiddenWorkerCannotPublishOrOverlap()
    {
        var settings = Connected();
        var first = new ControlledClient(UsageProviderID.Claude);
        int created = 0;
        using var monitor = new ProviderMonitor(settings, id => Interlocked.Increment(ref created) == 1
            ? first : new ImmediateClient(id, Snapshot(id, 89)), () => { });
        var active = monitor.RefreshAsync(UsageProviderID.Claude);
        await first.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var hide = monitor.SetEnabledAsync(UsageProviderID.Claude, false);
        Check(first.Token.IsCancellationRequested, "hide cancels owned IO");
        var show = monitor.SetEnabledAsync(UsageProviderID.Claude, true);
        Check(created == 1 && !show.IsCompleted, "reenable awaits previous worker cleanup");
        first.Complete(3); // Intentionally ignores cancellation, like a slow native read.
        await Task.WhenAll(active, hide, show).WaitAsync(TimeSpan.FromSeconds(3));
        Check(created == 2 && monitor.States.Single(state => state.Id == UsageProviderID.Claude).DisplayRemainingPercent == 89,
            "late hidden result cannot replace renewed snapshot");
        await monitor.SetEnabledAsync(UsageProviderID.Claude, false);
        await monitor.RefreshAsync(UsageProviderID.Claude, interactive: true);
        Check(created == 2, "hidden provider has zero new reads");
    }

    private static async Task DisconnectRevokesAndRejectsLateResult()
    {
        var settings = Connected();
        var first = new ControlledClient(UsageProviderID.Grok);
        int created = 0;
        using var monitor = new ProviderMonitor(settings, id =>
        {
            Interlocked.Increment(ref created);
            return first;
        }, () => { });
        var active = monitor.RefreshAsync(UsageProviderID.Grok);
        await first.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var disconnect = monitor.DisconnectAsync(UsageProviderID.Grok);
        Check(first.Token.IsCancellationRequested && !settings.Preferences(UsageProviderID.Grok).UsageConsent
            && !settings.Preferences(UsageProviderID.Grok).GrokWebVerified, "disconnect revokes flags and cancels");
        first.Complete(31);
        await Task.WhenAll(active, disconnect).WaitAsync(TimeSpan.FromSeconds(3));
        await monitor.RefreshAsync(UsageProviderID.Grok, interactive: true);
        var state = monitor.States.Single(item => item.Id == UsageProviderID.Grok);
        Check(created == 1 && state.Snapshot is null && state.LastSuccess is null && !state.AwaitingVerification,
            "disconnect deletes snapshot and rejects late result");
    }

    private static async Task GrokRequiresExplicitWebVerification()
    {
        var settings = new AppSettings();
        int created = 0;
        using var monitor = new ProviderMonitor(settings, id =>
        {
            Interlocked.Increment(ref created);
            return new ImmediateClient(id, Snapshot(id, 61));
        }, () => { });
        await monitor.ConnectAsync(UsageProviderID.Grok);
        Check(created == 1 && monitor.States.Single(state => state.Id == UsageProviderID.Grok).AwaitingVerification,
            "consent allows one initial Grok query");
        await monitor.RefreshAsync(UsageProviderID.Grok);
        Check(created == 1, "Grok auto refresh blocked before web comparison");
        Check(monitor.VerifyGrok(), "explicit web comparison enables Grok");
        await monitor.RefreshAsync(UsageProviderID.Grok);
        Check(created == 2 && settings.Preferences(UsageProviderID.Grok).GrokWebVerified,
            "verified Grok auto refresh permitted");
        await monitor.DisconnectAsync(UsageProviderID.Grok);
        Check(!monitor.VerifyGrok(), "disconnected Grok cannot verify");
    }

    private static async Task GrokRejectsMissingResetAndChangedCandidate()
    {
        var settings = new AppSettings();
        var time = DateTimeOffset.UtcNow;
        int created = 0;
        using var monitor = new ProviderMonitor(settings, id => new ImmediateClient(id,
            Interlocked.Increment(ref created) == 1
                ? new(id, [new("weekly", "주간", 65)]) : Snapshot(id, 65)), () => { }, () => time);
        await monitor.ConnectAsync(UsageProviderID.Grok);
        Check(!monitor.VerifyGrok(), "missing reset cannot verify a matching pool");
        await monitor.ConnectAsync(UsageProviderID.Grok);
        var candidate = monitor.States.Single(state => state.Id == UsageProviderID.Grok).LastSuccess;
        time = time.AddMinutes(1);
        await monitor.ConnectAsync(UsageProviderID.Grok);
        Check(!monitor.VerifyGrok(candidate), "changed candidate requires new user confirmation");
        time = time.AddMinutes(21);
        Check(!monitor.VerifyGrok(), "stale candidate cannot verify");
    }

    private static AppSettings Connected()
    {
        var settings = new AppSettings();
        foreach (var id in UsageProviders.All)
        {
            settings.Preferences(id).UsageConsent = true;
            settings.Preferences(id).GrokWebVerified = true;
        }
        return settings;
    }

    private static ProviderUsageSnapshot Snapshot(UsageProviderID id, double remaining) =>
        new(id, [new("primary", "기본 한도", remaining, DateTimeOffset.UtcNow.AddDays(3))]);

    private static void Check(bool condition, string name)
    {
        if (!condition) throw new InvalidOperationException($"Provider monitor self test failed: {name}");
    }

    private sealed class ImmediateClient(UsageProviderID id, ProviderUsageSnapshot result) : IUsageProviderClient
    {
        public UsageProviderID Id => id;
        public Task<ProviderUsageSnapshot> FetchAsync(CancellationToken cancellationToken = default) => Task.FromResult(result);
    }

    private sealed class FailureClient(UsageProviderID id) : IUsageProviderClient
    {
        public UsageProviderID Id => id;
        public Task<ProviderUsageSnapshot> FetchAsync(CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("sensitive synthetic error");
    }

    private sealed class ControlledClient(UsageProviderID id) : IUsageProviderClient
    {
        public UsageProviderID Id => id;
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<ProviderUsageSnapshot> _result = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public CancellationToken Token { get; private set; }
        public Task<ProviderUsageSnapshot> FetchAsync(CancellationToken cancellationToken = default)
        {
            Token = cancellationToken;
            Started.TrySetResult();
            return _result.Task;
        }
        public void Complete(double remaining) => _result.TrySetResult(Snapshot(id, remaining));
    }

    private sealed class Counter
    {
        private readonly System.Collections.Concurrent.ConcurrentDictionary<UsageProviderID, int> _values = new();
        public void Add(UsageProviderID id) => _values.AddOrUpdate(id, 1, (_, value) => value + 1);
        public int Get(UsageProviderID id) => _values.GetValueOrDefault(id);
    }
}

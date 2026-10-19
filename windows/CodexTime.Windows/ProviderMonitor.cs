namespace CodexTime.WinApp;

// Owns query lifetimes, not credentials. A provider is never constructed until its
// consent/visibility gate passes. Generation checks reject late, uncancellable results.
public sealed class ProviderMonitor : IDisposable
{
    private sealed class Worker(UsageProviderID id)
    {
        public ProviderUsageState State { get; } = new(id);
        public long Generation;
        public Task? Task;
        public CancellationTokenSource? Cancellation;
    }

    private readonly object _gate = new();
    private readonly AppSettings _settings;
    private readonly Func<UsageProviderID, IUsageProviderClient> _factory;
    private readonly Action _save;
    private readonly Func<DateTimeOffset> _now;
    private readonly Dictionary<UsageProviderID, Worker> _workers = UsageProviders.All.ToDictionary(id => id, id => new Worker(id));
    private bool _disposed;

    public ProviderMonitor(AppSettings settings, Func<UsageProviderID, IUsageProviderClient>? factory = null,
        Action? save = null, Func<DateTimeOffset>? now = null)
    {
        _settings = settings;
        _factory = factory ?? ProductionUsageProviders.Create;
        _save = save ?? (() => SettingsStore.Save(settings));
        _now = now ?? (() => DateTimeOffset.UtcNow);
        foreach (var id in UsageProviders.All)
        {
            var preferences = settings.Preferences(id);
            _workers[id].State.Failure = id == UsageProviderID.Codex || preferences.UsageConsent
                ? null : ProviderFailure.NotConnected;
            _workers[id].State.AwaitingVerification = id == UsageProviderID.Grok
                && preferences.UsageConsent && !preferences.GrokWebVerified;
        }
    }

    public event EventHandler? Changed;

    public IReadOnlyList<ProviderUsageState> States
    {
        get
        {
            lock (_gate)
                return UsageProviders.All.Select(id => Copy(_workers[id].State)).ToArray();
        }
    }

    public Task RefreshAllAsync() => Task.WhenAll(UsageProviders.All.Select(id => RefreshAsync(id)));

    public Task RefreshAsync(UsageProviderID id, bool interactive = false)
    {
        TaskCompletionSource completion;
        Worker worker;
        long generation;
        CancellationToken token;
        lock (_gate)
        {
            if (_disposed || !CanQuery(id, interactive)) return Task.CompletedTask;
            worker = _workers[id];
            if (worker.Task is { IsCompleted: false }) return worker.Task;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            worker.Task = completion.Task;
            worker.Cancellation?.Dispose();
            worker.Cancellation = new CancellationTokenSource();
            token = worker.Cancellation.Token;
            generation = worker.Generation;
            worker.State.LastAttempt = _now();
            worker.State.IsRefreshing = true;
        }
        Notify();
        // Credential stores may use bounded synchronous IO. Never block WPF's dispatcher.
        _ = Task.Run(async () =>
        {
            ProviderUsageSnapshot? result = null;
            ProviderFailure? failure = null;
            try
            {
                token.ThrowIfCancellationRequested();
                result = await _factory(id).FetchAsync(token).ConfigureAwait(false);
                if (result.Provider != id) throw new ProviderQueryException(ProviderFailure.InvalidResponse);
                token.ThrowIfCancellationRequested();
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { }
            catch (ProviderQueryException error) { failure = error.Failure; }
            catch (OperationCanceledException) { failure = ProviderFailure.Timeout; }
            catch { failure = ProviderFailure.QueryFailed; }
            finally
            {
                lock (_gate)
                {
                    if (!_disposed && worker.Generation == generation && !token.IsCancellationRequested
                        && CanQuery(id, interactive))
                    {
                        if (result is not null && failure is null)
                        {
                            worker.State.Snapshot = result;
                            worker.State.LastSuccess = _now();
                        }
                        worker.State.Failure = failure;
                        worker.State.IsRefreshing = false;
                        worker.State.AwaitingVerification = id == UsageProviderID.Grok
                            && !_settings.Preferences(id).GrokWebVerified;
                    }
                }
                completion.TrySetResult();
                Notify();
            }
        });
        return completion.Task;
    }

    public async Task ConnectAsync(UsageProviderID id)
    {
        Task? previous;
        lock (_gate)
        {
            if (_disposed) return;
            var preferences = _settings.Preferences(id);
            preferences.Enabled = true;
            preferences.UsageConsent = true;
            previous = Invalidate(_workers[id]);
            _save();
        }
        Notify();
        if (previous is not null) await previous.ConfigureAwait(false);
        await RefreshAsync(id, interactive: true).ConfigureAwait(false);
    }

    public async Task SetEnabledAsync(UsageProviderID id, bool enabled)
    {
        Task? previous;
        lock (_gate)
        {
            if (_disposed) return;
            _settings.Preferences(id).Enabled = enabled;
            previous = Invalidate(_workers[id]);
            _save();
        }
        Notify();
        // Do not overlap a replacement with a worker still cleaning up owned IO.
        if (previous is not null) await previous.ConfigureAwait(false);
        if (enabled) await RefreshAsync(id).ConfigureAwait(false);
    }

    public async Task DisconnectAsync(UsageProviderID id)
    {
        Task? previous;
        lock (_gate)
        {
            if (_disposed) return;
            var preferences = _settings.Preferences(id);
            preferences.UsageConsent = false;
            preferences.GrokWebVerified = false;
            // Codex keeps its legacy auto-connect behavior when enabled. Explicit
            // disconnect hides it so the next timer cannot reconnect implicitly.
            if (id == UsageProviderID.Codex) preferences.Enabled = false;
            previous = Invalidate(_workers[id]);
            var state = _workers[id].State;
            state.Snapshot = null;
            state.LastSuccess = null;
            state.LastAttempt = null;
            state.Failure = ProviderFailure.NotConnected;
            state.AwaitingVerification = false;
            _save();
        }
        Notify();
        if (previous is not null) await previous.ConfigureAwait(false);
    }

    public bool VerifyGrok(DateTimeOffset? expectedSuccess = null)
    {
        lock (_gate)
        {
            var preferences = _settings.Preferences(UsageProviderID.Grok);
            var state = _workers[UsageProviderID.Grok].State;
            if (_disposed || !preferences.Enabled || !preferences.UsageConsent || state.IsRefreshing
                || state.Snapshot?.DisplayRemainingPercent is null || state.Failure is not null
                || state.Snapshot?.DisplayWindow?.ResetsAt is null
                || state.LastSuccess is null || _now() - state.LastSuccess > TimeSpan.FromMinutes(20)
                || expectedSuccess is not null && expectedSuccess != state.LastSuccess) return false;
            preferences.GrokWebVerified = true;
            state.AwaitingVerification = false;
            _save();
        }
        Notify();
        return true;
    }

    private bool CanQuery(UsageProviderID id, bool interactive)
    {
        var preferences = _settings.Preferences(id);
        return preferences.Enabled && (id == UsageProviderID.Codex || preferences.UsageConsent)
            && (id != UsageProviderID.Grok || preferences.GrokWebVerified || interactive);
    }

    private static Task? Invalidate(Worker worker)
    {
        worker.Generation++;
        worker.Cancellation?.Cancel();
        worker.State.IsRefreshing = false;
        return worker.Task;
    }

    private static ProviderUsageState Copy(ProviderUsageState state) => new(state.Id)
    {
        Snapshot = state.Snapshot,
        LastSuccess = state.LastSuccess,
        LastAttempt = state.LastAttempt,
        Failure = state.Failure,
        IsRefreshing = state.IsRefreshing,
        AwaitingVerification = state.AwaitingVerification
    };

    private void Notify() => Changed?.Invoke(this, EventArgs.Empty);

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            foreach (var worker in _workers.Values)
            {
                Invalidate(worker);
                var cancellation = worker.Cancellation;
                if (worker.Task is { IsCompleted: false } task)
                    _ = task.ContinueWith(_ => cancellation?.Dispose(), TaskScheduler.Default);
                else cancellation?.Dispose();
            }
        }
    }
}

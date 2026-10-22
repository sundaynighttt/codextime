using System.Threading;
using System.Windows;

namespace CodexTime.WinApp;

public partial class App : System.Windows.Application
{
    private Mutex? _singleInstanceMutex;
    private UsageController? _controller;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        if (e.Args.Length == 2 && e.Args[0] == "--resource-fixture")
        {
            try { await ResourceSafetySelfTests.RunFixtureAsync(e.Args[1]); Shutdown(0); }
            catch { Shutdown(1); }
            return;
        }

        if (e.Args.Length == 2 && e.Args[0] == "--provider-wal-fixture")
        {
            try { await ProviderClientSelfTests.RunWalFixtureAsync(e.Args[1]); Shutdown(0); }
            catch { Shutdown(1); }
            return;
        }

        if (e.Args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                RateLimitParserSelfTest.Run();
                Console.WriteLine("Codex parser checks passed.");
                await ProviderClientSelfTests.RunAsync();
                Console.WriteLine("Provider HTTP and native Windows storage checks passed.");
                await ProviderMonitorSelfTests.RunAsync();
                Console.WriteLine("Provider lifecycle checks passed (7 scenarios).");
                ProviderUiSelfTests.Run();
                Console.WriteLine("Provider UI checks passed.");
                await ProviderUiSelfTests.CheckRepeatedDetailsAsync();
                await ResourceSafetySelfTests.RunAsync();
                Console.WriteLine("CLI stream, cancellation, process cleanup and log retention checks passed.");
                Shutdown(0);
            }
            catch (Exception error)
            {
                Console.Error.WriteLine("Synthetic self-test failure: " + error.GetType().Name);
                Console.Error.WriteLine(error.StackTrace);
                Shutdown(1);
            }
            return;
        }

        if (e.Args.Length == 2 && e.Args[0] == "--render-preview")
        {
            try { WindowsPreview.Render(e.Args[1]); Shutdown(0); }
            catch { Shutdown(1); }
            return;
        }

        _singleInstanceMutex = new Mutex(true, @"Local\CodexTime.Windows", out var createdNew);
        if (!createdNew)
        {
            Shutdown(0);
            return;
        }

        try
        {
            AppLog.Write("startup");
            _controller = new UsageController();
            await _controller.StartAsync();
        }
        catch (Exception exception)
        {
            AppLog.Write(exception);
            System.Windows.MessageBox.Show(
                "앱을 시작하지 못했습니다. 다시 실행해 주세요.",
                "CodexTime",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _controller?.Dispose();
        _singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }
}

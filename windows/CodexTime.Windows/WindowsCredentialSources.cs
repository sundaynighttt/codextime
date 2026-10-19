using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using Microsoft.Win32.SafeHandles;
using SQLitePCL;

namespace CodexTime.WinApp;

// Construction never opens storage. The controller calls these sources only
// after the user explicitly allows this provider's usage-only connection.
internal sealed class WindowsClaudeCredentialSource : IUsageCredentialSource
{
    private readonly string _path;
    public WindowsClaudeCredentialSource() : this(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", ".credentials.json")) { }
    internal WindowsClaudeCredentialSource(string syntheticPath) => _path = syntheticPath;

    public Task<UsageAuthorization> LoadAsync(DateTimeOffset now, CancellationToken cancellationToken) =>
        Task.Run(() =>
        {
            byte[]? bytes = null;
            try
            {
                cancellationToken.ThrowIfCancellationRequested();
                using var guarded = GuardedWindowsFiles.Open(_path, 65536);
                using var stream = new FileStream(guarded.Handle, FileAccess.Read);
                using var data = new MemoryStream();
                var buffer = new byte[4096];
                while (true)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    int count = stream.Read(buffer);
                    if (count == 0) break;
                    if (data.Length + count > 65536) throw new ProviderQueryException(ProviderFailure.AuthenticationRequired);
                    data.Write(buffer, 0, count);
                }
                bytes = data.ToArray();
                cancellationToken.ThrowIfCancellationRequested();
                return Parse(bytes, now);
            }
            catch (OperationCanceledException) { throw; }
            catch (ProviderQueryException) { throw; }
            catch { throw new ProviderQueryException(ProviderFailure.AuthenticationRequired); }
            finally { if (bytes is not null) Array.Clear(bytes); }
        }, cancellationToken);

    internal static UsageAuthorization Parse(byte[] data, DateTimeOffset now)
    {
        try
        {
            if (data.Length > 65536) throw new JsonException();
            using var document = JsonDocument.Parse(data, new JsonDocumentOptions { MaxDepth = 16 });
            var oauth = document.RootElement.GetProperty("claudeAiOauth");
            var token = oauth.GetProperty("accessToken").GetString();
            if (string.IsNullOrEmpty(token) || token.Length > 16384 || token.Any(c => c < 0x21 || c > 0x7e))
                throw new JsonException();
            var expiryValue = oauth.GetProperty("expiresAt");
            if (expiryValue.ValueKind != JsonValueKind.Number || !expiryValue.TryGetInt64(out var milliseconds))
                throw new JsonException();
            var expiry = DateTimeOffset.FromUnixTimeMilliseconds(milliseconds);
            if (expiry <= now.AddSeconds(15)) throw new JsonException();
            var scopes = oauth.GetProperty("scopes");
            if (scopes.ValueKind != JsonValueKind.Array || !scopes.EnumerateArray().Any(scope =>
                scope.ValueKind == JsonValueKind.String && scope.GetString() == "user:profile"))
                throw new ProviderQueryException(ProviderFailure.Unsupported);
            return new(token, expiry);
        }
        catch (ProviderQueryException) { throw; }
        catch { throw new ProviderQueryException(ProviderFailure.AuthenticationRequired); }
    }
}

internal sealed class WindowsCursorCredentialSource : IUsageCredentialSource
{
    internal const string Query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1";
    private readonly string _path;
    public WindowsCursorCredentialSource() : this(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Cursor", "User", "globalStorage", "state.vscdb")) { }
    internal WindowsCursorCredentialSource(string syntheticPath) => _path = syntheticPath;

    public Task<UsageAuthorization> LoadAsync(DateTimeOffset now, CancellationToken cancellationToken) =>
        Task.Run(() => Read(now, cancellationToken), cancellationToken);

    private UsageAuthorization Read(DateTimeOffset now, CancellationToken cancellationToken)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            using var databaseFile = GuardedWindowsFiles.Open(_path, 512L * 1024 * 1024);
            // Both existing sidecars are mandatory on Windows. Holding these
            // OPEN_EXISTING handles without FILE_SHARE_DELETE prevents SQLite's
            // OPEN_ALWAYS path from creating/replacing a sidecar during this read.
            // A rollback DB (both absent), partial WAL pair, custom location or
            // junction fails closed; no immutable/nolock/copy fallback exists.
            using var wal = GuardedWindowsFiles.Open(_path + "-wal", 256L * 1024 * 1024, missingUnsupported: true);
            using var shm = GuardedWindowsFiles.Open(_path + "-shm", 8L * 1024 * 1024, missingUnsupported: true);
            var uri = new Uri(Path.GetFullPath(_path)).AbsoluteUri + "?mode=ro&readonly_shm=1";
            var options = new SqliteConnectionStringBuilder
            {
                DataSource = uri, Mode = SqliteOpenMode.ReadOnly, Cache = SqliteCacheMode.Private,
                Pooling = false, DefaultTimeout = 2
            };
            using var connection = new SqliteConnection(options.ToString());
            connection.Open();
            var handle = connection.Handle ?? throw new ProviderQueryException(ProviderFailure.QueryFailed);
            // Native package is pinned and Windows CI validates real WAL/SHM
            // behavior. A changed/older runtime must not silently weaken it.
            if (raw.sqlite3_libversion_number() != 3053004 || raw.sqlite3_db_readonly(handle, "main") != 1)
                throw new ProviderQueryException(ProviderFailure.Unsupported);
            raw.sqlite3_limit(handle, raw.SQLITE_LIMIT_LENGTH, 65536);
            raw.sqlite3_limit(handle, raw.SQLITE_LIMIT_SQL_LENGTH, 1024);
            raw.sqlite3_limit(handle, raw.SQLITE_LIMIT_ATTACHED, 0);
            var budget = Stopwatch.StartNew();
            raw.sqlite3_progress_handler(handle, 1000,
                _ => cancellationToken.IsCancellationRequested || budget.Elapsed > TimeSpan.FromSeconds(2) ? 1 : 0, null!);
            strdelegate_authorizer authorizer = (_, action, first, second, schema, source) =>
            {
                if (!string.IsNullOrEmpty(source)) return raw.SQLITE_DENY;
                if (action == raw.SQLITE_SELECT) return raw.SQLITE_OK;
                return action == raw.SQLITE_READ && first == "ItemTable" && schema == "main"
                    && (second == "key" || second == "value") ? raw.SQLITE_OK : raw.SQLITE_DENY;
            };
            if (raw.sqlite3_set_authorizer(handle, authorizer, null!) != raw.SQLITE_OK)
                throw new ProviderQueryException(ProviderFailure.QueryFailed);
            using var interrupt = cancellationToken.Register(() => raw.sqlite3_interrupt(handle));
            try
            {
                using var command = connection.CreateCommand();
                command.CommandText = Query;
                command.CommandTimeout = 2;
                using var reader = command.ExecuteReader();
                if (!reader.Read() || reader.GetFieldType(0) != typeof(string))
                    throw new ProviderQueryException(ProviderFailure.AuthenticationRequired);
                var token = reader.GetString(0);
                cancellationToken.ThrowIfCancellationRequested();
                return ParseToken(token, now);
            }
            finally
            {
                raw.sqlite3_progress_handler(handle, 0, null!, null!);
                raw.sqlite3_set_authorizer(handle, (strdelegate_authorizer)null!, null!);
                GC.KeepAlive(authorizer);
            }
        }
        catch (OperationCanceledException) { throw; }
        catch (ProviderQueryException) { throw; }
        catch (SqliteException exception)
        {
            cancellationToken.ThrowIfCancellationRequested();
            throw new ProviderQueryException(exception.SqliteErrorCode switch
            {
                5 or 6 or 9 => ProviderFailure.Timeout,
                8 or 14 => ProviderFailure.Unsupported,
                _ => ProviderFailure.InvalidResponse
            });
        }
        catch { throw new ProviderQueryException(ProviderFailure.QueryFailed); }
    }

    internal static UsageAuthorization ParseToken(string token, DateTimeOffset now)
    {
        try
        {
            if (token.Length > 32768 || token.Any(c => c < 0x21 || c > 0x7e)) throw new JsonException();
            var parts = token.Split('.');
            if (parts.Length != 3 || parts.Any(string.IsNullOrEmpty) || parts[1].Length > 16384) throw new JsonException();
            var encoded = parts[1].Replace('-', '+').Replace('_', '/');
            encoded += new string('=', (4 - encoded.Length % 4) % 4);
            using var payload = JsonDocument.Parse(Convert.FromBase64String(encoded), new JsonDocumentOptions { MaxDepth = 8 });
            var value = payload.RootElement.GetProperty("exp");
            if (value.ValueKind != JsonValueKind.Number || !value.TryGetDouble(out var seconds)
                || !double.IsFinite(seconds)) throw new JsonException();
            var expiry = DateTimeOffset.UnixEpoch.AddSeconds(seconds);
            if (expiry <= now.AddSeconds(30)) throw new JsonException();
            // Expiry validation only; the fixed service authenticates signatures.
            return new(token, expiry);
        }
        catch { throw new ProviderQueryException(ProviderFailure.AuthenticationRequired); }
    }
}

// No path discovery or directory enumeration. Pin each component, reject all
// reparse points, remote paths and non-files, and retain no-delete handles for
// the whole read. These handles never request write access.
internal sealed class GuardedWindowsFiles : IDisposable
{
    private readonly List<SafeFileHandle> _handles = [];
    internal SafeFileHandle Handle => _handles[^1];

    internal static GuardedWindowsFiles Open(string path, long maximumBytes, bool missingUnsupported = false)
    {
        var result = new GuardedWindowsFiles();
        try
        {
            if (!OperatingSystem.IsWindows()) throw new ProviderQueryException(ProviderFailure.Unsupported);
            var full = Path.GetFullPath(path);
            var root = Path.GetPathRoot(full);
            if (root is null || root.StartsWith(@"\\", StringComparison.Ordinal)
                || new DriveInfo(root).DriveType != DriveType.Fixed)
                throw new ProviderQueryException(ProviderFailure.Unsupported);
            string current = root;
            var parts = full[root.Length..].Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
            for (int index = -1; index < parts.Length; index++)
            {
                if (index >= 0) current = Path.Combine(current, parts[index]);
                bool directory = index < parts.Length - 1;
                var handle = CreateFile(current, directory ? 0x80u : 0x80000000u,
                    1 | 2, IntPtr.Zero, 3, 0x00200000u | (directory ? 0x02000000u : 0), IntPtr.Zero);
                if (handle.IsInvalid)
                {
                    int error = Marshal.GetLastWin32Error();
                    handle.Dispose();
                    throw new ProviderQueryException(error == 5 ? ProviderFailure.PermissionRequired
                        : missingUnsupported ? ProviderFailure.Unsupported : ProviderFailure.AuthenticationRequired);
                }
                result._handles.Add(handle);
                if (!GetFileInformationByHandle(handle, out var info) || (info.Attributes & 0x400) != 0
                    || (((info.Attributes & 0x10) != 0) != directory))
                    throw new ProviderQueryException(ProviderFailure.Unsupported);
                var resolved = new StringBuilder(32768);
                uint count = GetFinalPathNameByHandle(handle, resolved, (uint)resolved.Capacity, 0);
                string actual = resolved.ToString();
                if (actual.StartsWith(@"\\?\", StringComparison.Ordinal)) actual = actual[4..];
                if (count == 0 || count >= resolved.Capacity || !string.Equals(actual.TrimEnd('\\'),
                    current.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                    throw new ProviderQueryException(ProviderFailure.Unsupported);
                if (!directory)
                {
                    long size = ((long)info.SizeHigh << 32) | info.SizeLow;
                    if (size <= 0 || size > maximumBytes || GetFileType(handle) != 1)
                        throw new ProviderQueryException(ProviderFailure.Unsupported);
                }
            }
            return result;
        }
        catch { result.Dispose(); throw; }
    }

    public void Dispose()
    {
        for (int index = _handles.Count - 1; index >= 0; index--) _handles[index].Dispose();
        _handles.Clear();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation
    {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        public uint VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateFileW")]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security,
        uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation information);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "GetFinalPathNameByHandleW")]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint size, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint GetFileType(SafeFileHandle handle);
}

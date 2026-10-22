using System.IO;
using System.Text;

namespace CodexTime.WinApp;

// Two bounded files, including when upgrading an installation with a huge log.
// Rotation copies a bounded tail with a small buffer instead of loading the log.
internal sealed class RollingFileLog
{
    private static readonly Encoding Utf8 = new UTF8Encoding(false);
    private readonly object _gate = new();
    private readonly string _path;
    private readonly int _maxFileBytes;
    private readonly int _maxMessageChars;

    internal RollingFileLog(string path, int maxFileBytes = 1_048_576, int maxMessageChars = 2048)
    {
        if (maxFileBytes < 256) throw new ArgumentOutOfRangeException(nameof(maxFileBytes));
        if (maxMessageChars < 1) throw new ArgumentOutOfRangeException(nameof(maxMessageChars));
        _path = Path.GetFullPath(path);
        _maxFileBytes = maxFileBytes;
        // Reserve space for the timestamp and marker, even with multi-byte text.
        _maxMessageChars = Math.Min(maxMessageChars, (maxFileBytes - 128) / 3);
    }

    internal void Write(string message)
    {
        var marker = _maxMessageChars >= 12 ? " [truncated]" : string.Empty;
        var bounded = message.Length > _maxMessageChars
            ? message[..(_maxMessageChars - marker.Length)] + marker : message;
        var entry = Utf8.GetBytes($"[{DateTimeOffset.Now:O}] {bounded}{Environment.NewLine}");
        lock (_gate)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var archive = _path + ".1";
            if (File.Exists(archive) && new FileInfo(archive).Length > _maxFileBytes)
            {
                using var previous = new FileStream(archive, FileMode.Open, FileAccess.Write, FileShare.Read);
                previous.SetLength(_maxFileBytes);
            }
            if (File.Exists(_path) && new FileInfo(_path).Length + entry.Length > _maxFileBytes)
            {
                using (var source = new FileStream(_path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (var destination = new FileStream(archive, FileMode.Create, FileAccess.Write, FileShare.Read))
                {
                    var remaining = (int)Math.Min(source.Length, _maxFileBytes);
                    source.Position = source.Length - remaining;
                    var skipPartialLine = source.Position > 0;
                    var buffer = new byte[8192];
                    while (remaining > 0)
                    {
                        var count = source.Read(buffer, 0, Math.Min(buffer.Length, remaining));
                        if (count == 0) break;
                        var offset = 0;
                        if (skipPartialLine)
                        {
                            var newline = Array.IndexOf(buffer, (byte)'\n', 0, count);
                            if (newline < 0) { remaining -= count; continue; }
                            offset = newline + 1;
                            skipPartialLine = false;
                        }
                        destination.Write(buffer, offset, count - offset);
                        remaining -= count;
                    }
                }
                using var current = new FileStream(_path, FileMode.Create, FileAccess.Write, FileShare.Read);
                current.Write(entry);
            }
            else
            {
                using var current = new FileStream(_path, FileMode.Append, FileAccess.Write, FileShare.Read);
                current.Write(entry);
            }
        }
    }
}

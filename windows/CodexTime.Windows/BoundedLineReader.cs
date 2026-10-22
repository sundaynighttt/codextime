using System.IO;
using System.Text;

namespace CodexTime.WinApp;

// StreamReader.ReadLineAsync allocates the whole line before a caller can check
// its length. Keep both the read buffer and the in-progress JSONL line bounded.
internal sealed class BoundedLineReader(TextReader reader, int maximumLineChars)
{
    private readonly char[] _buffer = new char[4096];
    private readonly int _maximumLineChars = maximumLineChars > 0
        ? maximumLineChars : throw new ArgumentOutOfRangeException(nameof(maximumLineChars));
    private int _offset;
    private int _count;
    private bool _skipLineFeed;

    internal async Task<string?> ReadLineAsync(CancellationToken cancellationToken = default)
    {
        var line = new StringBuilder();
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_offset == _count)
            {
                _count = await reader.ReadAsync(_buffer.AsMemory(), cancellationToken);
                _offset = 0;
                if (_count == 0) return line.Length == 0 ? null : line.ToString();
            }

            var character = _buffer[_offset++];
            if (_skipLineFeed)
            {
                _skipLineFeed = false;
                if (character == '\n') continue;
            }
            if (character is '\r' or '\n')
            {
                _skipLineFeed = character == '\r';
                return line.ToString();
            }
            if (line.Length == _maximumLineChars)
                throw new InvalidDataException("Codex response line exceeds the size limit.");
            line.Append(character);
        }
    }
}

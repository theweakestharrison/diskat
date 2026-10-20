using System.IO.Enumeration;

namespace Diskat.Core;

public sealed record FindResult(List<FileRecord> Files, long Total, long TotalBytes);

/// <summary>
/// Tìm file theo mẫu tên, dung lượng tối thiểu và tuổi (lần sửa cuối) trong cả cây thư mục.
/// Chỉ tạo chuỗi đường dẫn cho file khớp; giữ lại tối đa <c>max</c> file lớn nhất.
/// </summary>
public static class FileFinder
{
    public sealed class Counter { public long Found; }

    /// <summary>
    /// "*.log; *.tmp" hoặc "*.log *.tmp" là các mẫu riêng; chữ không có * ? được hiểu là "tên có chứa".
    /// Trả về null nếu không lọc theo tên.
    /// </summary>
    public static List<string>? ParsePatterns(string text)
    {
        text = text.Trim();
        if (text.Length == 0) return null;
        bool wild = text.IndexOfAny(['*', '?']) >= 0;
        var parts = wild
            ? text.Split([';', ',', ' ', '\t'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            : text.Split([';', ','], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var list = parts.Select(p => p.IndexOfAny(['*', '?']) >= 0 ? p : "*" + p + "*").ToList();
        return list.Count == 0 ? null : list;
    }

    public static FindResult Find(string root, IReadOnlyList<string>? patterns, long minSize, DateTime olderThanUtc,
        int max, Counter counter, CancellationToken ct)
    {
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = 0, // file "chỉ có trên mạng" của OneDrive cũng là reparse point: vẫn liệt kê
            BufferSize = 64 * 1024,
        };
        var en = new FileSystemEnumerable<FileRecord>(root,
            (ref FileSystemEntry e) => new FileRecord(e.ToFullPath(), e.Length, e.LastWriteTimeUtc.UtcDateTime), options)
        {
            // Không đi vào junction / symlink (tránh đếm trùng, lặp vô hạn) và tên kết thúc bằng "." hoặc " "
            ShouldRecursePredicate = (ref FileSystemEntry e) =>
                (e.Attributes & FileAttributes.ReparsePoint) == 0 && e.FileName.Length > 0 && e.FileName[^1] is not ('.' or ' '),
            ShouldIncludePredicate = (ref FileSystemEntry e) =>
            {
                ct.ThrowIfCancellationRequested();
                if (e.IsDirectory || e.Length < minSize) return false;
                if (e.LastWriteTimeUtc.UtcDateTime >= olderThanUtc) return false;
                if (patterns == null) return true;
                foreach (var p in patterns)
                    if (FileSystemName.MatchesSimpleExpression(p, e.FileName, ignoreCase: true)) return true;
                return false;
            },
        };

        var heap = new PriorityQueue<FileRecord, long>();
        long total = 0, bytes = 0;
        foreach (var f in en)
        {
            total++;
            bytes += f.Size;
            Volatile.Write(ref counter.Found, total);
            if (heap.Count < max) heap.Enqueue(f, f.Size);
            else if (f.Size > heap.Peek().Size) heap.EnqueueDequeue(f, f.Size);
        }
        var files = heap.UnorderedItems.Select(x => x.Element).ToList();
        files.Sort((a, b) => b.Size.CompareTo(a.Size));
        return new FindResult(files, total, bytes);
    }
}

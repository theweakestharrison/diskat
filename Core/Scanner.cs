using System.Collections.Concurrent;
using System.IO.Enumeration;

namespace Diskat.Core;

public sealed record FileRecord(string Path, long Size, DateTime LastWriteUtc);

/// <summary>Tổng theo phần mở rộng (".mp4", "" = không có phần mở rộng).</summary>
public sealed record TypeStat(string Extension, long Size, long Count);

/// <summary>Tổng theo tuổi file (lần sửa cuối). MaxDays = null: nhóm cũ nhất.</summary>
public sealed record AgeStat(int? MaxDays, long Size, long Count);

/// <summary>Thống kê riêng của một luồng quét, gộp lại khi quét xong (không cần khóa trong lúc quét).</summary>
internal sealed class WorkerStats
{
    public sealed class Total { public long Size, Count; }

    public static readonly int[] AgeLimitsDays = [30, 182, 365, 730, 1825];

    public readonly Dictionary<string, Total> Types = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Total>.AlternateLookup<ReadOnlySpan<char>> _lookup;
    public readonly long[] AgeSize = new long[AgeLimitsDays.Length + 1];
    public readonly long[] AgeCount = new long[AgeLimitsDays.Length + 1];
    private readonly long[] _ageLimitTicks;

    public WorkerStats(DateTime nowUtc)
    {
        _lookup = Types.GetAlternateLookup<ReadOnlySpan<char>>();
        _ageLimitTicks = AgeLimitsDays.Select(d => (nowUtc - TimeSpan.FromDays(d)).Ticks).ToArray();
    }

    public void Add(ReadOnlySpan<char> fileName, long size, DateTime lastWriteUtc)
    {
        var ext = Path.GetExtension(fileName);
        // Tên kiểu "bản sao.2023-01-01 cuối" không phải phần mở rộng thật
        if (ext.Length > 12 || ext.Length == fileName.Length || ext.Contains(' ')) ext = default;
        if (!_lookup.TryGetValue(ext, out var t))
        {
            t = new Total();
            _lookup[ext] = t;
        }
        t.Size += size;
        t.Count++;

        long ticks = lastWriteUtc.Ticks;
        int bucket = 0;
        while (bucket < _ageLimitTicks.Length && ticks < _ageLimitTicks[bucket]) bucket++;
        AgeSize[bucket] += size;
        AgeCount[bucket]++;
    }
}

/// <summary>
/// Bộ quét song song: nhiều luồng cùng lấy thư mục từ một ngăn xếp chung,
/// liệt kê bằng FileSystemEnumerable (NtQueryDirectoryFile, không tạo FileInfo),
/// rồi cộng dồn dung lượng lên các thư mục cha.
/// </summary>
public sealed class Scanner
{
    public const int TopFileCapacity = 500;

    private static readonly EnumerationOptions Options = new()
    {
        RecurseSubdirectories = false,
        IgnoreInaccessible = false,
        AttributesToSkip = 0,
        ReturnSpecialDirectories = false,
        BufferSize = 64 * 1024,
    };

    private readonly ConcurrentStack<DirNode> _stack = new();
    private readonly SemaphoreSlim _signal = new(0);
    private readonly PriorityQueue<FileRecord, long> _topFiles = new();
    private readonly object _topLock = new();
    private long _topThreshold;
    private int _pending;
    private volatile bool _finished;
    private int _errors;
    private CancellationToken _token;
    private readonly List<WorkerStats> _stats = new();
    private readonly DateTime _startedUtc = DateTime.UtcNow;

    public DateTime StartedUtc => _startedUtc;

    public DirNode Root { get; }
    public int Errors => Volatile.Read(ref _errors);
    public string? CurrentPath { get; private set; }

    public Scanner(string rootPath)
    {
        var full = Path.GetFullPath(rootPath);
        if (full.Length > 3) full = full.TrimEnd('\\', '/');
        Root = new DirNode(full, null);
        try { Root.LastWriteUtc = Directory.GetLastWriteTimeUtc(full); } catch { }
    }

    public List<FileRecord> GetTopFiles()
    {
        lock (_topLock)
        {
            var list = _topFiles.UnorderedItems.Select(x => x.Element).ToList();
            list.Sort((a, b) => b.Size.CompareTo(a.Size));
            return list;
        }
    }

    /// <summary>Dung lượng theo phần mở rộng, lớn nhất trước. Chỉ gọi khi đã quét xong (hoặc đã dừng).</summary>
    public List<TypeStat> GetFileTypes()
    {
        var merged = new Dictionary<string, (long Size, long Count)>(StringComparer.OrdinalIgnoreCase);
        lock (_stats)
        {
            foreach (var s in _stats)
                foreach (var (ext, t) in s.Types)
                {
                    merged.TryGetValue(ext, out var cur);
                    merged[ext] = (cur.Size + t.Size, cur.Count + t.Count);
                }
        }
        return merged.Select(kv => new TypeStat(kv.Key.ToLowerInvariant(), kv.Value.Size, kv.Value.Count))
                     .OrderByDescending(t => t.Size).ToList();
    }

    /// <summary>Dung lượng theo tuổi file (lần sửa cuối), từ mới đến cũ.</summary>
    public List<AgeStat> GetAgeBuckets()
    {
        int n = WorkerStats.AgeLimitsDays.Length + 1;
        var size = new long[n];
        var count = new long[n];
        lock (_stats)
        {
            foreach (var s in _stats)
                for (int i = 0; i < n; i++) { size[i] += s.AgeSize[i]; count[i] += s.AgeCount[i]; }
        }
        return Enumerable.Range(0, n)
            .Select(i => new AgeStat(i < n - 1 ? WorkerStats.AgeLimitsDays[i] : null, size[i], count[i])).ToList();
    }

    public Task RunAsync(CancellationToken token)
    {
        _token = token;
        int workers = Math.Clamp(Environment.ProcessorCount, 4, 24);
        var done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        int alive = workers;

        Push(Root);
        var reg = token.Register(() => { _finished = true; _signal.Release(workers); });

        for (int i = 0; i < workers; i++)
        {
            var t = new Thread(() =>
            {
                try { Worker(); }
                finally
                {
                    if (Interlocked.Decrement(ref alive) == 0) done.TrySetResult();
                }
            })
            {
                IsBackground = true,
                Name = "Scanner" + i,
                Priority = ThreadPriority.BelowNormal,
            };
            t.Start();
        }
        return done.Task.ContinueWith(_ => reg.Dispose(), TaskScheduler.Default);
    }

    private void Push(DirNode node)
    {
        Interlocked.Increment(ref _pending);
        _stack.Push(node);
        _signal.Release();
    }

    private void Worker()
    {
        var stats = new WorkerStats(_startedUtc);
        lock (_stats) _stats.Add(stats);
        while (true)
        {
            _signal.Wait();
            if (_finished) return;
            if (!_stack.TryPop(out var node)) continue;

            try { Process(node, stats); }
            catch { Interlocked.Increment(ref _errors); }

            if (Interlocked.Decrement(ref _pending) == 0)
            {
                _finished = true;
                _signal.Release(64);
                return;
            }
        }
    }

    private readonly struct Entry(string? name, long length, bool isDir, FileAttributes attr, DateTime lastWrite)
    {
        public readonly string? Name = name;
        public readonly long Length = length;
        public readonly bool IsDir = isDir;
        public readonly FileAttributes Attributes = attr;
        public readonly DateTime LastWriteUtc = lastWrite;
    }

    private void Process(DirNode node, WorkerStats stats)
    {
        if (_token.IsCancellationRequested) return;

        string path = node.FullPath;
        CurrentPath = path;

        long bytes = 0;
        int files = 0;
        List<DirNode>? dirs = null;
        long threshold = Volatile.Read(ref _topThreshold);

        try
        {
            var en = new FileSystemEnumerable<Entry>(path, (ref FileSystemEntry e) =>
            {
                if (e.IsDirectory)
                    return new Entry(e.FileName.ToString(), 0, true, e.Attributes, e.LastWriteTimeUtc.UtcDateTime);
                long len = e.Length;
                var lastWrite = e.LastWriteTimeUtc.UtcDateTime;
                stats.Add(e.FileName, len, lastWrite);
                // Chỉ cấp phát chuỗi tên cho file đủ lớn để lọt vào danh sách "file lớn nhất"
                string? name = len >= threshold ? e.FileName.ToString() : null;
                return new Entry(name, len, false, e.Attributes, lastWrite);
            }, Options);

            foreach (var e in en)
            {
                if (e.IsDir)
                {
                    var child = new DirNode(e.Name!, node) { LastWriteUtc = e.LastWriteUtc };
                    if ((e.Attributes & FileAttributes.ReparsePoint) != 0 && IsLinkDirectory(Path.Join(path, e.Name)))
                    {
                        // Junction / symlink: không đi vào để tránh đếm trùng hoặc lặp vô hạn
                        child.IsLink = true;
                        child.Scanned = true;
                    }
                    else if (e.Name!.EndsWith('.') || e.Name.EndsWith(' '))
                    {
                        // "foo." bị Win32 hiểu thành "foo": quét vào sẽ đếm nhầm nội dung thư mục khác
                        child.BadName = true;
                        child.AccessDenied = true;
                        child.Scanned = true;
                        Interlocked.Increment(ref _errors);
                    }
                    (dirs ??= new List<DirNode>()).Add(child);
                }
                else
                {
                    bytes += e.Length;
                    files++;
                    if (e.Name != null && e.Length >= threshold)
                        threshold = OfferTopFile(path, e);
                }
            }
        }
        catch (UnauthorizedAccessException) { node.AccessDenied = true; Interlocked.Increment(ref _errors); }
        catch (IOException) { node.AccessDenied = true; Interlocked.Increment(ref _errors); }

        node.OwnSize = bytes;
        node.OwnFiles = files;
        int dirCount = dirs?.Count ?? 0;
        if (dirs != null) node.Children = dirs.ToArray();
        node.Scanned = true;

        for (var p = node; p != null; p = p.Parent)
        {
            if (bytes != 0) Interlocked.Add(ref p.Size, bytes);
            if (files != 0) Interlocked.Add(ref p.FileCount, files);
            if (dirCount != 0) Interlocked.Add(ref p.DirCount, dirCount);
        }

        if (dirs != null)
        {
            // Đẩy ngược để thư mục đầu tiên được lấy ra trước (duyệt theo chiều sâu)
            for (int i = dirs.Count - 1; i >= 0; i--)
                if (!dirs[i].Scanned) Push(dirs[i]);
        }
    }

    private long OfferTopFile(string dir, in Entry e)
    {
        lock (_topLock)
        {
            var rec = new FileRecord(Path.Join(dir, e.Name), e.Length, e.LastWriteUtc);
            if (_topFiles.Count < TopFileCapacity)
                _topFiles.Enqueue(rec, e.Length);
            else if (e.Length > _topFiles.Peek().Size)
                _topFiles.EnqueueDequeue(rec, e.Length);

            long t = _topFiles.Count < TopFileCapacity ? 0 : _topFiles.Peek().Size + 1;
            Volatile.Write(ref _topThreshold, t);
            return t;
        }
    }

    private static bool IsLinkDirectory(string path)
    {
        try { return new DirectoryInfo(path).LinkTarget != null; }
        catch { return false; }
    }
}

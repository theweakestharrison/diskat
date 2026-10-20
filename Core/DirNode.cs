namespace Diskat.Core;

/// <summary>
/// Một thư mục trong cây đã quét. Các bộ đếm tổng hợp (Size/FileCount/DirCount)
/// được cộng dồn bằng Interlocked từ nhiều luồng quét song song.
/// </summary>
public sealed class DirNode
{
    public static readonly DirNode[] NoChildren = [];

    public string Name;
    public DirNode? Parent;

    // Tổng hợp (bao gồm toàn bộ cây con)
    public long Size;
    public long FileCount;
    public long DirCount;

    // Chỉ các file nằm trực tiếp trong thư mục này
    public long OwnSize;
    public int OwnFiles;

    public DateTime LastWriteUtc;

    /// <summary>Được gán đúng một lần sau khi quét xong thư mục (danh sách hoàn chỉnh).</summary>
    public volatile DirNode[] Children = NoChildren;

    public volatile bool Scanned;
    public bool AccessDenied;
    public bool IsLink;
    /// <summary>Tên kết thúc bằng "." hoặc " ": Win32 sẽ hiểu nhầm đường dẫn nên không quét vào.</summary>
    public bool BadName;

    // Trạng thái giao diện
    public bool IsExpanded;

    public DirNode(string name, DirNode? parent)
    {
        Name = name;
        Parent = parent;
    }

    public string FullPath => Parent is null ? Name : Path.Join(Parent.FullPath, Name);

    public int Depth
    {
        get
        {
            int d = 0;
            for (var p = Parent; p != null; p = p.Parent) d++;
            return d;
        }
    }

    public bool IsAncestorOf(DirNode other)
    {
        for (var p = other.Parent; p != null; p = p.Parent)
            if (ReferenceEquals(p, this)) return true;
        return false;
    }

    /// <summary>Gỡ node khỏi cây (sau khi xóa) và trừ dung lượng ở tất cả thư mục cha.</summary>
    public void Detach()
    {
        var parent = Parent;
        if (parent is null) return;

        Parent = null;
        var list = parent.Children;
        int idx = Array.IndexOf(list, this);
        // Không còn trong danh sách con (ví dụ cha vừa được quét lại): tổng của cha đã không tính node này
        if (idx < 0) return;

        var copy = new DirNode[list.Length - 1];
        Array.Copy(list, 0, copy, 0, idx);
        Array.Copy(list, idx + 1, copy, idx, list.Length - idx - 1);
        parent.Children = copy;

        long size = Size, files = FileCount, dirs = DirCount + 1;
        for (var p = parent; p != null; p = p.Parent)
        {
            Interlocked.Add(ref p.Size, -size);
            Interlocked.Add(ref p.FileCount, -files);
            Interlocked.Add(ref p.DirCount, -dirs);
        }
    }

    /// <summary>True nếu node đang nằm trong cây có gốc là <paramref name="root"/> (chưa bị gỡ ra khi xóa).</summary>
    public bool IsAttachedTo(DirNode root)
    {
        var p = this;
        while (p.Parent != null) p = p.Parent;
        return ReferenceEquals(p, root);
    }

    /// <summary>False nếu có thư mục con chưa quét xong hoặc không đọc được, tức dung lượng có thể thiếu.</summary>
    public bool IsFullyScanned()
    {
        var stack = new Stack<DirNode>();
        stack.Push(this);
        while (stack.Count > 0)
        {
            var n = stack.Pop();
            if (!n.Scanned || n.AccessDenied) return false;
            foreach (var c in n.Children)
                if (!c.IsLink) stack.Push(c);
        }
        return true;
    }

    /// <summary>Trừ dung lượng một file đã bị xóa khỏi thư mục này.</summary>
    public void RemoveFile(long length)
    {
        OwnSize -= length;
        OwnFiles--;
        for (var p = this; p != null; p = p.Parent)
        {
            Interlocked.Add(ref p.Size, -length);
            Interlocked.Add(ref p.FileCount, -1);
        }
    }

    public override string ToString() => Name;
}

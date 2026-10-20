using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using Diskat.Core;
using Diskat.UI;

namespace Diskat;

public partial class MainWindow
{
    private const int MaxFilesPerFolder = 1000;

    private readonly RowCollection _rows = new();
    private readonly Dictionary<DirNode, Row> _dirRows = new();
    private readonly Dictionary<DirNode, List<Row>> _fileRows = new();
    private string _sortKey = "size";
    private bool _sortDesc = true;
    private bool _suppressSelection;
    private bool _selectingFromMap;

    private void ResetTreeState()
    {
        _dirRows.Clear();
        _fileRows.Clear();
        _rows.ReplaceAll([]);
    }

    private Row GetDirRow(DirNode d, int depth)
    {
        if (!_dirRows.TryGetValue(d, out var r) || r.Depth != depth)
        {
            r = Row.ForDir(d, depth);
            _dirRows[d] = r;
        }
        r.IsExpanded = d.IsExpanded;
        return r;
    }

    private List<Row> GetFileRows(DirNode dir, int depth)
    {
        if (_fileRows.TryGetValue(dir, out var list) && (list.Count == 0 || list[0].Depth == depth))
            return list;

        list = new List<Row>();
        if (!dir.Scanned) return list; // chưa quét xong thì chưa cache

        if (dir.OwnFiles > 0)
        {
            var files = FileOps.ListFiles(dir.FullPath);
            files.Sort((a, b) => b.Size.CompareTo(a.Size));
            int n = Math.Min(files.Count, MaxFilesPerFolder);
            for (int i = 0; i < n; i++) list.Add(Row.ForFile(dir, files[i], depth));
            if (files.Count > n)
            {
                long rest = 0;
                for (int i = n; i < files.Count; i++) rest += files[i].Size;
                list.Add(Row.ForSummary(dir, files.Count - n, rest, depth));
            }
        }
        _fileRows[dir] = list;
        return list;
    }

    // ================= Sắp xếp =================

    private readonly record struct SortKey(int Group, long Num, string Name);

    private SortKey KeyOf(Row r)
    {
        int group = r.Kind == RowKind.Summary ? 2 : (_sortKey == "name" && r.Kind == RowKind.File ? 1 : 0);
        long num = _sortKey switch
        {
            "files" => r.FileCountValue,
            "dirs" => r.DirCountValue,
            "date" => r.TimeValue,
            "name" => 0,
            _ => r.SizeBytes,
        };
        return new SortKey(group, num, r.Name);
    }

    private int CompareKeys(SortKey a, SortKey b)
    {
        int c = a.Group.CompareTo(b.Group);
        if (c != 0) return c;
        if (_sortKey == "name")
        {
            c = string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
            return _sortDesc ? -c : c;
        }
        c = a.Num.CompareTo(b.Num);
        if (_sortDesc) c = -c;
        return c != 0 ? c : string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
    }

    private void SortRows(List<Row> rows)
    {
        if (rows.Count < 2) return;
        // Chụp nhanh khóa trước khi sắp xếp vì dung lượng có thể thay đổi trong lúc quét
        var keys = new SortKey[rows.Count];
        var items = rows.ToArray();
        for (int i = 0; i < items.Length; i++) keys[i] = KeyOf(items[i]);
        Array.Sort(keys, items, Comparer<SortKey>.Create(CompareKeys));
        rows.Clear();
        rows.AddRange(items);
    }

    // ================= Làm phẳng cây =================

    private void AppendChildren(List<Row> output, DirNode dir, int depth)
    {
        var kids = new List<Row>(dir.Children.Length + 4);
        foreach (var c in dir.Children) kids.Add(GetDirRow(c, depth));
        kids.AddRange(GetFileRows(dir, depth));
        SortRows(kids);
        foreach (var r in kids)
        {
            output.Add(r);
            if (r.Kind == RowKind.Dir && r.IsExpanded && !r.Dir!.IsLink)
                AppendChildren(output, r.Dir, depth + 1);
        }
    }

    private ScrollViewer? TreeScroller => FindChild<ScrollViewer>(Tree);

    private static T? FindChild<T>(DependencyObject parent) where T : DependencyObject
    {
        int n = VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < n; i++)
        {
            var c = VisualTreeHelper.GetChild(parent, i);
            if (c is T t) return t;
            var r = FindChild<T>(c);
            if (r != null) return r;
        }
        return null;
    }

    /// <summary>Thực hiện thay đổi danh sách nhưng giữ nguyên dòng đang chọn và vị trí cuộn.</summary>
    private void PreserveView(Action change)
    {
        var selected = Tree.SelectedItem as Row;
        var sv = TreeScroller;
        double off = sv?.VerticalOffset ?? 0;
        _suppressSelection = true;
        try
        {
            change();
            if (selected != null && !ReferenceEquals(Tree.SelectedItem, selected) && _rows.Contains(selected))
                Tree.SelectedItem = selected;
        }
        finally { _suppressSelection = false; }
        sv?.ScrollToVerticalOffset(off);
    }

    private void RebuildRows()
    {
        if (_root == null) { _rows.ReplaceAll([]); return; }

        var list = new List<Row>(Math.Max(64, _rows.Count));
        var rootRow = GetDirRow(_root, 0);
        list.Add(rootRow);
        if (rootRow.IsExpanded) AppendChildren(list, _root, 1);

        bool same = list.Count == _rows.Count;
        if (same)
            for (int i = 0; i < list.Count; i++)
                if (!ReferenceEquals(list[i], _rows[i])) { same = false; break; }

        if (!same) PreserveView(() => _rows.ReplaceAll(list));
        foreach (var r in _rows) r.Refresh();
        UpdateSelectionText();
    }

    private void Expand(Row row)
    {
        if (row.Kind != RowKind.Dir || row.IsExpanded || !row.HasChildren) return;
        int idx = _rows.IndexOf(row);
        row.IsExpanded = true;
        if (idx < 0) return;
        var list = new List<Row>();
        AppendChildren(list, row.Dir!, row.Depth + 1);
        PreserveView(() => _rows.InsertRange(idx + 1, list));
    }

    private void Collapse(Row row)
    {
        if (!row.IsExpanded) return;
        int idx = _rows.IndexOf(row);
        row.IsExpanded = false;
        if (idx < 0) return;
        int end = idx + 1;
        while (end < _rows.Count && _rows[end].Depth > row.Depth) end++;
        PreserveView(() => _rows.RemoveRange(idx + 1, end - idx - 1));
    }

    private void Toggle(Row row)
    {
        if (row.IsExpanded) Collapse(row); else Expand(row);
    }

    /// <summary>Mở các thư mục cha cần thiết và trả về dòng của node.</summary>
    private Row? RevealNode(DirNode node)
    {
        if (_root == null) return null;
        var chain = new Stack<DirNode>();
        var p = node;
        while (p != null && !ReferenceEquals(p, _root)) { chain.Push(p); p = p.Parent; }
        if (p == null) return null;

        var cur = GetDirRow(_root, 0);
        while (chain.Count > 0)
        {
            var next = chain.Pop();
            if (!cur.IsExpanded) Expand(cur);
            if (!_dirRows.TryGetValue(next, out var nr)) return cur;
            cur = nr;
        }
        return cur;
    }

    private void SelectRow(Row row)
    {
        Tree.SelectedItem = row;
        Tree.ScrollIntoView(row);
    }

    // ================= Sự kiện cây =================

    private void Expander_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: Row row }) Toggle(row);
        e.Handled = true;
    }

    private static bool IsInsideButton(object? source)
    {
        for (var d = source as DependencyObject; d != null; d = d is Visual ? VisualTreeHelper.GetParent(d) : null)
        {
            if (d is ButtonBase) return true;
            if (d is ListViewItem) return false;
        }
        return false;
    }

    private void Tree_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (IsInsideButton(e.OriginalSource)) return;
        if (Tree.SelectedItem is not Row row) return;
        if (row.Kind == RowKind.Dir) Toggle(row);
        else if (row.Kind == RowKind.File) FileOps.SelectInExplorer(row.FullPath);
    }

    private void Tree_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (Tree.SelectedItem is not Row row) return;
        switch (e.Key)
        {
            case Key.Delete:
                _ = DeleteRowAsync(row, Keyboard.Modifiers.HasFlag(ModifierKeys.Shift));
                e.Handled = true;
                break;
            case Key.Right when row.Kind == RowKind.Dir && !row.IsExpanded && row.HasChildren:
                Expand(row);
                e.Handled = true;
                break;
            case Key.Left:
                if (row.IsExpanded) Collapse(row);
                else
                {
                    var parent = row.Kind == RowKind.Dir ? row.Dir!.Parent : row.Owner;
                    if (parent != null && _dirRows.TryGetValue(parent, out var pr) && _rows.Contains(pr)) SelectRow(pr);
                }
                e.Handled = true;
                break;
            case Key.Enter:
                if (row.Kind == RowKind.Dir) Toggle(row);
                e.Handled = true;
                break;
            case Key.F5:
                if (row.Kind == RowKind.Dir) _ = RescanNodeAsync(row.Dir!);
                e.Handled = true;
                break;
        }
    }

    private void Tree_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        UpdateActionButtons();
        UpdateSelectionText();
        if (_suppressSelection || _selectingFromMap) return;
        if (Tree.SelectedItem is Row r)
        {
            var target = r.Kind == RowKind.Dir ? r.Dir : r.Owner;
            if (target != null && !target.IsLink && !ReferenceEquals(target, Map.Root))
            {
                Map.SetRoot(target);
                UpdateMapHeader();
            }
        }
    }

    private static readonly string[] HeaderKeys = ["ColName", "ColSize", "ColPercent", "ColFiles", "ColFolders", "ColModified"];
    private string _sortHeaderTag = "size";

    private void UpdateHeaderCaptions()
    {
        if (Tree.View is not GridView gv) return;
        for (int i = 0; i < gv.Columns.Count && i < HeaderKeys.Length; i++)
        {
            if (gv.Columns[i].Header is not GridViewColumnHeader h) continue;
            string caption = Loc.T(HeaderKeys[i]);
            h.Content = (h.Tag as string) == _sortHeaderTag ? caption + (_sortDesc ? "  ▼" : "  ▲") : caption;
        }
    }

    private void TreeHeader_Click(object sender, RoutedEventArgs e)
    {
        if (e.OriginalSource is not GridViewColumnHeader { Tag: string tag }) return;
        string key = tag == "pct" ? "size" : tag;

        if (_sortKey == key) _sortDesc = !_sortDesc;
        else { _sortKey = key; _sortDesc = key != "name"; }
        _sortHeaderTag = tag;

        UpdateHeaderCaptions();
        RebuildRows();
    }

    private void CollapseAll_Click(object sender, RoutedEventArgs e)
    {
        if (_root == null) return;
        foreach (var r in _dirRows.Values) r.IsExpanded = false;
        foreach (var n in _dirRows.Keys) n.IsExpanded = false;
        _root.IsExpanded = true;
        RebuildRows();
        if (_rows.Count > 0) SelectRow(_rows[0]);
    }

    private void UpdateSelectionText()
    {
        if (Tree.SelectedItem is Row r)
        {
            string extra = r.Kind == RowKind.Dir ? Loc.F("SelFiles", r.Files) : "";
            SelectionText.Text = $"{r.FullPath}  ·  {r.Size}{extra}";
        }
        else SelectionText.Text = _root == null ? Loc.T("NoSelection") : _root.FullPath;
    }

    private void UpdateActionButtons()
    {
        var sel = Tree.SelectedItem as Row;
        bool hasSel = sel is { Kind: not RowKind.Summary };
        bool canDelete = hasSel && !IsBusy && !ReferenceEquals(sel!.Dir, _root);
        ExplorerBtn.IsEnabled = hasSel;
        RecycleBtn.IsEnabled = canDelete;
        DeleteBtn.IsEnabled = canDelete;
    }

    // ================= Bản đồ =================

    private void UpdateMapHeader()
    {
        var m = Map.Root;
        MapTitle.Text = m?.FullPath ?? "";
        MapSize.Text = m != null ? FileOps.FormatSize(Interlocked.Read(ref m.Size)) : "";
        MapUpBtn.IsEnabled = m != null && _root != null && !ReferenceEquals(m, _root) && m.Parent != null;
    }

    private void MapUp_Click(object sender, RoutedEventArgs e)
    {
        if (Map.Root?.Parent is { } parent && _root != null && !ReferenceEquals(Map.Root, _root))
        {
            Map.SetRoot(parent);
            UpdateMapHeader();
        }
    }

    // True khi ô vừa nhấp trên bản đồ khớp đúng một dòng trong cây. Nếu không (ô "[N file]",
    // "[N mục khác]", file ngoài danh sách), không mở menu chuột phải để tránh xóa nhầm cả thư mục chứa.
    private bool _mapClickExact;

    private void Map_ContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        if (!_mapClickExact) e.Handled = true;
    }

    private void Map_ItemClicked(TreemapItem it)
    {
        _mapClickExact = false;
        _selectingFromMap = true;
        try
        {
            if (it.Node != null)
            {
                var row = RevealNode(it.Node);
                if (row != null) { SelectRow(row); _mapClickExact = true; }
            }
            else
            {
                var orow = RevealNode(it.Owner);
                if (orow == null) return;
                Row? target = orow;
                if (it.FilePath != null)
                {
                    if (!orow.IsExpanded) Expand(orow);
                    var name = Path.GetFileName(it.FilePath);
                    var match = _fileRows.TryGetValue(it.Owner, out var files)
                        ? files.FirstOrDefault(f => f.Kind == RowKind.File && string.Equals(f.Name, name, StringComparison.OrdinalIgnoreCase))
                        : null;
                    if (match != null) { target = match; _mapClickExact = true; }
                }
                SelectRow(target);
            }
        }
        finally { _selectingFromMap = false; }
    }

    private void Map_ItemDoubleClicked(TreemapItem it)
    {
        if (it.Node != null && !it.Node.IsLink && (it.Node.Children.Length > 0 || it.Node.OwnFiles > 0))
        {
            Map.SetRoot(it.Node);
            UpdateMapHeader();
        }
        else if (it.FilePath != null)
        {
            FileOps.SelectInExplorer(it.FilePath);
        }
    }

    private void Map_HoverChanged(TreemapItem? it)
    {
        if (it == null)
        {
            MapHover.Text = Loc.T("MapHint");
            return;
        }
        long total = Map.Root != null ? Interlocked.Read(ref Map.Root.Size) : 0;
        double pct = total > 0 ? it.Size * 100.0 / total : 0;
        string path = it.Node?.FullPath ?? it.FilePath ?? it.Owner.FullPath;
        MapHover.Text = $"{it.Label}  ·  {FileOps.FormatSize(it.Size)}  ·  {pct:0.0}%  ·  {path}";
    }
}

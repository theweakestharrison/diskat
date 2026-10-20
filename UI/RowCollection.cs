using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;

namespace Diskat.UI;

/// <summary>ObservableCollection hỗ trợ chèn/xóa hàng loạt (một sự kiện Reset thay vì hàng nghìn sự kiện).</summary>
public sealed class RowCollection : ObservableCollection<Row>
{
    private const int BulkThreshold = 40;

    private List<Row> Inner => (List<Row>)Items;

    public void ReplaceAll(IEnumerable<Row> rows)
    {
        Inner.Clear();
        Inner.AddRange(rows);
        RaiseReset();
    }

    public void InsertRange(int index, IList<Row> rows)
    {
        if (rows.Count == 0) return;
        if (rows.Count <= BulkThreshold)
        {
            for (int i = 0; i < rows.Count; i++) Insert(index + i, rows[i]);
            return;
        }
        Inner.InsertRange(index, rows);
        RaiseReset();
    }

    public void RemoveRange(int index, int count)
    {
        if (count <= 0) return;
        if (count <= BulkThreshold)
        {
            for (int i = 0; i < count; i++) RemoveAt(index);
            return;
        }
        Inner.RemoveRange(index, count);
        RaiseReset();
    }

    private void RaiseReset()
    {
        OnPropertyChanged(new PropertyChangedEventArgs(nameof(Count)));
        OnPropertyChanged(new PropertyChangedEventArgs("Item[]"));
        OnCollectionChanged(new NotifyCollectionChangedEventArgs(NotifyCollectionChangedAction.Reset));
    }
}

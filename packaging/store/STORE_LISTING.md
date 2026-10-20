# Diskat: Microsoft Store listing

Copy each field into Partner Center > Diskat > Store listings. The package declares **English (en-US)** and **Vietnamese (vi-VN)**, so Partner Center asks for a listing in both languages.

---

## English (en-US)

**Product name:** Diskat

**Short description** (shown at the top of the listing):
> See what's eating your disk space in seconds, then clean it up safely.

**Description:**
> Diskat is a fast disk space analyzer for Windows. Point it at a drive or folder and it scans in parallel, showing the heaviest folders first so you can see at a glance where your storage went.
>
> Browse a folder tree sorted by size with "% of parent" bars, explore a colorful space map where every tile is sized by how much room it takes, and check the Largest files list to find forgotten ISOs, videos and backups.
>
> When you find something you don't need, delete it right inside Diskat. Items go to the Recycle Bin by default so you can always restore them. Every delete asks for confirmation, and critical system folders are protected.
>
> Diskat runs fully offline. It never uploads or collects your files or personal data.

**What's new in this version:**
> First release.

**Product features** (one per line):
- Fast multi-threaded scanning: millions of files in seconds
- Folder tree sorted by size with "% of parent" bars
- Interactive space map (treemap): click to select, double-click to drill in
- Largest files list across the whole scan
- Delete to Recycle Bin or permanently, always with confirmation
- Protects drive roots, Windows, Program Files and your user profile folder
- Live results while scanning; junctions and symlinks are never double-counted
- Optional "Run as Admin" to include protected system folders
- English and Vietnamese interface
- Works offline, no data collection

**Search terms** (max 7):
disk space, storage analyzer, treemap, folder size, free up space, disk cleanup, large files

**Screenshots** (`screenshots/en/`, in order):
1. `01-overview.png`: "Scan a whole drive and see the heaviest folders first"
2. `02-largest-files.png`: "Find the biggest files anywhere on the drive"
3. `03-folder-map.png`: "Space map shows every file and folder by size"
4. `04-safe-delete.png`: "Delete safely: Recycle Bin by default, always confirmed"

**Store logo (optional):** `store-logo-300.png`

---

## Tiếng Việt (vi-VN)

**Tên sản phẩm:** Diskat

**Mô tả ngắn:**
> Biết ngay thư mục nào đang chiếm ổ đĩa của bạn và dọn dẹp an toàn chỉ trong vài giây.

**Mô tả:**
> Diskat là ứng dụng phân tích dung lượng ổ đĩa tốc độ cao cho Windows. Chọn một ổ hoặc thư mục, Diskat quét song song và đưa các thư mục nặng nhất lên đầu để bạn thấy ngay dung lượng đã đi đâu.
>
> Xem cây thư mục sắp xếp theo dung lượng với thanh "% thư mục cha", khám phá bản đồ dung lượng đầy màu sắc (ô càng lớn càng tốn chỗ) và danh sách File lớn nhất để tìm lại các file ISO, video, bản sao lưu bị bỏ quên.
>
> Khi gặp thứ không cần, bạn xóa ngay trong Diskat. Mặc định mục bị xóa sẽ vào Thùng rác nên luôn khôi phục được. Mỗi lần xóa đều có hộp xác nhận, các thư mục hệ thống quan trọng được bảo vệ.
>
> Diskat hoạt động hoàn toàn ngoại tuyến, không tải lên hay thu thập file và dữ liệu cá nhân của bạn.

**Có gì mới:**
> Phiên bản đầu tiên.

**Tính năng:**
- Quét đa luồng tốc độ cao: hàng triệu file chỉ trong vài giây
- Cây thư mục sắp xếp theo dung lượng, có thanh "% thư mục cha"
- Bản đồ dung lượng tương tác: nhấp để chọn, nhấp đúp để đi vào thư mục
- Danh sách file lớn nhất trên toàn bộ lần quét
- Xóa vào Thùng rác hoặc xóa vĩnh viễn, luôn có xác nhận
- Bảo vệ gốc ổ đĩa, Windows, Program Files và thư mục người dùng
- Kết quả cập nhật ngay khi đang quét; không đếm trùng junction/symlink
- Tùy chọn "Quyền Admin" để quét cả thư mục hệ thống bị chặn
- Giao diện tiếng Anh và tiếng Việt
- Hoạt động ngoại tuyến, không thu thập dữ liệu

**Từ khóa tìm kiếm:**
dung lượng ổ đĩa, phân tích ổ cứng, dọn dẹp ổ đĩa, thư mục nặng, file lớn, giải phóng dung lượng, treemap

**Ảnh chụp:** `screenshots/vi/01-tong-quan.png`, sau đó có thể dùng lại 3 ảnh tiếng Anh còn lại.

---

## Other Partner Center fields

| Field | Value |
|---|---|
| Category | Utilities & tools (subcategory: File managers) |
| Pricing | Free |
| Markets | All markets |
| Age rating (IARC questionnaire) | Answer "No" to every content question → rated 3+ / Everyone |
| Privacy policy URL | https://diskat.cc/privacy |
| Support contact | https://diskat.cc (links to GitHub issues) |
| Product declarations | Does not access, collect or transmit personal information |

### Notes for certification (paste into "Submission options > Notes for certification")

> Diskat is a disk space analyzer (WPF desktop app packaged as MSIX).
> - runFullTrust: required for a classic desktop app that scans the file system and deletes files the user selects.
> - allowElevation: used only when the user clicks "Run as Admin", which restarts Diskat elevated so it can also measure protected system folders. The app never elevates on its own.
>
> How to test: launch Diskat, click a drive card (or "Choose folder…") to scan. Select any folder in the tree and press Delete: a confirmation dialog appears and the item goes to the Recycle Bin. No account, network access or sample data is required.

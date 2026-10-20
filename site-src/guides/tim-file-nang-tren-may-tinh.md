---
title: Cách tìm file và thư mục nặng trên máy tính Windows
description: Ổ đĩa đầy mà không biết vì sao? Bốn cách tìm file và thư mục nặng trên Windows 10 và 11: Cài đặt, File Explorer, PowerShell và công cụ phân tích dung lượng.
slug: tim-file-nang-tren-may-tinh
lang: vi
updated: 2026-10-20
alternate: find-large-files-windows
---
Khi ổ đĩa sắp đầy, câu hỏi đầu tiên là: cái gì đang chiếm chỗ? File Explorer không trả lời được, vì nó không hiển thị dung lượng của thư mục. Bài này giới thiệu bốn cách tìm file và thư mục nặng trên Windows 10 và 11, và những gì cần kiểm tra trước khi xóa.

## Cách 1: Xem nhanh trong Cài đặt

Mở **Cài đặt > Hệ thống > Lưu trữ**. Windows chia dung lượng ổ C theo nhóm: ứng dụng, tệp tạm thời, tài liệu, ảnh, video. Bấm **Show more categories** (hiện thêm danh mục) để xem đủ các nhóm, rồi bấm vào từng nhóm để xem chi tiết.

Cách này nhanh nhưng chỉ cho biết nhóm. Nó không chỉ ra thư mục cụ thể, và nhóm "Khác" (Other) thường lớn mà không có giải thích.

## Cách 2: Tìm file lớn bằng File Explorer

1. Nhấn `Win + E` để mở File Explorer, vào ổ đĩa hoặc thư mục cần tìm.
2. Gõ `size:>1GB` vào ô tìm kiếm rồi nhấn Enter. Muốn ngưỡng thấp hơn, thay bằng `size:>500MB`.
3. Chuyển sang chế độ xem **Chi tiết** (Details), bấm vào cột **Kích thước** (Size) để sắp xếp từ lớn đến nhỏ.

Để xem dung lượng của một thư mục, chuột phải vào nó và chọn **Thuộc tính** (Properties).

Giới hạn của cách này:

- Tìm kiếm chỉ trả về file, không trả về thư mục. Một thư mục chứa hàng chục nghìn file nhỏ (bộ nhớ đệm, ảnh, mã nguồn) có thể nặng hàng chục GB mà không file nào vượt 1 GB.
- Tìm trên cả ổ có thể rất chậm, nhất là ở những chỗ Windows không lập chỉ mục.
- Xem Thuộc tính thì phải mở từng thư mục một.

## Cách 3: Dùng PowerShell

Nếu quen dòng lệnh, bạn có thể liệt kê 20 file lớn nhất trong thư mục tài khoản. Mở PowerShell (gõ `powershell` trong Start) và chạy:

`Get-ChildItem $env:USERPROFILE -Recurse -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 20 FullName, @{n='GB';e={[math]::Round($_.Length/1GB,2)}}`

Thay `$env:USERPROFILE` bằng đường dẫn khác, ví dụ `D:\`, để quét chỗ khác. Lệnh này chạy khá chậm trên ổ lớn và cũng không cộng dung lượng theo thư mục.

## Cách 4: Dùng công cụ phân tích dung lượng

Cách nhanh và đầy đủ nhất là dùng phần mềm đo dung lượng của cả cây thư mục. Ví dụ với Diskat, phần mềm miễn phí, mã nguồn mở, chạy từ một file .exe không cần cài và không thu thập dữ liệu:

1. [Tải Diskat](/download) và chạy file vừa tải. Nếu Windows SmartScreen hiện "Windows protected your PC", bấm **More info** rồi **Run anyway** (bản tải về chưa được ký số).
2. Bấm vào thẻ ổ đĩa, ví dụ ổ C, hoặc bấm **Chọn thư mục…** để quét một thư mục. Ứng dụng quét song song nhiều luồng: một ổ SSD 476 GB có 1,95 triệu file mất khoảng 12,5 giây.
3. Xem **Cây thư mục**. Thư mục nặng nhất luôn ở trên cùng. Cột **% thư mục cha** cho biết mỗi thư mục con chiếm bao nhiêu phần của thư mục chứa nó. Dùng phím mũi tên phải để mở, mũi tên trái để thu gọn.
4. Mở thẻ **Bản đồ dung lượng**. Mỗi ô là một thư mục hoặc file, ô càng to càng nặng. Nhấp đúp để đi vào bên trong.
5. Mở thẻ **File lớn nhất** để xem 500 file lớn nhất trên cả ổ, dù chúng nằm ở đâu.

Chuột phải vào một mục để **Hiện trong Explorer** hoặc **Sao chép đường dẫn**. Không cần quyền Admin để quét, nhưng khi đó một số thư mục hệ thống bị chặn đọc và không được tính. Bấm nút **Quyền Admin** nếu muốn số liệu đầy đủ.

Một lưu ý: ứng dụng tính theo kích thước file. Nếu bạn dùng OneDrive với file chỉ lưu trên mạng (online-only), thư mục OneDrive có thể trông lớn hơn chỗ nó thực sự chiếm trên ổ.

## Những thứ thường chiếm nhiều dung lượng

| Thủ phạm | Thường nằm ở | Nên làm gì |
|---|---|---|
| File cài đặt, ISO, video tải về | Downloads | Xóa những gì đã cài hoặc đã xem |
| Video, ảnh gốc | Videos, Pictures, Desktop | Chuyển sang ổ ngoài hoặc đám mây |
| Game | Thư mục thư viện của Steam, Epic | Gỡ bằng launcher của game |
| Máy ảo, WSL, Docker | File .vhdx, .vmdk | Xóa trong chính phần mềm đó |
| Bộ nhớ đệm trình duyệt, ứng dụng chat | AppData\Local | Dọn trong cài đặt của ứng dụng |
| File tạm | AppData\Local\Temp | Xóa trực tiếp |
| Bản Windows cũ | C:\Windows.old | Xóa bằng Dọn đĩa |

Với file tạm, Windows.old và các thư mục hệ thống, xem bài [giải phóng dung lượng ổ C](/guides/giai-phong-dung-luong-o-c).

## Trước khi xóa, kiểm tra ba điều

- **Nó thuộc về ai.** File trong `AppData` thường là dữ liệu của một ứng dụng. Xóa thẳng có thể làm ứng dụng lỗi hoặc mất lịch sử, tin nhắn, cài đặt. Hãy dọn từ bên trong ứng dụng đó nếu có thể.
- **Nó có phải của hệ thống không.** Không đụng vào `C:\Windows`, `Program Files` hay `ProgramData`. Diskat khóa sẵn các thư mục này, cùng gốc ổ đĩa, `C:\Users`, thư mục gốc của từng tài khoản, `AppData\Roaming` và `AppData\Local`, nên không thể lỡ tay xóa.
- **Bạn có lấy lại được không.** Xóa vào Thùng rác trước (phím `Del`), dùng máy vài ngày, rồi mới dọn Thùng rác. Chỉ dùng `Shift+Del` (xóa vĩnh viễn) khi chắc chắn.

Nếu Windows báo file đang mở trong chương trình khác, xem [cách xóa file đang được sử dụng](/guides/xoa-file-dang-duoc-mo).

## Câu hỏi thường gặp

### Vì sao File Explorer không hiện dung lượng thư mục?

Để biết dung lượng một thư mục, phải đọc kích thước của mọi file bên trong nó. Explorer không làm việc này khi bạn duyệt vì sẽ rất chậm. Bạn chỉ xem được từng thư mục qua Thuộc tính.

### Làm sao tìm tất cả file lớn hơn 1 GB?

Trong File Explorer, mở ổ đĩa và gõ `size:>1GB` vào ô tìm kiếm. Công cụ phân tích dung lượng cho kết quả nhanh hơn và xếp sẵn theo kích thước.

### Thư mục AppData rất nặng, xóa được không?

Không nên xóa cả thư mục. AppData chứa dữ liệu và cài đặt của ứng dụng. Hãy xem thư mục con nào nặng, rồi dọn từ trong ứng dụng tương ứng. Riêng `AppData\Local\Temp` thì xóa được.

### Quét cả ổ có cần quyền Admin không?

Không bắt buộc. Thiếu quyền Admin, một số thư mục hệ thống không đọc được nên không được tính vào tổng. Muốn số liệu đầy đủ, hãy chạy công cụ với quyền quản trị.

### Có quét được ổ D, ổ USB hay ổ mạng không?

Được. Diskat hiển thị mọi ổ đĩa đang sẵn sàng, kể cả USB và ổ mạng, kèm dung lượng đã dùng và còn trống. Bấm vào ổ nào để quét ổ đó.

---
title: Cách xem dung lượng thư mục trong File Explorer trên Windows
description: File Explorer để trống cột Kích thước của thư mục. Năm cách xem dung lượng thư mục trên Windows 10 và 11, từ Thuộc tính, PowerShell đến phần mềm miễn phí.
slug: xem-dung-luong-thu-muc
lang: vi
updated: 2026-10-20
alternate: show-folder-size-windows
---
Mở một thư mục trong File Explorer, chuyển sang chế độ xem **Details** (Chi tiết), và cột **Size** (Kích thước) có số cho từng file nhưng để trống cho mọi thư mục. Windows chưa bao giờ hiện dung lượng thư mục ở đây. Để biết một thư mục nặng bao nhiêu, Explorer phải cộng dung lượng của mọi file trong mọi thư mục con, và làm việc đó cho cả một danh sách thư mục sẽ khiến việc duyệt file chậm đi. Dưới đây là năm cách để vẫn có con số, từ xem nhanh một thư mục đến danh sách tất cả thư mục xếp theo dung lượng.

## 1. Thuộc tính: dung lượng của một thư mục

Chuột phải vào thư mục và chọn **Thuộc tính** (Properties), hoặc chọn thư mục rồi nhấn Alt+Enter. Thẻ General cho biết:

- **Kích thước** (Size): tổng dung lượng các file bên trong, tính cả mọi thư mục con
- **Kích thước trên đĩa** (Size on disk): số chỗ các file đó thực sự chiếm trên ổ
- **Chứa** (Contains): số file và thư mục bên trong

Với thư mục lớn, con số sẽ tăng dần trong vài giây khi Windows cộng hết. Bạn có thể chọn nhiều thư mục rồi mở Thuộc tính một lần để xem tổng dung lượng của chúng.

Cách này ổn cho một hai thư mục. Nhưng muốn biết thư mục nào nặng nhất trong hai mươi thư mục thì phải mở Thuộc tính hai mươi lần.

## 2. Mẹo thư mục: xem dung lượng khi rê chuột

File Explorer có thể hiện dung lượng thư mục trong khung nhỏ xuất hiện khi bạn rê chuột lên nó:

1. Trong File Explorer, mở **Options** (Tùy chọn). Trên Windows 11, bấm dấu ba chấm (**See more**) trên thanh công cụ rồi chọn **Options**. Trên Windows 10, nút này nằm ở thẻ **View**.
2. Ở thẻ **View** của Folder Options, tick **Display file size information in folder tips** (hiển thị thông tin kích thước tệp trong mẹo thư mục).
3. Bấm **OK**, rồi rê chuột lên một thư mục.

Khung gợi ý sẽ có dung lượng với thư mục nhỏ và vừa. Với thư mục rất lớn, nó có thể hiện chậm hoặc không có dung lượng.

## 3. Cài đặt Lưu trữ: nhìn tổng quát

**Cài đặt > Hệ thống > Lưu trữ** cho thấy dung lượng ổ đĩa được chia theo các nhóm như Ứng dụng, Tài liệu, Ảnh và Tệp tạm thời. Bấm vào một nhóm để xem chi tiết hoặc dọn dẹp, ví dụ Tệp tạm thời.

Đây là cách xem tổng quát tốt khi ổ C bị đầy, nhưng nó gom theo nhóm chứ không theo thư mục, nên sẽ không cho bạn biết một thư mục dự án hay một game cụ thể đang chiếm 80 GB.

## 4. PowerShell hoặc Command Prompt

Muốn có con số chính xác mà không mở cửa sổ nào, hãy dùng PowerShell. Lệnh này in ra dung lượng thư mục Videos theo GB:

`"{0:N2} GB" -f ((Get-ChildItem "$env:USERPROFILE\Videos" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB)`

Còn lệnh này liệt kê mọi thư mục trong thư mục tài khoản của bạn kèm dung lượng, lớn nhất trước:

`Get-ChildItem "$env:USERPROFILE" -Directory -Force | ForEach-Object { [pscustomobject]@{ Folder = $_.Name; GB = [math]::Round((Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB, 2) } } | Sort-Object GB -Descending`

Trong Command Prompt, lệnh `dir /s "C:\Users\TenBan\Videos"` liệt kê mọi file và kết thúc bằng tổng dung lượng ở dòng **Total Files Listed**.

Cả hai cách đều được, nhưng chậm với thư mục có nhiều file, lặng lẽ bỏ qua các thư mục bạn không có quyền đọc, và bạn phải chạy lại cho từng thư mục muốn xem sâu hơn.

## 5. Phần mềm xem dung lượng thư mục: mọi thư mục cùng lúc

Phần mềm phân tích ổ đĩa làm được điều Explorer không làm: quét một ổ hoặc thư mục một lần rồi hiện dung lượng của mọi thư mục, xếp từ lớn đến nhỏ. [Diskat](/download) là một phần mềm như vậy, miễn phí và mã nguồn mở, cho Windows 10 và 11. Nó chỉ là một file .exe nên không cần cài đặt.

1. Mở Diskat và bấm vào một ổ đĩa, hoặc **Chọn thư mục…** để chọn một thư mục.
2. Cây thư mục hiện dần trong lúc quét. Mỗi thư mục có dung lượng, thanh "% thư mục cha", số file và thư mục con, ngày sửa cuối, và thư mục nặng nhất tự nổi lên đầu.
3. Mở một thư mục để xem bên trong, cũng xếp theo dung lượng. Tab **Bản đồ dung lượng** bên cạnh vẽ chính các thư mục đó thành những ô có kích thước theo dung lượng.

Để mở nhanh từ Explorer, bật **Hiện "Quét bằng Diskat" trong Explorer** trong menu ⋯ của Diskat. Sau đó chuột phải vào bất kỳ thư mục hay ổ đĩa nào và chọn **Quét bằng Diskat**. Trên Windows 11, mục này nằm trong **Show more options** (Hiển thị thêm tùy chọn).

Nếu mục đích là giải phóng dung lượng, bạn xử lý luôn trong cửa sổ đó: tab **File lớn nhất** liệt kê các file lớn nhất, và xóa thì mặc định vào Thùng rác, còn thư mục hệ thống được khóa sẵn.

## Kích thước hay kích thước trên đĩa?

Cửa sổ Thuộc tính có hai con số, và chúng có thể chênh nhau nhiều:

- **Kích thước** là tổng độ dài các file. Đây là con số mà hầu hết các phần mềm, kể cả Diskat, hiển thị.
- **Kích thước trên đĩa** là số chỗ các file chiếm trên ổ. Nó thường lớn hơn một chút vì ổ đĩa cấp chỗ theo từng khối nhỏ. Nó cũng có thể nhỏ hơn nhiều: file nén chiếm ít hơn, và file OneDrive chỉ có trên mạng hầu như không chiếm chỗ cho tới khi bạn mở.

Nếu một thư mục trong OneDrive trông rất lớn mà ổ đĩa vẫn chưa đầy, hãy xem Kích thước trên đĩa. Có thể phần lớn file đang nằm trên đám mây.

## Câu hỏi thường gặp

### Vì sao File Explorer không hiện dung lượng thư mục?

Vì dung lượng thư mục là tổng của mọi file bên trong nó và trong tất cả thư mục con. Tính như vậy cho từng thư mục trong danh sách nghĩa là phải đọc cả cây thư mục mỗi lần bạn mở một thư mục, khiến Explorer chậm đi.

### Làm sao xem dung lượng tất cả thư mục cùng lúc?

Dùng một phần mềm phân tích ổ đĩa như Diskat. Nó quét một lần và hiện dung lượng mọi thư mục trong một cây xếp theo dung lượng. Với PowerShell, lệnh thứ hai ở trên liệt kê các thư mục của một vị trí kèm dung lượng.

### Có thêm được cột dung lượng thư mục vào File Explorer không?

Không thể bằng cài đặt của Windows. Cột Size của Explorer chỉ áp dụng cho file. Mẹo thư mục cho thấy dung lượng khi rê chuột, còn phần mềm phân tích ổ đĩa cho thấy dung lượng của mọi thư mục cùng lúc.

### Thư mục nào thường nặng nhất?

Trên một máy bình thường: Downloads, Videos và Pictures trong thư mục tài khoản, thư viện game, `AppData` chứa dữ liệu và bộ nhớ đệm của ứng dụng, và `C:\Windows` với các file cập nhật. Bài [giải phóng dung lượng ổ C](/guides/giai-phong-dung-luong-o-c) giải thích những gì xóa được an toàn.

---
title: Cách giải phóng dung lượng ổ C trên Windows 10 và 11
description: Ổ C đầy? Cách giải phóng dung lượng ổ C trên Windows 10 và 11 bằng công cụ có sẵn, từng bước, kèm những gì xóa an toàn và những gì không nên đụng vào.
slug: giai-phong-dung-luong-o-c
lang: vi
updated: 2026-10-20
alternate: free-up-disk-space-windows
---
Ổ C đầy làm Windows chậm đi và không tải được bản cập nhật. Phần lớn dung lượng có thể lấy lại bằng công cụ có sẵn trong Windows. Bài này đi từ bước an toàn nhất đến bước nâng cao, và nói rõ chỗ nào có rủi ro.

## Xem ổ C đang dùng bao nhiêu

Nhấn `Win + I` để mở Cài đặt, rồi vào **Cài đặt > Hệ thống > Lưu trữ**. Windows hiển thị dung lượng đã dùng của ổ C, chia theo nhóm: ứng dụng, tệp tạm thời, tài liệu, ảnh, video. Ghi lại con số này để so sánh sau khi dọn.

Trang này chỉ cho biết nhóm, không cho biết thư mục cụ thể. Nếu nhóm "Khác" (Other) chiếm nhiều, bạn cần một công cụ quét thư mục, xem Bước 4.

## Bước 1: Xóa tệp tạm thời

Trong trang **Lưu trữ**, bấm **Tệp tạm thời** (Temporary files). Windows liệt kê các nhóm có thể xóa, kèm dung lượng từng nhóm.

1. Tick các mục hệ thống như tệp tạm thời, tệp Tối ưu hóa phân phối (Delivery Optimization Files), dọn dẹp Windows Update (Windows Update Cleanup), hình thu nhỏ (Thumbnails).
2. Cẩn thận với **Thùng rác** và **Downloads** (Tải xuống). Hai mục này chứa file của bạn. Nếu tick Downloads, toàn bộ file trong thư mục Downloads sẽ bị xóa.
3. Bấm **Remove files** (Xóa tệp).

Bạn cũng có thể dọn thư mục tạm của tài khoản bằng tay: nhấn `Win + R`, gõ `%TEMP%`, Enter, chọn tất cả bằng `Ctrl + A` rồi xóa. File nào đang được dùng sẽ báo lỗi, bấm **Skip** (Bỏ qua). Nếu một file cụ thể không chịu xóa, xem [cách xóa file đang được chương trình khác sử dụng](/guides/xoa-file-dang-duoc-mo).

## Bước 2: Dùng Dọn đĩa và "Dọn tệp hệ thống"

Dọn đĩa (Disk Cleanup) là công cụ cũ nhưng vẫn hữu ích, nhất là sau khi nâng cấp Windows.

1. Nhấn `Win + R`, gõ `cleanmgr`, Enter, chọn ổ C.
2. Bấm **Dọn tệp hệ thống** (Clean up system files) và chọn lại ổ C. Bước này cần quyền quản trị và hiện thêm các mục của hệ thống.
3. Tick các mục muốn xóa, bấm OK.

Mục đáng chú ý nhất là bản cài đặt Windows trước (Previous Windows installation(s)), tức thư mục `C:\Windows.old`. Nó có thể chiếm hàng chục GB sau khi nâng cấp. **Cảnh báo:** xóa nó thì bạn không quay lại được phiên bản Windows cũ. Nếu máy đã chạy ổn vài ngày, xóa là hợp lý. Windows cũng tự xóa thư mục này sau khoảng 10 ngày. Đừng xóa `Windows.old` bằng tay trong File Explorer, hãy dùng Dọn đĩa.

## Bước 3: Bật Cảm biến lưu trữ

Cảm biến lưu trữ (Storage Sense) tự xóa tệp tạm và dọn Thùng rác theo lịch. Trong **Cài đặt > Hệ thống > Lưu trữ**, bật **Cảm biến lưu trữ**, rồi bấm vào nó để chỉnh:

- Tần suất chạy: hằng ngày, hằng tuần, hằng tháng, hoặc khi ổ sắp hết chỗ.
- Số ngày giữ file trong Thùng rác.
- Số ngày giữ file chưa mở trong Downloads. Nếu bạn hay để file quan trọng ở đây, chọn **Never** (Không bao giờ).

## Bước 4: Tìm xem cái gì thực sự đang chiếm chỗ

Dọn file tạm thường chỉ lấy lại vài GB. Phần lớn dung lượng nằm ở file của chính bạn: video, file ISO, game, máy ảo, file cài đặt cũ. File Explorer lại không hiển thị dung lượng thư mục, nên bạn cần một công cụ phân tích dung lượng.

[Diskat](/download) là phần mềm miễn phí, mã nguồn mở, chạy từ một file .exe không cần cài. Bạn bấm vào ổ C, cây thư mục được sắp theo dung lượng, thư mục nặng nhất nằm trên cùng. Trên một ổ SSD 476 GB có 1,95 triệu file, lần quét mất khoảng 12,5 giây, không cần quyền Admin. Thẻ **File lớn nhất** gom 500 file lớn nhất trên cả ổ vào một danh sách.

Xóa trong Diskat mặc định là chuyển vào Thùng rác (phím `Del`) và luôn có hộp xác nhận. Gốc ổ đĩa, `C:\Windows`, `Program Files`, `ProgramData` và thư mục gốc của các tài khoản người dùng bị khóa, nên bạn không thể lỡ tay xóa chúng. Hướng dẫn chi tiết có trong bài [cách tìm file và thư mục nặng](/guides/tim-file-nang-tren-may-tinh).

## Bước 5: Gỡ ứng dụng không dùng

Mở **Cài đặt > Ứng dụng > Ứng dụng đã cài đặt** (Installed apps) trên Windows 11, hoặc **Cài đặt > Ứng dụng > Ứng dụng và tính năng** (Apps & features) trên Windows 10. Sắp xếp theo kích thước, gỡ những gì bạn không còn dùng. Game thường chiếm nhiều nhất.

Đừng xóa thư mục trong `Program Files` bằng tay. Chương trình sẽ bị gỡ dở dang và để lại rác trong hệ thống.

## Bước 6 (nâng cao): Thu gọn thư mục WinSxS

`C:\Windows\WinSxS` chứa các thành phần của Windows và bản cũ của chúng sau mỗi lần cập nhật. Không bao giờ xóa file trong thư mục này bằng tay. Thay vào đó, gõ `cmd` trong Start, chuột phải vào Command Prompt, chọn **Chạy với tư cách quản trị viên** (Run as administrator), rồi chạy:

`DISM /Online /Cleanup-Image /StartComponentCleanup`

Lệnh này xóa các bản thành phần cũ đã được thay thế và có thể chạy hơn mười phút. Lưu ý: nhiều công cụ đo dung lượng thấy WinSxS lớn hơn thực tế, vì nhiều file trong đó là hard link dùng chung với thư mục hệ thống khác.

## Bước 7 (nâng cao): Tắt ngủ đông để xóa hiberfil.sys

`C:\hiberfil.sys` lưu nội dung RAM khi máy ngủ đông (Hibernate) và thường chiếm vài GB, tùy dung lượng RAM. Nếu bạn không dùng ngủ đông, chạy lệnh sau trong Command Prompt quyền quản trị:

`powercfg /hibernate off`

File sẽ tự biến mất. **Cảnh báo:** lệnh này cũng tắt Khởi động nhanh (Fast Startup), nên máy có thể khởi động chậm hơn một chút. Muốn bật lại, chạy `powercfg /hibernate on`. Đừng xóa trực tiếp file `hiberfil.sys`.

## Không xóa pagefile.sys

`C:\pagefile.sys` là bộ nhớ ảo (virtual memory) của Windows. Đừng xóa hay tắt nó: chương trình có thể báo thiếu bộ nhớ hoặc bị đóng đột ngột. Cứ để Windows tự quản lý.

## Khi thư mục bản cập nhật quá lớn

`C:\Windows\SoftwareDistribution\Download` chứa file tải về của Windows Update. Bình thường Windows tự dọn nó. Nếu thư mục này phình to vì bản cập nhật bị kẹt, bạn có thể làm sạch:

1. Mở Command Prompt quyền quản trị, chạy `net stop wuauserv` rồi `net stop bits`.
2. Xóa mọi thứ bên trong `C:\Windows\SoftwareDistribution\Download`, giữ lại chính thư mục.
3. Chạy `net start wuauserv` rồi `net start bits`.

Chỉ làm khi không có bản cập nhật nào đang cài. Windows sẽ tải lại những gì còn cần.

## Tóm tắt: xóa gì và xóa thế nào

| Mục | Xóa được không | Cách đúng |
|---|---|---|
| %TEMP% | Có | Xóa trực tiếp, bỏ qua file đang dùng |
| Thùng rác, Downloads | Có, nhưng xem lại trước | Kiểm tra từng file trước khi xóa |
| Windows.old | Có, nếu không cần quay lại bản cũ | Dọn đĩa, Dọn tệp hệ thống |
| WinSxS | Không xóa tay | Lệnh DISM |
| hiberfil.sys | Không xóa tay | powercfg /hibernate off |
| pagefile.sys | Không | Để Windows quản lý |
| SoftwareDistribution\Download | Có, sau khi dừng dịch vụ | Dừng wuauserv và bits trước |

## Câu hỏi thường gặp

### Xóa file trong thư mục %TEMP% có an toàn không?

Có. Đây là file tạm do chương trình tạo ra. File nào đang được dùng thì Windows không cho xóa, bạn chỉ cần bỏ qua chúng.

### Vì sao dọn xong mà ổ C vẫn đầy?

Phần lớn dung lượng thường là file cá nhân, ứng dụng và game, không phải file rác. Hãy tìm thư mục nặng nhất rồi quyết định giữ hay xóa.

### Có nên xóa thư mục Windows.old không?

Nên, nếu máy đã chạy ổn sau khi nâng cấp và bạn không cần quay lại bản cũ. Hãy xóa bằng Dọn đĩa với "Dọn tệp hệ thống", không xóa bằng tay.

### Tắt ngủ đông có ảnh hưởng gì?

Bạn mất chế độ ngủ đông và Khởi động nhanh. Chế độ ngủ (Sleep) vẫn hoạt động bình thường.

### Có cần cài phần mềm dọn rác không?

Thường là không. Cài đặt, Dọn đĩa và Cảm biến lưu trữ đã dọn được file tạm.

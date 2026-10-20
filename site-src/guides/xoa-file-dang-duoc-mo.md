---
title: Cách xóa file đang được chương trình khác sử dụng
description: Gặp lỗi "file is open in another program" khi xóa? Cách tìm chương trình đang giữ file trên Windows 10 và 11, đóng nó an toàn rồi xóa, kể cả khi khởi động lại.
slug: xoa-file-dang-duoc-mo
lang: vi
updated: 2026-10-20
alternate: delete-file-in-use
---
Bạn bấm xóa một file và Windows hiện thông báo "The action can't be completed because the file is open in another program" (bản tiếng Việt: "Không thể hoàn tất thao tác vì tệp đang mở trong chương trình khác"). Với thư mục, thông báo sẽ nói thư mục hoặc một file bên trong đang được mở. Windows chặn lại vì xóa lúc này có thể làm chương trình kia lỗi hoặc mất dữ liệu. Việc của bạn là tìm ra chương trình đó và đóng nó. Bài này đi từ cách đơn giản nhất đến cách mạnh tay nhất.

## Vì sao file bị khóa

Khi một chương trình mở file, nó thường khóa file lại để chương trình khác không xóa hay sửa giữa chừng. Thủ phạm hay gặp:

- Chương trình bạn vừa dùng: Word, Excel, trình đọc PDF, trình phát video.
- File Explorer, khi khung xem trước hoặc hình thu nhỏ đang đọc file.
- OneDrive hoặc dịch vụ đồng bộ khác đang tải file lên.
- Phần mềm diệt virus đang quét file.
- Một chương trình vẫn chạy ngầm dù bạn đã đóng cửa sổ của nó.

## Cách 1: Đọc kỹ thông báo và đóng chương trình

Nhiều khi thông báo nêu luôn tên chương trình, ví dụ "...because the file is open in Microsoft Word". Lưu công việc, đóng chương trình đó, rồi bấm **Try Again** (Thử lại).

Nếu đã đóng cửa sổ mà vẫn lỗi, chương trình có thể vẫn chạy ngầm. Xem các biểu tượng ở khay hệ thống (góc phải thanh tác vụ) và thoát hẳn từ đó. Bạn cũng có thể mở Task Manager bằng `Ctrl + Shift + Esc`, chọn chương trình trong danh sách và bấm **End task** (Kết thúc tác vụ).

## Cách 2: Tắt khung xem trước của File Explorer

Khung xem trước (Preview pane) hiển thị nội dung file đang chọn, và trong lúc đó nó giữ file. Trong File Explorer, nhấn `Alt + P` để tắt khung này, bấm chọn một file khác, rồi thử xóa lại.

Nếu vẫn không được, khởi động lại File Explorer: trong Task Manager, tìm **Windows Explorer**, chuột phải và chọn **Restart** (Khởi động lại). Thanh tác vụ sẽ biến mất vài giây rồi hiện lại, đó là bình thường.

## Cách 3: Tìm chương trình đang giữ file bằng Resource Monitor

Resource Monitor có sẵn trong Windows và cho biết chính xác tiến trình nào đang mở file:

1. Nhấn `Win + R`, gõ `resmon`, Enter.
2. Mở thẻ **CPU**, rồi mở rộng mục **Associated Handles**.
3. Gõ tên file, hoặc một phần tên, vào ô tìm kiếm của mục này.
4. Cột **Image** cho biết tên tiến trình đang giữ file. Chuột phải vào dòng đó, chọn **End Process** để đóng tiến trình.

**Cảnh báo:** đóng tiến trình kiểu này làm mất mọi dữ liệu chưa lưu của chương trình đó. Đừng đóng các tiến trình hệ thống như `System`, `svchost.exe`, `csrss.exe` hay `lsass.exe`: máy có thể treo hoặc khởi động lại đột ngột. Nếu file bị một tiến trình hệ thống giữ, hãy khởi động lại máy (xem Cách 6).

## Cách 4: Dùng File Locksmith hoặc Process Explorer

Hai công cụ miễn phí của Microsoft làm việc này tiện hơn Resource Monitor:

- **File Locksmith** trong bộ PowerToys: sau khi cài PowerToys, chuột phải vào file và chọn **Unlock with File Locksmith**. Cửa sổ hiện ra liệt kê các tiến trình đang dùng file, kèm nút kết thúc từng tiến trình. Trên Windows 11, nếu không thấy mục này, bấm **Show more options** (Hiển thị thêm tùy chọn) trước.
- **Process Explorer** của Sysinternals: mở menu **Find**, chọn **Find Handle or DLL** (hoặc `Ctrl + F`), gõ tên file để thấy tiến trình đang giữ nó.

Tải các công cụ này từ trang chính thức của Microsoft, không tải từ trang trung gian.

## Cách 5: Để Diskat chỉ ra chương trình đang giữ file

Nếu bạn đang dọn ổ đĩa bằng [Diskat](/download), không cần mở thêm công cụ nào. Khi một file không xóa được vì chương trình khác đang mở, Diskat cho biết chương trình nào đang giữ file và đưa ra hai lựa chọn:

- Đóng chương trình đó rồi xóa lại ngay. Hãy lưu công việc trong chương trình đó trước.
- Xóa file khi Windows khởi động lại, hữu ích khi chương trình đang giữ file không đóng được (cần chạy Diskat bằng quyền Admin).

Như mọi lần xóa khác trong ứng dụng, bạn luôn thấy hộp xác nhận trước, và các thư mục hệ thống quan trọng vẫn bị khóa. Bạn cũng có thể [tìm file và thư mục nặng](/guides/tim-file-nang-tren-may-tinh) rồi xóa ngay trong cùng một cửa sổ.

## Cách 6: Khởi động lại máy hoặc vào Safe Mode

Khởi động lại sẽ đóng mọi chương trình. Hãy xóa file ngay sau khi đăng nhập, trước khi mở lại chương trình đã dùng nó.

Nếu một chương trình tự chạy cùng Windows vẫn giữ file, hãy vào Chế độ an toàn (Safe Mode), nơi chỉ những thành phần tối thiểu của Windows được chạy:

1. Mở Start, bấm nút nguồn, giữ phím `Shift` rồi bấm **Restart** (Khởi động lại).
2. Chọn **Troubleshoot** > **Advanced options** > **Startup Settings** > **Restart**.
3. Khi máy hiện danh sách tùy chọn, nhấn phím `4` để vào Safe Mode.
4. Xóa file, rồi khởi động lại máy như bình thường.

## Khi lỗi không phải do file đang mở

Một số lỗi trông giống nhưng có nguyên nhân khác:

- "You need permission to perform this action": đây là lỗi quyền truy cập. File thuộc hệ thống hoặc một tài khoản khác. Hãy chắc rằng bạn thật sự nên xóa nó trước khi tìm cách lấy quyền.
- Ổ đĩa ở chế độ chỉ đọc, ví dụ thẻ nhớ có khóa gạt bảo vệ ghi: đóng chương trình nào cũng không giúp được.

Sau khi xóa xong, nếu bạn đang cần lấy lại chỗ trống, xem thêm [cách giải phóng dung lượng ổ C](/guides/giai-phong-dung-luong-o-c).

## Câu hỏi thường gặp

### Vì sao đã đóng chương trình mà vẫn không xóa được file?

Chương trình có thể vẫn chạy ngầm, hoặc File Explorer, OneDrive, phần mềm diệt virus đang giữ file. Dùng Resource Monitor hoặc File Locksmith để biết chính xác tiến trình nào.

### Xóa bằng quyền Admin có vượt qua được lỗi này không?

Không. Đây là khóa do một chương trình đang mở file, không phải vấn đề quyền. Bạn phải đóng chương trình đó, hoặc xóa file sau khi khởi động lại.

### Làm sao biết chương trình nào đang dùng file?

Dùng Resource Monitor có sẵn trong Windows (thẻ CPU, mục Associated Handles), PowerToys File Locksmith hoặc Process Explorer. Diskat cũng tự chỉ ra chương trình đang giữ file khi xóa không thành công.

### Kết thúc tiến trình trong Task Manager có nguy hiểm không?

Với ứng dụng thông thường, bạn chỉ mất dữ liệu chưa lưu. Với tiến trình hệ thống, máy có thể treo hoặc khởi động lại đột ngột. Khi không chắc, hãy khởi động lại máy thay vì kết thúc tiến trình.

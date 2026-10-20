---
title: Cách tìm và xóa file trùng lặp trên Windows
description: Tìm file trùng lặp trên Windows 10 và 11 theo nội dung chứ không theo tên, rồi xóa các bản thừa an toàn. Bằng phần mềm miễn phí hoặc bằng PowerShell.
slug: tim-file-trung-lap
lang: vi
updated: 2026-10-20
alternate: find-duplicate-files-windows
---
File trùng lặp tích tụ dần mà không ai để ý: ảnh trong điện thoại được chép vào máy hai lần, một file tải về lại lần nữa, bản sao lưu được chép thêm vào thư mục khác "cho chắc", một video vừa nằm trong Downloads vừa nằm trong Videos. Mỗi bản sao lại chiếm trọn dung lượng một lần nữa. Bài này hướng dẫn cách tìm đúng file trùng trên Windows 10 và 11, chọn bản cần giữ và xóa phần còn lại mà không mất gì.

## Thế nào là file trùng lặp

Hai file trùng nhau khi nội dung của chúng giống hệt nhau đến từng byte. Tên file không nói lên nhiều:

- `IMG_2041.jpg` và `IMG_2041 (1).jpg` thường là cùng một ảnh, nhưng không phải lúc nào cũng vậy.
- Hai file cùng tên `baocao.docx` ở hai thư mục khác nhau có thể là hai tài liệu hoàn toàn khác.
- Một file được đổi tên thành `du-lich.mp4` vẫn có thể là bản sao y hệt của `VID_0815.mp4`.

Vì vậy phần mềm tìm file trùng tốt phải so nội dung. Trước hết nó nhóm file theo dung lượng, vì hai file khác dung lượng không thể giống nhau, rồi mới so nội dung của các file cùng dung lượng, thường bằng mã băm (hash): một "dấu vân tay" ngắn tính từ các byte của file.

## Trước khi bắt đầu: những chỗ không nên đụng vào

Có những bản trùng tồn tại là có lý do. Xóa chúng chỉ được thêm chút chỗ mà có thể làm hỏng thứ khác:

- **Windows, Program Files và ProgramData.** Các chương trình hay để những bản giống hệt nhau của cùng một file ở nhiều thư mục. Đừng đụng vào các thư mục này.
- **AppData.** Ứng dụng giữ dữ liệu, bộ nhớ đệm và đôi khi cả bản cài đặt ở đây.
- **OneDrive và các thư mục đồng bộ khác.** Xóa một file trong thư mục đồng bộ là xóa luôn trên đám mây và trên các máy khác của bạn. Ngoài ra, file "chỉ có trên mạng" (online-only) phải được tải về thì phần mềm mới đọc được.
- **Thư viện ảnh, nhạc do một ứng dụng quản lý.** Những ứng dụng như Lightroom hay iTunes giữ một danh mục trỏ tới file theo đường dẫn. Hãy xóa bản trùng ngay trong ứng dụng đó.
- **Hard link.** Hai tên cùng trỏ tới một dữ liệu trên ổ đĩa không phải là hai bản sao. Xóa một tên không giải phóng được chỗ nào.

An toàn nhất là dọn trong các thư mục của chính bạn: Downloads, Desktop, Documents, Pictures, Videos và thư mục sao lưu trên ổ cứng gắn ngoài.

## Tìm file trùng bằng Diskat

Từ Diskat 1.2, phần mềm phân tích ổ đĩa miễn phí [Diskat](/download) có tab **Trùng lặp**. Nó so theo nội dung, mặc định bỏ qua những chỗ rủi ro nói ở trên, và không bao giờ cho bạn xóa hết mọi bản của một file.

1. Mở Diskat và quét thư mục hoặc ổ đĩa cần dọn, ví dụ `C:\Users\TenBan` hoặc ổ sao lưu gắn ngoài.
2. Mở tab **Trùng lặp** ở bên phải.
3. Chọn dung lượng tối thiểu. Mặc định **Từ 1 MB trở lên** bỏ qua hàng nghìn file nhỏ mà bản trùng của chúng hầu như không chiếm chỗ. Chọn 100 MB nếu chỉ muốn tìm video và file ảnh đĩa lớn.
4. Để nguyên dấu tick ở **Bỏ qua thư mục Windows và chương trình**. Tùy chọn này bỏ qua Windows, Program Files, ProgramData, mọi thư mục AppData và file hệ thống.
5. Bấm **Tìm file trùng**. Diskat chỉ đọc những file có cùng dung lượng với một file khác: trước là 64 KB đầu, sau đó mới đọc cả file. Thanh tiến độ cho biết đã làm tới đâu, và bạn có thể dừng bất cứ lúc nào.
6. Kết quả là các nhóm file giống hệt nhau, xếp theo dung lượng bị lãng phí. Mở một nhóm để xem từng bản, kèm thư mục và ngày sửa cuối.
7. Đánh dấu những bản muốn xóa, hoặc bấm **Chọn tất cả trừ bản mới nhất** để đánh dấu mọi bản trừ bản được sửa gần đây nhất trong mỗi nhóm.
8. Bấm **Xóa bản đã chọn**. Các bản đó vào Thùng rác, nên bạn khôi phục lại được nếu đổi ý. Shift+Del để xóa vĩnh viễn.

Diskat có sẵn vài quy tắc an toàn. Bạn không thể đánh dấu bản cuối cùng của một nhóm. File OneDrive chỉ có trên mạng được bỏ qua và không bao giờ bị tải về. Các hard link được tính là một file và không đánh dấu được. Ngay trước khi xóa, Diskat kiểm tra lại rằng bản bạn giữ vẫn còn và không có file nào thay đổi kể từ lúc tìm.

## Tìm file trùng bằng PowerShell

Nếu không muốn cài gì, PowerShell cũng tìm được file trùng chính xác. Lệnh dưới đây tìm trong thư mục Pictures các file lớn hơn 1 MB, nhóm theo dung lượng, chỉ tính mã băm cho những file cùng dung lượng, rồi liệt kê các bản trùng:

`Get-ChildItem "$env:USERPROFILE\Pictures" -Recurse -File | Where-Object Length -gt 1MB | Group-Object Length | Where-Object Count -gt 1 | ForEach-Object { $_.Group | Get-FileHash -Algorithm SHA256 } | Group-Object Hash | Where-Object Count -gt 1 | ForEach-Object { $_.Group.Path; "" }`

Mỗi khối đường dẫn là một bộ file giống hệt nhau. Mở chúng trong Explorer và tự xóa các bản thừa, để chúng vào Thùng rác.

Cần nhớ:

- Tính mã băm phải đọc hết từng file, nên với thư mục lớn có thể mất khá lâu.
- Nếu thư mục nằm trong OneDrive, tính mã băm một file chỉ có trên mạng sẽ tải file đó về trước.
- Lệnh này không biết hard link, nên hai tên của cùng một file vẫn hiện như hai bản trùng.

## Nên giữ bản nào

Khi hai bản giống hệt nhau, nội dung không quan tâm bản nào được giữ, nhưng bạn thì có. Vài nguyên tắc:

- Giữ bản nằm ở nơi bạn sẽ tìm tới: trong Pictures thay vì Downloads, trong thư mục sao lưu gọn gàng thay vì bản trong "New folder (3)".
- Nếu không chắc, giữ bản mới nhất. Đó thường là bản "hiện tại". Nút **Chọn tất cả trừ bản mới nhất** làm đúng như vậy.
- Trước khi xóa cả loạt, hãy bắt đầu từ những nhóm lãng phí nhiều nhất. Vài video trùng thường giải phóng nhiều hơn hàng nghìn tấm ảnh.

## Câu hỏi thường gặp

### Xóa file trùng lặp có an toàn không?

Có, nếu chúng thật sự giống hệt nhau và là file của bạn. Hãy so theo nội dung chứ không theo tên, giữ lại một bản của mỗi file, xóa vào Thùng rác, và tránh xa Windows, Program Files, ProgramData và AppData.

### Windows có sẵn công cụ tìm file trùng không?

Không. File Explorer sắp xếp được theo tên và dung lượng, giúp nhận ra vài bản sao rõ ràng, nhưng không so được nội dung. Bạn cần một phần mềm hoặc một lệnh PowerShell như ở trên.

### Vì sao hai file cùng tên lại không được coi là trùng?

Vì nội dung của chúng khác nhau. Phần mềm so theo nội dung chỉ nhóm những file có các byte giống hệt nhau, bất kể tên gọi.

### Phần mềm tìm file trùng có tải file OneDrive của tôi về không?

Nhiều phần mềm có, vì phải đọc file thì mới so được. Diskat bỏ qua file OneDrive chỉ có trên mạng và mở file theo cách không kích hoạt việc tải về.

### Xóa file trùng lấy lại được bao nhiêu dung lượng?

Tùy thói quen của bạn. Thư mục ảnh và video từng được chép hoặc nhập vào máy nhiều lần thường là nơi được nhiều nhất. Diskat cho thấy dung lượng lãng phí của từng nhóm và tổng cộng trước khi bạn xóa gì. Dọn xong file trùng, hãy [tìm file và thư mục nặng](/guides/tim-file-nang-tren-may-tinh) hoặc làm theo [hướng dẫn giải phóng dung lượng ổ C](/guides/giai-phong-dung-luong-o-c).

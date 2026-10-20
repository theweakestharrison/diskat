---
title: Phần mềm phân tích dung lượng ổ đĩa miễn phí tốt nhất 2026
description: So sánh Diskat, WizTree, WinDirStat, TreeSize Free và SpaceSniffer: giá, dùng ở công ty, mã nguồn mở, treemap, tìm file trùng và điểm mạnh của từng phần mềm.
slug: phan-mem-phan-tich-o-dia
lang: vi
updated: 2026-10-20
alternate: best-disk-space-analyzer
---
Phần mềm phân tích dung lượng ổ đĩa quét một ổ hoặc thư mục rồi cho bạn biết thư mục và file nào đang chiếm chỗ, để bạn xóa đúng thứ cần xóa thay vì đoán mò. Windows không có sẵn công cụ như vậy: File Explorer thậm chí không hiện dung lượng thư mục trong danh sách. May là có vài phần mềm miễn phí rất tốt. Bài này so sánh năm phần mềm theo những điều quan trọng khi chọn: giá khi dùng ở nhà và ở công ty, giấy phép, cách hiển thị dữ liệu và việc nó giúp bạn làm tiếp.

Diskat là phần mềm của chúng tôi, nên chúng tôi cố gắng công bằng và nói rõ khi nào phần mềm khác phù hợp hơn. Thông tin về các phần mềm khác lấy từ trang web chính thức của chúng, kiểm tra vào tháng 10 năm 2026. Giá và tính năng có thể thay đổi, hãy xem điều khoản hiện tại trước khi quyết định.

## So sánh nhanh

| | Diskat | WizTree | WinDirStat | TreeSize Free | SpaceSniffer |
|---|---|---|---|---|---|
| Dùng ở nhà | Miễn phí | Miễn phí | Miễn phí | Miễn phí | Miễn phí (nhận ủng hộ) |
| Dùng ở công ty | Miễn phí | Cần mua giấy phép | Miễn phí | Chỉ bản trả phí | Trang web không nói rõ |
| Mã nguồn mở | Có (MIT) | Không | Có (GPL-3.0) | Không | Không |
| Giao diện chính | Cây thư mục xếp theo dung lượng | Cây và danh sách file | Cây, loại file, treemap | Cây kiểu Explorer | Treemap |
| Treemap | Có | Có | Có | Có | Có |
| Tìm file trùng | Có (Diskat 1.2) | Có | Có | Bản trả phí | Không có trong danh sách tính năng |
| Xuất dữ liệu | PDF và CSV | CSV | CSV và JSON | PDF | Báo cáo dạng văn bản |
| Cách tải | Một file .exe chạy ngay | Bản cài hoặc bản portable | Bản cài, bản portable hoặc Microsoft Store | Bản cài hoặc bản portable | Bản portable |

## Diskat

Diskat là phần mềm phân tích dung lượng ổ đĩa miễn phí, mã nguồn mở cho Windows 10 và 11, phát hành theo giấy phép MIT. Nó quét nhiều thư mục song song: khi thử trên SSD laptop 476 GB với 1,95 triệu file, Diskat quét xong trong khoảng 12,5 giây mà không cần quyền Admin. Kết quả hiện ngay trong lúc quét và thư mục nặng nhất tự nổi lên đầu.

Giao diện chính là cây thư mục xếp theo dung lượng, bên cạnh là bản đồ dung lượng hai cấp. Các tab khác cho xem 500 file lớn nhất, dung lượng theo loại file và theo tuổi file, và từ Diskat 1.2 có tab **Trùng lặp** tìm file giống hệt nhau, xếp theo dung lượng bị lãng phí. Bạn có thể tìm mọi file theo tên, dung lượng, tuổi, rồi lưu báo cáo PDF hoặc file CSV cho Excel.

Điểm khác biệt lớn nhất của Diskat là xóa an toàn. Mặc định mọi thứ vào Thùng rác, thư mục hệ thống và thư mục gốc của tài khoản người dùng không xóa được, junction không bao giờ bị đi vào, và khi file đang được chương trình khác mở, Diskat cho biết đó là chương trình nào.

**Hợp với:** người dùng gia đình và doanh nghiệp nhỏ cần một công cụ miễn phí vừa tìm thứ chiếm chỗ vừa xóa an toàn, với giấy phép cho phép dùng ở công ty.

## WizTree

WizTree của Antibody Software nổi tiếng nhờ tốc độ. Trên ổ NTFS, nó đọc thẳng bảng Master File Table thay vì mở từng thư mục, nên quét cả ổ rất nhanh. Nó tính file có hard link một lần, nên tổng dung lượng khớp với số Windows báo. WizTree cũng tìm được file trùng, xuất danh sách file ra CSV, và giờ có cả bản cho macOS.

WizTree miễn phí khi dùng cá nhân. Dùng cho mục đích thương mại cần mua supporter code, giá tính theo quy mô tổ chức.

**Hợp với:** quét ổ NTFS lớn nhanh nhất có thể khi dùng ở nhà.

## WinDirStat

WinDirStat là phần mềm phân tích ổ đĩa mã nguồn mở lâu đời, theo giấy phép GPL. Các bản gần đây đã thành một bộ công cụ cho người dùng chuyên sâu: treemap, sunburst, flame graph, thống kê loại file, so sánh dung lượng logic và dung lượng thật, tìm file trùng bằng mã băm nội dung, xem quyền truy cập, lưu bản chụp lần quét, xuất CSV và JSON, công cụ dọn dẹp và cả khôi phục file đã xóa. Nó quét ổ NTFS cục bộ nhanh hơn khi chạy bằng quyền Admin.

**Hợp với:** người dùng chuyên sâu và quản trị viên muốn nhiều công cụ phân tích trong một phần mềm miễn phí, mã nguồn mở.

## TreeSize Free

TreeSize Free của JAM Software, một công ty phần mềm thương mại có bán cả bản trả phí. Bản miễn phí có cây thư mục kiểu Explorer kèm dung lượng, biểu đồ treemap và báo cáo PDF, nhưng chỉ dành cho mục đích cá nhân, phi thương mại. Tìm file trùng, so sánh dung lượng theo thời gian và nhiều tính năng khác nằm trong TreeSize Personal, từ 20,40 € mỗi người mỗi năm, và TreeSize Professional, từ 41 € mỗi người mỗi năm.

**Hợp với:** người muốn phần mềm của một hãng lâu năm, hoặc công ty đã mua bản TreeSize trả phí.

## SpaceSniffer

SpaceSniffer của Uderzo Software là phần mềm freeware chạy không cần cài, xây dựng hoàn toàn quanh một treemap có thể phóng to. Bấm vào một ô để xem bên trong, nhấp đúp để phóng to, và dùng ô lọc để chỉ hiện một loại file, dung lượng hay thời gian nhất định, ví dụ `*.jpg;>1mb`. Bạn có thể gắn màu cho file và mở nhiều chế độ xem có bộ lọc khác nhau trên cùng một lần quét. Nó cũng xuất được báo cáo dạng văn bản.

**Hợp với:** người thích khám phá ổ đĩa bằng hình ảnh và không cần tìm file trùng hay danh sách xếp theo dung lượng.

## Nên chọn phần mềm nào

- **Cần miễn phí cả khi dùng ở công ty:** Diskat hoặc WinDirStat. Cả hai đều mã nguồn mở. WizTree và TreeSize cần mua giấy phép khi dùng cho doanh nghiệp.
- **Hay quét ổ NTFS rất lớn:** WizTree nhanh nhất vì đọc thẳng Master File Table.
- **Muốn nhiều công cụ nhất:** WinDirStat, nhất là khi cần xem quyền truy cập, bản chụp lần quét hay khôi phục file.
- **Muốn dọn dẹp an toàn mà không phải học nhiều:** Diskat, với cây thư mục xếp theo dung lượng, xóa vào Thùng rác mặc định và thư mục hệ thống được khóa sẵn.
- **Thích nhìn bằng hình ảnh:** SpaceSniffer, hoặc bản đồ dung lượng của Diskat và treemap trong các phần mềm còn lại.

Dù chọn phần mềm nào, hãy quét trước rồi mới xóa. Các bài hướng dẫn giải thích những gì xóa được an toàn khi [ổ C bị đầy](/guides/giai-phong-dung-luong-o-c) và cách [tìm file và thư mục nặng](/guides/tim-file-nang-tren-may-tinh). Bạn cũng có thể [tải Diskat](/download) và thử ngay trên ổ đĩa của mình.

## Câu hỏi thường gặp

### Phần mềm phân tích dung lượng ổ đĩa miễn phí nào tốt nhất?

Tùy nhu cầu. WizTree nhanh nhất trên ổ NTFS, WinDirStat có nhiều công cụ nhất, còn Diskat tập trung vào tìm file lớn và xóa an toàn. Diskat và WinDirStat còn miễn phí khi dùng ở công ty vì là phần mềm mã nguồn mở.

### Windows có sẵn công cụ phân tích dung lượng không?

Không hẳn. **Cài đặt > Hệ thống > Lưu trữ** cho thấy dung lượng theo từng nhóm lớn, và cửa sổ **Thuộc tính** (Properties) của một thư mục cho biết dung lượng của nó, nhưng File Explorer không liệt kê dung lượng các thư mục cạnh nhau. Phần mềm phân tích ổ đĩa làm việc đó cho mọi thư mục cùng lúc.

### Phần mềm nào miễn phí khi dùng cho doanh nghiệp?

Diskat (giấy phép MIT) và WinDirStat (GPL) miễn phí khi dùng ở công ty. WizTree cần mua giấy phép khi dùng thương mại, còn TreeSize Free chỉ dành cho mục đích cá nhân. Trang web của SpaceSniffer không nói rõ điều khoản dùng cho doanh nghiệp.

### Dùng phần mềm phân tích ổ đĩa có an toàn không?

Quét chỉ đọc thông tin thư mục nên an toàn. Rủi ro nằm ở bước xóa. Hãy chọn phần mềm xóa vào Thùng rác và khóa thư mục hệ thống, và đừng tự tay xóa gì trong `C:\Windows`, Program Files hay ProgramData.

# Hướng dẫn nộp Diskat lên Microsoft Store

Cài từ Microsoft Store thì Windows **không chặn** (không có màn hình SmartScreen), vì Microsoft ký gói thay bạn. Toàn bộ quy trình miễn phí.

## 1. Tạo tài khoản nhà phát triển (một lần)

1. Vào **https://storedeveloper.microsoft.com**, bấm **Get started for free**.
   (Phải bắt đầu từ trang này mới được miễn phí; vào thẳng Partner Center sẽ là luồng cũ có phí.)
2. Chọn **Individual** (cá nhân) hoặc **Company** (công ty).
3. Đăng nhập tài khoản Microsoft, xác minh danh tính bằng **CCCD/hộ chiếu + ảnh selfie**.

## 2. Giữ tên app

1. Trong **Partner Center** > **Apps and games** > **New product** > **MSIX or PWA app**.
2. Nhập tên **Diskat** > **Check availability** > **Reserve product name**.
   Nếu tên đã có người dùng, chọn tên khác (ví dụ "Diskat Disk Analyzer"). Tên hiển thị trong app không cần đổi.

## 3. Lấy thông tin định danh gói

Vào app vừa tạo > **Product management** > **Product identity**, ghi lại 3 dòng:

| Trong Partner Center | Tham số của script |
|---|---|
| Package/Identity/Name | `-IdentityName` |
| Package/Identity/Publisher | `-Publisher` |
| Package/Properties/PublisherDisplayName | `-PublisherDisplayName` |

## 4. Đóng gói

Mở PowerShell trong thư mục dự án, thay 3 giá trị của bạn vào lệnh:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\build-msix.ps1 -IdentityName "12345TenBan.Diskat" -Publisher "CN=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX" -PublisherDisplayName "Ten Ban"
```

Kết quả: `packaging\out\Diskat_1.0.0.0_x64.msix`.

Mỗi lần cập nhật app, tăng phiên bản (số cuối luôn là 0): `-Version 1.0.1.0`, `1.1.0.0`...

**Cài thử trên máy trước khi nộp (tùy chọn):** bật **Developer Mode** (Settings > Update & Security > For developers), rồi chạy:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\install-test.ps1
```

Gỡ bản thử: thêm `-Uninstall` vào lệnh trên.

## 5. Tạo bản nộp (Start submission)

| Mục | Điền gì |
|---|---|
| **Pricing and availability** | Free, chọn tất cả thị trường |
| **Properties** | Category: *Utilities & tools* (File managers). Privacy policy URL: `https://diskat.cc/privacy`. Không thu thập dữ liệu cá nhân. |
| **Age ratings** | Làm bảng câu hỏi IARC, trả lời "No" hết → 3+ |
| **Packages** | Kéo thả file `.msix` ở bước 4 |
| **Store listings** | Thêm 2 ngôn ngữ **English (United States)** và **Vietnamese**, chép nội dung từ `STORE_LISTING.md`, ảnh trong `screenshots\` |
| **Submission options** | Dán đoạn "Notes for certification" trong `STORE_LISTING.md`. Ở phần **Restricted capabilities**, giải thích `runFullTrust` và `allowElevation` (đã soạn sẵn trong cùng đoạn đó). |

Bấm **Submit to the Store**. Microsoft kiểm duyệt thường mất từ vài giờ tới vài ngày, có kết quả sẽ báo qua email.

## 6. Chính sách quyền riêng tư

Dùng link **https://diskat.cc/privacy** (trang này nằm sẵn trong landing page, thư mục `website/`).

## Nếu bị từ chối vì `allowElevation`

Capability này chỉ phục vụ nút "Run as Admin". Nếu Microsoft không duyệt, xóa dòng sau trong `packaging\AppxManifest.template.xml`, đóng gói lại (tăng version) và nộp lại:

```xml
<rescap:Capability Name="allowElevation" />
```

App vẫn chạy bình thường, chỉ là bản Store sẽ không tự khởi động lại với quyền Admin được.

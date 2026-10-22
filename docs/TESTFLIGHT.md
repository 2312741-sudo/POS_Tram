# Hướng dẫn đưa POS Trạm lên TestFlight

> Phiên bản hiện tại: **1.0.1 (build 2)** — bundle `com.tramapp.tramFlutter` — team `W97CS7VC54`.
> Bộ thông tin dưới đây dùng để dán vào App Store Connect (các form này phải do chủ tài khoản Apple tự điền).

## 1. Thông tin ứng dụng (App Information)

| Mục | Nội dung gợi ý |
|---|---|
| Tên | POS Trạm |
| Phụ đề (≤ 30 ký tự) | Bán hàng & quản lý quán F&B |
| Ngôn ngữ chính | Tiếng Việt |
| SKU | POSTRAM-IOS-001 |
| Danh mục chính | Doanh nghiệp (Business) |
| Danh mục phụ | Năng suất (Productivity) |
| Xếp hạng độ tuổi | 4+ (không có nội dung nhạy cảm) |
| Giá | Miễn phí |
| Support URL | `https://pos-tram.vercel.app/support` |
| Marketing URL | `https://pos-tram.vercel.app/marketing` |
| Hotline hỗ trợ | 0865.062.205 |

### Mô tả (Description)
POS Trạm là ứng dụng bán hàng dành cho quán cà phê, trà sữa và nhà hàng. Nhân viên gọi món theo bàn, gửi phiếu bếp, thu tiền (tiền mặt, chuyển khoản, QR), in hóa đơn qua máy in nhiệt Bluetooth hoặc mạng LAN, và quản lý ca két. Chủ quán theo dõi doanh thu, kho, khuyến mãi, khách hàng tích điểm và nhật ký thao tác cho nhiều chi nhánh.

Tính năng chính:
- Sơ đồ bàn theo khu vực, chuyển bàn, gộp bàn, phiếu tạm tính
- Thực đơn với size, topping, đường/đá, ghi chú món
- Khuyến mãi, voucher, giảm giá theo món / theo đơn
- Khách hàng tích điểm dùng chung toàn chuỗi
- Báo cáo cuối ngày, đơn hủy, xóa món có lý do
- Phân quyền theo vai trò: Chủ quán, Quản lý, Nhân viên, Bếp/Bar
- Đăng nhập một chạm bằng tài khoản Chấm Công Trạm

### Từ khóa (≤ 100 ký tự, cách nhau dấu phẩy)
`pos,bán hàng,quán cà phê,trà sữa,nhà hàng,F&B,hóa đơn,máy in,kho,khuyến mãi`

### Văn bản quảng bá (≤ 170 ký tự)
Quản lý bán hàng, bếp, kho và khách hàng tích điểm cho quán F&B — một ứng dụng cho cả chuỗi chi nhánh.

## 2. Thông tin để kiểm thử (TestFlight → Test Information)

| Mục | Nội dung |
|---|---|
| Mô tả beta | Bản thử nghiệm nội bộ của POS Trạm. Vui lòng thử: đăng nhập, gọi món theo bàn, thanh toán, chọn khách tích điểm, in hóa đơn, xem báo cáo cuối ngày. |
| Email phản hồi | _(điền email của bạn)_ |
| Thông tin liên hệ | Họ tên, số điện thoại, email người phụ trách |
| Yêu cầu đăng nhập | **Có** — cần tài khoản demo cho người duyệt (xem mục 4) |

Nhóm thử nghiệm **Internal** (tối đa 100 người trong tổ chức) không cần Apple duyệt. Nhóm **External** phải qua duyệt beta của Apple (thường 1 ngày).

## 3. Khai báo Quyền riêng tư ứng dụng (App Privacy)

Trả lời theo đúng dữ liệu app thu thập thực tế:

| Loại dữ liệu | Thu thập | Liên kết với danh tính | Dùng để theo dõi | Mục đích |
|---|---|---|---|---|
| Tên, email, số điện thoại (nhân viên đăng nhập, khách hàng tích điểm) | Có | Có | Không | Chức năng ứng dụng |
| Lịch sử mua hàng / đơn hàng | Có | Có | Không | Chức năng ứng dụng |
| Nội dung người dùng (ảnh món) | Có | Không | Không | Chức năng ứng dụng |
| ID người dùng (Firebase UID) | Có | Có | Không | Chức năng ứng dụng, xác thực |
| Nhật ký sự cố | Không (chưa tích hợp) | — | — | — |

- **Theo dõi (Tracking):** Không. Không dùng quảng cáo, không dùng SDK theo dõi chéo ứng dụng.
- **Mã hóa xuất khẩu:** đã khai báo `ITSAppUsesNonExemptEncryption = false` (chỉ dùng HTTPS tiêu chuẩn) nên không bị hỏi từng bản build.

## 4. Tài khoản demo cho người duyệt Apple

Tạo một cửa hàng và tài khoản **riêng cho việc duyệt** (không dùng dữ liệu thật), vai trò Quản lý. Điền vào App Store Connect → App Review Information:

- Tên đăng nhập: _(tài khoản demo)_
- Mật khẩu: _(mật khẩu demo)_
- Mã cửa hàng: _(mã cửa hàng demo)_

> Không đưa mật khẩu thật vào repo. Điền trực tiếp trên App Store Connect.

## 5. Các quyền ứng dụng sẽ xin trên thiết bị

| Quyền | Khi nào | Lý do hiển thị cho người dùng |
|---|---|---|
| Bluetooth | Kết nối máy in nhiệt | Kết nối và in hóa đơn / phiếu bếp |
| Mạng nội bộ | In qua máy in LAN (cổng 9100) | Kết nối máy in qua mạng LAN |
| Thư viện ảnh | Chọn ảnh món | Chọn ảnh cho món trong thực đơn |
| Đăng nhập bằng Apple | Đăng nhập qua Chấm Công Trạm | Entitlement `com.apple.developer.applesignin` |

## 6. Quy trình build và tải lên

```bash
cd app_flutter
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
flutter build ipa --release --export-method app-store
# Kết quả: build/ios/ipa/*.ipa và build/ios/archive/Runner.xcarchive
```

Tải lên (dùng tài khoản Apple đang đăng nhập trong Xcode, không cần khóa API) bằng `xcodebuild -exportArchive` với `destination = upload`, hoặc kéo file `.ipa` vào ứng dụng **Transporter**.

**Mỗi lần tải lên phải tăng số build** (`version: 1.0.1+2` trong `pubspec.yaml`, số sau dấu `+`). Apple từ chối build trùng số.

## 7. Việc cần làm trên Apple Developer / App Store Connect

1. Đăng ký mã định danh `com.tramapp.tramFlutter` (Xcode tự đăng ký khi ký bản build đầu tiên).
2. Bật capability **Sign in with Apple** cho mã đó (Xcode tự bật khi build có file `Runner.entitlements`).
3. App Store Connect → My Apps → **+** → tạo app (tên, ngôn ngữ, bundle ID, SKU).
4. Sau khi tải lên, build xuất hiện ở tab **TestFlight** sau vài phút xử lý; thêm người thử vào nhóm Internal.

## 8. Lưu ý trước khi thử với dữ liệu thật

- App phải kết nối được Firebase production (`tramapp-36f53`); cần mạng.
- Rules mới đã triển khai: **bản app cũ không tích/đổi điểm được** — mọi máy bán hàng phải cài bản mới này.
- Đăng nhập Chấm Công Trạm cần cấu hình `assets/config/chamcong_firebase_options.json` (file này nằm ngoài git); nếu thiếu thì nút đăng nhập Chấm Công tự ẩn.

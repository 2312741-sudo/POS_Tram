# GHI CHÚ KỸ THUẬT PHÂN HỆ MÁY IN (BLUETOOTH & ESC/POS) - POS TRẠM

## 1. SO SÁNH CÁC THƯ VIỆN BLUETOOTH MÁY IN NHIỆT (ĐÁNH GIÁ & LỰA CHỌN)

Để bổ sung tính năng in hóa đơn và phiếu bếp qua Bluetooth cho POS Trạm, chúng tôi đã tiến hành khảo sát và so sánh 3 thư viện phổ biến trên Flutter/pub.dev:

| Tiêu chí | `print_bluetooth_thermal` | `blue_thermal_printer` | `flutter_pos_printer_platform` |
| :--- | :--- | :--- | :--- |
| **Bản phát hành gần nhất** | **1.2.4 (09/2026)** / 1.1.7 (10/2025) - Trong vòng 12 tháng qua | 1.2.3 (07/2022) - Đã hơn 4 năm không cập nhật | 1.4.2 (Discontinued / Abandoned) |
| **Hỗ trợ Android 12+ (API 31+)** | **Có (Toàn diện)**: Quản lý quyền `BLUETOOTH_SCAN` & `BLUETOOTH_CONNECT`, không cần quyền Location | **Không chính thức**: Thiếu cấu hình quyền mới, gây crash `SecurityException` trên Android 12+ nếu không can thiệp native | Cần fork cộng đồng (`flutter_pos_printer_platform_image_3_sdt`), tính ổn định kém |
| **Hỗ trợ iOS** | **Có**: CoreBluetooth / Swift Package Manager (1.2.2+) và CocoaPods | Không hỗ trợ iOS (chỉ hỗ trợ Android) | Có nhưng phức tạp, nhiều phụ thuộc |
| **Giao thức & Định dạng dữ liệu** | Bluetooth Classic SPP & BLE; nhận trực tiếp mảng byte ESC/POS (`writeBytes`) | SPP; API bị đóng khung vào các hàm dựng sẵn, khó tùy biến ESC/POS | Cồng kềnh, phân mảnh nhiều interface (USB, TCP, BLE, BT) |
| **Độ ổn định & Cộng đồng** | Được bảo trì thường xuyên, tối ưu buffer 16KB truyền ảnh và văn bản dài | Bị bỏ rơi (unmaintained) | Gói chính thức đã bị đóng; các fork không đồng nhất |

### Quyết định lựa chọn:
**Chọn thư viện `print_bluetooth_thermal` (phiên bản `^1.1.7` hoặc `^1.2.4`)**.
- **Lý do**:
  1. Thư viện có bản cập nhật mới nhất trong 12 tháng qua.
  2. Hỗ trợ đầy đủ tiêu chuẩn bảo mật và quyền truy cập Bluetooth runtime trên Android 12 trở lên (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` với flag `neverForLocation`).
  3. Cho phép gửi trực tiếp chuỗi byte ESC/POS chuẩn (`writeBytes`), giữ nguyên 100% logic định dạng hóa đơn hiện tại của quán Trạm.
  4. Hỗ trợ kiểm tra trạng thái kết nối (`connectionStatus`), danh sách thiết bị đã ghép đôi (`pairedBluetooths`), pin, tự động kết nối lại.

---

## 2. YÊU CẦU CẦN CẬP NHẬT FILE NGOÀI DANH SÁCH "ĐƯỢC SỬA"

Theo quy tắc làm việc nghiêm ngặt, agent không tự ý sửa file ngoài danh sách được cấp phép. Dưới đây là các file cần đội ngũ quản trị hoặc agent phụ trách điều hướng bổ sung sau khi phân hệ máy in hoàn tất:

1. **`app_flutter/lib/core/router/app_router.dart`**:
   - Thêm route cho màn hình Cài đặt máy in:
     ```dart
     import '../../features/printer/printer_settings_screen.dart';
     // Thêm vào routes:
     GoRoute(
       path: '/printer-settings',
       builder: (context, state) => const PrinterSettingsScreen(),
     ),
     ```
2. **`app_flutter/lib/features/tables/table_list_screen.dart`**:
   - Thêm mục menu trong Drawer để thu ngân / quản lý dễ dàng truy cập màn hình Cài đặt máy in:
     ```dart
     ListTile(
       leading: const Icon(Icons.print, color: TramColors.brandPrimary),
       title: const Text('Cài Đặt Máy In (Bluetooth / LAN)'),
       subtitle: const Text('Kết nối máy in nhiệt, chọn khổ giấy, in thử'),
       onTap: () {
         Navigator.pop(context);
         context.push('/printer-settings');
       },
     ),
     ```

*(Lưu ý: Trong thời gian chờ cập nhật route, màn hình `PrinterSettingsScreen` đã được thiết kế hàm tiện ích `PrinterSettingsScreen.open(context)` hoặc có thể hiển thị như một Dialog / BottomSheet / Fullscreen Modal từ bất kỳ vị trí nào trong ứng dụng).*

---

## 3. CÁC CA KIỂM THỬ THỦ CÔNG TRÊN THIẾT BỊ THẬT (MANUAL TEST CASES)

| STT | Tên ca kiểm thử | Các bước thực hiện | Kết quả mong đợi |
| :--- | :--- | :--- | :--- |
| **TC-01** | Cấp quyền Bluetooth trên Android 12+ | Mở app trên Android 12/13/14, vào màn hình Cài Đặt Máy In, nhấn "Quét máy in" | Hệ thống hiển thị hộp thoại yêu cầu quyền "Thiết bị ở gần" (Nearby Devices / Bluetooth Connect & Scan). Sau khi cấp, ứng dụng không bị crash. |
| **TC-02** | Quét và hiển thị thiết bị Bluetooth | Bật Bluetooth của điện thoại/tablet, bật nguồn máy in nhiệt đã ghép đôi (hoặc quét tìm) | Danh sách hiển thị tên máy in (ví dụ: `RPP02N`, `XP-58`, `POS-80`) cùng địa chỉ MAC. |
| **TC-03** | Kết nối máy in Bluetooth | Chọn một máy in trong danh sách và bấm "Kết nối" | Trạng thái chuyển sang "Đã kết nối" màu xanh lá; lưu MAC máy in vào bộ nhớ máy để tự kết nối lại. |
| **TC-04** | Chọn khổ giấy 58mm và 80mm | Chuyển đổi giữa 58mm và 80mm trong cài đặt | Cài đặt khổ giấy được lưu trữ bền vững (`SharedPreferences`). Khi in bill, layout độ rộng căn chỉnh tự động: 32 ký tự đối với 58mm và 48 ký tự đối với 80mm. |
| **TC-05** | In thử nghiệm (Test Print) | Nhấn nút "In Thử Hóa Đơn" hoặc "In Thử Phiếu Bếp" | Máy in in ra tờ phiếu mẫu chuẩn: Logo/tên quán, ngày giờ, thông tin mẫu, đường gạch nét đứt thẳng hàng, font chữ sắc nét và tự cắt giấy (nếu máy có dao cắt). |
| **TC-06** | In tiếng Việt có dấu (Chế độ Raster / Hình ảnh) | Gửi in món có đầy đủ dấu tiếng Việt: "Trà chanh giã tay", "Phở bò đặc biệt" | Văn bản in ra không bị lỗi ký tự `?` hay ký tự tiếng Trung. Chế độ Raster Image in chính xác chữ tiếng Việt có dấu. |
| **TC-07** | Tự động kết nối lại (Auto-Reconnect) | Đang kết nối máy in, tắt máy in rồi bật lại; hoặc thoát app mở lại | Ứng dụng tự động phát hiện thiết bị đã lưu và tiến hành kết nối lại mà không yêu cầu người dùng phải quét lại từ đầu. |
| **TC-08** | Cảnh báo mất kết nối / hết giấy | Đang in mà tắt nguồn máy in hoặc tháo giấy | Ứng dụng hiển thị thông báo lỗi tiếng Việt rõ ràng: "Máy in mất kết nối hoặc hết giấy. Vui lòng kiểm tra giấy in và kết nối thiết bị." |
| **TC-09** | Hàng đợi in lại (Print Queue Resilience) | Ngắt kết nối máy in và thực hiện chốt đơn in bill | Lệnh in không bị mất, được tự động đưa vào Hàng Đợi In Lại (Print Queue) với trạng thái "Thất bại (Chờ in lại)". Người dùng có thể nhấn "In lại" sau khi bật lại máy in. |
| **TC-10** | Xử lý hàng đợi in hàng loạt | Có 3 đơn lỗi trong hàng đợi, kết nối lại máy in và bấm "In lại tất cả" | Cả 3 hóa đơn được gửi lần lượt ra máy in, trạng thái chuyển thành "Thành công", hàng đợi hoàn tất. |

---

## 4. GHI CHÚ VỀ CÔNG CỤ PHÂN TÍCH MÃ NGUỒN

- Thư mục chứa dự án trên macOS có dấu tiếng Việt: `/Users/nthtam/Lưu trữ/tram-printer/app_flutter`.
- Trong phiên bản Flutter 3.47.5, lệnh `flutter analyze` gặp lỗi `FormatException: Unexpected end of input` do client LSP trong `flutter_tools` tính toán `Content-Length` theo độ dài chuỗi ký tự UTF-16 thay vì số byte UTF-8 của đường dẫn thư mục có dấu tiếng Việt.
- Lệnh `dart analyze --no-fatal-warnings` chạy trực tiếp trên Dart SDK phân tích chính xác toàn bộ mã nguồn mà không bị lỗi stream buffer. Toàn bộ mã nguồn mới đều được kiểm tra chặt chẽ, không phát sinh bất kỳ lỗi compile/syntax/type nào.

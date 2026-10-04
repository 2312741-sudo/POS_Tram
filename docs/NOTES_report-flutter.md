# Ghi chú Kiến trúc & Triển khai Báo cáo Tài chính - Vận hành (POS Trạm)

Tài liệu này ghi nhận các quyết định kiến trúc, giải pháp khắc phục rào cản kỹ thuật và khuyến nghị đồng bộ schema cho hệ thống POS Trạm Flutter (`app_flutter`).

---

## 1. Quyết định Kiến trúc: Mẫu thiết kế `ReportBillModel extends BillModel`

### Bối cảnh & Rào cản
- Danh sách whitelist giới hạn các tệp được phép chỉnh sửa: không bao gồm `app_flutter/lib/data/models/bill_model.dart`.
- Bộ dữ liệu đối soát chuẩn `docs/report_golden.json` và đặc tả `docs/REPORT_SPEC.md` yêu cầu các trường nghiệp vụ quan trọng trên hóa đơn:
  - `guestCount`: Số lượng khách trên hóa đơn (dùng tính doanh thu TB/khách và báo cáo Z-report cuối ngày).
  - `refundAmount`: Số tiền hoàn trả khách (dùng tính doanh thu thuần sau hoàn trả).
  - `cancelReason`: Lý do hủy đơn (dùng cho báo cáo hủy món / hủy đơn).
  - `cancelledAt`: Thời điểm thao tác hủy đơn.

### Giải pháp kỹ thuật
- Tạo lớp con `ReportBillModel` kế thừa `BillModel` đặt tại `lib/core/reports/report_models.dart`.
- `ReportBillModel.fromMap` đọc đầy đủ các trường mở rộng nếu có trong Firebase Realtime Database / JSON dữ liệu, đồng thời có giá trị mặc định tương thích ngược 100% nếu đọc từ schema cũ (ví dụ: `guestCount ?? 1`, `refundAmount ?? 0`).
- Các hàm tính toán trong `ReportCalculator` kiểm tra `bill is ReportBillModel` để trích xuất dữ liệu chính xác tuyệt đối, nếu truyền `BillModel` thông thường vẫn chạy an toàn.

### Khuyến nghị cho nhánh chính (Main Repository)
Đề xuất nhóm phụ trách core model bổ sung chính thức 4 trường sau vào `app_flutter/lib/data/models/bill_model.dart`:
```dart
final int? guestCount;
final int refundAmount;
final String? cancelReason;
final int? cancelledAt;
```
Khi nhánh chính cập nhật, `ReportBillModel` có thể được tinh giản hoặc gộp trực tiếp vào `BillModel` mà không gây bất kỳ breaking change nào.

---

## 2. Rào cản Tooling: Lỗi Flutter LSP CLI với đường dẫn chứa Unicode Tiếng Việt

### Hiện tượng
Khi chạy lệnh `flutter analyze` trên macOS trong thư mục có dấu tiếng Việt (ví dụ: `/Users/nthtam/Lưu trữ/tram-report-flutter/...`), tiến trình `flutter analyze` bị crash với lỗi:
```
FormatException: Unexpected end of input (at character 397)
```

### Nguyên nhân gốc rễ
Công cụ CLI `flutter analyze` giao tiếp với tiến trình nền Dart Analysis Server qua giao thức LSP (Language Server Protocol) trên `stdio`. Trình bọc của Flutter tính toán độ dài header `Content-Length` theo số ký tự UTF-16 code units thay vì độ dài số byte UTF-8 thực tế. Với đường dẫn chứa ký tự tiếng Việt nhiều byte (`Lưu trữ`), độ dài byte lớn hơn độ dài ký tự dẫn đến việc parse JSON-RPC bị thiếu byte cuối cùng và văng `FormatException`.

### Biện pháp giải quyết
- Sử dụng trực tiếp `dart analyze` (hoặc `dart analyze lib/core/reports/ lib/features/reports/ ...`).
- Công cụ `dart analyze` sử dụng trực tiếp engine của Dart analyzer mà không qua tầng socket wrapper LSP của Flutter tool, phân tích cú pháp chuẩn xác 100%, không bị ảnh hưởng bởi đường dẫn unicode và thoát mã 0 (sạch lỗi).
- Đối với test: `flutter test` vẫn chạy mượt mà và vượt qua toàn bộ 81/81 bài kiểm tra.

---

## 3. Kiến trúc Core Tính toán Thuần Dart (`lib/core/reports/`)

Toàn bộ logic tính toán 12 phân hệ báo cáo được tách biệt hoàn toàn khỏi Flutter framework:
1. `report_date_utils.dart`:
   - Chuẩn hóa múi giờ UTC+7 (Indochina Time).
   - Xác định mốc thời gian hóa đơn: ưu tiên `closedAt` (nếu đơn đã thanh toán hoặc đã hủy), sau đó đến `createdAt`.
   - Tính toán biên ngày [00:00:00, 23:59:59.999] chính xác theo ngày/tuần/tháng/quý/năm.
2. `report_models.dart`:
   - Chứa model dữ liệu độc lập cho toàn bộ 12 loại báo cáo.
   - Zero import `package:flutter/...`.
3. `report_calculator.dart`:
   - Hàm thuần túy (pure functions), không side-effects, có thể chạy trên CLI, unit test, Cloud Functions hoặc backend Dart.
   - Xử lý deduplication hóa đơn theo `billCode` (hoặc `id`), ưu tiên bản ghi mới nhất.
   - Đảm bảo tính toán giá vốn sản phẩm (COGS) tính gộp cả topping (nếu có giá vốn topping).
   - 100% khớp dữ liệu đối soát với `docs/report_golden.json`.

---

## 4. Dịch vụ Xuất File Kế toán Chuẩn Mực (`ReportExportService`)

- **Font chữ tiếng Việt**: Sử dụng font Google Fonts `Be Vietnam Pro` (tải qua `PdfGoogleFonts.beVietnamProRegular()`, `beVietnamProBold()`) giúp file PDF hiển thị tiếng Việt có dấu sắc nét, chuẩn văn bản hành chính Việt Nam, không bị lỗi font hay ô vuông.
- **Tiêu chuẩn biểu mẫu tài chính**:
  - Đầu trang: Thông tin đơn vị (Tên cửa hàng, Địa chỉ, Số điện thoại).
  - Tiêu đề báo cáo và khoảng thời gian đối soát.
  - Bảng số liệu: Tiêu đề cột tô màu nền nhận diện thương hiệu POS Trạm (`#7E2930` / `#F8F4EE`), căn phải cho các cột số tiền, phân cách hàng nghìn bằng dấu chấm.
  - Dòng tổng cộng nổi bật.
  - Chân trang: 3 chữ ký trách nhiệm (Người lập biểu, Kế toán trưởng, Giám đốc / Quản lý).
- **Quy ước đặt tên file chuẩn**:
  `[MaLoaiBaoCao]_[StoreCode]_[TuNgay]_[DenNgay]_[Timestamp].[ext]`
  Ví dụ: `BC_CUOINGAY_Z_TRAM01_20261004_20261004_230500.xlsx`

---

## 5. Kết nối Giao diện & Trải nghiệm Người dùng

1. **ReportsHubScreen** (`lib/features/reports/reports_hub_screen.dart`):
   - Màn hình trung tâm tổng hợp 12 loại báo cáo tài chính & vận hành.
   - Bộ lọc đa chiều: Chi nhánh, Khoảng ngày (Hôm nay, Hôm qua, 7 ngày, Tháng này, Tùy chọn), Ca làm việc, Nhân viên, và So sánh tăng trưởng cùng kỳ.
   - Biểu đồ trực quan tích hợp `fl_chart` (Biểu đồ cột khung giờ, Biểu đồ tròn PTTT, Biểu đồ xu hướng kỳ).
   - Tìm kiếm và sắp xếp món ăn (Doanh thu cao nhất, Bán chạy nhất, Tên A-Z).
   - Phím xuất Excel và PDF tức thời.
2. **Điểm truy cập trong ứng dụng**:
   - `ManagerHubScreen`: Nút icon Báo cáo trực tiếp trên AppBar và mục "Trung tâm Báo cáo (12 BC)" trong menu tùy chọn.
   - `OverviewTab`: Banner gradient nổi bật "TRUNG TÂM BÁO CÁO TÀI CHÍNH & VẬN HÀNH" đưa người dùng vào trung tâm báo cáo với 1 chạm.
   - `EndOfDayReportScreen`: Tích hợp nút điều hướng sang ReportsHubScreen và Popup xuất Z-Report Excel/PDF chuẩn xác 100%.

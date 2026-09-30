# POS Trạm (Tram F&B Management System)

> **Hệ sinh thái Quản lý Bán hàng & Chuỗi Cửa hàng F&B Đa Nền tảng**  
> Kết hợp đồng bộ hai chiều thời gian thực giữa **Web Admin (Next.js 16)** và **App POS (Flutter 3)** trên nền tảng **Firebase Realtime Database**.

---

## 🌟 Tính Năng Nổi Bật

- **Chuỗi Đa Cửa Hàng (Multi-Store Ecosystem)**: Quản lý và chuyển đổi nhiều chi nhánh linh hoạt, cô lập dữ liệu theo từng cửa hàng (`/stores/{STORE_CODE}`) và tổng hợp số liệu toàn chuỗi tự động.
- **Đồng Bộ Phòng Bàn Thời Gian Thực**: 21 bàn chuẩn phân bố trên 5 khu vực (`Khu A`, `Khu B`, `Khu C`, `Khu D`, `Mang về`). Cập nhật trạng thái tức thì giữa Web và App POS.
- **Thực Đơn Chuẩn KiotViet F&B**: 37 món với đầy đủ cấu hình kích cỡ (Sizes S/M/L), danh sách Topping phong phú, tùy chỉnh % đường và % đá.
- **Quản Lý Ca Két Tiền & Đối Soát Doanh Thu**: Tự động tính toán doanh thu Tiền mặt, VietQR, Thẻ ngân hàng, cảnh báo chênh lệch tiền két và xuất báo cáo tài chính Excel.
- **Tích Hợp Phần Cứng Chuyên Dụng**:
  - Tự động sinh mã VietQR Napas 24/7 theo từng hóa đơn.
  - In phiếu thanh toán và phiếu báo bếp qua mạng LAN (cổng 9100) hoặc Bluetooth SPP với chuẩn ESC/POS.
- **Bảo Mật & Phân Quyền Vai Trò (RBAC)**: Phân quyền chi tiết cho Admin, Quản lý, Thu ngân, Phục vụ và Bếp cùng cơ chế quyền tối thượng cho Chủ quán.

---

## 📚 Tài Liệu Kỹ Thuật

Tài liệu chi tiết về kiến trúc hệ thống, sơ đồ phân tầng, lược đồ cơ sở dữ liệu và các quy trình vận hành:
👉 **[Xem Tài Liệu Kỹ Thuật Chi Tiết (TAI_LIEU_KY_THUAT.md)](docs/TAI_LIEU_KY_THUAT.md)**

Các tài liệu bổ trợ:
- [Lược đồ Cơ sở Dữ liệu Firebase (docs/database_schema.md)](docs/database_schema.md)
- [Báo cáo Kiểm toán & Tối ưu Hệ thống (docs/audit_report.md)](docs/audit_report.md)

---

## 🚀 Cấu Trúc Dự Án

```
Tram_FnB_System/
 ├── web/                 # Web Admin Dashboard (Next.js 16, React 19, Tailwind CSS)
 ├── app_flutter/         # App POS Điểm Bán Hàng (Flutter 3, Dart, Provider)
 ├── docs/                # Tài liệu kỹ thuật, kiến trúc & lược đồ database
 ├── .gitignore           # Cấu hình bỏ qua file biên dịch, dependencies & caches
 └── README.md            # Giới thiệu dự án
```

---

## 🛠️ Hướng Dẫn Khởi Chạy

### 1. Khởi chạy Web Quản trị (Next.js)
```bash
cd web
npm install
npm run dev
# Truy cập: http://localhost:3000
```

### 2. Khởi chạy App POS (Flutter)
```bash
cd app_flutter
flutter pub get
flutter test
flutter run
```

---
*Bản quyền © 2026 POS Trạm. Phát triển cho hệ thống chuỗi F&B chuyên nghiệp.*

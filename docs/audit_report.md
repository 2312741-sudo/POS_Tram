# BÁO CÁO AUDIT HỆ THỐNG VÀ KẾ HOẠCH CONVERT SANG FLUTTER
**Dự án:** Hệ Thống Quản Lý Gọi Món & Nhà Hàng Trạm (Trạm F&B System)  
**Ngày thực hiện:** 24/08/2026  
**Thư mục dự án mới:** `D:\Tram_FnB_System\`

---

## 1. TỔNG QUAN AUDIT CÁC DỰ ÁN HIỆN HỮU

Qua quá trình rà soát toàn bộ các thư mục tại `D:\TramApp` và `D:\app_cham_cong`, kết quả kiểm tra cấu trúc mã nguồn như sau:

### 1.1. Ứng dụng Android Native (`D:\TramApp\TramApp\app\src\main\java`)
- **Công nghệ:** Java, Android SDK, Android Jetpack (Room Database SQLite), Google Firebase Realtime Database.
- **Các thành phần cốt lõi:**
  - `AppDatabase.java`, `ProductDao.java`, `TableDao.java`, `OrderHistoryDao.java`, `KitchenOrderDao.java`, `OnlineOrderDao.java`, `UserDao.java`, `ZoneDao.java`, `CategoryDao.java`: Hệ thống Room SQLite lưu trữ dữ liệu offline.
  - `FirebaseHelper.java`: Đồng bộ dữ liệu real-time lên Firebase `ungdungdidong-94edd-default-rtdb`.
  - `EscPosPrinter.java`: Mã lệnh ESC/POS in nhiệt kết nối máy in qua Bluetooth/Socket.
  - `MainActivity.java`, `OrderActivity.java`, `KitchenActivity.java`, `TableListActivity.java`, `UserManagementActivity.java`, `OrderHistoryActivity.java`, `QRCodeActivity.java`, `OnlineOrderActivity.java`.
- **Đánh giá:** Logic nghiệp vụ chạy ổn định nhưng UI Android XML truyền thống, khó bảo trì đồng thời trên iOS, mã nguồn phân tán giữa Room DB và Firebase. Đã được sao lưu sang `docs/legacy_reference/android_java`.

### 1.2. Ứng dụng iOS Native (`D:\TramApp\ios\TramApp_iOS`)
- **Công nghệ:** Swift, SwiftUI, Combine.
- **Các thành phần:**
  - `Models/` (`Order.swift`, `Product.swift`, `Table.swift`, `AdditionalModels.swift`).
  - `Services/` (`FirebaseManager.swift`, `LocalDatabase.swift`, `TcpPrinter.swift` kết nối TCP Socket Port 9100).
  - `Views/` (`PaymentView.swift`, `OrderDetailView.swift`, `KitchenView.swift`, `SettingsView.swift`, `ZoneAndCategoryViews.swift`).
- **Đánh giá:** Thiết kế SwiftUI hiện đại, đã có cơ chế in bill qua mạng LAN TCP Socket (`TcpPrinter.swift`). Đã sao lưu sang `docs/legacy_reference/ios_swift`.

### 1.3. Web Admin Dashboard (`D:\TramApp\New folder\tram_web_admin`)
- **Công nghệ:** Next.js 15 (App Router), React 19, TypeScript, Tailwind CSS, Lucide Icons, Firebase Web SDK v11.
- **Chức năng đã có:**
  - Dashboard tổng quan (Doanh thu, số đơn, món bán chạy).
  - Quản lý danh mục & món ăn (`app/dashboard/products`).
  - Quản lý bàn & khu vực (`app/dashboard/tables`).
  - Quản lý tài khoản nhân viên (`app/dashboard/users`).
  - Quản lý đơn hàng & xuất báo cáo Excel (`app/dashboard/orders`, `lib/export.ts`).
  - Lịch sử kiểm toán cơ bản (`app/dashboard/audit`).
- **Đánh giá:** Web Admin hiện đại, sạch sẽ. Đã được sao chép nguyên vẹn sang `D:\Tram_FnB_System\web` để tiếp tục nâng cấp.

### 1.4. Hệ Thống Chấm Công Trạm (`D:\app_cham_cong\cham_cong_tram`)
- **Kiến trúc xác thực:** Sử dụng cơ chế **Mã Cửa Hàng (Store Code)** 2 bước:
  1. Người dùng nhập Store Code (VD: `TRAM01`) để tìm đúng tenant / cửa hàng.
  2. Đăng nhập bằng tài khoản/mật khẩu của nhân viên thuộc cửa hàng đó.
  3. Cấp quyền phân tầng chặt chẽ (Chủ cửa hàng, Quản lý, Nhân viên).
- **Đánh giá:** Mô hình Multi-Tenant và RBAC Permission Matrix này rất lý tưởng để áp dụng vào hệ thống F&B, giúp mỗi quán/chi nhánh có dữ liệu hoàn toàn độc lập và bảo mật.

---

## 2. KIẾN TRÚC HỆ THỐNG MỚI TẠI `D:\Tram_FnB_System`

### 2.1. Cấu Trúc Dự Án
```text
D:\Tram_FnB_System\
├── app_flutter\                    # Toàn bộ Flutter App (Mobile + Tablet POS)
│   ├── lib\
│   │   ├── app\                   # App wrapper, router, theme
│   │   ├── core\
│   │   │   ├── auth\              # Multi-tenant Store Code Auth State & Session
│   │   │   ├── permissions\       # Dynamic Permission Matrix & RBAC
│   │   │   ├── printer\           # Driver in bill ESC/POS (Bluetooth & LAN TCP)
│   │   │   ├── vietqr\            # Sinh mã thanh toán VietQR động
│   │   │   └── utils\             # Tiện ích format tiền tệ VND, thời gian
│   │   ├── data\
│   │   │   ├── models\            # Models (Bill, Promo, AuditLog, Role, Store...)
│   │   │   └── services\          # Firebase Realtime DB multi-tenant service
│   │   ├── features\
│   │   │   ├── auth\              # Đăng nhập Store Code + Nhân viên
│   │   │   ├── permissions\       # Quản lý ma trận phân quyền & vai trò tùy biến
│   │   │   ├── billing\           # Quản lý hóa đơn: Ghép, tách bill, VAT, Giảm giá, In bill
│   │   │   ├── promotions\        # Quản lý khuyến mãi, Voucher, Gộp CTKM
│   │   │   ├── audit_logs\        # Lịch sử thao tác & chống gian lận (Snapshot diff)
│   │   │   ├── tables\            # Sơ đồ bàn, chuyển bàn, trạng thái thời gian thực
│   │   │   ├── kitchen\           # Màn hình KDS Bếp/Bar
│   │   │   ├── menu\              # Quản lý món & danh mục
│   │   │   ├── dashboard\         # Thống kê doanh thu & báo cáo ca
│   │   │   └── online_orders\     # Đơn đặt online qua QR code tại bàn
│   │   └── widgets\               # Components dùng chung (Matrix table, dialogs...)
├── web\                            # Web Admin Dashboard (Next.js 15)
└── docs\                           # Tài liệu & mã tham khảo
    ├── audit_report.md
    └── legacy_reference\          # Android Java, iOS Swift, Old Lib
```

---

## 3. THIẾT KẾ CƠ SỞ DỮ LIỆU MULTI-TENANT (FIREBASE REALTIME DB)

Toàn bộ dữ liệu được phân chia theo nút gốc `stores/{storeCode}`:

```json
{
  "stores": {
    "TRAM01": {
      "storeInfo": {
        "storeCode": "TRAM01",
        "storeName": "Trạm Chanh - Chi Nhánh 1",
        "address": "123 Phù Đổng Thiên Vương, Đà Lạt",
        "phone": "0987654321",
        "bankId": "MB",
        "bankAccount": "0987654321",
        "accountName": "NGUYEN THANH TAM",
        "allowStackPromotions": true,
        "defaultVatRate": 8
      },
      "roles": {
        "ROLE_MANAGER": {
          "id": "ROLE_MANAGER",
          "name": "Quản lý ca",
          "permissions": ["VIEW_MENU", "EDIT_MENU", "CREATE_ORDER", "EDIT_ORDER", "SPLIT_MERGE_ORDER", "CANCEL_ORDER", "APPLY_DISCOUNT", "VIEW_REPORTS", "VIEW_AUDIT_LOG", "MANAGE_STAFF"]
        },
        "ROLE_CASHIER": {
          "id": "ROLE_CASHIER",
          "name": "Thu ngân",
          "permissions": ["VIEW_MENU", "CREATE_ORDER", "EDIT_ORDER", "APPLY_DISCOUNT", "PRINT_BILL", "VIEW_OWN_HISTORY"]
        }
      },
      "users": {
        "admin": {
          "username": "admin",
          "fullName": "Chủ Quán (Root Admin)",
          "password": "admin",
          "roleId": "OWNER",
          "isRootOwner": true,
          "customPermissions": []
        }
      },
      "promotions": {},
      "bills": {},
      "audit_logs": {}
    }
  }
}
```

---

## 4. KẾ HOẠCH TRIỂN KHAI 4 TÍNH NĂNG NGHIỆP VỤ

1. **Module Đăng nhập Multi-Tenant:**
   - Hỗ trợ chọn nhanh danh sách quán đã lưu hoặc nhập Mã Cửa Hàng.
   - Ghi nhớ phiên làm việc trên thiết bị.
2. **Module Phân quyền Ma trận:**
   - Danh sách 18 đầu việc chi tiết trong nhà hàng.
   - Cho phép chủ quán cấu hình vai trò tùy ý và tick quyền riêng cho từng nhân viên.
3. **Module Quản lý Hóa đơn & In Bill:**
   - Ghép nhiều bàn thành 1 hóa đơn, tách một số món trong bàn ra hóa đơn mới.
   - Kết nối máy in Bluetooth ESC/POS và máy in LAN (IP:Port 9100).
   - Tự động sinh mã VietQR chuyển khoản ngân hàng chuẩn Napas247.
4. **Module Khuyến mại & Voucher:**
   - Quản lý voucher code, giảm theo %, giảm theo tiền, giảm theo món.
   - Cơ chế gộp nhiều khuyến mãi và hiển thị rõ ràng từng khoản giảm dưới tổng tiền hàng.
5. **Module Lịch sử Thao tác & Chống Gian lận:**
   - Log snapshot before/after mọi thao tác nhạy cảm (hủy món, giảm giá, sửa hóa đơn, in lại bill).
   - Bảng lọc log trực quan theo nhân viên, loại thao tác và thời gian.

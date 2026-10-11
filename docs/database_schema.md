# SƠ ĐỒ CƠ SỞ DỮ LIỆU MULTI-TENANT (FIREBASE REALTIME DATABASE)
**Hệ thống:** Trạm F&B System  
**Phiên bản:** 2.0 (Flutter + Multi-Tenant Store Code)

---

## 1. NGUYÊN TẮC CÔ LẬP DỮ LIỆU (TENANT ISOLATION)
Mỗi quán hoặc chi nhánh hoạt động độc lập dưới nút gốc:
`/stores/{STORE_CODE}/...` (Ví dụ: `/stores/TRAM01/...`)

---

## 2. CHI TIẾT CÁC BẢNG VÀ CẤU TRÚC JSON

### 2.1. Cấu hình Quán (`/stores/{storeCode}/storeInfo`)
```json
{
  "storeCode": "TRAM01",
  "storeName": "Trạm Chanh - Chi Nhánh 1",
  "address": "123 Phù Đổng Thiên Vương, Đà Lạt",
  "phone": "0987654321",
  "wifiName": "TramChanh_Free",
  "bankId": "MB",
  "bankAccount": "0987654321",
  "accountName": "CHU QUAN FNB",
  "allowStackPromotions": true,
  "defaultVatRate": 8.0,
  "kitchenPrinterIp": "192.168.1.200",
  "billPrinterIp": "192.168.1.201",
  "printerType": "LAN"
}
```

### 2.2. Vai trò tùy biến (`/stores/{storeCode}/roles/{roleId}`)
```json
{
  "id": "ROLE_CASHIER",
  "name": "Thu Ngân",
  "description": "Gọi món, tạo hóa đơn, áp dụng khuyến mãi và in bill.",
  "permissions": [
    "VIEW_MENU",
    "OPEN_TABLE",
    "CHANGE_TABLE",
    "MERGE_SPLIT_TABLE",
    "SEND_KITCHEN",
    "CREATE_BILL",
    "EDIT_BILL",
    "APPLY_PROMOTION",
    "PRINT_BILL"
  ],
  "isSystemRole": true
}
```

### 2.3. Tài khoản nhân viên & Phân quyền riêng (`/stores/{storeCode}/users/{username}`)
```json
{
  "username": "thungan1",
  "fullName": "Nguyễn Thu Ngân",
  "password": "123",
  "roleId": "ROLE_CASHIER",
  "isRootOwner": false,
  "customPermissions": [
    "MANUAL_DISCOUNT",
    "SPLIT_MERGE_ORDER"
  ],
  "isActive": true,
  "phone": "0912345678"
}
```

### 2.4. Bàn ăn & Sơ đồ khu vực (`/stores/{storeCode}/tables/{zone_name}`)
```json
{
  "name": "Bàn 01",
  "zone": "Tầng 1",
  "inUse": true,
  "currentOrderJson": "[{\"productId\":1,\"name\":\"Trà chanh giã tay\",\"price\":25000,\"quantity\":2,\"note\":\"Ít đá\",\"isSentKitchen\":true,\"discountAmount\":0}]",
  "mergedIntoTable": null,
  "currentBillId": "BILL_1771901234567"
}
```

### 2.5. Hóa đơn chi tiết (`/stores/{storeCode}/bills/{billId}`)
```json
{
  "id": "BILL_1771901234567",
  "billCode": "HD-260824-143000",
  "tableName": "Bàn 01",
  "zone": "Tầng 1",
  "createdAt": 1771901234567,
  "closedAt": 1771902400000,
  "status": "PAID",
  "staffUsername": "thungan1",
  "staffFullName": "Nguyễn Thu Ngân",
  "items": [
    {
      "productId": 1,
      "name": "Trà chanh giã tay",
      "price": 25000,
      "quantity": 2,
      "note": "Ít đá",
      "isSentKitchen": true,
      "discountAmount": 0
    }
  ],
  "subTotal": 50000,
  "discounts": [
    {
      "promoId": "PROMO_WELCOME",
      "promoCode": "CHAOBAN20",
      "description": "Giảm 20% Chào Bạn Mới",
      "amount": 10000
    }
  ],
  "totalDiscount": 10000,
  "vatRate": 8.0,
  "vatAmount": 3200,
  "finalAmount": 43200,
  "paymentMethod": "TRANSFER_QR",
  "notes": ""
}
```

### 2.6. Chương trình Khuyến Mãi / Voucher (`/stores/{storeCode}/promotions/{promoId}`)
```json
{
  "id": "PROMO_WELCOME",
  "code": "CHAOBAN20",
  "name": "Giảm 20% Chào Bạn Mới",
  "description": "Giảm 20% tối đa 50k cho đơn từ 50k",
  "type": "PERCENT_BILL",
  "value": 20,
  "maxDiscountAmount": 50000,
  "minBillAmount": 50000,
  "startDate": 1771900000000,
  "endDate": 1774500000000,
  "isActive": true,
  "usageCount": 14,
  "maxUsage": 200
}
```

### 2.7. Lịch Sử Thao Tác & Chống Gian Lận (`/stores/{storeCode}/audit_logs/{logId}`)
```json
{
  "timestamp": 1771901234567,
  "username": "thungan1",
  "userFullName": "Nguyễn Thu Ngân",
  "userRole": "ROLE_CASHIER",
  "action": "CANCEL_KITCHEN_ITEM",
  "targetType": "ITEM",
  "targetId": "1",
  "details": "Hủy món đã gửi bếp: Trà chanh giã tay x1 tại Bàn 01",
  "beforeState": { "quantity": 2, "subTotal": 50000 },
  "afterState": { "quantity": 1, "subTotal": 25000 },
  "isSuspicious": true
}
```

### 2.8. Điểm khách hàng: cấu hình hạng, lịch sử, dùng chung (Web Admin)
- `storeInfo.loyaltyTiers` (Chủ quán ghi): mảng `[{ "name": "Bạc", "minPoints": 200 }, ...]` do Chủ quán tự đặt từng mốc (có thể áp cho mọi chi nhánh).
  Hạng của khách = hạng cao nhất mà `totalPoints` (tổng điểm đã tích lũy) đạt được. Chưa cấu hình → chỉ có hạng gốc "Thành viên" 0 điểm.
- `storeInfo.sharedLoyalty` = `{ enabled, deductOrder: "HOME_FIRST"|"LARGEST_FIRST", confirmedBy, confirmedAt }`: Chủ quán xác nhận gộp điểm theo SĐT
  giữa các chi nhánh và thứ tự trừ. Trừ điểm dùng chung ghi một `update()` đa chi nhánh: giảm `diem_hien_tai/currentPoints` từng nơi
  (giữ `totalPoints`), `point_history` loại `POOL_REDEEM`, audit `LOYALTY_POOL_REDEEM`. Người trừ phải có quyền ghi tại MỌI chi nhánh liên quan.
- `customers/{id}`: khách mới do Web tạo có `diem_hien_tai = currentPoints = totalPoints = 0` (rules chỉ cho Thu ngân tạo khách 0 điểm).
- `point_history/{key}` (chỉ tạo mới, Chủ/Quản lý ghi, Thu ngân trở lên đọc): sổ **chỉnh điểm thủ công**
  `{ customerId, customerName, type:"ADJUST", mode:"SET|ADD|SUB", delta, before, after, reason, by, byName, at }`.
- `loyalty_applied/{billId}/{redeem|award|refund}` (POS ghi): sổ cái đổi/tích/hoàn điểm theo hóa đơn — cùng với `point_history`
  là nguồn của báo cáo **Lịch sử điểm khách hàng**.
- Hóa đơn: `pointsUsed`, `pointsDiscount`, `customerId/Name/Phone`; báo cáo chi tiết hóa đơn tách "Giảm giá đổi điểm" khỏi "Giảm giá voucher/khác".

### 2.9. Gọi món trên Web (dự phòng POS), khu vực, kho, dữ liệu mẫu
- Gọi món trên Web (kèm size / đường / đá / topping theo quy tắc của POS: `selectedSize`, `sizeExtraPrice`, `selectedSugar`, `selectedIce`, `selectedToppings`, `toppingPrice`) ghi `tables/{khóa}` (`inUse`, `openedAt`, `guestCount`, `currentOrderJson`, `currentOrderCode`, `actionLogsJson`) và
  `kitchen_orders/{key}` theo đúng hợp đồng của Flutter (`KitchenOrderModel`); audit action `WEB_ORDER`.
- `zones/{tên khu}` = `{ name }`; Web thêm khu (kèm tạo nhanh N bàn `tables/{khu}_{tên bàn}`) và chỉ xóa được khu không còn bàn.
- Nhập tồn thủ công: ghi `stock_balances/{store}_{itemId}` + `stock_events` (`documentType` = `OPENING` hoặc `STOCK_ADJUSTMENT`) + audit `STOCK_SET_ONHAND`.
  Nhóm hàng của nguyên vật liệu lưu ở `catalog_items.managementGroup` và `groupIds[0]`.
- Dữ liệu mẫu (đơn + KM từng loại) mang cờ `isSample: true`, mã `MAU-xxxx`; xóa được bằng nút "Xóa dữ liệu mẫu".


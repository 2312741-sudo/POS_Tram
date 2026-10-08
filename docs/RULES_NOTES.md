# Ghi Chú Security Rules POS Trạm (Chốt Chính Thức)

> **LƯU Ý QUAN TRỌNG:**
> Bộ Security Rules này (`database.rules.json`) được thiết kế và áp dụng cho project Firebase mà **POS Trạm là ứng dụng duy nhất sử dụng Realtime Database** (`tramapp-36f53`).
> Cấp gốc (`rules/`) được cấu hình chặn mặc định (`.read: false, .write: false`), triệt tiêu hoàn toàn mọi nút gốc cũ.

---

## 0. Bản vá bảo mật 10/2026 (đọc trước khi deploy)

### Lỗ hổng đã vá
1. **Tự đăng ký làm Chủ quán (CRITICAL):** trước đây bất kỳ ai có tài khoản Firebase Auth (API key là công khai) đều ghi được `stores/{s}/users/{uid} = {roleId:'owner', isRootOwner:true}` rồi đọc/ghi toàn bộ quán.
   - Client **không còn được tạo hồ sơ của chính mình**. Hồ sơ chỉ được tạo qua Cloud Function `createStaffAccount` (Admin SDK), script migrate, hoặc Chủ quán/Quản lý.
   - "Thành viên quán" giờ bắt buộc: `userIndex/{uid}/{storeCode} === true` (chỉ Admin SDK ghi được) **và** hồ sơ `users/{uid}` tồn tại **và** `isActive !== false`. Đã bỏ fallback "chỉ cần `users/{uid}` tồn tại". Hồ sơ đã xóa nhưng còn sót `userIndex` cũng mất quyền.
   - Nhân viên chỉ tự ghi được `lastLoginAt`, `lastPasswordChangedAt`, `mustChangePassword = false`.
2. **Quản lý tự nâng quyền (CRITICAL):** Quản lý không được đổi `roleId/role/isRootOwner/isActive/username/uid` của chính mình, không thêm `customPermissions` cho mình, không cấp vai trò Chủ quán (`owner`, `ROLE_OWNER`, `admin`, …) và không sửa/xóa hồ sơ Chủ quán.
3. **Sửa hóa đơn đã thanh toán (HIGH):** `bills/{id}` & `history/{id}`:
   - Mọi nhân viên: tạo/sửa hóa đơn chưa chốt và ghi bản hủy (`CANCELLED`) cho bàn đang mở.
   - Chuyển sang `PAID`/`REFUNDED` hoặc sửa hóa đơn đã `PAID/CANCELLED/REFUNDED`: chỉ **Thu ngân / Quản lý / Chủ quán**.
   - Xóa: chỉ **Quản lý / Chủ quán**.
   - Validate: `status` thuộc tập cho phép; `subTotal/finalAmount/totalAmount` là số ≥ 0; các trường giảm giá/VAT là số.
   - `tables/{key}`, `kitchen_orders/{id}`: mọi nhân viên ghi; xóa chỉ Quản lý/Chủ quán.
4. **Khóa tạm đăng nhập không hoạt động:** client cũ đọc/ghi `login_attempts` khi chưa đăng nhập nên luôn bị rules chặn. Nay chuyển sang Cloud Function **`staffSignIn`** (xem mục 3).

### Nhóm vai trò dùng trong rules
| Nhóm | `roleId` |
| :--- | :--- |
| Chủ quán | `isRootOwner === true`, `owner`, `ROLE_OWNER` |
| Quản lý | `manager`, `manager_1`, `manager_2`, `ROLE_MANAGER`, `ROLE_MANAGER_1`, `ROLE_MANAGER_2` |
| Thu ngân (người thanh toán) | `cashier`, `ROLE_CASHIER`, `employee` (alias thu ngân trên Web) |
| Nhân viên khác | `waiter`, `ROLE_WAITER`, `ROLE_KITCHEN`, … (chỉ là thành viên quán) |

### Nút mới cho luồng thanh toán
| Nhánh | Quyền ghi |
| :--- | :--- |
| `counters/bill_seq/{yyMMdd}` | Thành viên; số nguyên, chỉ tăng đúng +1 (transaction); cấm xóa |
| `bill_stock_applied/{billId}` | Người thanh toán tạo **một lần** (`true`); sửa/xóa: Quản lý/Chủ quán |
| `stock_balances/{id}` | Quản lý: toàn quyền. Người thanh toán: chỉ **giảm** `onHandQty`/`inventoryValue`, không đổi `averageCostScaled` |
| `stock_events/{id}` | Quản lý: toàn quyền. Người thanh toán: chỉ tạo mới, `documentType === 'SALE'`, `qtyDeltaBase <= 0` |
| `campaign_counters/{id}` | Quản lý: toàn quyền. Người thanh toán: `spentMoney`, `committedUseCount` chỉ tăng |
| `customer_campaign_counters/{key}` | Quản lý: toàn quyền. Người thanh toán: `usedCount` chỉ tăng |
| `vouchers/{campaignId}/{voucherId}` | Quản lý: toàn quyền. Người thanh toán: chỉ cập nhật voucher đã có, không đổi mã/campaign, không sửa voucher đã `REDEEMED`/`CANCELLED` |
| `promotions/{id}/usageCount` | Người thanh toán: chỉ tăng đúng +1 |
| `voucher_lookup` | Quản lý/Chủ quán |

Checkout có thể dùng một lệnh `update()` nhiều đường dẫn tại `stores/{storeCode}`; rules được đánh giá theo từng đường dẫn con.

---

## 1. Phân Quyền Theo Nhánh Dữ Liệu

| Nhánh dữ liệu | Quyền Đọc (`.read`) | Quyền Ghi (`.write`) | Ghi chú bảo mật |
| :--- | :--- | :--- | :--- |
| **Gốc (`/`)** | ❌ Chặn | ❌ Chặn | Chặn mặc định |
| **`userIndex/{uid}`** | Chỉ chính chủ | ❌ Chặn | Chỉ Cloud Functions & Admin SDK ghi |
| **`stores/{storeCode}`** | Thành viên (userIndex + hồ sơ + active) | Theo nút con | |
| `├── storeInfo` | Kế thừa | Chủ quán | |
| `├── users/{uid}` | Kế thừa | Chủ quán / Quản lý (có giới hạn, xem mục 0); tự ghi 3 trường đăng nhập | Cấm trường `password` |
| `├── products, categories, zones, campaigns, inventory, catalog_items, inventory_documents, suppliers, supplier_ledger, receipts` | Kế thừa | Chủ quán & Quản lý | |
| `├── promotions, vouchers, campaign_counters, customer_campaign_counters, stock_*` | Kế thừa | Xem bảng "Nút mới" | |
| `├── product_notes` | Kế thừa | Thành viên | |
| `├── tables`, `kitchen_orders` | Kế thừa | Thành viên; xóa: Quản lý | |
| `├── bills`, `history` | Kế thừa | Xem mục 0.3 | |
| `├── online_orders`, `cash_shifts` | Kế thừa | Chủ quán, Quản lý, Thu ngân | |
| `├── customers` | Chủ quán, Quản lý, Thu ngân | Chủ quán, Quản lý, Thu ngân | |
| `├── audit_logs` | Kế thừa | Thành viên, chỉ thêm mới | Validate timestamp, action, username |
| `└── login_attempts` | ❌ Chặn | ❌ Chặn | Chỉ `staffSignIn` (Admin SDK) |

---

## 2. Danh Sách Nút Gốc Đã Xóa Bỏ
Toàn bộ các khối rules của các nút gốc sau đã được gỡ bỏ khỏi file rules và bị chặn mặc định bởi rule gốc:
- `users`, `tables`, `products`, `categories`, `zones`, `history`, `audit_logs`, `online_orders`, `kitchen_orders`, `kmt_customers`, `cham_cong`, `timekeeping`, `employees`, `shifts`.

---

## 3. Đăng nhập qua Cloud Function `staffSignIn`

Luồng: client gọi callable `staffSignIn({storeCode, username, password})` (region `asia-southeast1`) → máy chủ:
1. Không tồn tại tài khoản → lỗi chung "Sai tài khoản hoặc mật khẩu", **không** tạo bản ghi đếm.
2. Giữ chỗ 1 lượt thử bằng transaction trên `stores/{s}/login_attempts/{username}` (yêu cầu song song không vượt quá 5 lượt).
3. Xác minh mật khẩu qua Identity Toolkit REST `accounts:signInWithPassword`.
4. Sai 5 lần liên tiếp → khóa 15 phút, trả lỗi `resource-exhausted` (kèm `remainingSeconds`) + ghi audit `LOGIN_ATTEMPT_LOCKED_OUT`. Khi đang khóa, máy chủ không kiểm tra mật khẩu và không gia hạn khóa.
5. Đúng → xóa bộ đếm, kiểm tra `users/{uid}` + `userIndex` + `isActive`, trả **Custom Token**; client gọi `signInWithCustomToken`.

Giới hạn còn lại: kẻ tấn công vẫn có thể gọi trực tiếp REST `signInWithPassword` bằng API key công khai (bỏ qua bộ đếm của POS, chỉ bị throttle mặc định của Firebase). Muốn chặn hoàn toàn cần Identity Platform blocking functions hoặc App Check.

---

## 4. Việc cần làm khi deploy (thủ công)

1. **Tắt tự đăng ký Email/Password** (phòng thủ nhiều lớp): Firebase Console → Authentication → Settings → User actions → bỏ chọn **Enable create (sign-up)**. Tài khoản nhân viên vẫn được tạo qua `createStaffAccount` (Admin SDK).
2. **Cấu hình `WEB_API_KEY`** cho Functions: tạo `functions/.env` với `WEB_API_KEY=<Web API Key của project>` (hoặc nhập khi `firebase deploy` hỏi). Không commit secret khác vào repo.
3. **Cấp quyền ký Custom Token:** service account chạy Functions (mặc định `PROJECT_NUMBER-compute@developer.gserviceaccount.com`) cần vai trò **Service Account Token Creator** (`iam.serviceAccounts.signBlob`).
4. **Thứ tự deploy:** `firebase deploy --only functions` (có `staffSignIn`) **trước**, sau đó phát hành app/web mới, rồi `firebase deploy --only database`. App cũ (đăng nhập trực tiếp bằng email/mật khẩu) vẫn hoạt động với rules mới, nhưng không có khóa tạm.
5. Đảm bảo mọi nhân viên hiện có đều có `userIndex/{uid}/{storeCode} = true` (chạy `scripts/migrate_legacy_users` nếu còn hồ sơ legacy theo username) — nếu thiếu, họ sẽ không đọc được dữ liệu quán.
6. Chạy test rules: `cd tests/rules && npm ci && npm run test:emulator` (cần Java 21+ và firebase-tools).

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
| Quản lý | `ROLE_MANAGER` (chuẩn) + alias cũ `manager`, `manager_1`, `manager_2`, `ROLE_MANAGER_1`, `ROLE_MANAGER_2` |
| Nhân viên (người thanh toán; đã gộp Thu ngân + Phục vụ) | `ROLE_STAFF` (chuẩn), `staff` + alias cũ `cashier`, `ROLE_CASHIER`, `employee`, `waiter`, `ROLE_WAITER` |
| Bếp / khác | `ROLE_KITCHEN`, … (chỉ là thành viên quán) |

### Nút mới cho luồng thanh toán
| Nhánh | Quyền ghi |
| :--- | :--- |
| `counters/bill_seq/{yyMMdd}` | Thành viên; số nguyên, chỉ tăng đúng +1 (transaction); cấm xóa |
| `bill_stock_applied/{billId}` | Người thanh toán tạo **một lần** (`true`); sửa/xóa: Quản lý/Chủ quán |
| `bill_stock_lines/{billId}/{itemKey}` | Marker từng dòng nguyên liệu đã trừ: người thanh toán tạo **một lần** (số); xóa: Quản lý/Chủ quán. `bill_stock_applied` = `true` chỉ ghi khi mọi dòng đã trừ |
| `stock_retry_queue/{billId}` | Hàng đợi trừ kho lại: người thanh toán ghi/xóa từng mục (`billId` khớp khóa, `attempts` số); xóa cả nhánh: Quản lý/Chủ quán |
| `loyalty_applied/{billId}/{redeem\|award\|refund}` | Sổ cái điểm: người thanh toán tạo **một lần** (`customerId`, `points`); xóa: Quản lý/Chủ quán |
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
| **`stores/{storeCode}`** | ❌ Không cấp ở cấp này (quyền `.read` RTDB lan xuống mọi nút con, không thể thu hẹp lại) | Theo nút con | Đọc theo từng nút con; client phải đọc `stores/{s}/<nút>` chứ không đọc cả `stores/{s}` |
| `├── storeInfo` | Thành viên | Chủ quán | |
| `├── users/{uid}` | Thành viên | Chủ quán / Quản lý (có giới hạn, xem mục 0); tự ghi 3 trường đăng nhập | Cấm trường `password` |
| `├── products, categories, zones, campaigns, inventory, catalog_items, inventory_documents, suppliers, supplier_ledger, receipts` | Thành viên | Chủ quán & Quản lý | |
| `├── promotions, vouchers, campaign_counters, customer_campaign_counters, stock_*` | Thành viên | Xem bảng "Nút mới" | |
| `├── product_notes` | Thành viên | Thành viên | |
| `├── tables`, `kitchen_orders` | Thành viên | Thành viên; xóa: Quản lý | |
| `├── bills`, `history` | Thành viên | Xem mục 0.3 | |
| `├── online_orders`, `cash_shifts` | Thành viên | Chủ quán, Quản lý, Thu ngân | |
| `├── customers` | Chủ quán, Quản lý, Thu ngân | Chủ quán, Quản lý: toàn quyền. Thu ngân: tạo khách mới **chỉ với 0 điểm** (không `loyaltyOps` / `lastLoyaltyOp` / `lastRedeem`; khách đã có điểm trên Firestore nhập qua `importCustomerToStore`), sửa thông tin, **không xóa**, không thêm/sửa trường điểm cũ `diemHienTai` / `tongDiem`; đổi điểm chỉ qua thao tác hóa đơn (`lastLoyaltyOp = billId:type`): `redeem` giảm điểm kèm `lastRedeem`, `award` cho HĐ PAID của đúng khách, ≤ tiền × `pointEarnRate`% / `pointRedeemRate` + 1, chưa có sổ cái; `refund` ≤ `lastRedeem.points` khi HĐ chưa PAID | Stock balance có vòng khóa `recentSaleBills`, khách có `loyaltyOps` (idempotent trong transaction) |
| `├── audit_logs` | Thành viên | Thành viên, chỉ thêm mới | Validate timestamp, action, username |
| `└── (mọi nút con khác: counters, recipes, roles, payment_events, loyalty_applied, migration_log, ...)` | Thành viên | Xem từng khối rules | Mỗi nút con tự khai báo `.read` (test RC6) |
| **`login_attempts/{storeCode}/{username}`** (gốc) | ❌ Chặn | ❌ Chặn | Chỉ `staffSignIn` (Admin SDK). Nhánh cũ `stores/{s}/login_attempts` bỏ, có thể xóa |
| **`manager_pins/{storeCode}/{uid}`**, **`manager_pin_attempts/...`** (gốc) | ❌ Chặn | ❌ Chặn | Chỉ Admin SDK |

---

## 2. Danh Sách Nút Gốc Đã Xóa Bỏ
Toàn bộ các khối rules của các nút gốc sau đã được gỡ bỏ khỏi file rules và bị chặn mặc định bởi rule gốc:
- `users`, `tables`, `products`, `categories`, `zones`, `history`, `audit_logs`, `online_orders`, `kitchen_orders`, `kmt_customers`, `cham_cong`, `timekeeping`, `employees`, `shifts`.

---

## 3. Đăng nhập qua Cloud Function `staffSignIn`

Luồng: client gọi callable `staffSignIn({storeCode, username, password})` (region `asia-southeast1`) → máy chủ:
1. Không tồn tại tài khoản → lỗi chung "Sai tài khoản hoặc mật khẩu", **không** tạo bản ghi đếm.
2. Giữ chỗ 1 lượt thử bằng transaction trên `login_attempts/{s}/{username}` (nút GỐC, ngoài `stores/{s}`) (yêu cầu song song không vượt quá 5 lượt).
3. Xác minh mật khẩu qua Identity Toolkit REST `accounts:signInWithPassword`.
4. Sai 5 lần liên tiếp → khóa 15 phút, trả lỗi `resource-exhausted` (kèm `remainingSeconds`) + ghi audit `LOGIN_ATTEMPT_LOCKED_OUT`. Khi đang khóa, máy chủ không kiểm tra mật khẩu và không gia hạn khóa.
5. Đúng → xóa bộ đếm, kiểm tra `users/{uid}` + `userIndex` + `isActive`, trả **Custom Token**; client gọi `signInWithCustomToken`.

Giới hạn còn lại: kẻ tấn công vẫn có thể gọi trực tiếp REST `signInWithPassword` bằng API key công khai (bỏ qua bộ đếm của POS, chỉ bị throttle mặc định của Firebase). Muốn chặn hoàn toàn cần Identity Platform blocking functions hoặc App Check.

---

## 3b. Điểm khách hàng: RTDB là nguồn chuẩn, Firestore là bản sao chỉ đọc

> **Đã được thay thế một phần bởi §3c** (điểm gộp một bản ghi toàn chuỗi `loyalty_members`). Phần dưới còn đúng cho nhập khách từ Firestore và bản sao Firestore; các câu về "điểm đổi trực tiếp trên node chi nhánh" và `kmt_point_history` theo node chi nhánh là bản cũ.

- **Nguồn chuẩn (bản cũ):** `stores/{s}/customers/{id}` (RTDB). Điểm chỉ đổi qua `LoyaltyService` (transaction theo hóa đơn) hoặc Quản lý / Chủ quán.
- **Nhập khách từ Firestore** `kmt_customers/{id}` → callable `importCustomerToStore({storeCode, customerId})` (region `asia-southeast1`): người gọi là Thu ngân trở lên, đang hoạt động, có `userIndex`; Admin SDK đọc Firestore và tạo node RTDB với số dư thật bằng transaction (đã có thì giữ nguyên → idempotent), ghi audit `IMPORT_CUSTOMER`. Client không tự sao chép nữa.
- **Đồng bộ ngược** → trigger `mirrorCustomerToFirestore` (`onValueWritten /stores/{storeCode}/customers/{customerId}`): merge thông tin + `diem_hien_tai` / `currentPoints` / `totalPoints` vào `kmt_customers/{customerId}` (doc id = khóa RTDB) và ghi `kmt_point_history` với doc id cố định (`POS_{store}_{customer}_{billId:type}`; chỉnh tay: `POS_EVT_{eventId}`). Xóa khách RTDB không xóa Firestore.
- App Flutter đã bỏ mọi ghi `kmt_customers` / `kmt_point_history` (gỡ `awardPoints` / `redeemCustomerPoints` cũ). Web chỉ đọc.
- **Firestore rules KHÔNG có trong repo** (`firebase.json` không có mục `firestore`) nên chưa thể chặn client ghi điểm Firestore bằng mã nguồn ở đây. Không thêm `firestore.rules` vào `firebase.json` vì `firebase deploy` sẽ ghi đè rules Firestore đang chạy (có thể đang phục vụ hệ thống Khuyến Mãi Trạm). Cần cập nhật thủ công trên Console, ví dụ:

```
match /kmt_customers/{id} {
  allow read: if request.auth != null;
  allow create, update: if <điều kiện hiện tại> &&
    !request.resource.data.diff(resource == null ? {} : resource.data).affectedKeys()
      .hasAny(['diem_hien_tai', 'currentPoints', 'totalPoints', 'diemHienTai', 'tongDiem']);
}
match /kmt_point_history/{id} { allow read: if request.auth != null; allow write: if false; }
```
  (Cloud Functions dùng Admin SDK nên không bị rules chặn.) Nếu hệ thống Khuyến Mãi Trạm vẫn cộng/trừ điểm trực tiếp trên Firestore thì số đó sẽ bị RTDB ghi đè ở lần đồng bộ kế tiếp - cần chuyển hệ thống đó sang gọi qua RTDB/Function.

---

## 3c. Điểm DÙNG CHUNG toàn chuỗi: một bản ghi duy nhất `loyalty_members`

**Mô hình**
- `loyalty_members/{memberKey}`: `{name, phone, points, totalPoints, joinedAt, updatedAt, lastStoreCode, branches:{store:{customerId:true}}, ops:{opId:{p,t,at}}}`. `memberKey` = SĐT chuẩn hóa `0xxxxxxxxx`; khách không có SĐT hợp lệ → `L_{store}_{customerId}` (bản ghi riêng, không gộp). `ops` là vòng khóa idempotent (200 thao tác mới nhất, dùng cho hoàn điểm).
- `loyalty_ledger/{memberKey}/{opId}`: sổ cái chỉ tạo mới `{type: earn|redeem|refund|adjust|opening, points (có dấu), balanceAfter, billId, billCode, storeCode, customerId, staff, note, at}`. `opId` = `{billId}_{earn|redeem|refund}`, `adj_*`, `opening_{store}_{customerId}`, `merge_*`.
- `loyalty_config` (đọc: mọi nhân viên thuộc ≥ 1 chi nhánh; ghi: chỉ callable `setLoyaltyConfig`, Chủ quán): `{pointEarnRate, pointRedeemRate, loyaltyTiers:[{name,minPoints}]}`. Ưu tiên hơn `storeInfo.*` của chi nhánh (fallback khi chuỗi chưa đặt). **Mốc hạng không có mặc định**: Chủ tự đặt.
- `stores/{s}/customers/{id}`: thông tin/viếng thăm của chi nhánh; `diem_hien_tai`/`currentPoints`/`totalPoints` chỉ còn là **bản sao đọc** (trigger `mirrorMemberToBranches` + `linkBranchCustomer`). Rules: mọi client (kể cả Quản lý/Chủ) không đổi được các trường điểm; tạo khách mới chỉ với 0 điểm; xóa khách chỉ Quản lý/Chủ (điểm chung vẫn giữ).
- `storeInfo.sharedLoyalty` **không còn tác dụng** (luôn dùng chung). Callable `pullPooledPoints` là stub không ghi dữ liệu (để app cũ không lỗi 404) - xóa sau khi mọi POS đã cập nhật.

**Rules:** `loyalty_members`, `loyalty_ledger`, `loyalty_migration` đóng đọc/ghi với mọi client (rules RTDB không liệt kê được chi nhánh của người dùng nên không thể cấp "đọc cho Thu ngân của bất kỳ chi nhánh"; mọi truy vấn đi qua callable có kiểm tra vai trò). `stores/{s}/loyalty_applied` đóng ghi (sổ cũ chỉ đọc).

**Callable** (region `asia-southeast1`, Thu ngân trở lên đang hoạt động của `storeCode`, trừ ghi chú): `applyLoyaltyEarn{storeCode,billId}` (điểm tính phía máy chủ từ `bills/{id}.finalAmount` PAID), `redeemLoyaltyPoints{storeCode,customerId,billId,points}` (không đủ → `failed-precondition` `details.code="insufficient"`), `refundLoyaltyPoints{storeCode,customerId,billId}` (chỉ khi hóa đơn chưa PAID), `lookupMember{storeCode,customerId|phone}`, `getMemberLedger{storeCode,customerId|phone,limit}`, `adjustLoyaltyPoints{storeCode,customerId|phone,mode:ADD|SUB|SET,points,reason,opId?}` (Quản lý/Chủ), `setLoyaltyConfig{storeCode,pointEarnRate?,pointRedeemRate?,loyaltyTiers?}` (Chủ). Mọi thao tác theo hóa đơn idempotent theo `(billId, op)`.

**Di trú (làm TRƯỚC khi deploy rules/functions/app mới, khi đóng cửa):**
1. `cd scripts/migrate_shared_loyalty && npm i && node migrate.js --service-account=KEY.json` (dry-run: nhóm theo SĐT, trùng, khách không SĐT, kiểm tra tổng).
2. Đọc kỹ báo cáo rồi `--apply` (sao lưu `migration_output/`, marker `loyalty_migration/shared_v1`, tạo `loyalty_members` + sổ `opening_*`, cập nhật cache điểm các node chi nhánh). Không xóa/ghi đè gì khác; chạy lại an toàn.
3. Deploy: `firebase deploy --only functions` → phát hành app POS/Web mới → `firebase deploy --only database`. POS cũ không đổi/tích điểm được sau khi rules mới có hiệu lực.

---

## 4. Việc cần làm khi deploy (thủ công)

1. **Tắt tự đăng ký Email/Password** (phòng thủ nhiều lớp): Firebase Console → Authentication → Settings → User actions → bỏ chọn **Enable create (sign-up)**. Tài khoản nhân viên vẫn được tạo qua `createStaffAccount` (Admin SDK).
2. **Cấu hình `WEB_API_KEY`** cho Functions: tạo `functions/.env` với `WEB_API_KEY=<Web API Key của project>` (hoặc nhập khi `firebase deploy` hỏi). Không commit secret khác vào repo.
3. **Cấp quyền ký Custom Token:** service account chạy Functions (mặc định `PROJECT_NUMBER-compute@developer.gserviceaccount.com`) cần vai trò **Service Account Token Creator** (`iam.serviceAccounts.signBlob`).
4. **Thứ tự deploy:** `firebase deploy --only functions` (có `staffSignIn`) **trước**, sau đó phát hành app/web mới, rồi `firebase deploy --only database`. App cũ (đăng nhập trực tiếp bằng email/mật khẩu) vẫn hoạt động với rules mới, nhưng không có khóa tạm.
5. Đảm bảo mọi nhân viên hiện có đều có `userIndex/{uid}/{storeCode} = true` (chạy `scripts/migrate_legacy_users` nếu còn hồ sơ legacy theo username) — nếu thiếu, họ sẽ không đọc được dữ liệu quán.
6. **Điểm khách hàng:** deploy `importCustomerToStore` + `mirrorCustomerToFirestore` (`firebase deploy --only functions`) **trước** khi phát hành app mới và `--only database` (rules mới chặn Thu ngân tạo khách có điểm). Cập nhật Firestore rules thủ công theo mục 3b.
7. Chạy test rules: `cd tests/rules && npm ci && npm run test:emulator` (cần Java 21+ và firebase-tools).
8. **PIN duyệt quản lý (bỏ PIN bản rõ trong `storeInfo`):** PIN cũ lưu bản rõ tại `stores/{storeCode}/storeInfo/managerPin` — mọi nhân viên đọc được storeInfo nên coi như đã lộ. App Flutter và web giờ chỉ xác minh PIN qua callable `verifyManagerPin` (băm scrypt tại `manager_pins/{storeCode}/{uid}`, chỉ Admin SDK truy cập, khóa tạm 15 phút sau 5 lần sai) và đặt PIN qua `setManagerPin`. Rules mới đặt `.validate: false` trên nút con `storeInfo/managerPin`: không ai ghi được PIN mới, nhưng vẫn xóa được giá trị cũ và cập nhật các trường khác của `storeInfo` bình thường.
   - Deploy `verifyManagerPin` + `setManagerPin` (`firebase deploy --only functions`) **trước** khi phát hành app/web mới.
   - **Ngay khi deploy rules, xóa giá trị cũ** cho TỪNG cửa hàng: Firebase Console → Realtime Database → xóa nút `stores/{storeCode}/storeInfo/managerPin` (VD `stores/TRAM01/storeInfo/managerPin`), hoặc `firebase database:remove /stores/TRAM01/storeInfo/managerPin --project <project>`. Chừng nào nút này còn tồn tại, PIN cũ vẫn đọc được bởi nhân viên (cập nhật các trường khác của `storeInfo` vẫn chạy bình thường); lệnh `set()` toàn bộ storeInfo từ app Flutter mới sẽ tự bỏ trường này.
   - Mỗi Quản lý / Chủ quán phải **đặt lại PIN mới** (Flutter: Trung tâm Quản lý → menu ⋮ → "PIN duyệt của tôi"; web: hộp thoại đặt PIN duyệt). Không dùng lại PIN cũ. Không còn PIN mặc định/dự phòng (`1234`, `9999` đã bị gỡ khỏi app).

## 5. Liên kết Chấm Công Trạm (`chamcong_links/**`)

- Nút gốc `chamcong_links/` (`stores/{storeCode}`, `byChamCongStore/{chamCongStoreId}`, `users/{storeCode}/{chamCongUid}`) **không có rule riêng** → bị chặn bởi `.read/.write: false` ở gốc; chỉ Cloud Functions (`chamCongSignIn`, `linkChamCongStore`, `unlinkChamCongStore`, `getChamCongLinkStatus`) truy cập bằng Admin SDK. Test: `CC1` trong `tests/rules/rules.test.ts`.
- Không đặt dữ liệu liên kết dưới `stores/{storeCode}` (quyền đọc của thành viên quán sẽ lan xuống). `storeInfo/chamCongStoreId`, `storeInfo/chamCongStoreName` chỉ để hiển thị — máy chủ không tin các trường này.
- Hồ sơ nhân viên do SSO cấp nằm ở `stores/{storeCode}/users/cc_{chamCongUid}` (`authProvider: "chamcong"`), dùng chung rules `users` hiện có. Chi tiết: `docs/CHAMCONG_SSO.md`.

## 6. Gộp vai trò: Quản lý (ROLE_MANAGER) và Nhân viên (ROLE_STAFF)

- **Quản lý 1 + Quản lý 2 → `ROLE_MANAGER`** ("Quản lý"); **Thu ngân + Phục vụ → `ROLE_STAFF`** ("Nhân viên"). Bếp (`ROLE_KITCHEN`) giữ riêng. Mã chuẩn do `normalizeRoleId` (functions `permissions.ts`, web `lib/roles.ts`, Flutter `app_permissions.dart`) trả về; ghi mới luôn dùng mã chuẩn.
- **Rules**: danh sách vai trò vốn đã chứa mọi mã Quản lý cũ. Mọi chỗ cho phép Thu ngân (`cashier`/`ROLE_CASHIER`/`employee`, 17 điểm) nay thêm `ROLE_STAFF`, `staff`, `ROLE_WAITER`, `waiter` ⇒ **mã cũ vẫn hoạt động nguyên trạng**, không cần migrate khẩn.
- **Quyền Phục vụ TĂNG khi gộp** (vì `waiter`/`ROLE_WAITER` nay = Nhân viên): thanh toán (ghi `bills`/`history` sang `PAID`/`REFUNDED`, sửa hóa đơn đã thanh toán), ghi `cash_shifts`, `online_orders`, `customers` (đọc + tạo/sửa không đụng điểm), `point_history` (đọc), `loyalty_applied`, `bill_stock_applied`/`bill_stock_lines`/`stock_events`/`stock_balances`/`stock_retry_queue`, `promotions/*/usageCount`, `vouchers/*/*`, `campaign_counters`, `customer_campaign_counters`. Các ràng buộc **không còn áp cho Phục vụ**: chặn sửa/xóa hóa đơn PAID, chặn đọc `customers`, chặn ghi tồn kho/điểm. Muốn siết lại: dùng vai trò **Bếp** cho người chỉ gọi món, hoặc (đề xuất) thêm cờ từ chối quyền theo từng người — hiện `customPermissions` chỉ **cộng thêm**, không trừ bớt.
- **Quản lý** không còn phân biệt QL1/QL2 ở rules (trước đây cũng không phân biệt) — thay đổi chỉ ở quyền chức năng (ứng dụng/Web).
- **Migrate dữ liệu** (tùy chọn, không bắt buộc): `scripts/migrate_merge_roles/` (`node migrate.js` = dry-run; `--apply` để ghi). Chạy sau khi đã deploy bản app/Web/Functions mới.
- Callable `resetStaffPassword`/`setStaffDisabled`: Quản lý chỉ thao tác được với Nhân viên/Bếp (không Chủ quán, không Quản lý khác); tìm người gọi/đối tượng theo khóa nút, trường `uid` hoặc tên đăng nhập (hồ sơ cũ khóa theo username).
- Test: `MR1`–`MR4` trong `tests/rules/rules.test.ts` (cần emulator) kiểm tra mọi mã cũ/mới. Fixture `waiter_uid` của các test cũ nay mang vai trò **Bếp** (nhóm "chỉ là thành viên quán") để các kiểm tra giới hạn quyền (hóa đơn PAID, khách hàng, tồn kho, điểm...) vẫn đúng ngữ nghĩa; chưa chạy được emulator cục bộ nên cần chạy `npm run test:emulator` trước khi deploy.

# Rà soát Rules RTDB so với luồng thật của app (RULES_AUDIT)

Trạng thái: **MỘT PHẦN** — đã kiểm kê và đối chiếu các luồng chính bằng đọc code; ma trận đầy đủ (luồng × vai trò, chạy trên emulator) **chưa xong** (xem mục "Chưa xong").

## 1. Kiểm kê đã làm
- Flutter (`app_flutter/lib`): mọi `set/update/push/remove/runTransaction`, `orderByChild/equalTo/limitToLast`, các nút `stores/{s}/*` đọc/ghi.
- Web (`web/lib`, `web/app`, `web/components`): cùng loại thao tác (`ref(db, ...)`, `set/update/remove/runTransaction`, multi-path `update(ref(db), {...})`).
- Payload thật lấy từ `toMap()` của: BillModel + BillRecordBuilder, TableModel, KitchenOrderModel, CashShiftModel, KmtCustomerModel, StockBalance/StockEvent, ProductModel, OrderActionLogModel, AuditLogModel, StoreInfoModel.
- Dữ liệu sản xuất (`migration_output/backup_tramapp_36f53_20261005.json`, chỉ đếm, không đọc thông tin cá nhân).

## 2. Lỗi đã sửa (đã kiểm chứng)
| # | Đường dẫn | Vấn đề | Sửa |
|---|---|---|---|
| F1 | `stores/$s/cash_shifts/$shiftId` `.write` | Chủ ca cũ (ca chưa có `staffUid`, nhận diện theo username) **không đóng được ca** nếu payload không kèm `staffUid` (điều kiện top-level bắt buộc `newData.staffUid === auth.uid`). SH4 cũ không bắt được vì payload có kèm `staffUid`. | Thêm nhánh: nếu ca cũ chưa có `staffUid` (cả data lẫn newData) và username người ghi khớp `staffUsername` thì được ghi. Người khác vẫn bị chặn. Có test RA1. |

Không cần đổi client cho F1.

## 3. Luồng đã đối chiếu và KHÔNG bị chặn (đủ điều kiện)
- Thanh toán (bills + history + tables multi-path, `counters/bill_seq` +1) — Nhân viên/Quản lý/Chủ: OK; Bếp bị chặn đúng.
- Hủy bàn đang mở (bill mới CANCELLED): OK.
- Gửi bếp (`kitchen_orders` push), Bếp đánh dấu xong / nhận món: OK.
- Bật/tắt món hết hàng (`isAvailable`, `soldOut*`), kể cả Bếp: OK.
- Trừ kho khi bán (`stock_balances` giảm + `recentSaleBills`, `stock_events`, `bill_stock_lines`, `bill_stock_applied`, `stock_retry_queue`): OK.
- Khách mới 0 điểm (`set`), sửa hồ sơ không đụng điểm, `lastVisitAt`: OK.
- Ca: mở ca của mình, đóng ca của mình, cộng dồn doanh số/két, tự đóng ca cũ khi mở ca mới (có `staffUid`): OK.
- Voucher giữ/đổi/hoàn tác REDEEMED→RELEASED (khi bill không tồn tại): OK. Bộ đếm CTKM/khách tăng: OK.
- Ghi nhật ký `audit_logs`: mọi payload web/Flutter đều có `timestamp`, `action`, `username` (đã kiểm tra các điểm ghi chính).
- Cập nhật `lastLoginAt`, `mustChangePassword`, `lastPasswordChangedAt` của chính mình: OK (child rule).
- Chỉ mục: `bills.createdAt`, `payment_events.timestamp`, `stock_balances.branchId`, `stock_events.itemId`, `inventory_documents.docType`, `recipes.outputItemId`, `supplier_ledger.supplierId` đều có `.indexOn`.
- Status hóa đơn app ghi (OPEN, PRE_PRINT, PAID, CANCELLED, REFUNDED) đều nằm trong regex `bills/status`.

## 4. Luồng bị chặn có chủ ý (giữ nguyên)
- Hủy/xóa hóa đơn ĐÃ THANH TOÁN: chỉ Chủ hoặc Quản lý có `CANCEL_BILL`.
- Quản lý xóa hóa đơn chưa chốt: được. Nhân viên xóa hóa đơn: bị chặn.
- Chỉnh điểm khách trực tiếp: bị chặn (chỉ qua callable/Cloud Function).
- Ghi `storeInfo`, `roles`, `products` (giá/tên), `categories`, `zones`, `note_groups`, `campaigns`, `vouchers` (tạo), `catalog_items`, `suppliers`, `inventory_documents`, `recipes`, `supplier_ledger`: chỉ Chủ/Quản lý theo đúng ROLE_RULES.
- Nhân viên không tăng tồn kho (nhập kho chỉ Quản lý/Chủ).

## 5. Luồng CẦN Cloud Function (client không thể làm an toàn)
- **Hoàn tác bộ đếm khuyến mãi** (`campaign_counters` giảm `spentMoney`/`committedUseCount`, `customer_campaign_counters` giảm `usedCount`, `promotions/{id}/usageCount` -1): khi ghi hóa đơn lỗi, Nhân viên không hoàn tác được. Cho phép giảm sẽ cho phép vượt giới hạn khuyến mãi. Hậu quả hiện tại: đếm dư (an toàn theo hướng chặn bán, không mất tiền). Đề xuất: callable `rollbackPromotion`.

## 6. Rủi ro còn lại (rules mở hơn ROLE_RULES — chưa siết, cần quyết định)
- Bếp ghi được `tables` và tạo/sửa bill OPEN/CANCELLED (nhánh "không PAID" của `bills` cho mọi thành viên). Bếp đọc được `cash_shifts`.
- Quản lý (không phải Chủ) ghi được `users/{uid}` của nhân viên: đổi `roleId`, tạo, xóa tài khoản. ROLE_RULES ghi "Quản lý nhân sự" là KHÔNG mặc định.
- Nhân viên đọc được `cash_shifts` và `users` của cả quán (app cần đọc toàn bộ ca khi mở ca; UI tự lọc).
- `bills`: nhân viên vẫn sửa được hóa đơn PAID bằng ghi PAID→PAID (chỉ chặn chuyển sang CANCELLED).
- `audit_logs.timestamp <= now`: nếu đồng hồ máy POS nhanh hơn server, mọi ghi nhật ký sẽ bị từ chối. Cân nhắc cho sai lệch vài phút.
- Alias vai trò: web chấp nhận thêm mã (`ql1`, `nv`, `bep`, `chu`, `admin`...), rules chỉ nhận danh sách đã chốt. Tài khoản dùng mã ngoài danh sách sẽ thấy giao diện nhưng bị rules từ chối. Cần kiểm tra dữ liệu live.
- **Dữ liệu cũ**: bản backup 05/10 còn `stores/{s}/users/*` có trường `password` (plaintext) và `role` không có `roleId`. Rules đọc được cho mọi thành viên. Phải kiểm tra và xóa `password` trên live trước khi chạy thật.
- Node gốc cũ (`/history`, `/users`, `/tables`...) còn trong backup; rules đã đóng, cần đảm bảo không app nào đọc.

## 7. Chưa xong
- Ma trận đầy đủ "luồng × vai trò" (khoảng 80 luồng × 9 vai trò) chạy trên emulator — CHƯA viết (`tests/rules/flows.test.ts` chưa có). Các kết luận ở trên dựa trên đọc code, không phải test chạy.
- Kiểm tra đường `payment_events` (bot thanh toán) với vai trò thật — chưa chạy test.
- Dead code: `PromotionsScreen` (không được tham chiếu) — bỏ qua.
- `functions` và `web` test: chỉ xác nhận một bộ "132 passed"; chưa đối chiếu đủ đầu ra.

## 8. Kết quả kiểm chứng
- Rules emulator: **83/83 xanh** (82 cũ + RA1).
- `python3 -m json.tool database.rules.json`: OK.
- `flutter test`: All tests passed.
- Không đổi code Flutter/Web/Functions. Không commit, không deploy.

## 9. Thứ tự triển khai
1. Deploy rules trước (`firebase deploy --only database --project tramapp-36f53`): chỉ mở thêm một trường hợp hẹp (F1), không cần đổi app.
2. Sau đó mới phát hành app; không có phụ thuộc giữa hai bước.

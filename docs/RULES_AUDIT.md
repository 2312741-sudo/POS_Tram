# Rà soát Rules RTDB so với luồng thật của app (RULES_AUDIT)

Trạng thái: **ĐÃ CHẠY MA TRẬN** — đã kiểm kê và đối chiếu các luồng bằng đọc code, và ma trận luồng × vai trò đã chạy trên emulator (mục 7): 282/294 ô khớp tài liệu, 12 ô lệch cần quyết định. Còn vài việc ngoài phạm vi (mục 7, "Các việc còn lại").

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

## 7. Ma trận luồng × vai trò (đã chạy trên emulator)

File: `tests/rules/flows.test.ts` (projectId riêng `demo-tram-pos-flows`, để không tranh dữ liệu với `rules.test.ts`).
42 luồng × 7 vai trò = **294 ô**: Chủ (ROLE_OWNER, isRootOwner), Quản lý, Quản lý + CANCEL_BILL (customPermissions), Nhân viên, Bếp, Nhân viên bị khóa, người không thuộc quán.
Kỳ vọng lấy từ `docs/ROLE_RULES.md`, `docs/PERMISSIONS_AUDIT.md`, và mục 3–6 của file này. Payload lấy từ `toMap()` của app Flutter.

**Kết quả: 282 ô khớp tài liệu, 12 ô lệch (8 luồng).** Không sửa rules. Mỗi ô lệch được assert theo hành vi thật của rules và đánh dấu `MISMATCH` trong test.

| Luồng | Vai trò | Tài liệu | Rules (thật) | Loại |
|---|---|---|---|---|
| F01 Mở bàn, lưu order (`tables`) | Bếp | từ chối | cho phép | ĐÃ BIẾT (mục 6) |
| F02 Tạo hóa đơn OPEN khi mở bàn | Bếp | từ chối | cho phép | ĐÃ BIẾT (mục 6) |
| F06 Hủy bàn đang mở (OPEN -> CANCELLED) | Bếp | từ chối | cho phép | ĐÃ BIẾT (mục 6) |
| F04 Đánh dấu xong món (`kitchen_orders`) | Nhân viên | chỉ xem màn Bếp | cho phép | LỖI RULES (quá rộng), hoặc tài liệu thiếu; cần chốt |
| F09 Sửa hóa đơn ĐÃ thanh toán (PAID -> PAID) | Nhân viên | từ chối | cho phép | ĐÃ BIẾT (mục 6). Rủi ro doanh thu |
| F23 Đọc ca của người khác | Nhân viên | từ chối | cho phép | ĐÃ BIẾT (mục 6); lệch ROLE_RULES §1 |
| F23 Đọc ca của người khác | Bếp | từ chối | cho phép | ĐÃ BIẾT (mục 6) |
| F39 Đổi `roleId` của nhân viên khác | Quản lý | từ chối | cho phép | ĐÃ BIẾT (mục 6) |
| F39 Đổi `roleId` của nhân viên khác | Quản lý + CANCEL_BILL | từ chối | cho phép | ĐÃ BIẾT (mục 6) |
| F26 Chỉnh điểm khách trực tiếp | Chủ | cho phép | từ chối | LỆCH TÀI LIỆU (PERMISSIONS_AUDIT §4) |
| F26 Chỉnh điểm khách trực tiếp | Quản lý | cho phép | từ chối | LỆCH TÀI LIỆU |
| F26 Chỉnh điểm khách trực tiếp | Quản lý + CANCEL_BILL | cho phép | từ chối | LỆCH TÀI LIỆU |

Tổng theo loại: 8 ô ĐÃ BIẾT (đã có trong mục 6, cần quyết định trước go-live), 1 ô LỖI RULES mới (F04), 3 ô LỆCH TÀI LIỆU (F26).

Ghi chú:
- Các luồng nghiệp vụ chính đều đúng tài liệu: thanh toán (bills + history + tables + bill_seq), gửi bếp, bật/tắt hết hàng (kể cả Bếp), đổi giá bị chặn với NV/Bếp, mở/đóng ca của chính mình, mở ca đứng tên người khác bị chặn với NV, hủy/xóa hóa đơn ĐÃ thanh toán chỉ Chủ hoặc QL có CANCEL_BILL, khách mới 0 điểm (NV được, có điểm bị chặn), xóa khách chỉ QL/Chủ, khu vực và ghi chú chỉ QL/Chủ, storeInfo chỉ Chủ, nhật ký: ai cũng ghi được, chỉ Chủ đọc, không ai sửa/xóa, userIndex chỉ đọc của mình, loyalty_members đóng với client, sao chép thực đơn chỉ Chủ/QL, trừ kho khi bán (NV/QL/Chủ), nhập kho tăng tồn (chỉ Chủ/QL; NV/Bếp bị chặn).
- Hai giả định ban đầu bị test bác bỏ, nên không còn là lệch: NV/Bếp bị chặn xóa hóa đơn chưa chốt (rules khớp tài liệu), và Chủ/QL tăng được tồn trực tiếp (rules cho phép, NV/Bếp bị chặn). Không có chặn go-live từ nhóm nhập kho.
- LỆCH TÀI LIỆU F26: PERMISSIONS_AUDIT §4 ghi ADJUST_POINTS dựa trên "rules customers". Thực tế web đổi điểm qua callable (`web/lib/loyalty-client.ts`), còn rules chặn ghi điểm trực tiếp cho mọi vai trò (đúng ý mục 4). Nên sửa câu chữ tài liệu, không sửa rules.
- Ứng viên xử lý trước go-live: **F09** (Nhân viên sửa số tiền hóa đơn đã thanh toán) và **F39** (Quản lý đổi vai trò nhân viên). Đề xuất: chặn PAID -> PAID với vai trò không có EDIT_BILL, và chặn `users/{uid}/roleId` của người không phải Chủ. Đây là thay đổi rules, cần Chủ quyết định.
- Chưa phủ: luồng đọc hóa đơn của người khác (rules cho mọi thành viên đọc `bills`; tài liệu không nói rõ), đường `payment_events` (bot thanh toán), đối chiếu đầu ra test `functions` và `web`.

Các việc còn lại từ phiên trước:
- Kiểm tra đường `payment_events` (bot thanh toán) với vai trò thật — chưa chạy test.
- Dead code: `PromotionsScreen` (không được tham chiếu) — bỏ qua.
- `functions` và `web` test: chỉ xác nhận một bộ "132 passed"; chưa đối chiếu đủ đầu ra.

## 8. Kết quả kiểm chứng
- Rules emulator: **83/83 xanh** (82 cũ + RA1). Sau khi thêm ma trận `flows.test.ts`: **378/378 xanh** (83 cũ + 295 mới: 294 ô + 1 kiểm tra cấu trúc).
- `python3 -m json.tool database.rules.json`: OK.
- `flutter test`: All tests passed.
- Không đổi code Flutter/Web/Functions. Không commit, không deploy.

## 9. Thứ tự triển khai
1. Deploy rules trước (`firebase deploy --only database --project tramapp-36f53`): chỉ mở thêm một trường hợp hẹp (F1), không cần đổi app.
2. Sau đó mới phát hành app; không có phụ thuộc giữa hai bước.

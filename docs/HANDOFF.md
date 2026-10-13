# HANDOFF — POS Trạm (ngữ cảnh để tiếp tục ở VS Code)

> Tài liệu bàn giao. Cập nhật lần cuối: 2026-10-12, commit `cb659f9` trên `main`.
> **Không chứa mật khẩu.** Mật khẩu tài khoản demo nằm ở `docs/private/APP_REVIEW_NOTES.md` (đã loại khỏi git). Đọc file đó khi cần dán vào App Store Connect.

---

## 1. Dự án là gì

**POS Trạm** — hệ thống bán hàng cho quán cà phê/trà sữa/nhà hàng, thay thế KiotViet.

| Thành phần | Thư mục | Công nghệ | Ghi chú |
|---|---|---|---|
| App POS (iOS/Android) | `app_flutter/` | Flutter 3, Provider/Riverpod, firebase_* | App chính cho nhân viên, bếp, quản lý |
| Web quản trị | `web/` | Next.js 16, React 19, Tailwind v4 | Chủ quán/quản lý. Deploy: `pos-tram.vercel.app` |
| Cloud Functions | `functions/` | TypeScript, firebase-functions v2 | Region `asia-southeast1` |
| Rules RTDB | `database.rules.json` | — | Test: `tests/rules/` (emulator) |
| Script chuyển dữ liệu | `scripts/*` | Node + firebase-admin | Đều dry-run mặc định, `--apply` mới ghi |
| Bot thanh toán | `tools/tram_payment_bot/` | Flutter | **Không thuộc phạm vi tiếp tục; đừng sửa** |
| Tài liệu | `docs/` | Markdown | Xem mục 9 |

**Firebase project:** `tramapp-36f53` (POS). Chấm công (tách biệt): `chamcongtram`.
**Repo GitHub:** `2312741-sudo/POS_Tram`. Nhánh chính `main`.
**Bundle iOS:** `com.tramapp.tramFlutter` — team `W97CS7VC54`. Android package hiện là `com.example.tramapp` (chưa đổi, xem mục 6).

---

## 2. Trạng thái hiện tại

### Đã deploy lên production
- **Cloud Functions `pos`**: đầy đủ, gồm `deleteMyAccount` (vừa deploy), `listLoyaltyLedger`, nhóm điểm dùng chung (`applyLoyaltyEarn`, `redeemLoyaltyPoints`, `refundLoyaltyPoints`, `lookupMember`, `adjustLoyaltyPoints`, `setLoyaltyConfig`, `getMemberLedger`, trigger `mirrorMemberToBranches`, `linkBranchCustomer`, `mirrorLedgerToHistory`), nhóm Chấm Công (`chamCongSignIn`, `linkChamCongStore`, `unlinkChamCongStore`, `getChamCongLinkStatus`), PIN quản lý, `staffSignIn`.
- **Rules RTDB**: bản deploy gần nhất là **trước** đợt "ca/két độc lập + quy tắc vai trò + danh mục note + bếp hết món" (commit `3be1545`). Xem mục 4.
- **Web**: auto-deploy qua Vercel khi push `main`. Đã có `/privacy`, `/privacy-choices`, trang 404, và (mới) trang Support/Marketing URL.
- **Cửa hàng demo `DEMO`**: đã tạo 4 tài khoản (`chu_demo`, `quanly_demo`, `banhang_demo`, `bep_demo`), 6 món bánh lăn, Khu A với bàn A1–A4.

### Đã commit, CHƯA deploy
- Toàn bộ đợt `3be1545`: rules (ca độc lập `staffUid`, quy tắc vai trò, `note_groups`/`topping_groups`, `products` soldOut fields), client Flutter, web.
- Rules deploy **phải sau** khi app mới đã cài lên máy bán hàng (xem mục 4).

### Đã build nhưng KHÔNG chứa các thay đổi mới
- IPA `1.0.0 (1)` ở `app_flutter/build/ios/ipa/` — build trước khi có ca độc lập, quy tắc vai trò, danh mục note, bếp hết món. **Phải build lại** trước khi tải lên TestFlight.

### Chưa làm
- Tải lên TestFlight / gửi App Review (cần bạn xác nhận từng bước).
- Chưa chạy thử thiết bị thật cho nhiều tính năng mới (chỉ có test tự động).
- Android: chưa đăng ký app vào project `chamcongtram`, package chưa đổi.

---

## 3. Việc đã làm trong phiên (tóm tắt)

Theo thứ tự lớn:
1. Rà soát bảo mật → rules, auth, PIN quản lý, khóa đăng nhập server-side.
2. Điểm dùng chung một dữ liệu (`loyalty_members`, `loyalty_ledger`), chuyển/gộp bàn web, sao chép thực đơn.
3. Khuyến mãi (engine app + web), voucher có danh sách mã, báo cáo khuyến mãi.
4. Xóa món có lý do, báo cáo hủy đơn theo ngày hủy, báo cáo cuối ngày.
5. Đăng nhập một chạm **Chấm Công Trạm** (Google/Apple/Email), liên kết cửa hàng.
6. Vai trò: gộp Quản lý 1/2 → `ROLE_MANAGER`; Thu ngân + Phục vụ → `ROLE_STAFF` ("Nhân viên"); mã cũ vẫn chấp nhận qua `normalizeRoleId`.
7. Ca/két và lịch sử hóa đơn **độc lập theo tài khoản** (`cash_shifts.staffUid`, `bills.staffUid`).
8. Danh mục note/topping gắn theo nhóm món hoặc từng món (`docs/NOTE_CATALOG.md`).
9. Bếp báo hết món (`products.isAvailable`, `soldOutAt/By/Until`).
10. Chuẩn bị App Store: `PrivacyInfo.xcprivacy`, entitlements Apple Sign-In, mô tả quyền, ảnh iPad (`app_store_screenshots/`), xóa tài khoản trong app (5.1.1(v)).

---

## 4. Thứ tự triển khai — QUAN TRỌNG

Có thay đổi rules, nên **sai thứ tự sẽ làm nhân viên không mở được ca**:

1. Build lại IPA từ `main` → tải lên TestFlight → cài lên máy bán hàng.
2. Deploy rules: `firebase deploy --only database --project tramapp-36f53`
3. Web: tự cập nhật qua Vercel khi push.
4. Chủ quán (`chu_demo` ở DEMO; cửa hàng thật tự xử lý): bấm "Nhập từ cấu hình cũ" ở trang Danh mục note; cấp lại quyền cho quản lý cần hủy đơn/xem nhật ký (mặc định đã bị gỡ).
5. Xóa `stores/{store}/storeInfo/managerPin` ở mọi cửa hàng (PIN cũ dạng chữ thường) nếu còn.

Functions đã deploy hết; không cần deploy lại trừ khi sửa `functions/`.

---

## 5. Lệnh thường dùng

```bash
# Kiểm tra toàn bộ (chạy trước mỗi commit)
cd functions && npm run build && npm test
cd app_flutter && flutter test && dart analyze lib        # 0 lỗi là đạt
cd web && npx tsc --noEmit && npm run lint && npx vitest run && npm run build
python3 -m json.tool database.rules.json >/dev/null && echo RULES_OK

# Rules test trên emulator (cần JDK 21 — đã cài ở ~/development/jdk-21)
export JAVA_HOME=~/development/jdk-21/Contents/Home PATH=$JAVA_HOME/bin:$PATH
firebase emulators:exec --only database --project demo-tram-pos "cd tests/rules && npx vitest run"
# Hiện: 82 test đạt

# Deploy
firebase deploy --only functions:pos --project tramapp-36f53
firebase deploy --only database --project tramapp-36f53

# Build IPA (LANG bắt buộc vì CocoaPods)
cd app_flutter && export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && flutter build ipa --release --export-method app-store
# Kết quả: build/ios/ipa/POS Trạm.ipa  (tăng số build trong pubspec.yaml: 1.0.0+N trước khi build lại)
```

**Lưu ý môi trường:**
- Máy có Java 17 (mặc định) và Java 21 (`~/development/jdk-21`). Emulator RTDB cần 21.
- Cổng emulator mặc định 9000; nếu đang bận dùng cổng khác (ví dụ 9187) — xem config `firebase.json`.
- `firebase` CLI đã đăng nhập bằng `nthanhtam.402@gmail.com`. Token nằm ở `~/.config/configstore/firebase-tools.json` (không đưa vào repo).
- Xcode đã có tài khoản Apple trả phí team `W97CS7VC54`; nếu báo "Account credentials have expired" thì đăng nhập lại trong Xcode → Settings → Accounts.

---

## 6. Các việc còn mở (theo độ ưu tiên)

1. **Build lại IPA** (có tính năng mới) → TestFlight. Tăng `version: 1.0.0+2` trong `pubspec.yaml` trước khi build (bản `+1` đã tải lên hoặc đã từng build — kiểm tra App Store Connect).
2. **Deploy rules** theo mục 4 (sau khi app mới đã cài).
3. **Android**: đổi package `com.example.tramapp` → `vn.tram.fnb.pos` (hướng dẫn chi tiết trong `docs/CHAMCONG_SSO.md` §B). Cần Firebase Console: thêm app Android, tải `google-services.json` mới. Hiện bản Android **không build được** nếu đổi package mà chưa có file mới.
4. **Kiểm thử thiết bị thật** các luồng: mở/đóng ca từng tài khoản, báo hết món bếp, danh mục note/topping, xóa tài khoản, cấp quyền riêng cho quản lý.
5. **Ảnh chụp App Store**: đã có iPad 13" (`app_store_screenshots/ipad_13_landscape/`, 2752×2064). Còn thiếu iPhone 6.9" (1290×2796) nếu app chạy trên iPhone. Nên chụp từ cửa hàng DEMO (không dùng số liệu thật của Trạm Chanh).
6. **Email liên hệ** trên trang chính sách: đặt biến Vercel `NEXT_PUBLIC_PRIVACY_EMAIL` rồi Redeploy (hiện trang hướng dẫn "liên hệ chủ cửa hàng").
7. **Gửi App Review**: điền Notes (phần A của `docs/private/APP_REVIEW_NOTES.md`), tick Sign-in required, điền Contact Information. Chỉ gửi khi bạn xác nhận.
8. **Mục nhỏ đã biết**: nút "tạm ngưng" cũ của quản lý không ghi người báo; topping hết vẫn chọn được trong bảng tùy chọn; nhãn nhật ký mới chưa có tiếng Việt thân thiện.

---

## 7. Quyết định thiết kế đã chốt (đừng đảo ngược nếu không hỏi bạn)

- **Mỗi tài khoản một ca, một két.** Thanh toán tính vào ca của người thu tiền. Nhân viên đóng ca "mù" (không thấy dự kiến/chênh lệch), không xem phiếu bàn giao.
- **Quản lý mặc định không** hủy/xóa hóa đơn đã chốt, không xem nhật ký (`CANCEL_BILL`, `CANCEL_KITCHEN_ITEM`, `VIEW_AUDIT_LOGS`, `EXPORT_AUDIT_LOGS` là "chủ-cấp-riêng").
- **Điểm dùng chung một dữ liệu** cho cả chuỗi (`loyalty_members/{SĐT}`). Client không ghi điểm trực tiếp; mọi thao tác qua callable, idempotent theo hóa đơn.
- **Khuyến mãi không tự áp** vào giỏ — nhân viên chọn hoặc nhập mã.
- **Chủ quán gốc không tự xóa tài khoản** trong app (ngoại lệ có chủ đích, giải thích cho Apple).
- **Danh mục note/topping**: món chưa gắn gì thì **không hiện** topping/note nhanh. Cửa hàng chưa cấu hình giữ hành vi cũ.
- **Size/đường/đá** vẫn lấy từ thuộc tính món (chưa đổi sang nhóm). Đồ uống vẫn hiện S/M/L — nếu cần đổi, làm riêng.
- **Quyền tùy chỉnh chỉ THÊM quyền**, không bớt. Muốn giới hạn nhân viên cụ thể cần cơ chế từ chối (chưa làm).
- Tên vai trò "Nhân viên" là tạm; đổi ở một hằng số mỗi codebase.

---

## 8. Giới hạn kỹ thuật đã biết (không phải bug, nhưng cần nhớ)

- **Quyền đọc RTDB vẫn cấp theo cửa hàng**: người có bản app bị chỉnh sửa vẫn đọc được ca/hóa đơn của người khác. Muốn chặn hẳn phải chuyển sang đọc qua Cloud Function.
- **Hủy món đã gửi bếp** không chặn được bằng rules (chỉ UI + handler + PIN).
- **Quyền tùy chỉnh** dò tới 40 phần tử (`customPermissions/0..39`) vì RTDB rules không duyệt mảng.
- **Hóa đơn và báo cáo cuối ngày trên web** chưa lọc theo tài khoản.
- **Tìm khách** trong app chỉ liệt kê khách của chi nhánh đang bán; khách chỉ ở chi nhánh khác tìm bằng đúng số điện thoại.
- **Bản app cũ** (chưa cập nhật) sẽ không tích/đổi điểm được sau khi rules mới có hiệu lực.

---

## 9. Bản đồ tài liệu

| File | Nội dung |
|---|---|
| `docs/HANDOFF.md` | **File này** |
| `docs/private/APP_REVIEW_NOTES.md` | Ghi chú Apple + mật khẩu demo (**không git**) |
| `docs/TESTFLIGHT.md` | Bộ thông tin App Store Connect, quy trình build/upload |
| `docs/APP_REVIEW.md` | Ghi chú xóa tài khoản cho Apple |
| `docs/ROLE_RULES.md` | Quy tắc từng vai trò (cái gì được/không) |
| `docs/PERMISSIONS_AUDIT.md` | Mọi mã quyền × vai trò × nơi áp dụng |
| `docs/NOTE_CATALOG.md` | Danh mục note/topping |
| `docs/CHAMCONG_SSO.md` | Đăng nhập Chấm Công: IAM, app, triển khai |
| `docs/RULES_NOTES.md` | Rules: thay đổi, thứ tự deploy, PIN cũ |
| `docs/REPORT_SPEC.md` | Đặc tả báo cáo (ngày hủy, giảm giá theo dòng...) |
| `docs/AUTH_CONTRACT.md` | Hợp đồng đăng nhập |
| `docs/database_schema.md`, `docs/TAI_LIEU_KY_THUAT.md` | Cấu trúc dữ liệu tổng thể (có thể cũ hơn code) |

**Cửa hàng demo** — tài khoản và mật khẩu: `docs/private/APP_REVIEW_NOTES.md` (phần Tài khoản demo). Bản sao thô: `/private/tmp/.../scratchpad/demo_credentials.json` (tạm, sẽ mất khi máy khởi động lại — lấy từ file trong `docs/private/` là chính).

---

## 10. Cách làm việc đã thống nhất với chủ dự án

- **Không commit, push, deploy, tải lên Apple hay gửi duyệt khi chưa được xác nhận rõ ràng** cho từng bước. Đã nhiều lần bạn bảo "commit hết" nên cứ làm khi có lệnh.
- Commit có `Co-Authored-By` theo quy định phiên bản model đang dùng.
- Mọi ghi dữ liệu production phải có **sao lưu trước** và dry-run mặc định cho script.
- Trả lời bằng tiếng Việt, ngắn gọn, nêu rõ việc đã xong / chưa xong / cần bạn quyết.
- Khi đề xuất thay đổi lớn (rules, deploy, xóa dữ liệu) — hỏi trước.

---

## 11. Bắt đầu nhanh ở VS Code

1. Mở thư mục `Tram_FnB_System` trong VS Code.
2. Đọc file này, rồi `docs/ROLE_RULES.md` nếu làm về quyền, `docs/NOTE_CATALOG.md` nếu làm về topping/note.
3. Chạy bộ kiểm tra (mục 5) để xác nhận môi trường: kỳ vọng functions 108, Flutter 372, web 381, rules 82 đều xanh.
4. Việc đầu tiên thường là mục 6.1 (build IPA) hoặc 6.2 (deploy rules) — **hỏi chủ dự án xác nhận trước**.

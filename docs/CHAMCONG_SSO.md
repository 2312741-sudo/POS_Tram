# Đăng nhập bằng Chấm Công Trạm (SSO) — Hướng dẫn cài đặt & mô hình bảo mật

Nhân viên / chủ quán bấm **"Đăng nhập bằng Chấm Công Trạm"** trên màn hình đăng nhập POS, đăng nhập bằng tài khoản Firebase của project **`chamcongtram`** (app Chấm Công Trạm, Firestore), rồi POS tự cấp tài khoản và cho vào quán.

```
App POS ──(1) đăng nhập Firebase app phụ "chamcong" (project chamcongtram)──► lấy ID token chấm công
        ──(2) callable chamCongSignIn({ idToken, storeCode? })──► Cloud Functions (tramapp-36f53)
               • verifyIdToken(idToken, checkRevoked=false) bằng Admin app phụ "chamcong"
               • đọc Firestore chamcongtram: members (collectionGroup theo userId) + stores (ownerId)
               • đối chiếu chamcong_links (RTDB) → cấp/cập nhật stores/{storeCode}/users/cc_{uid}
               • trả về customToken
        ──(3) signInWithCustomToken(customToken) trên app Firebase CHÍNH (tramapp-36f53)
```

## Hợp đồng API (callable, region `asia-southeast1`)

| Callable | Yêu cầu đăng nhập POS | Request | Response |
|---|---|---|---|
| `chamCongSignIn` | Không | `{ idToken, storeCode? }` | `{status:"OK", customToken, storeCode, uid, roleId, isNewAccount}` hoặc `{status:"CHOOSE_STORE", stores:[{storeCode, storeName}]}` |
| `linkChamCongStore` | Chủ quán | `{ storeCode, idToken, chamCongStoreId? }` | `{status:"CHOOSE_CHAMCONG_STORE", stores:[{chamCongStoreId, name, code}]}` hoặc `{status:"LINKED", chamCongStoreId, chamCongStoreName}` |
| `unlinkChamCongStore` | Chủ quán | `{ storeCode }` | `{status:"UNLINKED", wasLinked}` |
| `getChamCongLinkStatus` | Chủ quán / Quản lý | `{ storeCode }` | `{linked, chamCongStoreId?, chamCongStoreName?, linkedAt?, provisionedCount}` |

Lỗi là `HttpsError` với thông báo tiếng Việt và `details.code`:

| HttpsError | `details.code` | Ý nghĩa |
|---|---|---|
| `unauthenticated` | `INVALID_TOKEN` | Token sai project / hết hạn / bị thu hồi / tài khoản chấm công bị vô hiệu / ẩn danh |
| `permission-denied` | `NOT_LINKED` | Không cửa hàng chấm công nào của user được liên kết POS, hoặc `storeCode` gửi lên không thuộc các cửa hàng đó |
| `permission-denied` | `NOT_ACTIVE_MEMBER` | Thành viên `pending` / `kicked` / đã bị xóa khỏi cửa hàng |
| `permission-denied` | `POS_ACCOUNT_DISABLED` | Chủ quán đã khóa tài khoản này trong POS |
| `permission-denied` | `POS_ACCOUNT_CONFLICT` | (Hiếm) uid `cc_…` trùng với tài khoản POS gốc không do chấm công cấp |
| `permission-denied` | `NOT_STORE_OWNER` | (`linkChamCongStore`) tài khoản chấm công không phải Chủ của cửa hàng đã chọn |
| `failed-precondition` | `ALREADY_LINKED` | Cửa hàng chấm công đã liên kết với cửa hàng POS khác |
| `internal` | — | Thiếu quyền IAM (xem mục A) hoặc lỗi máy chủ |

### Ánh xạ vai trò

| Chấm Công (`members.role`) | POS `roleId` |
|---|---|
| `owner`, `chu` (hoặc `stores.ownerId === uid`) | `owner` (KHÔNG phải `isRootOwner`) |
| `manager1`, `manager_1`, `manager`, `legacyManager` | `manager_1` |
| `manager2`, `manager_2` | `manager_2` |
| `employee` / khác | `ROLE_WAITER` (vai trò thấp nhất — không dùng `employee` vì rules POS coi `employee` = Thu ngân) |

- Lần đăng nhập sau: tên / số điện thoại / avatar được đồng bộ; Chủ/Quản lý bên chấm công → luôn đặt lại vai trò ánh xạ; nhân viên bên chấm công mà POS đang là chủ/quản lý → **hạ về `ROLE_WAITER`**; còn lại giữ vai trò chủ quán đã chọn trong POS (Thu ngân, Bếp…). Muốn ai làm quản lý POS thì nâng vai trò bên Chấm Công.
- Username: `employeeCode` viết thường → slug họ tên → `nv` + 6 ký tự uid; trùng thì thêm `-2`, `-3`… Username không đổi sau khi đã cấp.
- Tài khoản POS do SSO cấp không có mật khẩu (`authProvider: "chamcong"`, `mustChangePassword: false`), chỉ đăng nhập được qua nút Chấm Công.

### Dữ liệu RTDB

```
chamcong_links/stores/{storeCode}               = { chamCongStoreId, chamCongStoreName, linkedByUid, linkedAt }
chamcong_links/byChamCongStore/{chamCongStoreId} = storeCode
chamcong_links/users/{storeCode}/{chamCongUid}   = "cc_{chamCongUid}"
stores/{storeCode}/storeInfo/chamCongStoreId, chamCongStoreName   (chỉ để hiển thị)
stores/{storeCode}/users/cc_{chamCongUid}       = { uid, username, fullName, phone, avatarUrl, roleId, isRootOwner:false,
                                                   isActive, authProvider:"chamcong", chamCongUid, chamCongStoreId,
                                                   mustChangePassword:false, customPermissions:[], createdAt, lastLoginAt,
                                                   deactivatedBy?:"chamcong", chamCongRevokedAt? }
userIndex/cc_{chamCongUid}/{storeCode} = true
```

`chamcong_links/**` nằm ở GỐC: rules gốc `.read/.write: false` nên client không đọc/ghi được (test `CC1` trong `tests/rules/rules.test.ts`). Chỉ Cloud Functions (Admin SDK) truy cập.

Audit log (`stores/{s}/audit_logs`): `CHAMCONG_SIGN_IN`, `CHAMCONG_ACCOUNT_PROVISIONED`, `CHAMCONG_ROLE_SYNCED`, `CHAMCONG_ACCESS_REVOKED`, `CHAMCONG_STORE_LINKED`, `CHAMCONG_STORE_UNLINKED`.

---

## A. IAM: cho Functions của POS đọc project `chamcongtram`

Functions v2 (Cloud Run) của `tramapp-36f53` mặc định chạy bằng **default compute service account**:

```
866082811261-compute@developer.gserviceaccount.com
```

(`866082811261` là project number của `tramapp-36f53`; kiểm tra lại tại Cloud Console → Cloud Run → service `chamcongsignin` → tab Security, hoặc `gcloud run services describe chamcongsignin --region asia-southeast1 --project tramapp-36f53 --format='value(spec.template.spec.serviceAccountName)'`. Nếu để trống nghĩa là đang dùng SA mặc định ở trên.)

Cấp **trên project `chamcongtram`** (người thực hiện phải là Owner/IAM Admin của `chamcongtram`):

```bash
SA=866082811261-compute@developer.gserviceaccount.com

# 1. Đọc Firestore chấm công (members, stores) — chỉ đọc
gcloud projects add-iam-policy-binding chamcongtram \
  --member="serviceAccount:$SA" --role="roles/datastore.viewer"

# 2. (KHÔNG còn bắt buộc từ 2026-10-09: đã tắt checkRevoked; quyền thật kiểm tra qua trạng thái thành viên Firestore)
gcloud projects add-iam-policy-binding chamcongtram \
  --member="serviceAccount:$SA" --role="roles/firebaseauth.viewer"
```

Nếu log Functions báo lỗi kiểu `USER_PROJECT_DENIED` / "Caller does not have required permission to use project", cấp thêm `roles/serviceusage.serviceUsageConsumer` trên `chamcongtram` cho cùng SA.

Trên `tramapp-36f53` (đã có từ `staffSignIn`): SA trên cần **Service Account Token Creator** trên chính nó để `createCustomToken`.

**Cách verifyIdToken cho project khác hoạt động:** Functions tạo Admin app phụ tên `"chamcong"` với `projectId = CHAMCONG_PROJECT_ID` (mặc định `chamcongtram`) và `applicationDefault()` (chính SA ở trên). Việc kiểm tra chữ ký ID token chỉ cần khóa công khai của Google và so `aud`/`iss` với `chamcongtram` — token của project khác (kể cả `tramapp-36f53`) đều bị từ chối. `checkRevoked` đang tắt nên không cần quyền ở bước 2 (bật lại thì cần `roles/firebaseauth.viewer` và có thể cả `roles/serviceusage.serviceUsageConsumer`). Đọc Firestore cần bước 1. Truy vấn `collectionGroup("members").where("userId","==",uid)` dùng index field override đã có sẵn trong `app_cham_cong/.../firestore.indexes.json`.

## B. Đăng ký app POS trong Firebase project `chamcongtram`

App POS cần một Firebase app phụ trỏ tới `chamcongtram` để đăng nhập tài khoản chấm công (Firebase Console → project **chamcongtram** → Project settings → Your apps → Add app):

1. **Android** — package `com.example.tramapp`.
   - ⚠️ **Việc cần làm sau (đã hoãn):** package hiện tại vẫn là mẫu `com.example.tramapp`; Google Play từ chối package bắt đầu bằng `com.example`. Dự kiến đổi sang **`vn.tram.fnb.pos`** (cùng họ với `vn.tram.fnb.tram_payment_bot`). Nên đổi **trước** khi đăng ký Android app vào `chamcongtram` để khỏi đăng ký lại. Các bước khi đổi:
     1. `app_flutter/android/app/build.gradle`: `namespace` và `applicationId` → `vn.tram.fnb.pos`.
     2. Chuyển `MainActivity.kt` sang `app/src/main/kotlin/vn/tram/fnb/pos/` (sửa dòng `package`), xóa `kotlin/com/example/tramapp/` và bản thừa `kotlin/com/example/tram_flutter/`.
     3. Firebase Console → project `tramapp-36f53` → Add app → Android `vn.tram.fnb.pos` (+ SHA-1/SHA-256) → tải `google-services.json` mới thay vào `app_flutter/android/app/` và chạy `flutterfire configure` (cập nhật `appId` Android trong `firebase_options.dart`). **Thiếu bước này bản Android không build được** (google-services báo "No matching client found for package name").
     4. Đăng ký package mới (không phải `com.example.tramapp`) vào `chamcongtram` ở bước này.
     5. (Tùy chọn) `app_flutter/windows/runner/Runner.rc`: đổi `CompanyName`/`LegalCopyright` khỏi `com.example`.
   - Thêm **SHA-1 và SHA-256** của keystore debug và release (`cd app_flutter/android && ./gradlew signingReport`; nếu phát hành qua Google Play thì thêm cả SHA của *App signing key* trong Play Console). Bắt buộc cho Google Sign-In.
   - Lấy `appId` / `apiKey` từ `google-services.json` của app này để khởi tạo app phụ trong Flutter (KHÔNG thay `google-services.json` chính của tramapp).
2. **iOS** — bundle `com.tramapp.tramFlutter`.
   - Tải `GoogleService-Info.plist` của chamcongtram, lấy `CLIENT_ID`, `REVERSED_CLIENT_ID`, `GOOGLE_APP_ID`, `API_KEY`.
   - Thêm **`REVERSED_CLIENT_ID` của chamcongtram** vào `CFBundleURLTypes` (URL Schemes) trong `ios/Runner/Info.plist` (bên cạnh scheme hiện có, nếu có) để Google Sign-In quay lại app.
3. **Web** — thêm Web app, lấy config (`apiKey`, `authDomain: chamcongtram.firebaseapp.com`, `appId`…).
   - **Đã tạo (2026-10-09):** Web app "POS Tram Web" (`1:476583007511:web:0616a296375326d7ce1352`) và iOS app "POS Tram iOS" (`com.tramapp.tramFlutter`, `1:476583007511:ios:85484a6abc0243cfce1352`) trong `chamcongtram`; config đã điền vào `app_flutter/assets/config/chamcong_firebase_options.json` và `web/.env.local` (gitignored), URL scheme `REVERSED_CLIENT_ID` đã thêm vào `ios/Runner/Info.plist`. Android chưa đăng ký (chờ đổi package).
   - Web POS production: **`pos-tram.vercel.app`** → thêm vào Authorized domains (bên dưới) và khai báo 4 biến `NEXT_PUBLIC_CHAMCONG_*` (giá trị trong `web/.env.local`) ở Vercel → Project → Settings → Environment Variables (Production + Preview), rồi Redeploy.
   - Authentication → Settings → **Authorized domains** của `chamcongtram`: thêm domain web POS (VD `tramapp-36f53.web.app`, `tramapp-36f53.firebaseapp.com`, domain riêng nếu có, và `localhost` khi dev).
4. Các phương thức đăng nhập dùng trong POS phải đang bật ở Authentication của `chamcongtram` (Email/Password, Google, Apple… đúng như app Chấm Công đang dùng).

## C. Apple Sign-In

- Nếu Chấm Công cho đăng nhập Apple: trong Apple Developer, App ID `com.tramapp.tramFlutter` bật capability **Sign in with Apple** và thêm entitlement vào target Runner.
- Firebase `chamcongtram` → Authentication → Apple: thêm bundle `com.tramapp.tramFlutter` vào danh sách (Services ID / bundle ID được chấp nhận). Với web/Android: cần Services ID + return URL `https://chamcongtram.firebaseapp.com/__/auth/handler`.
- Tài khoản Apple dùng "Hide My Email" vẫn là CÙNG uid Firebase trong `chamcongtram` khi đăng nhập từ cùng team Apple, nên tài khoản POS khớp đúng người. Nếu App ID POS thuộc **team Apple khác** app Chấm Công, Apple sẽ trả `sub` khác → Firebase tạo user khác → người đó sẽ "không phải thành viên". Giữ chung Apple team, hoặc khuyên nhân viên dùng Google/Email.

## D. Biến môi trường

`functions/.env` (tùy chọn):

```
CHAMCONG_PROJECT_ID=chamcongtram
```

Không khai báo thì mặc định `chamcongtram`. Không cần secret nào khác (dùng ADC của service account).

## E. Thứ tự triển khai

1. Cấp IAM (mục A) và đăng ký app (mục B, C).
2. `firebase deploy --only functions --project tramapp-36f53` (thêm `chamCongSignIn`, `linkChamCongStore`, `unlinkChamCongStore`, `getChamCongLinkStatus`). Không cần đổi `database.rules.json` (`chamcong_links` đã bị chặn bởi rules gốc).
3. Phát hành app Flutter / web có nút "Đăng nhập bằng Chấm Công Trạm" và màn hình liên kết trong Cài đặt.
4. **Chủ quán liên kết cửa hàng**: đăng nhập POS bằng tài khoản Chủ quán → Cài đặt → "Liên kết Chấm Công Trạm" → đăng nhập tài khoản Chủ trên Chấm Công → chọn cửa hàng chấm công (`linkChamCongStore`). Từ lúc này nhân viên `active` của cửa hàng đó đăng nhập được POS.
5. Chủ quán vào Quản lý nhân viên để nâng vai trò cho nhân viên (Thu ngân, Bếp…) — mặc định là Phục vụ.

## F. Mô hình bảo mật

- **Nguồn danh tính:** chỉ ID token do `chamcongtram` ký, kiểm tra thu hồi. Uid POS cố định `cc_{uidChấmCông}` nên một người luôn ứng với một tài khoản POS (dùng chung cho mọi chi nhánh được liên kết, phân biệt quán bằng `userIndex`).
- **Ai được vào quán nào:** chỉ cửa hàng POS đã được Chủ quán POS liên kết (Chủ quán POS + Chủ cửa hàng chấm công cùng xác nhận). Mỗi cửa hàng chấm công chỉ liên kết được 1 cửa hàng POS (`ALREADY_LINKED`).
- **Vai trò cao** (owner/manager) luôn lấy từ Chấm Công; POS không thể giữ quyền quản lý cho người chấm công coi là nhân viên. Chủ do SSO cấp là `owner` thường, không bao giờ `isRootOwner`; hồ sơ `isRootOwner` và tài khoản POS gốc (không phải `authProvider:"chamcong"`) không bao giờ bị ghi đè.
- **Khi bị kick / chờ duyệt / bị xóa trên Chấm Công:** ở lần gọi `chamCongSignIn` kế tiếp của người đó, hồ sơ POS ở quán tương ứng bị đặt `isActive:false` (`deactivatedBy:"chamcong"`), refresh token bị thu hồi (`revokeRefreshTokens`), ghi audit `CHAMCONG_ACCESS_REVOKED` và từ chối `NOT_ACTIVE_MEMBER`. Rules POS chặn mọi đọc/ghi của tài khoản `isActive:false`.
  - **Hạn chế:** phiên POS đang mở sẵn KHÔNG tự bị đá ra ngay khi bị kick bên chấm công (POS chưa có trigger từ Firestore chấm công). Khi cho nghỉ việc, chủ quán nên khóa thêm tài khoản trong POS (Quản lý nhân viên → Khóa) — khóa thủ công này có ưu tiên cao hơn: kể cả khi được duyệt lại trên Chấm Công, tài khoản vẫn `POS_ACCOUNT_DISABLED` cho tới khi mở khóa trong POS.
  - Nếu chỉ bị khóa do chấm công và sau đó được duyệt lại (`active`), lần đăng nhập sau tài khoản tự mở lại.
- **Hủy liên kết** (`unlinkChamCongStore`) chỉ xóa `chamcong_links/stores` + `byChamCongStore` và trường hiển thị trong `storeInfo`; tài khoản đã cấp và `chamcong_links/users` được giữ để liên kết lại dùng đúng tài khoản cũ. Sau khi hủy, không ai đăng nhập SSO được vào quán đó (`NOT_LINKED`). Xóa hồ sơ nhân viên SSO trong POS không chặn họ — lần đăng nhập sau sẽ được cấp lại; muốn chặn thì **khóa** thay vì xóa.

## G. Quan sát bảo mật phía Chấm Công (cần sửa bên app_cham_cong)

`app_cham_cong/firebase_functions/firestore.rules` (khoảng dòng 141):

```
match /stores/{storeId} {
  allow read: if isSignedIn();
```

cho **mọi người dùng đã đăng nhập** đọc toàn bộ document `/stores/{storeId}`, bao gồm trường **`deletePassword`** (mật khẩu bảo mật dùng khi xóa dữ liệu / xóa cửa hàng). Bất kỳ ai tạo được tài khoản chấm công (kể cả không thuộc cửa hàng) đều đọc được mật khẩu này. Khuyến nghị: chuyển `deletePassword` sang subcollection/document riêng chỉ chủ đọc được (hoặc chỉ lưu hash và kiểm tra qua Cloud Function), và giới hạn đọc `/stores/{storeId}` cho thành viên; nếu cần tra cứu theo mã khi tham gia, tách document công khai tối thiểu (tên, mã). Việc sửa này thuộc app Chấm Công; POS không phụ thuộc vào trường đó (POS chỉ đọc qua Admin SDK).

# Hướng Dẫn Thiết Lập & Đồng Nhất Dự Án Firebase POS Trạm (`tramapp-36f53`)

Tài liệu này hướng dẫn quy trình cấu hình, chuẩn hóa môi trường Firebase cho toàn bộ hệ sinh thái POS Trạm (Mobile Flutter, Web Admin Next.js, Cloud Functions backend) trên một dự án Firebase gốc duy nhất: **`tramapp-36f53`**.

---

## 1. Danh Sách Việc Cần Làm Bằng Tay (Thực hiện theo đúng thứ tự)

### Bước 1: Kiểm tra và Đăng ký App trên Firebase Console
1. Truy cập [Firebase Console](https://console.firebase.google.com/) và chọn project **`tramapp-36f53`**.
2. Kiểm tra danh sách Apps:
   - **Android App**: Đảm bảo package name `com.tram.pos` (hoặc package tương ứng trong AndroidManifest.xml) đã được đăng ký, tải file `google-services.json` mới nhất nếu có cập nhật SHA fingerprint.
   - **iOS App**: Đảm bảo bundle identifier `com.tram.pos` đã được đăng ký (nếu có build iOS).
   - **Web App**: Đã có App ID cho Web Admin.

### Bước 2: Bật Phương thức Xác thực (Authentication)
1. Trong menu **Build** > **Authentication** > tab **Sign-in method**.
2. Đảm bảo provider **Email/Password** đã được bật (**Enabled**).

### Bước 3: Đồng nhất cấu hình Flutter (`firebase_options.dart`)
1. Cài đặt FlutterFire CLI (nếu chưa có):
   ```bash
   dart pub global activate flutterfire_cli
   ```
2. Chạy lệnh sinh lại file cấu hình chuẩn trong thư mục `app_flutter/`:
   ```bash
   cd app_flutter
   flutterfire configure --project=tramapp-36f53
   ```
   *Lưu ý: Không chỉnh sửa tay các thông số `apiKey` hay `projectId` trong `firebase_options.dart`.*

### Bước 4: Kích hoạt gói Blaze (Pay-as-you-go)
- Cloud Functions v2 yêu cầu project phải bật gói cước **Blaze**.
- Gói Blaze dùng chung cho toàn bộ project `tramapp-36f53` (bao gồm cả app Chấm công và app Tích điểm). Mức dùng thông thường của POS vẫn nằm trong hạn mức miễn phí hàng tháng (Free tier) của Google Cloud.

### Bước 5: Kiểm tra biến môi trường Database URL cho Functions
- Database của dự án nằm tại khu vực Singapore: `asia-southeast1`.
- URL đầy đủ: `https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app`.
- Trong file `functions/src/index.ts`, hệ thống đã cấu hình fallback tự động về URL này khi biến `DATABASE_URL` không được truyền vào.

### Bước 6: Thử nghiệm trên môi trường Staging trước khi lên Production
1. Tạo một project Firebase thử nghiệm (ví dụ `tramapp-staging`).
2. Deploy Rules và Functions lên project staging để chạy test nghiệm thu:
   ```bash
   firebase deploy --only functions:pos --project tramapp-staging
   ```
3. Sau khi xác nhận hoạt động ổn định trên Staging, mới tiến hành triển khai lên project thật `tramapp-36f53`.

---

## 2. Lệnh Triển Khai (Deploy) An Toàn

> [!CAUTION]
> **TUYỆT ĐỐI KHÔNG CHẠY `firebase deploy` HOẶC `firebase deploy --only functions` KHÔNG CÓ TÊN CODEBASE!**
> Do project `tramapp-36f53` dùng chung với app Chấm công (có sẵn 13 Cloud Functions), lệnh deploy mặc định sẽ coi các hàm của app Chấm công là "dư thừa" và tiến hành XÓA toàn bộ các hàm đó.

### Lệnh Deploy Cloud Functions cho POS:
```bash
# Triển khai CHỈ các functions thuộc codebase "pos":
firebase deploy --only functions:pos --project tramapp-36f53
```

### Lệnh Deploy Realtime Database Rules:
```bash
# Triển khai rules cho Realtime Database mặc định:
firebase deploy --only database --project tramapp-36f53
```

---

## 3. Cần Chủ Dự Án Quyết Định (Khách Hàng KMT / CRM)

Trong `app_flutter/lib/data/repositories/report_repository.dart`:
- **Vị trí 1 - Dòng 417-427**: Hàm `lookupCustomer(query)` thực hiện tìm kiếm khách hàng trong Firestore collection `kmt_customers`, nếu không thấy hoặc lỗi thì fallback tìm trong Realtime Database node `kmt_customers`.
- **Vị trí 2 - Dòng 449-450**: Hàm `saveCustomer(customer)` ghi đồng thời dữ liệu khách hàng vào cả Realtime Database node `kmt_customers/{id}` và Firestore collection `kmt_customers/{id}`.

### Tình trạng kỹ thuật hiện tại:
- Cả hai lệnh Firestore trên đã được bọc trong khối `try { ... } catch (_) {}`, đảm bảo nếu Firestore chưa được kích hoạt hoặc Rules chặn quyền thì luồng bán hàng / thanh toán của POS **hoàn toàn không bị gián đoạn hay phát sinh crash**.

### Quyết định kiến trúc cần chốt:
1. Dữ liệu khách hàng tích điểm (CRM) chính thức của hệ thống KMT nằm ở **Realtime Database** hay **Cloud Firestore**?
2. POS nên dùng nguồn nào làm Single Source of Truth:
   - *Phương án A*: Giữ cơ chế lai hiện tại (ưu tiên Firestore, fallback RTDB).
   - *Phương án B*: Chuyển hẳn sang chỉ đọc/ghi trên Realtime Database để đồng nhất hạ tầng với đơn hàng và bàn của POS.
   - *Phương án C*: Chuyển hẳn sang Firestore nếu app tích điểm khách hàng đang hoạt động chủ yếu trên Firestore.

# Prompt giao việc: vá bảo mật eMudhra cho app Chấm Công Trạm

Dán nguyên văn nội dung trong khung dưới đây cho agent làm app Chấm Công (project Firebase `chamcongtram`, `chamcongtramblao`, `tamchau-865f3`).

---

Bạn là kỹ sư mobile. Hãy vá lỗ hổng bảo mật Firebase/Firestore cho **app Chấm Công Trạm** (repo của app chấm công, KHÔNG phải app POS). Làm tuần tự, tự kiểm tra, không hỏi lại những gì có thể tự xác minh.

## Bối cảnh (thông báo của Firebase, ngày 2026-10)

Khóa riêng của một số chứng chỉ CA trung gian của eMudhra bị lộ và đã bị thu hồi. Các SDK cũ biên dịch sẵn danh sách chứng chỉ gốc TLS vào file build nên **vẫn tin chứng chỉ giả** → kẻ tấn công trên đường truyền (man-in-the-middle, ví dụ cùng wifi công cộng) có thể đọc/sửa dữ liệu. Cập nhật hệ điều hành hay sửa phía server KHÔNG vá được bản app đã cài; phải nâng SDK, build lại, phát hành lại.

Project bị ảnh hưởng của chúng tôi: `chamcongtram`, `tamchau-865f3`, `chamcongtramblao`.

Hướng dẫn chính thức: https://firebase.google.com/support/guides/compromised-emudhra-intermediate-ca (đọc lại để xác nhận phiên bản trước khi làm, vì bảng phiên bản có thể được cập nhật).

## Phiên bản cần đạt

| Thành phần | Bị ảnh hưởng | Cần đạt |
|---|---|---|
| Flutter `cloud_firestore` (iOS/macOS/Windows) | 7.0.0 trở xuống (trừ 6.10.1, 6.10.2) | **7.1.0** (FlutterFire BoM 5.1.0+); hoặc bản vá cũ 6.10.1 cho iOS/macOS |
| Flutter/Dart trên **Android, Windows, Linux** (mọi app Flutter, kể cả không dùng Firestore) | Dart/Flutter cũ | **Flutter 3.47.8+** (Dart 3.13.7+) |
| Firebase Apple SDK native (CocoaPods) | 13.1.0 trở xuống (trừ 12.19.3); CocoaPods 12.19.2 trở xuống | **12.19.3** (CocoaPods) hoặc **13.1.1+** (SwiftPM) |
| Firebase Web SDK, Firebase Android SDK (native), server SDK | Không bị ảnh hưởng | Không cần |

(Nếu app chấm công là React Native, Unity, C++ hoặc native iOS thuần, dùng các dòng tương ứng trong hướng dẫn chính thức.)

## Các bước

1. **Xác định công nghệ** của app chấm công: Flutter? (xem `pubspec.yaml`, `pubspec.lock`), có dùng `cloud_firestore` không, có iOS/Android/Windows không. Ghi lại phiên bản đang dùng của `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_database`, `cloud_functions`, `firebase_storage`, `firebase_messaging`... và phiên bản Flutter (`flutter --version`).
2. **Nâng Flutter** lên ≥ 3.47.8: `flutter upgrade`, kiểm tra `flutter --version`.
3. **Nâng nhóm FlutterFire theo BoM 5.1.0** (phải nâng cả nhóm vì các gói phụ thuộc lẫn nhau): `flutter pub upgrade --major-versions firebase_core firebase_auth cloud_firestore <các gói firebase_*/cloud_* khác đang dùng>`. Kết quả mong đợi tham khảo: firebase_core 5.1.x, firebase_auth 7.0.x, cloud_firestore 7.1.0, firebase_database 13.0.x, cloud_functions 7.0.x. Nếu pub báo xung đột, nâng thêm các gói Firebase còn lại theo gợi ý của pub.
4. **Sửa lỗi biên dịch do đổi API.** Các lỗi đã gặp ở app POS cùng bộ nâng cấp, nhiều khả năng bạn cũng gặp:
   - `firebase_core` 5 xuất thêm class `FirebaseService` → nếu app có class trùng tên, đổi import thành `import 'package:firebase_core/firebase_core.dart' hide FirebaseService;`.
   - Firebase Android SDK mới có metadata Kotlin 2.4 → nâng Kotlin Gradle Plugin lên **2.3.20** (`android/settings.gradle`: `id "org.jetbrains.kotlin.android" version "2.3.20"`). Cần Gradle 8.14+ và AGP 8.11+ (đã đủ ở POS; kiểm tra ở app này).
   - iOS: Firebase Apple SDK 12.19.3 cần **iOS 16.0+** → đặt `platform :ios, '16.0'` trong `ios/Podfile`, `IPHONEOS_DEPLOYMENT_TARGET = 16.0` trong `ios/Runner.xcodeproj/project.pbxproj` và trong khối `post_install` của Podfile.
   - Đọc changelog của từng gói khi nâng nhiều bản major (firebase_auth 5→7, firebase_database 11→13, cloud_functions 5→7) và sửa các API đã đổi.
5. **Cập nhật pod iOS**: chạy với `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`, rồi trong thư mục `ios/` xóa `Podfile.lock` và chạy `pod install --repo-update` (spec cache cũ sẽ báo "không tìm thấy phiên bản tương thích"). Xác nhận `Podfile.lock` có `FirebaseFirestore (12.19.3)` hoặc mới hơn, không còn `11.x`/`12.19.2` trở xuống.
6. **Biên dịch thật cả hai nền tảng**: `flutter build apk --release` và `flutter build ios --release --no-codesign` phải thành công. (`flutter analyze` có thể crash nếu đường dẫn dự án có ký tự không phải ASCII; khi đó dùng `flutter test` + build để bắt lỗi.)
7. **Chạy toàn bộ test** (`flutter test`), sửa test hỏng do nâng cấp (đừng xóa/skip test để qua).
8. **Kiểm thử chức năng chính** trên máy thật hoặc giả lập: đăng nhập (Google/Apple/Email nếu có), chấm công vào/ra, đọc/ghi Firestore, thông báo đẩy, đăng nhập SSO với app POS nếu có. Báo rõ chỗ nào đã tự kiểm tra, chỗ nào cần người thử.
9. **Tăng số phiên bản** (`pubspec.yaml`, ví dụ tăng build number) để bản vá phát hành được lên App Store / phân phối Android.
10. **Quét các kết nối còn lại**: tìm mọi nơi app tự gọi HTTPS bằng `dart:io`/`http`/`dio` (chúng dùng danh sách chứng chỉ của Dart → cần Flutter ≥ 3.47.8). Không cần đổi code nếu đã nâng Flutter, nhưng ghi lại danh sách.

## Ràng buộc

- Không commit khóa/tệp bí mật (`google-services.json`, `GoogleService-Info.plist`, file options) nếu repo đang gitignore chúng.
- Không tự upload App Store Connect / TestFlight / gửi App Review; người dùng tự Archive bằng Xcode. Trước khi Archive nhớ chạy `flutter build ios --config-only --no-codesign` (hoặc `flutter pub get`) để file `ios/Flutter/Generated.xcconfig` lấy đúng số phiên bản mới.
- Không deploy production (rules, functions) nếu không cần; thay đổi này chỉ ở client.
- Chia commit gọn: (a) nâng SDK + sửa tương thích, (b) tăng phiên bản. Không đẩy lên remote nếu chưa được yêu cầu.

## Báo cáo cuối

Nêu: phiên bản trước/sau của Flutter và từng gói Firebase; các file đã sửa; kết quả build apk/ios, kết quả `flutter test`; việc cần người thử trên máy thật; và xác nhận app KHÔNG còn nằm trong dải phiên bản bị ảnh hưởng.

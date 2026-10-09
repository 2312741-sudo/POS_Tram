// lib/core/config/chamcong_firebase_config.dart
//
// Cấu hình Firebase app phụ "chamcong" (project chamcongtram) cho tính năng
// "Đăng nhập bằng Chấm Công Trạm".
//
// CÁCH NẠP CẤU HÌNH (không cần build flag):
//   - Dart không hỗ trợ import có điều kiện theo sự tồn tại của file, nên cấu hình
//     KHÔNG nằm trong file .dart mà trong asset JSON (đã gitignore):
//         app_flutter/assets/config/chamcong_firebase_options.json
//     Mẫu cấu trúc (được commit): assets/config/chamcong_firebase_options.example.json
//   - Thư mục assets/config/ được khai báo trong pubspec.yaml. Lúc chạy, loader đọc file
//     thật qua rootBundle; nếu thiếu file, JSON lỗi, thiếu nền tảng hiện tại hoặc còn giá
//     trị mẫu "YOUR_..." thì coi như CHƯA cấu hình → ẩn nút đăng nhập Chấm Công.
//   - App luôn biên dịch được dù không có file thật.
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Tên Firebase app phụ dùng để đăng nhập tài khoản Chấm Công Trạm
const String kChamCongAppName = 'chamcong';

/// Đường dẫn asset chứa cấu hình thật (gitignored)
const String kChamCongConfigAsset = 'assets/config/chamcong_firebase_options.json';

/// Project Firebase của ứng dụng Chấm Công Trạm
const String kChamCongProjectId = 'chamcongtram';

class ChamCongFirebaseConfig {
  final FirebaseOptions options;

  /// OAuth Web Client ID của project chamcongtram — dùng làm serverClientId cho
  /// google_sign_in (Android/iOS) để idToken Google có audience hợp lệ với chamcongtram.
  final String? googleServerClientId;

  const ChamCongFirebaseConfig({required this.options, this.googleServerClientId});

  static ChamCongFirebaseConfig? _cached;
  static bool _loaded = false;

  /// Nạp cấu hình (có cache). Trả về null nếu chưa cấu hình.
  static Future<ChamCongFirebaseConfig?> load() async {
    if (_loaded) return _cached;
    try {
      final raw = await rootBundle.loadString(kChamCongConfigAsset);
      _cached = parse(raw, platformKey: currentPlatformKey());
    } catch (_) {
      _cached = null;
    }
    _loaded = true;
    return _cached;
  }

  /// Chỉ dùng cho kiểm thử
  @visibleForTesting
  static void resetCache() {
    _cached = null;
    _loaded = false;
  }

  /// Khóa nền tảng trong file JSON: web / android / ios / macos / windows / linux
  static String currentPlatformKey() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'web';
    }
  }

  /// Phân tích nội dung JSON cấu hình cho một nền tảng. Trả về null nếu không hợp lệ.
  static ChamCongFirebaseConfig? parse(String raw, {required String platformKey}) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final p = decoded[platformKey];
    if (p is! Map) return null;

    String? str(Map m, String key) {
      final v = m[key]?.toString().trim();
      if (v == null || v.isEmpty) return null;
      return v;
    }

    final apiKey = str(p, 'apiKey');
    final appId = str(p, 'appId');
    final senderId = str(p, 'messagingSenderId');
    final projectId = str(p, 'projectId');
    if (apiKey == null || appId == null || senderId == null || projectId == null) return null;

    // Còn giá trị mẫu → chưa cấu hình
    bool isPlaceholder(String? v) => v != null && v.contains('YOUR_');
    if ([apiKey, appId, senderId, projectId].any(isPlaceholder)) return null;

    final serverClientId = str(decoded, 'googleServerClientId');

    return ChamCongFirebaseConfig(
      options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
        authDomain: str(p, 'authDomain'),
        storageBucket: str(p, 'storageBucket'),
        iosClientId: isPlaceholder(str(p, 'iosClientId')) ? null : str(p, 'iosClientId'),
        iosBundleId: str(p, 'iosBundleId'),
      ),
      googleServerClientId: isPlaceholder(serverClientId) ? null : serverClientId,
    );
  }
}

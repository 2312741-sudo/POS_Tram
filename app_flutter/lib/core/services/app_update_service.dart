import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import '../models/app_update_info.dart';

/// Kết quả kiểm tra phiên bản mới
class AppUpdateCheckResult {
  final bool hasUpdate;
  final bool isMandatory;
  final AppUpdateInfo? info;
  final String currentVersion;
  final int currentBuild;

  const AppUpdateCheckResult({
    required this.hasUpdate,
    required this.isMandatory,
    this.info,
    required this.currentVersion,
    required this.currentBuild,
  });
}

/// Dịch vụ kiểm tra và cập nhật APK tự động cho POS Trạm
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final _db = FirebaseDatabase.instance;
  http.Client? _httpClient;

  /// Đường dẫn cấu hình update trên Realtime Database
  static const String rtdbPath = 'system_config/app_update/android';

  /// Lấy thông tin PackageInfo hiện tại
  Future<PackageInfo> getPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return PackageInfo(
        appName: 'POS Trạm',
        packageName: 'com.example.tramapp',
        version: '1.0.6',
        buildNumber: '7',
      );
    }
  }

  /// Đọc thông tin cập nhật từ Firebase Realtime Database
  Future<AppUpdateInfo?> fetchRemoteUpdateInfo() async {
    try {
      final snap = await _db.ref(rtdbPath).get().timeout(const Duration(seconds: 8));
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        return null;
      }
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      return AppUpdateInfo.fromMap(data);
    } catch (e) {
      debugPrint('[AppUpdateService] Error fetching remote update: $e');
      return null;
    }
  }

  /// Kiểm tra xem có phiên bản cập nhật mới không
  Future<AppUpdateCheckResult> checkForUpdate() async {
    final pkg = await getPackageInfo();
    final currentBuild = int.tryParse(pkg.buildNumber) ?? 0;
    final currentVersion = pkg.version;

    final remote = await fetchRemoteUpdateInfo();
    if (remote == null) {
      return AppUpdateCheckResult(
        hasUpdate: false,
        isMandatory: false,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
      );
    }

    final hasNew = remote.hasNewerVersion(currentBuild);
    final isMandatory = hasNew && remote.isMandatory(currentBuild);

    return AppUpdateCheckResult(
      hasUpdate: hasNew,
      isMandatory: isMandatory,
      info: remote,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }

  /// Tải file APK từ URL với báo cáo tiến trình %
  Future<File> downloadApkFile(
    String url, {
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
    void Function(String status)? onStatusChange,
  }) async {
    if (!kIsWeb && !Platform.isAndroid) {
      throw UnsupportedError('Tự động cập nhật APK chỉ hỗ trợ trên thiết bị Android');
    }

    final uri = Uri.parse(url);
    final client = _httpClient ?? http.Client();
    final request = http.Request('GET', uri);
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Không thể tải file APK (Mã lỗi HTTP ${response.statusCode})');
    }

    final totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;

    // Lấy thư mục lưu file tạm trên Android
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/tram_pos_update.apk';
    final file = File(filePath);

    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    onStatusChange?.call('Đang tải xuống...');
    final sink = file.openWrite();

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        onProgress(progress, receivedBytes, totalBytes);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    onStatusChange?.call('Tải xong, chuẩn bị cài đặt...');
    return file;
  }

  /// Kích hoạt trình cài đặt APK của Android PackageInstaller
  Future<OpenResult> installApk(String filePath) async {
    if (!kIsWeb && !Platform.isAndroid) {
      throw UnsupportedError('Chức năng cài đặt APK chỉ hỗ trợ trên Android');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File APK không tồn tại hoặc đã bị xóa');
    }

    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
    return result;
  }

  @visibleForTesting
  void setHttpClientForTest(http.Client client) {
    _httpClient = client;
  }
}

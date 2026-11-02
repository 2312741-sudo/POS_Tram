/// Model chứa thông tin phiên bản cập nhật ứng dụng (In-app APK update)
class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final int minVersionCode;
  final String apkUrl;
  final String releaseNotes;
  final String? apkSize;
  final bool isForce;
  final int? publishedAt;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.minVersionCode,
    required this.apkUrl,
    required this.releaseNotes,
    this.apkSize,
    this.isForce = false,
    this.publishedAt,
  });

  /// Kiểm tra xem phiên bản từ xa có mới hơn phiên bản hiện tại trên máy không
  bool hasNewerVersion(int currentVersionCode) {
    return versionCode > currentVersionCode && apkUrl.trim().isNotEmpty;
  }

  /// Kiểm tra xem bản cập nhật này có bắt buộc cài đặt không
  bool isMandatory(int currentVersionCode) {
    return isForce || (minVersionCode > 0 && currentVersionCode < minVersionCode);
  }

  factory AppUpdateInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppUpdateInfo(
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      versionName: map['versionName']?.toString() ?? '',
      minVersionCode: (map['minVersionCode'] as num?)?.toInt() ?? 0,
      apkUrl: map['apkUrl']?.toString() ?? '',
      releaseNotes: map['releaseNotes']?.toString() ?? '',
      apkSize: map['apkSize']?.toString(),
      isForce: map['isForce'] == true,
      publishedAt: (map['publishedAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'versionCode': versionCode,
      'versionName': versionName,
      'minVersionCode': minVersionCode,
      'apkUrl': apkUrl,
      'releaseNotes': releaseNotes,
      if (apkSize != null) 'apkSize': apkSize,
      'isForce': isForce,
      if (publishedAt != null) 'publishedAt': publishedAt,
    };
  }
}

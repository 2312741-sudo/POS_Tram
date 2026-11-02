import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/models/app_update_info.dart';

void main() {
  group('AppUpdateInfo Model Tests', () {
    test('Parse fromMap correctly', () {
      final map = {
        'versionCode': 8,
        'versionName': '1.0.7',
        'minVersionCode': 6,
        'apkUrl': 'https://example.com/tram_pos_v1.0.7.apk',
        'releaseNotes': '- Tính năng mới\n- Sửa lỗi',
        'apkSize': '45 MB',
        'isForce': false,
        'publishedAt': 1793500000000,
      };

      final info = AppUpdateInfo.fromMap(map);
      expect(info.versionCode, 8);
      expect(info.versionName, '1.0.7');
      expect(info.minVersionCode, 6);
      expect(info.apkUrl, 'https://example.com/tram_pos_v1.0.7.apk');
      expect(info.releaseNotes, '- Tính năng mới\n- Sửa lỗi');
      expect(info.apkSize, '45 MB');
      expect(info.isForce, false);
      expect(info.publishedAt, 1793500000000);
    });

    test('hasNewerVersion returns true only when remote build > current build and url is valid', () {
      const info = AppUpdateInfo(
        versionCode: 8,
        versionName: '1.0.7',
        minVersionCode: 6,
        apkUrl: 'https://example.com/pos.apk',
        releaseNotes: 'Test',
      );

      expect(info.hasNewerVersion(7), isTrue); // Hiện tại build 7, remote 8 -> có bản mới
      expect(info.hasNewerVersion(8), isFalse); // Bằng nhau -> không có bản mới
      expect(info.hasNewerVersion(9), isFalse); // Lớn hơn -> không có bản mới

      const infoEmptyUrl = AppUpdateInfo(
        versionCode: 8,
        versionName: '1.0.7',
        minVersionCode: 6,
        apkUrl: '',
        releaseNotes: 'Test',
      );
      expect(infoEmptyUrl.hasNewerVersion(7), isFalse); // URL rỗng -> không kích hoạt
    });

    test('isMandatory evaluates correctly with isForce or minVersionCode', () {
      const normalUpdate = AppUpdateInfo(
        versionCode: 8,
        versionName: '1.0.7',
        minVersionCode: 6,
        apkUrl: 'https://example.com/pos.apk',
        releaseNotes: 'Test',
        isForce: false,
      );

      // Build 7 > minVersionCode 6 -> Không bắt buộc
      expect(normalUpdate.isMandatory(7), isFalse);
      // Build 5 < minVersionCode 6 -> Bắt buộc cập nhật
      expect(normalUpdate.isMandatory(5), isTrue);

      const forcedUpdate = AppUpdateInfo(
        versionCode: 8,
        versionName: '1.0.7',
        minVersionCode: 0,
        apkUrl: 'https://example.com/pos.apk',
        releaseNotes: 'Test',
        isForce: true,
      );
      // isForce = true -> Bắt buộc cập nhật bất kể build hiện tại
      expect(forcedUpdate.isMandatory(7), isTrue);
    });

    test('toMap serializes correctly', () {
      const info = AppUpdateInfo(
        versionCode: 8,
        versionName: '1.0.7',
        minVersionCode: 6,
        apkUrl: 'https://example.com/pos.apk',
        releaseNotes: 'Changelog',
        apkSize: '42 MB',
        isForce: true,
        publishedAt: 123456789,
      );

      final map = info.toMap();
      expect(map['versionCode'], 8);
      expect(map['versionName'], '1.0.7');
      expect(map['minVersionCode'], 6);
      expect(map['apkUrl'], 'https://example.com/pos.apk');
      expect(map['releaseNotes'], 'Changelog');
      expect(map['apkSize'], '42 MB');
      expect(map['isForce'], isTrue);
      expect(map['publishedAt'], 123456789);
    });
  });
}

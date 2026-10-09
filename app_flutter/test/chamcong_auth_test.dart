// test/chamcong_auth_test.dart
// Kiểm thử "Đăng nhập bằng Chấm Công Trạm": ánh xạ mã lỗi, phân tích phản hồi callable,
// nạp cấu hình Firebase app phụ và giữ nguyên trường máy chủ trên UserModel.
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/config/chamcong_firebase_config.dart';
import 'package:tram_flutter/core/services/chamcong_auth_service.dart';
import 'package:tram_flutter/data/models/app_models.dart';

void main() {
  group('Ánh xạ mã lỗi Chấm Công', () {
    test('Mã lỗi máy chủ (details.code) → thông điệp tiếng Việt', () {
      final e = mapChamCongFunctionsError(FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'not linked',
        details: {'code': 'NOT_LINKED'},
      ));
      expect(e.code, ChamCongErrorCodes.notLinked);
      expect(e.message,
          'Cửa hàng chấm công của bạn chưa được liên kết với POS. Nhờ chủ quán liên kết trong Cài đặt.');
    });

    test('Mọi mã lỗi hợp đồng đều có thông điệp riêng', () {
      for (final code in [
        ChamCongErrorCodes.invalidToken,
        ChamCongErrorCodes.notLinked,
        ChamCongErrorCodes.notActiveMember,
        ChamCongErrorCodes.posAccountDisabled,
        ChamCongErrorCodes.alreadyLinked,
      ]) {
        final msg = chamCongErrorMessage(code, 'FALLBACK');
        expect(msg, isNot('FALLBACK'), reason: code);
        expect(msg, isNotEmpty);
      }
      expect(chamCongErrorMessage(ChamCongErrorCodes.posAccountDisabled), contains('khóa'));
      expect(chamCongErrorMessage(ChamCongErrorCodes.alreadyLinked), contains('đã được liên kết'));
    });

    test('Mã lạ dùng thông điệp dự phòng của máy chủ', () {
      final e = mapChamCongFunctionsError(FirebaseFunctionsException(
        code: 'internal',
        message: 'Lỗi máy chủ X',
        details: {'code': 'SOMETHING_NEW'},
      ));
      expect(e.code, 'SOMETHING_NEW');
      expect(e.message, 'Lỗi máy chủ X');
    });

    test('Không có details.code: mạng / unauthenticated', () {
      final net = mapChamCongFunctionsError(FirebaseFunctionsException(code: 'unavailable', message: 'x'));
      expect(net.code, ChamCongErrorCodes.network);
      final unauth = mapChamCongFunctionsError(FirebaseFunctionsException(code: 'unauthenticated', message: 'x'));
      expect(unauth.code, ChamCongErrorCodes.invalidToken);
    });

    test('POS_ACCOUNT_CONFLICT / NOT_STORE_OWNER / internal không mã', () {
      final conflict = mapChamCongFunctionsError(FirebaseFunctionsException(
          code: 'permission-denied', message: 'x', details: {'code': 'POS_ACCOUNT_CONFLICT'}));
      expect(conflict.code, ChamCongErrorCodes.posAccountConflict);
      expect(conflict.message, contains('trùng'));
      final owner = mapChamCongFunctionsError(FirebaseFunctionsException(
          code: 'permission-denied', message: 'x', details: {'code': 'NOT_STORE_OWNER'}));
      expect(owner.message, contains('chủ'));
      final iam = mapChamCongFunctionsError(FirebaseFunctionsException(code: 'internal', message: 'INTERNAL'));
      expect(iam.message, 'Máy chủ chưa được cấu hình kết nối Chấm Công, liên hệ chủ quán.');
    });

    test('Phản hồi unlinkChamCongStore', () {
      expect(parseUnlinkResponse({'status': 'UNLINKED', 'wasLinked': true}), isTrue);
      expect(parseUnlinkResponse({'status': 'UNLINKED', 'wasLinked': false}), isFalse);
      expect(() => parseUnlinkResponse({'status': 'NOPE'}), throwsA(isA<ChamCongAuthException>()));
    });

    test('Lỗi Firebase Auth email/password của app chấm công', () {
      expect(chamCongErrorMessage('invalid-credential'), contains('không đúng'));
      expect(chamCongErrorMessage('wrong-password'), contains('không đúng'));
      expect(chamCongErrorMessage('too-many-requests'), contains('quá nhiều'));
    });

    test('Nhận diện thao tác hủy', () {
      expect(isChamCongCancellation(FirebaseAuthException(code: 'popup-closed-by-user')), isTrue);
      expect(isChamCongCancellation(FirebaseAuthException(code: 'web-context-cancelled')), isTrue);
      expect(isChamCongCancellation(const ChamCongAuthException(ChamCongErrorCodes.cancelled, '')), isTrue);
      expect(isChamCongCancellation(FirebaseAuthException(code: 'wrong-password')), isFalse);
      expect(const ChamCongAuthException(ChamCongErrorCodes.notLinked, '').isCancelled, isFalse);
    });
  });

  group('Phân tích phản hồi chamCongSignIn', () {
    test('OK', () {
      final r = ChamCongSignInResponse.fromData({
        'status': 'OK',
        'customToken': 'tok',
        'storeCode': 'TRAM01',
        'uid': 'u1',
        'roleId': 'ROLE_WAITER',
        'isNewAccount': true,
      });
      expect(r.needsStoreChoice, isFalse);
      expect(r.customToken, 'tok');
      expect(r.storeCode, 'TRAM01');
      expect(r.uid, 'u1');
      expect(r.roleId, 'ROLE_WAITER');
      expect(r.isNewAccount, isTrue);
    });

    test('CHOOSE_STORE (bỏ qua mục thiếu storeCode, tên rỗng → dùng mã)', () {
      final r = ChamCongSignInResponse.fromData({
        'status': 'CHOOSE_STORE',
        'stores': [
          {'storeCode': 'TRAM01', 'storeName': 'Trạm Q1'},
          {'storeCode': 'TRAM02', 'storeName': ''},
          {'storeName': 'thiếu mã'},
          'rác',
        ],
      });
      expect(r.needsStoreChoice, isTrue);
      expect(r.stores.map((s) => s.storeCode), ['TRAM01', 'TRAM02']);
      expect(r.stores[0].storeName, 'Trạm Q1');
      expect(r.stores[1].storeName, 'TRAM02');
    });

    test('Dữ liệu không hợp lệ → BAD_RESPONSE', () {
      Matcher bad() => throwsA(isA<ChamCongAuthException>()
          .having((e) => e.code, 'code', ChamCongErrorCodes.badResponse));
      expect(() => ChamCongSignInResponse.fromData(null), bad());
      expect(() => ChamCongSignInResponse.fromData({'status': 'OK', 'storeCode': 'X'}), bad());
      expect(() => ChamCongSignInResponse.fromData({'status': 'CHOOSE_STORE', 'stores': []}), bad());
      expect(() => ChamCongSignInResponse.fromData({'status': 'WHAT'}), bad());
    });
  });

  group('Phân tích phản hồi liên kết', () {
    test('LINKED', () {
      final r = ChamCongLinkResponse.fromData(
          {'status': 'LINKED', 'chamCongStoreId': 'cc1', 'chamCongStoreName': 'Trạm Chấm Công'});
      expect(r.linked, isTrue);
      expect(r.needsChoice, isFalse);
      expect(r.chamCongStoreName, 'Trạm Chấm Công');
    });

    test('CHOOSE_CHAMCONG_STORE', () {
      final r = ChamCongLinkResponse.fromData({
        'status': 'CHOOSE_CHAMCONG_STORE',
        'stores': [
          {'chamCongStoreId': 'a', 'name': 'Quán A', 'code': 'QA'},
          {'chamCongStoreId': 'b', 'name': 'Quán B'},
        ],
      });
      expect(r.needsChoice, isTrue);
      expect(r.choices.length, 2);
      expect(r.choices.first.code, 'QA');
      expect(r.choices.last.code, '');
    });

    test('getChamCongLinkStatus: đã/chưa liên kết', () {
      final linked = ChamCongLinkStatus.fromData({
        'linked': true,
        'chamCongStoreId': 'cc1',
        'chamCongStoreName': 'Trạm',
        'linkedAt': 1700000000000,
        'provisionedCount': 4,
      });
      expect(linked.linked, isTrue);
      expect(linked.linkedAt, 1700000000000);
      expect(linked.provisionedCount, 4);

      final nullAt = ChamCongLinkStatus.fromData({'linked': true, 'chamCongStoreId': 'cc1', 'linkedAt': null});
      expect(nullAt.linked, isTrue);
      expect(nullAt.linkedAt, isNull);
      expect(nullAt.provisionedCount, 0);

      final none = ChamCongLinkStatus.fromData({'linked': false, 'provisionedCount': 0});
      expect(none.linked, isFalse);
      expect(none.chamCongStoreId, isNull);
      expect(none.linkedAt, isNull);
    });
  });

  group('Cấu hình Firebase Chấm Công', () {
    final validJson = jsonEncode({
      'googleServerClientId': 'web-client.apps.googleusercontent.com',
      'android': {
        'apiKey': 'AIzaTest',
        'appId': '1:1:android:abc',
        'messagingSenderId': '1',
        'projectId': 'chamcongtram',
      },
      'ios': {
        'apiKey': 'AIzaTest',
        'appId': '1:1:ios:abc',
        'messagingSenderId': '1',
        'projectId': 'chamcongtram',
        'iosClientId': 'ios-client',
      },
    });

    test('Hợp lệ cho nền tảng có khai báo', () {
      final cfg = ChamCongFirebaseConfig.parse(validJson, platformKey: 'ios');
      expect(cfg, isNotNull);
      expect(cfg!.options.projectId, 'chamcongtram');
      expect(cfg.options.iosClientId, 'ios-client');
      expect(cfg.googleServerClientId, 'web-client.apps.googleusercontent.com');
    });

    test('Thiếu nền tảng / JSON lỗi → chưa cấu hình', () {
      expect(ChamCongFirebaseConfig.parse(validJson, platformKey: 'web'), isNull);
      expect(ChamCongFirebaseConfig.parse('{not json', platformKey: 'android'), isNull);
    });

    test('File mẫu (giá trị YOUR_...) → chưa cấu hình', () {
      final example = jsonEncode({
        'android': {
          'apiKey': 'YOUR_ANDROID_API_KEY',
          'appId': '1:000000000000:android:YOUR_POS_ANDROID_APP_ID',
          'messagingSenderId': '000000000000',
          'projectId': 'chamcongtram',
        },
      });
      expect(ChamCongFirebaseConfig.parse(example, platformKey: 'android'), isNull);
    });
  });

  group('UserModel tài khoản Chấm Công', () {
    test('authProvider + giữ nguyên trường do máy chủ ghi khi lưu lại', () {
      final u = UserModel.fromMap({
        'uid': 'u1',
        'username': 'cc_nguyenvana',
        'fullName': 'Nguyễn Văn A',
        'roleId': 'ROLE_WAITER',
        'authProvider': 'chamcong',
        'chamCongUid': 'abc',
        'password': 'không-được-ghi',
      });
      expect(u.isChamCongAccount, isTrue);
      final promoted = u.copyWith(roleId: 'ROLE_MANAGER').toMap();
      expect(promoted['roleId'], 'ROLE_MANAGER');
      expect(promoted['authProvider'], 'chamcong');
      expect(promoted['chamCongUid'], 'abc');
      expect(promoted.containsKey('password'), isFalse);
    });

    test('Hồ sơ tự cấp có trường máy chủ (deactivatedBy, chamCongRevokedAt)', () {
      final u = UserModel.fromMap({
        'uid': 'u2',
        'username': 'cc_b',
        'fullName': 'B',
        'roleId': 'ROLE_WAITER',
        'authProvider': 'chamcong',
        'customPermissions': [],
        'isActive': false,
        'deactivatedBy': 'chamcong',
        'chamCongRevokedAt': 1700000000000,
      });
      expect(u.isRevokedByChamCong, isTrue);
      expect(u.customPermissions, isEmpty);
      expect(u.toMap()['chamCongRevokedAt'], 1700000000000);
    });

    test('StoreInfoModel đọc trường chamCong* nhưng không ghi lại', () {
      final info = StoreInfoModel.fromMap(
          {'storeName': 'Trạm', 'chamCongStoreId': 'cc1', 'chamCongStoreName': 'Trạm CC'}, 'TRAM01');
      expect(info.isChamCongLinked, isTrue);
      expect(info.copyWith(storeName: 'Mới').chamCongStoreName, 'Trạm CC');
      expect(info.toMap().containsKey('chamCongStoreId'), isFalse);
    });

    test('Tài khoản thường không có authProvider', () {
      final u = UserModel(username: 'thungan1', fullName: 'TN', roleId: 'ROLE_CASHIER');
      expect(u.isChamCongAccount, isFalse);
      expect(u.toMap().containsKey('authProvider'), isFalse);
    });
  });
}

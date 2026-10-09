import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/services/manager_pin_service.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/store_info_model.dart';

void main() {
  group('ManagerPinLogic.validatePinFormat', () {
    test('chấp nhận 4–8 chữ số', () {
      expect(ManagerPinLogic.validatePinFormat('1357'), isNull);
      expect(ManagerPinLogic.validatePinFormat('13572468'), isNull);
    });
    test('từ chối sai định dạng / lặp một chữ số', () {
      expect(ManagerPinLogic.validatePinFormat('123'), isNotNull);
      expect(ManagerPinLogic.validatePinFormat('123456789'), isNotNull);
      expect(ManagerPinLogic.validatePinFormat('12a4'), isNotNull);
      expect(ManagerPinLogic.validatePinFormat('0000'), contains('lặp'));
      expect(ManagerPinLogic.validatePinFormat('9999'), contains('lặp'));
    });
  });

  group('ManagerPinLogic.mapError', () {
    test('khóa tạm: hiển thị số phút còn lại', () {
      final e = ManagerPinLogic.mapError('resource-exhausted', 'x', {'reason': 'LOCKED_OUT', 'remainingSeconds': 601});
      expect(e.isLockedOut, isTrue);
      expect(e.lockoutSeconds, 601);
      expect(e.message, contains('11 phút'));
    });
    test('khóa tạm không kèm số giây → mặc định 15 phút', () {
      final e = ManagerPinLogic.mapError('functions/resource-exhausted', null, null);
      expect(e.isLockedOut, isTrue);
      expect(e.message, contains('15 phút'));
    });
    test('sai PIN / người duyệt không có quyền', () {
      final e = ManagerPinLogic.mapError('permission-denied', null, null);
      expect(e.message, contains('PIN không đúng'));
      expect(e.message, contains('không có quyền'));
    });
    test('đặt PIN khi không phải quản lý', () {
      final e = ManagerPinLogic.mapError('permission-denied', null, null, settingPin: true);
      expect(e.message, contains('Chủ quán hoặc Quản lý'));
    });
    test('nhiều người trùng PIN → yêu cầu chọn người duyệt', () {
      final e = ManagerPinLogic.mapError('failed-precondition', 'msg', {'reason': 'AMBIGUOUS'});
      expect(e.needsApproverSelection, isTrue);
      expect(e.message, contains('chọn người duyệt'));
    });
    test('lỗi mạng', () {
      expect(ManagerPinLogic.mapError('unavailable', null, null).message, contains('Không kết nối được máy chủ'));
      expect(ManagerPinLogic.mapError('functions/deadline-exceeded', null, null).message, contains('Không kết nối'));
    });
    test('hết phiên đăng nhập', () {
      expect(ManagerPinLogic.mapError('unauthenticated', 'raw', null).message, contains('đăng nhập lại'));
    });
  });

  group('ManagerApproval.tryParse', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final raw = {
      'approvalId': 'LOG_1',
      'approverUid': 'mgr',
      'approverName': 'QL Lan',
      'approverUsername': 'lan',
      'action': 'DISCOUNT_ITEM',
      'approvedAt': now,
      'expiresAt': now + 300000,
    };
    test('hợp lệ', () {
      final a = ManagerApproval.tryParse(raw)!;
      expect(a.approverUid, 'mgr');
      expect(a.approverName, 'QL Lan');
      expect(a.isValidFor(ManagerApprovalAction.discountItem), isTrue);
      expect(a.isValidFor(ManagerApprovalAction.cancelKitchenItem), isFalse);
      expect(a.isValidFor(ManagerApprovalAction.discountItem, now: now + 300001), isFalse);
      expect(ManagerPinLogic.approvalSuffix(a), ' — QL Lan duyệt bằng PIN');
    });
    test('sai hình dạng → null', () {
      expect(ManagerApproval.tryParse(null), isNull);
      expect(ManagerApproval.tryParse({...raw, 'approverUid': ''}), isNull);
      expect(ManagerApproval.tryParse({...raw, 'action': 'VOID_BILL'}), isNull);
      expect(ManagerApproval.tryParse({...raw, 'expiresAt': 'x'}), isNull);
    });
  });

  group('Metadata người duyệt trên dòng giảm giá', () {
    OrderItemModel base() => OrderItemModel(productId: 1, name: 'Cà phê', price: 20000, quantity: 2);

    test('lưu và đọc lại người duyệt', () {
      final d = base().withLineDiscount(
        percent: 10,
        discountedQuantity: 2,
        reason: 'Khách quen',
        approvedBy: 'mgr',
        approvedByName: 'QL Lan',
        approvalId: 'LOG_1',
        approvedAt: 123,
      );
      final map = d.toMap();
      expect(map['discountApprovedBy'], 'mgr');
      expect(map['discountApprovedByName'], 'QL Lan');
      expect(map['discountApprovalId'], 'LOG_1');
      expect(map['discountApprovedAt'], 123);
      final back = OrderItemModel.fromMap(map);
      expect(back.discountApprovedBy, 'mgr');
      expect(back.copyWith(note: 'ít đá').discountApprovedByName, 'QL Lan');
    });

    test('bỏ giảm giá hoặc giảm lại không qua duyệt → xóa người duyệt', () {
      final d = base().withLineDiscount(percent: 10, discountedQuantity: 2, approvedBy: 'mgr', approvalId: 'L', approvedAt: 1);
      expect(d.withoutLineDiscount().toMap().containsKey('discountApprovedBy'), isFalse);
      expect(d.withoutLineDiscount().discountApprovedBy, '');
      final self = d.withLineDiscount(percent: 5, discountedQuantity: 1);
      expect(self.discountApprovedBy, '');
      expect(self.discountApprovedAt, isNull);
    });
  });

  test('StoreInfoModel không còn ghi managerPin', () {
    final info = StoreInfoModel.fromMap({'storeName': 'Trạm', 'managerPin': '1234'}, 'TRAM01');
    expect(info.toMap().containsKey('managerPin'), isFalse);
  });
}

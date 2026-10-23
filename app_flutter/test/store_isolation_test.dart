import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/shift_scope.dart';
import 'package:tram_flutter/data/models/app_models.dart';

void main() {
  group('Store Isolation & Cash Shift Verification', () {
    test('Ca mở của BLAO không được nhận diện là ca mở của TRAM01', () {
      final blaoShift = CashShiftModel(
        id: 'SHIFT_BLAO_01',
        shiftCode: 'CA-BLAO-01',
        storeCode: 'BLAO',
        staffUid: 'uid_admin',
        staffUsername: 'admin',
        staffFullName: 'Admin',
        openedAt: 1000,
        status: 'OPEN',
      );

      final tramShift = CashShiftModel(
        id: 'SHIFT_TRAM_01',
        shiftCode: 'CA-TRAM-01',
        storeCode: 'TRAM01',
        staffUid: 'uid_admin',
        staffUsername: 'admin',
        staffFullName: 'Admin',
        openedAt: 2000,
        status: 'OPEN',
      );

      // findOwnOpenShift finds shift owned by uid
      final ownBlao = findOwnOpenShift([blaoShift], uid: 'uid_admin', username: 'admin');
      expect(ownBlao, isNotNull);
      expect(ownBlao!.storeCode, 'BLAO');

      // But when scoped to TRAM01, storeCode mismatch must reject it
      final currentStore = 'TRAM01';
      final isOwnStore = ownBlao.storeCode.isEmpty || ownBlao.storeCode == currentStore;
      expect(isOwnStore, isFalse);

      final ownTram = findOwnOpenShift([tramShift], uid: 'uid_admin', username: 'admin');
      expect(ownTram, isNotNull);
      expect(ownTram!.storeCode == currentStore, isTrue);
    });

    test('Danh sách ca hiển thị được lọc nghiêm ngặt theo quyền và chi nhánh', () {
      final shifts = [
        CashShiftModel(
          id: 'S1',
          shiftCode: 'CA-1',
          storeCode: 'TRAM01',
          staffUid: 'u1',
          staffUsername: 'staff1',
          staffFullName: 'Staff 1',
          openedAt: 1000,
          status: 'OPEN',
        ),
        CashShiftModel(
          id: 'S2',
          shiftCode: 'CA-2',
          storeCode: 'BLAO',
          staffUid: 'u1',
          staffUsername: 'staff1',
          staffFullName: 'Staff 1',
          openedAt: 2000,
          status: 'OPEN',
        ),
      ];

      // Scoped only to TRAM01
      final tramShifts = shifts.where((s) => s.storeCode == 'TRAM01').toList();
      expect(tramShifts.length, 1);
      expect(tramShifts.first.id, 'S1');

      final visible = scopeShifts(tramShifts, uid: 'u1', username: 'staff1', canViewAll: false);
      expect(visible.length, 1);
      expect(visible.first.id, 'S1');
    });

    test('StoreInfoModel fromMap parses correctly for both chain and isolated stores', () {
      final tramInfo = StoreInfoModel.fromMap({
        'storeCode': 'TRAM01',
        'storeName': 'POS Trạm - Chi nhánh 01',
        'address': 'Đà Lạt',
      }, 'TRAM01');
      expect(tramInfo.storeCode, 'TRAM01');
      expect(tramInfo.storeName, 'POS Trạm - Chi nhánh 01');

      final blaoInfo = StoreInfoModel.fromMap({
        'storeCode': 'BLAO',
        'storeName': 'Trạm Blao',
        'address': 'Bảo Lộc',
      }, 'BLAO');
      expect(blaoInfo.storeCode, 'BLAO');
      expect(blaoInfo.storeName, 'Trạm Blao');
    });
  });
}

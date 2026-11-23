import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/shift_scope.dart';
import 'package:tram_flutter/data/models/bill_model.dart';
import 'package:tram_flutter/data/models/shift_model.dart';

// Khớp web/test/cash-shift-cancel.test.ts
void main() {
  CashShiftModel shift(String id, Map<String, dynamic> m) => CashShiftModel.fromMap({'storeCode': 'T1', 'staffFullName': '', ...m}, id);
  BillModel bill(Map<String, dynamic> m) => BillModel.fromMap({
        'billCode': 'HD-1', 'status': 'PAID', 'tableName': 'B1', 'zone': '', 'items': const [], 'subTotal': 0,
        'staffFullName': '', 'createdAt': 1, ...m,
      }, 'B1');

  final shifts = [
    shift('S_NV', {'shiftCode': 'CA-NV', 'staffUid': 'nv', 'staffUsername': 'nv1', 'status': 'OPEN', 'openedAt': 1000, 'totalCashSales': 50000}),
    shift('S_QL', {'shiftCode': 'CA-QL', 'staffUid': 'ql', 'staffUsername': 'ql1', 'status': 'OPEN', 'openedAt': 1500}),
    shift('S_OLD', {'shiftCode': 'CA-OLD', 'staffUid': 'nv', 'staffUsername': 'nv1', 'status': 'CLOSED', 'openedAt': 100, 'closedAt': 900}),
  ];

  group('Hủy hóa đơn → trừ ở ca đã thu tiền', () {
    test('Quản lý hủy đơn TM 30k của nhân viên → trừ ở ca nhân viên (50k → 20k)', () {
      final b = bill({'shiftId': 'S_NV', 'paymentMethod': 'CASH', 'finalAmount': 30000, 'staffUid': 'nv', 'staffUsername': 'nv1'});
      final target = findBillShift(b, shifts)!;
      expect(target.id, 'S_NV');
      final p = billShiftPortions(b);
      expect(target.totalCashSales - p.cash, 20000);
    });

    test('đơn hỗn hợp tách đúng từng phần', () {
      final b = bill({
        'paymentMethod': 'SPLIT', 'finalAmount': 30000, 'staffUsername': 'nv1',
        'paymentSplits': [{'method': 'CASH', 'amount': 10000}, {'method': 'TRANSFER_QR', 'amount': 20000}],
      });
      expect(billShiftPortions(b), (cash: 10000, qr: 20000, card: 0));
      expect(billShiftPortions(bill({'paymentMethod': 'TRANSFER_QR', 'finalAmount': 30000, 'staffUsername': 'nv1'})), (cash: 0, qr: 30000, card: 0));
      expect(billShiftPortions(bill({'paymentMethod': 'SPLIT', 'finalAmount': 30000, 'staffUsername': 'nv1'})), (cash: 0, qr: 0, card: 0));
    });

    test('hóa đơn không ghi ca: ca của người thu tiền bao trùm giờ thanh toán', () {
      expect(findBillShift(bill({'staffUid': 'nv', 'staffUsername': 'nv1', 'closedAt': 2000}), shifts)?.id, 'S_NV');
      expect(findBillShift(bill({'staffUsername': 'NV1', 'closedAt': 500}), shifts)?.id, 'S_OLD');
      expect(findBillShift(bill({'staffUid': 'nv', 'staffUsername': 'nv1', 'closedAt': 950}), shifts), isNull);
    });
  });
}

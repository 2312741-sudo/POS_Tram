import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/table_model.dart';

void main() {
  test('dọn bàn để lại dấu closedBillId; lưu / đọc lại giữ dấu', () {
    final t = TableModel(name: 'Bàn 1', zone: 'Trong', inUse: true, currentBillId: 'HD-261102-0001', currentOrderJson: '[]');
    t.clearTable();
    expect(t.currentBillId, isNull);
    expect(t.closedBillId, 'HD-261102-0001');
    final back = TableModel.fromMap(t.toMap(), 'Trong_Bàn 1');
    expect(back.closedBillId, 'HD-261102-0001');
    expect(back.toMap().containsKey('currentBillId'), isFalse);
  });
  test('bàn trống chưa có mã thì không ghi đè dấu cũ', () {
    final t = TableModel(name: 'Bàn 1', zone: 'Trong', closedBillId: 'HD-1');
    t.clearTable();
    expect(t.closedBillId, 'HD-1');
  });
}

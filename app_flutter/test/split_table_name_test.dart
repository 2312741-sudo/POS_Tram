import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/bill_model.dart';

/// Bàn tự tách khi 2 máy cùng thao tác 1 bàn ('Bàn 01 (2)') → báo cáo ghi nhận vào bàn gốc.
void main() {
  test('baseTableName', () {
    expect(BillModel.baseTableName('Bàn 01 (2)'), 'Bàn 01');
    expect(BillModel.baseTableName('Mang về (3) '), 'Mang về');
    expect(BillModel.baseTableName('Bàn 01'), 'Bàn 01');
    expect(BillModel.baseTableName('Bàn 01 (Tách)'), 'Bàn 01');
    expect(BillModel.baseTableName('MANG VỀ 01 (Tách) (2)'), 'MANG VỀ 01');
  });

  test('hóa đơn của bàn tự tách đọc ra tên bàn gốc', () {
    final b = BillModel.fromMap({'billCode': 'HD-1', 'status': 'PAID', 'tableName': 'Bàn 05 (2)', 'zone': 'Trong', 'finalAmount': 1}, 'B1');
    expect(b.tableName, 'Bàn 05');
  });
}

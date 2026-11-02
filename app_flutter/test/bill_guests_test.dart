import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_integrity.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/bill_model.dart';

/// Số khách trên báo cáo = tổng số khách thật trên hóa đơn (trước đây màn Cuối ngày = số hóa đơn).
void main() {
  BillModel bill(String id, Object? guests) => BillModel.fromMap({
        'billCode': id, 'status': 'PAID', 'tableName': 'Bàn 1', 'finalAmount': 100000, 'subTotal': 100000,
        if (guests != null) 'guestCount': guests,
      }, id);

  test('đọc số khách trên hóa đơn; hóa đơn cũ không có → 1', () {
    expect(bill('A', 4).guests, 4);
    expect(bill('B', '2').guests, 2);
    expect(bill('C', null).guests, 1);
    final bills = [bill('A', 4), bill('B', 2), bill('C', null)];
    expect(bills.fold<int>(0, (s, b) => s + ReportCalculator.getGuestCount(b)), 7);
  });

  test('ghi lại hóa đơn (hủy / hoàn tiền) giữ số khách', () {
    final rec = BillRecordBuilder.build(bill('A', 4), storeCode: 'TRAM01', storeName: 'Trạm');
    expect(rec['guestCount'], 4);
  });
}

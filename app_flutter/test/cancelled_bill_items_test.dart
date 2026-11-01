import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/reports/bill_report_rows.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/app_models.dart';

/// Hủy đơn chưa thanh toán = hủy từng món còn trong đơn (khớp web: billCancelledItems).
void main() {
  Map<String, dynamic> bill(String id, String status) => {
        'billCode': 'HD-$id', 'status': status, 'tableName': 'Bàn 2', 'cancelReason': 'Khách về', 'cancelledAt': 1000,
        'closedAt': 1000, 'staffUsername': 'tn1', 'staffFullName': 'Thu Ngân A', 'subTotal': 130000, 'finalAmount': 0,
        'items': [
          {'productId': 1, 'name': 'Trà đào', 'price': 30000, 'quantity': 3, 'isSentKitchen': true},
          {'productId': 2, 'name': 'Bánh mì', 'price': 20000, 'quantity': 2},
        ],
        'deletedItems': [
          {'name': 'Cà phê', 'productId': 3, 'quantity': 1, 'unitPrice': 25000, 'amount': 25000, 'reason': 'Nhập sai', 'timestamp': 900},
        ],
      };

  test('đơn 5 món bị hủy → 5 món hủy, lý do + người hủy + giờ hủy', () {
    final b = BillModel.fromMap(bill('1', 'CANCELLED'), 'B1');
    final cancelled = b.removedItems.skip(1).toList();
    expect(cancelled.map((e) => [e.name, e.quantity, e.amount, e.reason, e.staffFullName, e.timestamp, e.sentToKitchen]), [
      ['Trà đào', 3, 90000, 'Hủy đơn: Khách về', 'Thu Ngân A', 1000, true],
      ['Bánh mì', 2, 40000, 'Hủy đơn: Khách về', 'Thu Ngân A', 1000, false],
    ]);
    expect(b.removedItemsCount, 1 + 5);
    expect(b.deletedItemsCount, 1); // trường ghi lên hóa đơn giữ nguyên
    expect(ReportCalculator.cancelledBillValue(b), 130000); // giá trị đơn hủy không bị cộng đôi
    expect(BillReportRows.deletedRows(b), hasLength(3));
  });

  test('báo cáo kỳ: cộng món xóa trước khi hủy; đơn đã thanh toán không tính thêm món', () {
    final s = ReportCalculator.calculateDeletedItems([
      BillModel.fromMap(bill('1', 'CANCELLED'), 'B1'),
      BillModel.fromMap(bill('2', 'PAID'), 'B2'),
    ]);
    expect(s.count, 1 + 5 + 1);
    expect(s.amount, 25000 + 130000 + 25000);
  });
}

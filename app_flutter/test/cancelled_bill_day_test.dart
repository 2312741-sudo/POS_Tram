import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/core/reports/report_date_utils.dart';
import 'package:tram_flutter/data/models/bill_model.dart';

int local(int m, int d, int h, int mi) => DateTime.utc(2026, m, d, h - 7, mi).millisecondsSinceEpoch;

BillModel bill(String id, {required int createdAt, int? closedAt, int? cancelledAt, int subTotal = 0, String status = 'CANCELLED'}) =>
    BillModel(
      id: id, billCode: id, tableName: 'Bàn 1', zone: 'A', createdAt: createdAt, closedAt: closedAt,
      cancelledAt: cancelledAt, status: status, staffUsername: 'u', staffFullName: 'U', items: const [],
      subTotal: subTotal, finalAmount: 0,
    );

void main() {
  test('đơn hủy thuộc ngày hủy (3 hóa đơn thật 12/10/2026)', () {
    final bills = [
      bill('HD-261011-180352-UBZF', createdAt: local(10, 11, 18, 3), closedAt: local(10, 12, 1, 4)),
      bill('HD-261009-015221', createdAt: local(10, 9, 1, 52), closedAt: local(10, 12, 1, 5)),
      bill('HD-261012-0003', createdAt: local(10, 9, 14, 24), closedAt: local(10, 12, 1, 4), cancelledAt: local(10, 12, 1, 5), subTotal: 90000),
    ];
    for (final b in bills) {
      expect(ReportDateUtils.formatYmd(ReportDateUtils.billDateTime(b)), '2026-10-12');
    }
    final r = ReportCalculator.calculateCancellationReport(bills);
    expect(r.cancelledBillsCount, 3);
    expect(r.totalLossValue, 90000);
  });

  test('thứ tự ưu tiên và PAID/OPEN giữ nguyên', () {
    expect(bill('a', createdAt: 5, closedAt: 9).reportTimeMs, 9);
    expect(bill('a', createdAt: 5).reportTimeMs, 5);
    expect(bill('p', createdAt: 1, closedAt: 2, status: 'PAID').reportTimeMs, 2);
    expect(bill('o', createdAt: 1, closedAt: 2, status: 'OPEN').reportTimeMs, 1);
  });

  test('dedupe: bản hủy thắng bản OPEN cùng id', () {
    final open = bill('D', createdAt: 100, status: 'OPEN');
    final canc = bill('D', createdAt: 100, cancelledAt: 500);
    expect(ReportCalculator.deduplicateBills([canc, open]).single.status, 'CANCELLED');
    expect(ReportCalculator.deduplicateBills([open, canc]).single.status, 'CANCELLED');
  });
}

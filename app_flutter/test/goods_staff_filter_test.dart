import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/reports/promo_attribution.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/bill_model.dart';

// Khớp web/test/goods-staff-filter.test.ts
void main() {
  BillModel bill() => BillModel.fromMap({
        'billCode': 'HD-1', 'status': 'PAID', 'tableName': 'B1', 'zone': '', 'createdAt': 1,
        'staffUsername': 'an', 'staffFullName': 'An', 'paymentMethod': 'CASH',
        'items': [
          {'productId': 1, 'name': 'Trà tắc', 'price': 25000, 'quantity': 2, 'orderedBy': 'binh', 'orderedByName': 'Bình'},
          {'productId': 2, 'name': 'Bánh', 'price': 20000, 'quantity': 1, 'orderedBy': 'chi', 'orderedByName': 'Chi'},
        ],
        'subTotal': 70000, 'totalDiscount': 10000, 'finalAmount': 60000,
        'discounts': [
          {
            'campaignId': 'C', 'campaignType': 'BUY_X_GET_Y', 'description': 'Combo', 'amount': 10000, 'comboCount': 1,
            'staffShares': [{'u': 'binh', 'n': 'Bình', 'amount': 10000, 'combo': 1}],
          }
        ],
      }, 'B1');

  List<BillModel> forStaff(String s) => PromoAttribution.goodsBillsForStaff([bill()], PromoAttribution.matcher(s));

  test('lọc nhân viên: chỉ món người đó bấm, tiền hóa đơn tính lại; cộng mọi người = tổng quán', () {
    final binh = ReportCalculator.calculateProductReport(forStaff('binh'));
    final chi = ReportCalculator.calculateProductReport(forStaff('chi'));
    expect(binh.map((p) => [p.productName, p.quantity, p.grossRevenue]).toList(), [
      ['Trà tắc', 2, 50000]
    ]);
    expect(chi.map((p) => [p.productName, p.quantity]).toList(), [
      ['Bánh', 1]
    ]);
    expect(forStaff('an'), isEmpty);

    final ob = ReportCalculator.calculateOverviewReport(forStaff('binh'));
    final oc = ReportCalculator.calculateOverviewReport(forStaff('chi'));
    final all = ReportCalculator.calculateOverviewReport([bill()]);
    expect([ob.grossRevenue, ob.totalDiscount, ob.netRevenue], [50000, 10000, 40000]);
    expect([oc.grossRevenue, oc.totalDiscount, oc.netRevenue], [20000, 0, 20000]);
    expect(ob.netRevenue + oc.netRevenue, all.netRevenue);
    final cats = ReportCalculator.calculateCategoryReport(forStaff('chi'));
    expect(cats.fold<int>(0, (s, c) => s + c.quantity), 1);
  });
}

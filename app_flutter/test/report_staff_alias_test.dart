import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/bill_model.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';

BillModel _bill(String id, String user, String full, {String orderUser = '', String orderName = ''}) {
  return BillModel(
    id: id,
    billCode: id,
    tableName: 'Bàn 1',
    zone: 'Khu A',
    shiftId: 'S1',
    staffUsername: user,
    staffFullName: full,
    items: [
      OrderItemModel(productId: 1, name: 'Trà', price: 10000, quantity: 1, orderedBy: orderUser, orderedByName: orderName),
    ],
    status: 'PAID',
    createdAt: 1000,
    closedAt: 1000,
    subTotal: 10000,
    finalAmount: 10000,
  );
}

void main() {
  group('filterHubBills staffAliases', () {
    final bills = [
      _bill('A', 'khoatran', 'Trần Hữu Đăng Khoa'),
      _bill('B', 'anthi', 'Thi An', orderUser: 'khoatran', orderName: 'Trần Hữu Đăng Khoa'),
      _bill('C', 'anthi', 'Thi An'),
    ];

    test('chọn theo họ tên, alias username vẫn khớp hóa đơn', () {
      final r = ReportCalculator.filterHubBills(bills,
          staff: 'Trần Hữu Đăng Khoa', staffAliases: {'khoatran'}, cashierOnly: true);
      expect(r.map((b) => b.id), ['A']);
    });

    test('alias không phân biệt hoa thường với username thu ngân', () {
      final r = ReportCalculator.filterHubBills([_bill('X', 'KhoaTran', '')],
          staff: 'Trần Hữu Đăng Khoa', staffAliases: {'khoatran'}, cashierOnly: true);
      expect(r.length, 1);
    });

    test('không chỉ thu ngân: tính cả người order món', () {
      final r = ReportCalculator.filterHubBills(bills,
          staff: 'Trần Hữu Đăng Khoa', staffAliases: {'khoatran'});
      expect(r.map((b) => b.id), ['A', 'B']);
    });

    test('staff = ALL bỏ qua alias', () {
      final r = ReportCalculator.filterHubBills(bills, staffAliases: {'khoatran'});
      expect(r.length, 3);
    });

    test('alias rỗng/khoảng trắng bị bỏ qua, không khớp nhầm', () {
      final r = ReportCalculator.filterHubBills(bills,
          staff: 'Trần Hữu Đăng Khoa', staffAliases: {'  ', ''}, cashierOnly: true);
      expect(r.map((b) => b.id), ['A']);
    });
  });
}

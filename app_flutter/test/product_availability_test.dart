import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/menu_copy.dart';
import 'package:tram_flutter/core/domain/product_availability.dart';
import 'package:tram_flutter/data/models/product_model.dart';

ProductModel prod(String name, {String cat = 'Trà', bool avail = true, int? until, int? at, String? by, String code = ''}) =>
    ProductModel(name: name, price: 1000, unit: 'ly', category: cat, isAvailable: avail, soldOutUntil: until, soldOutAt: at, soldOutBy: by, code: code);

void main() {
  final now = DateTime(2026, 10, 12, 14, 0);
  final nowMs = now.millisecondsSinceEpoch;

  group('isProductAvailable', () {
    test('thiếu trường hoặc isAvailable true => còn bán', () {
      expect(isProductAvailable(ProductModel.fromMap({'name': 'A', 'price': 1}), now), isTrue);
      expect(isProductAvailable(prod('A'), now), isTrue);
      expect(isProductAvailable(prod('A', until: nowMs + 1000), now), isTrue);
    });
    test('dữ liệu cũ isAvailable=false không có soldOutUntil => hết vô thời hạn', () {
      expect(isProductAvailable(prod('A', avail: false), now), isFalse);
      expect(isProductAvailable(ProductModel.fromMap({'name': 'A', 'isAvailable': false}), now), isFalse);
    });
    test('trước / sau soldOutUntil', () {
      expect(isProductAvailable(prod('A', avail: false, until: nowMs + 1), now), isFalse);
      expect(isProductAvailable(prod('A', avail: false, until: nowMs), now), isTrue);
      expect(isProductAvailable(prod('A', avail: false, until: nowMs - 1), now), isTrue);
      expect(isSoldOutStale(prod('A', avail: false, until: nowMs - 1), now), isTrue);
      expect(isSoldOutStale(prod('A', avail: false), now), isFalse);
    });
    test('fromMap đọc các trường báo hết và khóa nút', () {
      final p = ProductModel.fromMap({'name': 'A', 'isAvailable': false, 'soldOutAt': 5, 'soldOutBy': 'bep', 'soldOutUntil': 9}, '-Nabc');
      expect(p.soldOutAt, 5);
      expect(p.soldOutBy, 'bep');
      expect(p.soldOutUntil, 9);
      expect(p.dbKey, '-Nabc');
      expect(p.toMap()['soldOutBy'], 'bep');
      expect(p.toMap().containsKey('dbKey'), isFalse);
    });
  });

  group('nextSoldOutReset / soldOutPatch', () {
    test('05:00 sáng kế tiếp', () {
      expect(nextSoldOutReset(DateTime(2026, 10, 12, 14)), DateTime(2026, 10, 13, 5));
      expect(nextSoldOutReset(DateTime(2026, 10, 12, 2)), DateTime(2026, 10, 12, 5));
      expect(nextSoldOutReset(DateTime(2026, 10, 12, 5)), DateTime(2026, 10, 13, 5));
      expect(nextSoldOutReset(DateTime(2026, 10, 31, 23)), DateTime(2026, 11, 1, 5));
    });
    test('patch hết và bật lại', () {
      expect(soldOutPatch(soldOut: true, by: 'bep', now: now),
          {'isAvailable': false, 'soldOutAt': nowMs, 'soldOutBy': 'bep', 'soldOutUntil': null});
      expect(soldOutPatch(soldOut: true, by: 'bep', now: now, untilNextReset: true)['soldOutUntil'],
          DateTime(2026, 10, 13, 5).millisecondsSinceEpoch);
      expect(soldOutPatch(soldOut: false, by: 'bep', now: now),
          {'isAvailable': true, 'soldOutAt': null, 'soldOutBy': null, 'soldOutUntil': null});
      expect((soldOutPatch(soldOut: true, by: 'x' * 80, now: now)['soldOutBy'] as String).length, 64);
    });
  });

  group('gom nhóm / lọc màn Hết món', () {
    final list = [
      prod('Trà đào', cat: 'Trà'),
      prod('Cà phê sữa', cat: 'Cà phê', avail: false),
      prod('Trà vải', cat: 'Trà', avail: false, until: nowMs - 5), // quá hạn => đã bán lại
      prod('Bạc xỉu', cat: 'Cà phê', code: 'BX1'),
      prod('Bánh', cat: ''),
    ];
    test('nhóm theo danh mục, sắp xếp tên', () {
      final g = groupProductsForSoldOut(list, now: now);
      expect(g.map((e) => e.category), ['Cà phê', 'Khác', 'Trà']);
      expect(g.first.items.map((p) => p.name), ['Bạc xỉu', 'Cà phê sữa']);
    });
    test('lọc Đang hết tính cả soldOutUntil', () {
      final g = groupProductsForSoldOut(list, onlySoldOut: true, now: now);
      expect(g.expand((e) => e.items).map((p) => p.name), ['Cà phê sữa']);
      expect(countSoldOut(list, now), 1);
    });
    test('tìm theo tên hoặc mã, không phân biệt hoa thường', () {
      expect(groupProductsForSoldOut(list, query: 'TRÀ', now: now).expand((e) => e.items).length, 2);
      expect(groupProductsForSoldOut(list, query: 'bx1', now: now).expand((e) => e.items).map((p) => p.name), ['Bạc xỉu']);
      expect(groupProductsForSoldOut(list, query: 'zzz', now: now), isEmpty);
    });
  });

  group('sao chép thực đơn xóa trạng thái báo hết', () {
    final src = MenuSnapshot(
      products: {'Trà đào': {'id': 2, 'name': 'Trà đào', 'price': 30000, 'category': 'Trà', 'isAvailable': false, 'soldOutAt': 5, 'soldOutBy': 'bep', 'soldOutUntil': 9}},
      categories: {'Trà': {'name': 'Trà'}},
    );
    test('tạo mới => còn bán, không còn soldOut*', () {
      final plan = MenuCopy.buildPlan(source: src, target: const MenuSnapshot());
      final node = plan.updates.entries.firstWhere((e) => e.key.startsWith('products/') && e.key.split('/').length == 2).value as Map;
      expect(node['isAvailable'], isTrue);
      expect(node.containsKey('soldOutAt') || node.containsKey('soldOutBy') || node.containsKey('soldOutUntil'), isFalse);
    });
    test('ghi đè => bật lại và xóa dấu vết ở đích', () {
      final tgt = MenuSnapshot(
        products: {'tda': {'id': 7, 'name': 'Trà đào', 'price': 1, 'category': 'Trà', 'isAvailable': false, 'soldOutAt': 3}},
        categories: {'Trà': {'name': 'Trà'}},
      );
      final plan = MenuCopy.buildPlan(source: src, target: tgt, options: const CopyOptions(conflict: ConflictPolicy.overwrite));
      expect(plan.updates['products/tda/isAvailable'], isTrue);
      expect(plan.updates.containsKey('products/tda/soldOutAt'), isTrue);
      expect(plan.updates['products/tda/soldOutAt'], isNull);
      expect(plan.updates['products/tda/soldOutBy'], isNull);
      expect(plan.updates['products/tda/soldOutUntil'], isNull);
    });
  });
}

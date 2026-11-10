import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_merge.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';

String _json(List<OrderItemModel> items) => jsonEncode(items.map((e) => e.toMap()).toList());
List<OrderItemModel> _items(String json) => [for (final e in jsonDecode(json) as List) OrderItemModel.fromMap(e as Map)];
Map<String, int> _qty(String json) => {for (final i in _items(json)) i.name: i.quantity};

void main() {
  final tra = OrderItemModel(productId: 1, name: 'Trà chanh', price: 20000, quantity: 1, lineKey: 'A');
  final base = _json([tra]);

  test('2 máy cùng thêm món khác nhau → giữ cả hai (lỗi cũ: người lưu sau xóa món người trước)', () {
    final mayA = _json([tra, OrderItemModel(productId: 2, name: 'Bánh', price: 30000, lineKey: 'B')]);
    final mayB = _json([tra, OrderItemModel(productId: 3, name: 'Trà tắc', price: 20000, lineKey: 'C')]);
    // A lưu trước: server = mayA. B lưu sau trên nền base cũ:
    final merged = OrderMerge.mergeJson(base: base, local: mayB, server: mayA);
    expect(_qty(merged), {'Trà chanh': 1, 'Bánh': 1, 'Trà tắc': 1});
  });

  test('cùng tăng số lượng một dòng → cộng dồn chênh lệch', () {
    final mayA = _json([tra.copyWith(quantity: 2)]);
    final mayB = _json([tra.copyWith(quantity: 3)]);
    final merged = OrderMerge.mergeJson(base: base, local: mayB, server: mayA);
    expect(_qty(merged), {'Trà chanh': 4}); // 1 + 1 (A) + 2 (B)
  });

  test('máy này xóa dòng, máy khác thêm món → xóa đúng dòng, giữ món mới', () {
    final mayA = _json([tra, OrderItemModel(productId: 2, name: 'Bánh', price: 30000, lineKey: 'B')]);
    final merged = OrderMerge.mergeJson(base: base, local: _json([]), server: mayA);
    expect(_qty(merged), {'Bánh': 1});
  });

  test('máy này không đổi món (chỉ đổi số khách) → giữ nguyên đơn trên server', () {
    final mayA = _json([tra, OrderItemModel(productId: 2, name: 'Bánh', price: 30000, lineKey: 'B')]);
    expect(OrderMerge.mergeJson(base: base, local: base, server: mayA), mayA);
  });

  test('đổi ghi chú ở máy này, máy kia tăng số lượng → giữ cả hai thay đổi', () {
    final mayA = _json([tra.copyWith(quantity: 2)]);
    final mayB = _json([tra.copyWith(note: 'ít đá')]);
    final merged = _items(OrderMerge.mergeJson(base: base, local: mayB, server: mayA));
    expect(merged.single.quantity, 2);
    expect(merged.single.note, 'ít đá');
  });

  test('dữ liệu cũ chưa có lineKey vẫn khớp được dòng', () {
    final oldBase = jsonEncode([
      {'productId': 1, 'name': 'Trà chanh', 'price': 20000, 'quantity': 1, 'orderedAt': 100},
    ]);
    final server = jsonEncode([
      {'productId': 1, 'name': 'Trà chanh', 'price': 20000, 'quantity': 1, 'orderedAt': 100},
      {'productId': 2, 'name': 'Bánh', 'price': 30000, 'quantity': 1, 'orderedAt': 200},
    ]);
    final local = _json([for (final i in _items(oldBase)) i.copyWith(quantity: 2)]);
    expect(_qty(OrderMerge.mergeJson(base: oldBase, local: local, server: server)), {'Trà chanh': 2, 'Bánh': 1});
  });

  test('lineKey giữ nguyên qua toMap/fromMap/copyWith', () {
    final it = OrderItemModel(productId: 1, name: 'X', price: 1);
    expect(OrderItemModel.fromMap(it.toMap()).lineKey, it.lineKey);
    expect(it.copyWith(quantity: 5).lineKey, it.lineKey);
    expect(OrderItemModel(productId: 1, name: 'X', price: 1).lineKey, isNot(it.lineKey));
  });

  test('nhật ký: hợp hai danh sách, không mất dòng của máy khác', () {
    final s = jsonEncode([{'a': 1}, {'b': 2}]);
    final l = jsonEncode([{'a': 1}, {'c': 3}]);
    expect(jsonDecode(OrderMerge.unionJsonLists(s, l)!), [{'a': 1}, {'b': 2}, {'c': 3}]);
  });

  test('bản app cũ ghi lại đơn làm mất mã dòng: vẫn áp đúng thay đổi của máy này', () {
    final b = OrderItemModel(productId: 1, name: 'Trà chanh', price: 20000, quantity: 1, orderedAt: 100, lineKey: 'Lnew1');
    final baseJ = _json([b]);
    // Server: cùng dòng nhưng không còn lineKey (bản cũ ghi lại) + món máy kia thêm
    final server = jsonEncode([
      {'productId': 1, 'name': 'Trà chanh', 'price': 20000, 'quantity': 1, 'orderedAt': 100},
      {'productId': 2, 'name': 'Bánh', 'price': 30000, 'quantity': 1, 'orderedAt': 200},
    ]);
    expect(_qty(OrderMerge.mergeJson(base: baseJ, local: _json([b.copyWith(quantity: 3)]), server: server)),
        {'Trà chanh': 3, 'Bánh': 1});
    // Máy này xóa dòng đó → xóa đúng dòng trên server, giữ món máy kia
    expect(_qty(OrderMerge.mergeJson(base: baseJ, local: _json([]), server: server)), {'Bánh': 1});
  });

  test('differs: so nội dung, bỏ qua mã dòng và thứ tự', () {
    final a = OrderItemModel(productId: 1, name: 'A', price: 1, orderedAt: 1, lineKey: 'k1');
    final b = OrderItemModel(productId: 2, name: 'B', price: 1, orderedAt: 2, lineKey: 'k2');
    expect(OrderMerge.differs(_json([a, b]), _json([b.copyWith(lineKey: 'zz'), a])), false);
    expect(OrderMerge.differs(_json([a]), _json([a.copyWith(quantity: 2)])), true);
    expect(OrderMerge.differs(_json([a]), _json([a, b])), true);
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/kitchen_order_model.dart';

KitchenOrderModel _order(List<Map<String, dynamic>> items) => KitchenOrderModel(
      tableName: 'Bàn 1',
      itemsJson: jsonEncode(items),
      timestamp: 1,
    );

Map<String, dynamic> _item(String name, int qty, [int cancelled = 0]) =>
    {'productId': 1, 'name': name, 'price': 1000, 'quantity': qty, if (cancelled > 0) 'cancelledQty': cancelled};

void main() {
  test('phiếu không huỷ', () {
    final o = _order([_item('A', 2)]);
    expect(o.hasCancellation, false);
    expect(o.isFullyCancelled, false);
    expect(o.cancelledQtys, [0]);
  });

  test('huỷ một phần', () {
    final o = _order([_item('A', 3, 1), _item('B', 1)]);
    expect(o.hasCancellation, true);
    expect(o.isFullyCancelled, false);
    expect(o.cancelledQtys, [1, 0]);
  });

  test('huỷ hết', () {
    final o = _order([_item('A', 2, 2), _item('B', 1, 1)]);
    expect(o.isFullyCancelled, true);
  });

  test('cancelledAt đọc/ghi', () {
    final o = KitchenOrderModel.fromMap({'tableName': 'B', 'itemsJson': '[]', 'timestamp': 1, 'cancelledAt': 99});
    expect(o.cancelledAt, 99);
    expect(o.toMap()['cancelledAt'], 99);
  });
}

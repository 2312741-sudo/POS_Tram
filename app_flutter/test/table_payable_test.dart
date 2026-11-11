import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/table_model.dart';

void main() {
  test('tiền bàn đang phục vụ sau khuyến mãi = tiền món − giảm món − khuyến mãi đơn, không âm', () {
    final order = jsonEncode([
      {'productId': 1, 'name': 'Trà Olong - Xoài', 'price': 30000, 'quantity': 1},
      {'productId': 2, 'name': 'Trà đào', 'price': 30000, 'quantity': 2},
    ]);
    final t = TableModel(name: 'GRAB', zone: 'Mang về', inUse: true, currentOrderJson: order);
    expect(t.payableTotal, t.currentTotal);
    t.discountsJson = jsonEncode([
      {'description': 'Xoài 16K', 'amount': 16000},
      {'description': 'Giảm tay', 'amount': 4000},
    ]);
    expect(t.payableTotal, t.currentTotal - 20000);
    t.discountsJson = jsonEncode([
      {'description': 'Giảm 100%', 'amount': 999999},
    ]);
    expect(t.payableTotal, 0);
  });
}

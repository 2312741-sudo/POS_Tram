import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/reports/topping_split.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/data/models/product_model.dart';

/// Cùng tình huống với web/test/topping-split.test.ts — hai bên phải ra cùng số
void main() {
  final products = {
    901: ProductModel(id: 901, name: 'Trân châu', code: 'TP01', price: 5000, costPrice: 1500, unit: 'Phần', category: 'Topping', isTopping: true),
    902: ProductModel(id: 902, name: 'Kem cheese', code: 'TP02', price: 8000, costPrice: 2500, unit: 'Phần', category: 'Topping', isTopping: true),
  };
  OrderItemModel line({List<String> tops = const ['Trân châu', 'Kem cheese'], int toppingPrice = 13000, int discount = 10000}) =>
      OrderItemModel.fromMap({
        'productId': 1, 'name': 'Trà đào', 'price': 30000, 'sizeExtraPrice': 5000, 'quantity': 2,
        'selectedToppings': tops, 'toppingPrice': toppingPrice, 'lineDiscountTotal': discount, 'discountAmount': discount,
      });

  test('món gốc = giá + size; mỗi topping một dòng riêng; giảm giá chia theo tỉ lệ tiền', () {
    final parts = splitLineParts(line(), mainKey: 'id:1', mainUnitCost: 0, productsMap: products);
    expect(parts.map((p) => [p.name, p.isTopping, p.quantity, p.grossRevenue, p.itemDiscount, p.costPrice]).toList(), [
      ['Trà đào', false, 2, 70000, 7292, 0],
      ['Trân châu', true, 2, 10000, 1042, 3000],
      ['Kem cheese', true, 2, 16000, 1666, 5000],
    ]);
    expect(parts.fold<int>(0, (s, p) => s + p.grossRevenue), (30000 + 5000 + 13000) * 2);
    expect(parts.fold<int>(0, (s, p) => s + p.itemDiscount), 10000);
  });

  test('không tra được giá topping → chia đều toppingPrice', () {
    final parts = splitLineParts(line(tops: ['A', 'B'], toppingPrice: 9000, discount: 0), mainKey: 'id:1', mainUnitCost: 0);
    expect(parts.skip(1).map((p) => [p.name, p.grossRevenue, p.category]).toList(), [
      ['A', 9000, 'Topping'],
      ['B', 9000, 'Topping'],
    ]);
  });
}

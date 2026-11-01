import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/topping_ref.dart';
import 'package:tram_flutter/data/models/product_model.dart';

/// Web lưu KHÓA RTDB của món topping vào categories.allowedToppingIds → app phải tra được theo khóa,
/// không hiện mã thô với giá 5.000đ.
void main() {
  final grab5 = ProductModel.fromMap({'name': 'Tăng giá Grab 5K', 'price': 5000, 'category': 'Topping', 'isTopping': true}, '-NgrabUp5k');
  final grab10 = ProductModel.fromMap({'id': 12, 'name': 'Tăng giá Grab 10K', 'price': '10000', 'category': 'Topping', 'isTopping': true}, '-NgrabUp10k');
  final products = [grab5, grab10];
  final defaults = [ProductModel(id: 9001, name: 'Trân châu đen', price: 5000, unit: 'phần', category: 'Topping', isTopping: true)];

  test('tra theo khóa RTDB → đúng tên + giá', () {
    expect(ToppingRef.find('-NgrabUp5k', products)?.name, 'Tăng giá Grab 5K');
    expect(ToppingRef.find('-NgrabUp5k', products)?.price, 5000);
    expect(ToppingRef.find('-NgrabUp10k', products)?.price, 10000);
  });

  test('vẫn tra được theo id số, tên, mặc định; không thấy → null (không tạo topping mang tên mã)', () {
    expect(ToppingRef.find('12', products)?.name, 'Tăng giá Grab 10K');
    expect(ToppingRef.find('tăng giá grab 5k', products)?.name, 'Tăng giá Grab 5K');
    expect(ToppingRef.find('Trân châu đen', products, defaults: defaults)?.price, 5000);
    expect(ToppingRef.find('-NdaXoaMon123', products, defaults: defaults), isNull);
  });
}

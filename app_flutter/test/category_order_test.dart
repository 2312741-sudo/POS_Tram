import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/category_model.dart';

void main() {
  test('thứ tự danh mục: có order trước, chưa có sau theo tên', () {
    final l = [
      CategoryModel(name: 'Z'),
      CategoryModel(name: 'B', order: 1),
      CategoryModel(name: 'A', order: 0),
      CategoryModel(name: 'C'),
    ]..sort(compareCategories);
    expect(l.map((c) => c.name), ['A', 'B', 'C', 'Z']);
  });

  test('order được giữ khi đọc/ghi và copyWith', () {
    final c = CategoryModel.fromMap({'name': 'Cà phê', 'order': 3}, 'Cà phê');
    expect(c.order, 3);
    expect(c.toMap()['order'], 3);
    expect(c.copyWith(allowedToppingIds: ['t']).order, 3);
    expect(CategoryModel(name: 'X').toMap().containsKey('order'), isFalse);
  });
}

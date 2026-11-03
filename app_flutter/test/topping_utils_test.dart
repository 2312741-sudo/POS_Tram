import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/item_options.dart';
import 'package:tram_flutter/core/utils/topping_utils.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';

void main() {
  test('gộp topping lặp thành số phần', () {
    expect(toppingLabels(['Trân châu', 'Thạch', 'Trân châu']), ['Trân châu x2', 'Thạch']);
    expect(toppingCount(['A', 'B', 'A'], 'A'), 2);
    expect(groupToppings([]).isEmpty, true);
  });

  test('optionsSummary gộp x2, optionsSummaryNoTopping bỏ topping', () {
    final it = OrderItemModel(
      productId: 1, name: 'Trà', price: 30000,
      selectedSize: 'L', selectedSugar: '50% đường', selectedIce: '',
      selectedToppings: ['Trân châu', 'Trân châu'], toppingPrice: 10000,
    );
    expect(it.optionsSummary, 'Size L • 50% đường • Trân châu x2');
    expect(it.optionsSummaryNoTopping, 'Size L • 50% đường');
    expect(it.unitPrice, 40000);
  });

  test('addToppingUnit cho phép lặp, tôn trọng tối đa theo tổng số phần', () {
    final g = ToppingGroup(id: 'g', name: 'G', multi: true, max: 3, items: [
      ToppingItem(id: 'a', name: 'A', price: 5000), ToppingItem(id: 'b', name: 'B', price: 5000),
    ]);
    var sel = <String>[];
    sel = addToppingUnit(selected: sel, group: g, name: 'A');
    sel = addToppingUnit(selected: sel, group: g, name: 'A');
    sel = addToppingUnit(selected: sel, group: g, name: 'B');
    expect(sel, ['A', 'A', 'B']);
    sel = addToppingUnit(selected: sel, group: g, name: 'A'); // đã đủ 3 phần
    expect(sel, ['A', 'A', 'B']);
  });

  test('nhóm chọn một chỉ giữ 1 phần', () {
    final g = ToppingGroup(id: 'g', name: 'G', multi: false, max: 0, items: [
      ToppingItem(id: 'a', name: 'A'), ToppingItem(id: 'b', name: 'B'),
    ]);
    expect(addToppingUnit(selected: ['A'], group: g, name: 'B'), ['B']);
  });
}

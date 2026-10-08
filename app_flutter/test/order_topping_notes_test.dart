import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/product_model.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/category_model.dart';

void main() {
  group('Order Topping & Notes Tests', () {
    test('OrderItemModel calculates unitPrice and itemTotal with size and toppings correctly', () {
      final item = OrderItemModel(
        productId: 101,
        name: 'Trà Oolong Sữa Nướng',
        price: 35000,
        quantity: 2,
        selectedSize: 'L',
        sizeExtraPrice: 6000,
        selectedSugar: '70% đường',
        selectedIce: '50% đá',
        selectedToppings: ['Trân châu đen', 'Thạch phô mai'],
        toppingPrice: 13000, // 5k + 8k
        note: 'Ít ngọt, mang về',
      );

      // Đơn giá: 35.000 + 6.000 (Size L) + 13.000 (Toppings) = 54.000
      expect(item.unitPrice, 54000);
      // Tổng tiền cho 2 phần: 54.000 * 2 = 108.000
      expect(item.itemTotal, 108000);
      expect(item.note, 'Ít ngọt, mang về');
      expect(item.optionsSummary, contains('Size L'));
      expect(item.optionsSummary, contains('70% đường'));
      expect(item.optionsSummary, contains('50% đá'));
      expect(item.optionsSummary, contains('Trân châu đen'));
      expect(item.optionsSummary, contains('Thạch phô mai'));
    });

    test('OrderItemModel copyWith updates note and toppings seamlessly', () {
      final initialItem = OrderItemModel(
        productId: 102,
        name: 'Trà Đào Cam Sả',
        price: 30000,
        quantity: 1,
      );

      expect(initialItem.note, '');
      expect(initialItem.selectedToppings, isEmpty);
      expect(initialItem.unitPrice, 30000);

      final updatedItem = initialItem.copyWith(
        note: 'Nhiều đá, để riêng đào',
        selectedToppings: ['Đào miếng', 'Thạch chanh'],
        toppingPrice: 13000,
        selectedSugar: '50% đường',
        selectedIce: '100% đá',
      );

      expect(updatedItem.note, 'Nhiều đá, để riêng đào');
      expect(updatedItem.selectedToppings, ['Đào miếng', 'Thạch chanh']);
      expect(updatedItem.toppingPrice, 13000);
      expect(updatedItem.unitPrice, 43000);
      expect(updatedItem.itemTotal, 43000);
    });

    test('Beverage keywords detection covers all tea, coffee, and drink categories', () {
      final beverageCategories = [
        'Trà trái cây',
        'Trà sữa',
        'Cold Tea',
        'Cà phê máy',
        'Cafe truyền thống',
        'Coffee specialty',
        'Nước ép tươi',
        'Đồ uống có gas',
        'Sinh tố bơ',
        'Đá xay Frappe',
        'Sữa chua lắc',
        'Matcha latte',
      ];

      for (final cat in beverageCategories) {
        final product = ProductModel(
          id: 1,
          name: 'Test Beverage',
          price: 25000,
          unit: 'ly',
          category: cat,
        );

        final isDrinkOrTea = product.category.toLowerCase().contains('trà') ||
            product.category.toLowerCase().contains('tea') ||
            product.category.toLowerCase().contains('cà phê') ||
            product.category.toLowerCase().contains('cafe') ||
            product.category.toLowerCase().contains('coffee') ||
            product.category.toLowerCase().contains('nước') ||
            product.category.toLowerCase().contains('uống') ||
            product.category.toLowerCase().contains('sinh tố') ||
            product.category.toLowerCase().contains('đá xay') ||
            product.category.toLowerCase().contains('sữa') ||
            product.category.toLowerCase().contains('matcha') ||
            product.hasIceSugarOptions ||
            product.sizes.isNotEmpty;

        expect(isDrinkOrTea, isTrue, reason: 'Category "$cat" must be recognized as beverage');
      }
    });

    test('Category allowedToppingIds filters available toppings accurately', () {
      final category = CategoryModel(
        name: 'Trà Sữa',
        allowedToppingIds: ['9001', '9003'], // Trân châu đen, Thạch phô mai
      );

      final allProducts = [
        ProductModel(id: 9001, name: 'Trân châu đen', price: 5000, unit: 'phần', category: 'Topping', isTopping: true),
        ProductModel(id: 9002, name: 'Trân châu trắng', price: 6000, unit: 'phần', category: 'Topping', isTopping: true),
        ProductModel(id: 9003, name: 'Thạch phô mai', price: 8000, unit: 'phần', category: 'Topping', isTopping: true),
      ];

      final List<String> availableToppingNames = [];
      for (final tId in category.allowedToppingIds) {
        final match = allProducts.firstWhere(
          (p) => p.id.toString() == tId,
          orElse: () => ProductModel(name: tId, price: 5000, unit: 'phần', category: 'Topping'),
        );
        availableToppingNames.add(match.name);
      }

      expect(availableToppingNames, contains('Trân châu đen'));
      expect(availableToppingNames, contains('Thạch phô mai'));
      expect(availableToppingNames, isNot(contains('Trân châu trắng')));
    });

    test('Note preset toggling appends or removes cleanly', () {
      String note = '';
      const preset1 = 'Ít ngọt';
      const preset2 = 'Nhiều đá';

      // Append preset1
      note = note.isEmpty ? preset1 : '$note, $preset1';
      expect(note, 'Ít ngọt');

      // Append preset2
      note = note.isEmpty ? preset2 : '$note, $preset2';
      expect(note, 'Ít ngọt, Nhiều đá');

      // Remove preset1
      note = note.replaceAll(', $preset1', '').replaceAll('$preset1, ', '').replaceAll(preset1, '').trim();
      expect(note, 'Nhiều đá');
    });
  });
}

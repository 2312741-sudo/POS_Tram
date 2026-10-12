import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/note_catalog_migration.dart';

void main() {
  final products = {
    'Thạch chanh': {'id': 1, 'name': 'Thạch chanh', 'price': 5000, 'category': 'Topping', 'isTopping': true},
    'Thạch dừa': {'id': 2, 'name': 'Thạch dừa', 'price': 6000, 'category': 'Topping'},
    'Trà Olong - Đào': {'id': 3, 'name': 'Trà Olong - Đào', 'price': 30000, 'category': 'Trà Olong Trái Cây'},
    'Bánh lăn A': {'id': 4, 'name': 'Bánh lăn A', 'price': 20000, 'category': 'Bánh Lăn Nướng'},
    'Cà phê X': {'id': 5, 'name': 'Cà phê X', 'price': 20000, 'category': 'Cafe riêng', 'allowedToppings': ['Thạch dừa', 'Kem Cheese']},
  };
  final categories = {
    'Bánh Lăn Nướng': {'name': 'Bánh Lăn Nướng'},
    'Topping': {'name': 'Topping'},
    'Trà Olong Trái Cây': {'name': 'Trà Olong Trái Cây'},
    'Cafe riêng': {'name': 'Cafe riêng'},
    'Sữa tuỳ chọn': {'name': 'Sữa tuỳ chọn', 'allowedToppingIds': ['1', 'Kem Cheese']},
  };
  final notes = {'n1': {'text': 'Ít đá'}, 'n2': {'text': 'Ít ngọt'}};

  NoteCatalogMigrationPlan plan({dynamic ng, dynamic tg, dynamic cats, dynamic prods}) => planNoteCatalogMigration(
      products: prods ?? products, categories: cats ?? categories, productNotes: notes, noteGroups: ng, toppingGroups: tg);

  test('đồ uống được gắn topping + note; bánh/Topping không gắn gì', () {
    final p = plan().updates;
    expect((p['topping_groups/legacy_toppings'] as Map)['items'], hasLength(2));
    expect((p['note_groups/legacy_notes'] as Map)['items'], hasLength(2));
    expect(p['categories/Trà Olong Trái Cây/toppingGroupIds'], ['legacy_toppings']);
    expect(p['categories/Trà Olong Trái Cây/noteGroupIds'], ['legacy_notes']);
    expect(p.keys.any((k) => k.startsWith('categories/Bánh Lăn Nướng')), isFalse);
    expect(p.keys.any((k) => k.startsWith('categories/Topping/')), isFalse);
  });
  test('nhóm có allowedToppingIds -> nhóm riêng; món có allowedToppings riêng -> nhóm bộ', () {
    final p = plan().updates;
    expect(p['categories/Sữa tuỳ chọn/toppingGroupIds'], ['legacy_cat_Sữa_tuỳ_chọn']);
    final g = p['topping_groups/legacy_cat_Sữa_tuỳ_chọn'] as Map;
    expect((g['items'] as List).map((e) => (e as Map)['name']), ['Thạch chanh', 'Kem Cheese']);
    final setKey = p.keys.firstWhere((k) => k.startsWith('products/Cà phê X/'));
    expect(p[setKey], hasLength(1));
  });
  test('idempotent: nhóm có sẵn không ghi đè, trường gắn có sẵn (kể cả không có) giữ nguyên', () {
    final cats2 = {
      ...categories,
      'Trà Olong Trái Cây': {'name': 'Trà Olong Trái Cây', 'toppingGroupIds': ['__none__'], 'noteGroupIds': ['x']},
    };
    final p = plan(ng: {'legacy_notes': {}}, tg: {'legacy_toppings': {}}, cats: cats2).updates;
    expect(p.containsKey('note_groups/legacy_notes'), isFalse);
    expect(p.containsKey('topping_groups/legacy_toppings'), isFalse);
    expect(p.containsKey('categories/Trà Olong Trái Cây/toppingGroupIds'), isFalse);
    expect(p.containsKey('categories/Trà Olong Trái Cây/noteGroupIds'), isFalse);
  });
  test('không có món Topping -> dùng bộ chuẩn; không có gì -> kế hoạch rỗng', () {
    final p = plan(prods: {'A': {'name': 'A', 'price': 1, 'category': 'Trà'}}, cats: {'Trà': {'name': 'Trà'}}).updates;
    expect((p['topping_groups/legacy_toppings'] as Map)['items'], hasLength(8));
    expect(planNoteCatalogMigration(products: null, categories: null, productNotes: null, noteGroups: null, toppingGroups: null).isEmpty, isTrue);
  });
}

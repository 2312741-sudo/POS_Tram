import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/item_options.dart';

void main() {
  final notes = [
    NoteGroup(id: 'n1', name: 'Đồ uống', sortOrder: 1, items: const [NoteTemplate(id: 'a', text: 'Ít đá'), NoteTemplate(id: 'b', text: 'Ít ngọt')]),
    NoteGroup(id: 'n2', name: 'Bánh', sortOrder: 2, items: const [NoteTemplate(id: 'c', text: 'Cắt đôi'), NoteTemplate(id: 'd', text: 'Ít đá')]),
    NoteGroup(id: 'n3', name: 'Tắt', active: false, items: const [NoteTemplate(id: 'e', text: 'X')]),
  ];
  final tops = [
    ToppingGroup(id: 't1', name: 'Topping trà', items: const [ToppingItem(id: '1', name: 'Trân châu', price: 5000), ToppingItem(id: '2', name: 'Thạch', price: 4000)]),
    ToppingGroup(id: 't2', name: 'Sốt', multi: false, items: const [ToppingItem(id: '3', name: 'Socola', price: 3000), ToppingItem(id: '4', name: 'Dâu', price: 3000)]),
    ToppingGroup(id: 't3', name: 'Rỗng'),
  ];
  final cat = ItemCatalog(noteGroups: notes, toppingGroups: tops);

  group('resolveItemOptions', () {
    test('chưa cấu hình -> legacy', () {
      final r = resolveItemOptions(catalog: const ItemCatalog());
      expect(r.legacy, isTrue);
      expect(r.noteGroups, isEmpty);
    });
    test('không gắn gì -> không hiện note/topping', () {
      final r = resolveItemOptions(catalog: cat);
      expect(r.legacy, isFalse);
      expect(r.noteGroups, isEmpty);
      expect(r.toppingGroups, isEmpty);
      expect(r.noteSource, OptionSource.none);
    });
    test('kế thừa từ nhóm món', () {
      final r = resolveItemOptions(categoryNoteGroupIds: ['n1'], categoryToppingGroupIds: ['t1'], catalog: cat);
      expect(r.noteGroups.map((g) => g.id), ['n1']);
      expect(r.toppingGroups.map((g) => g.id), ['t1']);
      expect(r.noteSource, OptionSource.category);
    });
    test('món ghi đè nhóm món (kể cả rỗng = không có)', () {
      final over = resolveItemOptions(productNoteGroupIds: ['n2'], categoryNoteGroupIds: ['n1'], catalog: cat);
      expect(over.noteGroups.map((g) => g.id), ['n2']);
      expect(over.noteSource, OptionSource.product);
      final none = resolveItemOptions(productNoteGroupIds: [], productToppingGroupIds: [kNoGroups], categoryNoteGroupIds: ['n1'], categoryToppingGroupIds: ['t1'], catalog: cat);
      expect(none.noteGroups, isEmpty);
      expect(none.toppingGroups, isEmpty);
    });
    test('bỏ nhóm đã tắt, không tồn tại, rỗng; giữ thứ tự gắn, bỏ trùng', () {
      final r = resolveItemOptions(productNoteGroupIds: ['n2', 'n3', 'zzz', 'n1', 'n2'], productToppingGroupIds: ['t3', 't2', 't1'], catalog: cat);
      expect(r.noteGroups.map((g) => g.id), ['n2', 'n1']);
      expect(r.toppingGroups.map((g) => g.id), ['t2', 't1']);
      expect(r.noteChips, ['Cắt đôi', 'Ít đá', 'Ít ngọt']);
      expect(r.toppingPrices['Trân châu'], 5000);
    });
  });

  group('encode/parse', () {
    test('rỗng -> [__none__], null -> null', () {
      expect(encodeGroupIds(null), isNull);
      expect(encodeGroupIds([]), [kNoGroups]);
      expect(encodeGroupIds(['a', kNoGroups]), ['a']);
      expect(parseGroupIds(null), isNull);
      expect(parseGroupIds({'0': 'a', '2': 'b'}), ['a', 'b']);
    });
  });

  group('toggleTopping', () {
    test('chọn một: thay thế trong cùng nhóm', () {
      var s = <String>['Trân châu'];
      s = toggleTopping(selected: s, group: tops[1], name: 'Socola');
      s = toggleTopping(selected: s, group: tops[1], name: 'Dâu');
      expect(s, ['Trân châu', 'Dâu']);
    });
    test('giới hạn tối đa', () {
      final g = tops[0].copyWith(max: 1);
      var s = toggleTopping(selected: const [], group: g, name: 'Trân châu');
      s = toggleTopping(selected: s, group: g, name: 'Thạch');
      expect(s, ['Trân châu']);
      expect(toggleTopping(selected: s, group: g, name: 'Trân châu'), isEmpty);
    });
  });

  test('fromMap chịu được dữ liệu RTDB dạng map', () {
    final g = ToppingGroup.fromMap('x', {
      'name': 'A', 'multi': false, 'max': 2,
      'items': {'0': {'id': 'i', 'name': 'T', 'price': 1000}, '2': {'name': 'U', 'price': -5}},
    });
    expect(g.items.map((e) => e.name), ['T', 'U']);
    expect(g.items[1].price, 0);
    expect(g.multi, isFalse);
    expect(g.max, 2);
  });
}

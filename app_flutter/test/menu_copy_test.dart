import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/menu_copy.dart';

MenuSnapshot snap({Map<String, dynamic> p = const {}, Map<String, dynamic> c = const {}, Map<String, dynamic> n = const {}}) =>
    MenuSnapshot(products: p, categories: c, notes: n);

String nk(int i) => 'n$i';

final source = snap(
  p: {
    'Cà phê sữa': {'id': 1, 'name': 'Cà phê sữa', 'code': 'CF1', 'price': 25000, 'category': 'Cà phê', 'sizes': {'S': 0, 'L': 5000}, 'allowedToppings': ['Trân châu'], 'hasIceSugarOptions': true, 'imageBase64': 'AAA', 'imageResourceName': 'cf.jpg'},
    'Trà đào': {'id': 2, 'name': 'Trà đào', 'price': 30000, 'category': 'Trà', 'unit': 'Ly'},
    'Trân châu': {'id': 3, 'name': 'Trân châu', 'price': 5000, 'category': 'Topping', 'isTopping': true},
  },
  c: {'Cà phê': {'name': 'Cà phê', 'allowedToppingIds': ['Trân châu']}, 'Trà': {'name': 'Trà'}, 'Topping': 'Topping'},
  n: {'a': {'text': 'Ít ngọt'}, 'b': 'Nhiều đá'},
);

void main() {
  group('chuẩn hóa tên', () {
    test('bỏ dấu tiếng Việt, đ, hoa thường, khoảng trắng', () {
      expect(MenuCopy.normalizeName('  Cà   Phê  Sữa Đá '), 'ca phe sua da');
      expect(MenuCopy.normalizeName('TRÀ ĐÀO'), MenuCopy.normalizeName('tra dao'));
      expect(MenuCopy.normalizeName('Bạc-xỉu!'), 'bac xiu');
      expect(MenuCopy.normalizeName(null), '');
      expect(MenuCopy.normalizeName('Ơ Ư Ê Ô Ă Â'), 'o u e o a a');
    });
    test('khóa RTDB hợp lệ', () {
      expect(MenuCopy.sanitizeKey('A.B/C#D\$E[F]'), 'A_B_C_D_E_F_');
    });
  });

  group('đích trống', () {
    final plan = MenuCopy.buildPlan(source: source, target: snap(), noteKey: nk);
    test('giữ id/khóa nguồn, tạo đủ nhóm + ghi chú', () {
      expect(plan.created, 3);
      expect(plan.categoriesCreated, 3);
      expect(plan.notesToAdd, 2);
      expect(plan.idMap, {1: 1, 2: 2, 3: 3});
      final cf = plan.updates['products/Cà phê sữa'] as Map;
      expect(cf['id'], 1);
      expect(cf['imageBase64'], 'AAA');
      expect(plan.updates['categories/Cà phê'], {'name': 'Cà phê', 'allowedToppingIds': ['Trân châu']});
      expect(plan.updates['product_notes/n0'], {'text': 'Ít ngọt'});
    });
    test('không có giá trị null (null trong update() = xóa)', () {
      expect(plan.updates.values.any((v) => v == null), isFalse);
    });
  });

  group('cấp id không va chạm', () {
    final target = snap(
      p: {
        'Bạc xỉu': {'id': 1, 'name': 'Bạc xỉu', 'price': 20000, 'category': 'Cà phê'},
        '7': {'id': 7, 'name': 'Sinh tố', 'price': 40000, 'category': 'Sinh tố'},
      },
      c: {'Cà phê': {'name': 'Cà phê'}},
    );
    test('id mới sau id lớn nhất ở đích', () {
      final plan = MenuCopy.buildPlan(source: source, target: target, noteKey: nk);
      final ids = plan.productOps.map((p) => p.targetId).toList();
      expect(ids, [8, 9, 10]);
      expect(plan.idMap, {1: 8, 2: 9, 3: 10});
      expect(plan.productOps.every((p) => !target.products.containsKey(p.targetKey)), isTrue);
    });
    test('khóa trùng khóa có sẵn thì đổi khóa', () {
      final t = snap(p: {'Trà đào': {'id': 50, 'name': 'Trà đào ', 'price': 1, 'category': 'Khác'}});
      final s = snap(p: {'Trà đào': {'id': 2, 'name': 'Trà đào', 'price': 30000, 'category': 'Trà'}});
      final plan = MenuCopy.buildPlan(source: s, target: t);
      expect(plan.productOps.first.action, ProductAction.create);
      expect(plan.productOps.first.targetKey, isNot('Trà đào'));
      expect(plan.productOps.first.targetId, 51);
    });
    test('khóa số nguồn thành khóa số = id mới', () {
      final s = snap(p: {'5': {'id': 5, 'name': 'X', 'price': 1, 'category': 'A'}});
      final t = snap(p: {'5': {'id': 5, 'name': 'Y', 'price': 1, 'category': 'B'}});
      final op = MenuCopy.buildPlan(source: s, target: t).productOps.first;
      expect(op.targetId, 6);
      expect(op.targetKey, '6');
    });
  });

  group('nhóm', () {
    test('quy đổi nhóm đích khác dấu, chỉ tạo nhóm thiếu', () {
      final plan = MenuCopy.buildPlan(source: source, target: snap(c: {'TRA': {'name': 'TRA'}}), noteKey: nk);
      expect((plan.updates['products/Trà đào'] as Map)['category'], 'TRA');
      expect(plan.categoryOps.where((c) => c.create).map((c) => c.name).toList()..sort(), ['Cà phê', 'Topping']);
      expect(plan.updates.containsKey('categories/Trà'), isFalse);
    });
    test('tắt sao chép nhóm', () {
      final plan = MenuCopy.buildPlan(source: source, target: snap(), options: const CopyOptions(copyCategories: false));
      expect(plan.updates.keys.any((k) => k.startsWith('categories/')), isFalse);
      expect((plan.updates['products/Trà đào'] as Map)['category'], 'Trà');
    });
  });

  group('xung đột', () {
    final target = snap(
      p: {'ca phe sua': {'id': 4, 'name': 'CA PHE SUA', 'price': 99000, 'costPrice': 1234, 'category': 'CÀ PHÊ'}},
      c: {'CÀ PHÊ': {'name': 'CÀ PHÊ'}},
      n: {'x': {'text': 'ít ngọt'}},
    );
    test('bỏ qua', () {
      final plan = MenuCopy.buildPlan(source: source, target: target, noteKey: nk);
      expect(plan.skipped, 1);
      expect(plan.created, 2);
      expect(plan.productOps.firstWhere((p) => p.action == ProductAction.skip).targetKey, 'ca phe sua');
      expect(plan.notesToAdd, 1);
      expect(plan.updates.containsKey('products/ca phe sua'), isFalse);
    });
    test('ghi đè giữ khóa + id đích, ghi từng trường', () {
      final plan = MenuCopy.buildPlan(source: source, target: target, options: const CopyOptions(conflict: ConflictPolicy.overwrite));
      expect(plan.overwritten, 1);
      expect(plan.updates['products/ca phe sua/price'], 25000);
      expect(plan.updates['products/ca phe sua/id'], 4);
      expect(plan.updates['products/ca phe sua/category'], 'CÀ PHÊ');
      expect(plan.updates.containsKey('products/ca phe sua/costPrice'), isFalse);
      expect(plan.idMap[1], 4);
    });
    test('bản sao: hậu tố, id mới, bỏ SKU, lần sau hậu tố 2', () {
      const opt = CopyOptions(conflict: ConflictPolicy.duplicate);
      final plan = MenuCopy.buildPlan(source: source, target: target, options: opt);
      final dup = plan.productOps.firstWhere((o) => o.action == ProductAction.duplicate);
      expect(dup.targetId, isNot(4));
      final node = plan.updates['products/${dup.targetKey}'] as Map;
      expect(node['name'], 'Cà phê sữa (bản sao)');
      expect(node['code'], '');
      final t2 = snap(p: {...target.products, dup.targetKey!: node}, c: target.categories);
      final plan2 = MenuCopy.buildPlan(source: source, target: t2, options: opt);
      final dup2 = plan2.productOps.firstWhere((o) => o.action == ProductAction.duplicate && o.sourceKey == 'Cà phê sữa');
      expect((plan2.updates['products/${dup2.targetKey}'] as Map)['name'], 'Cà phê sữa (bản sao 2)');
    });
    test('hai món nguồn cùng tên+nhóm chỉ lấy một', () {
      final s = snap(p: {'a': {'id': 1, 'name': 'Trà', 'price': 1, 'category': 'T'}, 'b': {'id': 2, 'name': 'TRA', 'price': 2, 'category': 't'}});
      final plan = MenuCopy.buildPlan(source: s, target: snap());
      expect(plan.created, 1);
      expect(plan.skipped, 1);
    });
  });

  group('phạm vi và tùy chọn', () {
    test('chọn theo nhóm / khóa món', () {
      final byCat = MenuCopy.buildPlan(source: source, target: snap(), selection: const CopySelection(categories: ['tra']));
      expect(byCat.productOps.map((p) => p.name).toList(), ['Trà đào']);
      final byKey = MenuCopy.buildPlan(source: source, target: snap(), selection: const CopySelection(productKeys: ['Trân châu']));
      expect(byKey.productOps.map((p) => p.name).toList(), ['Trân châu']);
      final both = MenuCopy.buildPlan(source: source, target: snap(), selection: const CopySelection(categories: ['Trà'], productKeys: ['Trân châu']));
      expect(both.productOps.length, 2);
    });
    test('tắt ảnh / tùy chọn / ghi chú', () {
      final plan = MenuCopy.buildPlan(
        source: source,
        target: snap(),
        options: const CopyOptions(copyImages: false, copyOptions: false, copyNotes: false),
      );
      final cf = plan.updates['products/Cà phê sữa'] as Map;
      for (final f in ['imageBase64', 'imageResourceName', 'sizes', 'allowedToppings', 'hasIceSugarOptions']) {
        expect(cf.containsKey(f), isFalse, reason: f);
      }
      expect(cf['price'], 25000);
      expect(plan.notesToAdd, 0);
    });
    test('dữ liệu dạng danh sách / null không làm hỏng', () {
      final s = MenuSnapshot(products: MenuCopy.toRecord([null, {'id': 1, 'name': 'A', 'price': 1, 'category': 'C'}]));
      expect(MenuCopy.buildPlan(source: s, target: snap()).created, 1);
    });
  });

  group('nhiều đích, lô, nhật ký, quyền', () {
    test('mỗi đích có kế hoạch độc lập', () {
      final t1 = snap(p: {'x': {'id': 100, 'name': 'X', 'price': 1, 'category': 'K'}});
      expect(MenuCopy.buildPlan(source: source, target: t1, noteKey: nk).productOps.map((o) => o.targetId).toList(), [101, 102, 103]);
      expect(MenuCopy.buildPlan(source: source, target: snap(), noteKey: nk).productOps.map((o) => o.targetId).toList(), [1, 2, 3]);
    });
    test('chia lô', () {
      final u = <String, Object?>{for (var i = 0; i < 905; i++) 'products/p$i': {'i': i}};
      expect(MenuCopy.chunkUpdates(u).map((c) => c.length).toList(), [400, 400, 105]);
      expect(MenuCopy.chunkUpdates({}), isEmpty);
    });
    test('nhật ký COPY_MENU', () {
      final e = MenuCopy.auditEntry(sourceStore: 'TRAM01', targetStore: 'TRAM02', created: 3, overwritten: 0, skipped: 1, username: 'admin', now: 123);
      expect(e['action'], 'COPY_MENU');
      expect(e['details'], 'Sao chép 3 món từ TRAM01 sang TRAM02');
      expect(e['skipped'], 1);
      expect(e['username'], 'admin');
    });
    test('quyền', () {
      expect(MenuCopy.canCopyMenu(isOwnerOrManager: true, canEditMenu: true), isTrue);
      expect(MenuCopy.canCopyMenu(isOwnerOrManager: true, canEditMenu: false), isFalse);
      expect(MenuCopy.canCopyMenu(isOwnerOrManager: false, canEditMenu: true), isFalse);
    });
  });

  group('danh mục note & topping', () {
    final src = MenuSnapshot(
      products: {
        'Trà A': {'id': 1, 'name': 'Trà A', 'price': 1, 'category': 'Trà', 'noteGroupIds': ['n1'], 'toppingGroupIds': ['__none__']},
        'Bánh B': {'id': 2, 'name': 'Bánh B', 'price': 1, 'category': 'Bánh', 'noteGroupIds': ['ghost']},
      },
      categories: {
        'Trà': {'name': 'Trà', 'noteGroupIds': ['n1'], 'toppingGroupIds': ['t1', 't2']},
        'Bánh': {'name': 'Bánh'},
      },
      noteGroups: {'n1': {'name': 'Đồ uống', 'items': [{'id': 'a', 'text': 'Ít đá'}]}},
      toppingGroups: {
        't1': {'name': 'Topping trà', 'items': [{'id': '1', 'name': 'Trân châu', 'price': 5000}]},
        't2': {'name': 'Sốt', 'multi': false, 'items': [{'id': '2', 'name': 'Dâu', 'price': 0}]},
      },
    );

    test('đích trống: sao chép nhóm, giữ id nguồn, đổi id trong phần gắn', () {
      final plan = MenuCopy.buildPlan(source: src, target: const MenuSnapshot(), noteKey: nk);
      expect(plan.groupsToAdd, 3);
      expect((plan.updates['note_groups/n1'] as Map)['name'], 'Đồ uống');
      expect(plan.updates['categories/Trà'], {'name': 'Trà', 'noteGroupIds': ['n1'], 'toppingGroupIds': ['t1', 't2']});
      final a = plan.updates['products/Trà A'] as Map;
      expect(a['noteGroupIds'], ['n1']);
      expect(a['toppingGroupIds'], ['__none__']);
      // id nhóm không còn ở nguồn -> "không có" (không rơi về kế thừa)
      expect((plan.updates['products/Bánh B'] as Map)['noteGroupIds'], ['__none__']);
    });

    test('đích đã có nhóm trùng tên: dùng lại, không ghi đè, id khác thì đổi id; id trùng khác tên thì cấp id mới', () {
      final target = MenuSnapshot(
        noteGroups: {'x9': {'name': 'ĐỒ UỐNG', 'items': []}},
        toppingGroups: {'t1': {'name': 'Khác hẳn', 'items': []}},
      );
      final plan = MenuCopy.buildPlan(source: src, target: target, noteKey: nk);
      expect(plan.updates.containsKey('note_groups/n1'), isFalse);
      expect((plan.updates['products/Trà A'] as Map)['noteGroupIds'], ['x9']);
      expect(plan.updates.containsKey('topping_groups/t1'), isFalse);
      expect(plan.updates['topping_groups/t1_2'], isNotNull);
      expect((plan.updates['categories/Trà'] as Map)['toppingGroupIds'], ['t1_2', 't2']);
    });

    test('nhóm món đã có ở đích: chỉ bổ sung phần gắn khi đích chưa có; tắt copyCatalog thì bỏ hết', () {
      final target = MenuSnapshot(categories: {'Trà': {'name': 'Trà'}});
      final plan = MenuCopy.buildPlan(source: src, target: target, noteKey: nk);
      expect(plan.updates['categories/Trà/noteGroupIds'], ['n1']);
      final off = MenuCopy.buildPlan(source: src, target: const MenuSnapshot(), options: const CopyOptions(copyCatalog: false), noteKey: nk);
      expect(off.groupsToAdd, 0);
      expect(off.updates.keys.any((k) => k.startsWith('note_groups') || k.startsWith('topping_groups')), isFalse);
      expect((off.updates['products/Trà A'] as Map).containsKey('noteGroupIds'), isFalse);
      expect((off.updates['categories/Trà'] as Map).containsKey('noteGroupIds'), isFalse);
    });
  });
}

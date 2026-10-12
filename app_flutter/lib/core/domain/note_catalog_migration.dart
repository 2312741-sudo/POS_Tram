// lib/core/domain/note_catalog_migration.dart
//
// "Nhập từ cấu hình cũ": dựng kế hoạch chuyển topping/ghi chú mẫu cũ sang danh mục note & topping mới
// — LOGIC THUẦN, idempotent, KHÔNG ghi gì (trả về các đường dẫn cần ghi).
// Bản song song: web/lib/note-catalog-migrate.ts và scripts/migrate_note_catalog/plan.js (giữ cùng quy tắc).
//
// Quy tắc:
//  1. Nhóm topping `legacy_toppings` = mọi món Topping (isTopping hoặc nhóm tên chứa "topping"); không có món nào -> bộ topping chuẩn.
//  2. Nhóm có allowedToppingIds -> nhóm topping riêng `legacy_cat_<khóa nhóm>` gắn vào nhóm đó.
//     Nhóm là đồ uống (trà/cà phê/sữa/nước...) mà chưa có allowedToppingIds -> gắn `legacy_toppings`.
//  3. Món có allowedToppings riêng (đã lưu trong DB) và nhóm của món không có allowedToppingIds -> nhóm theo bộ topping
//     `legacy_set_<hash>`, gắn vào món.
//  4. Ghi chú mẫu cũ (product_notes) -> nhóm note `legacy_notes` gắn vào các nhóm đồ uống. Bánh/đồ ăn không gắn gì.
//  5. Idempotent: nhóm đã tồn tại không bị ghi đè; trường gắn đã có (kể cả "không có") không bị đổi.

const List<Map<String, Object>> kLegacyDefaultToppings = [
  {'name': 'Trân châu đen', 'price': 5000},
  {'name': 'Trân châu trắng', 'price': 6000},
  {'name': 'Thạch phô mai', 'price': 8000},
  {'name': 'Thạch củ năng', 'price': 7000},
  {'name': 'Kem Cheese', 'price': 10000},
  {'name': 'Pudding trứng', 'price': 7000},
  {'name': 'Đào miếng', 'price': 8000},
  {'name': 'Thạch chanh', 'price': 5000},
];

const List<String> _drinkWords = [
  'trà', 'tea', 'cà phê', 'cafe', 'coffee', 'nước', 'uống', 'sinh tố', 'đá xay', 'sữa', 'matcha', 'bơ',
];

bool isDrinkCategoryName(String name) {
  final c = name.toLowerCase();
  return _drinkWords.any(c.contains);
}

/// djb2 32-bit trên mã UTF-16 (giống bản TS/JS)
String legacyHash(String s) {
  var h = 5381;
  for (final c in s.codeUnits) {
    h = ((h * 33) + c) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

String _sanitizeKey(String s) => s.replaceAll(RegExp(r'[.#$\[\]/\u0000-\u001f\u007f\s]+'), '_');

class NoteCatalogMigrationPlan {
  /// Đường dẫn ghi, tương đối theo stores/{s}
  final Map<String, Object?> updates;
  final List<String> summary;
  final int newNoteGroups;
  final int newToppingGroups;
  final int attachments;
  const NoteCatalogMigrationPlan(this.updates, this.summary, this.newNoteGroups, this.newToppingGroups, this.attachments);
  bool get isEmpty => updates.isEmpty;
}

Map<String, dynamic> _rec(dynamic v) {
  if (v is Map) return v.map((k, x) => MapEntry(k.toString(), x));
  if (v is List) {
    return {for (var i = 0; i < v.length; i++) if (v[i] != null) '$i': v[i]};
  }
  return <String, dynamic>{};
}

List<String> _strList(dynamic v) {
  if (v is List) return v.where((e) => e != null).map((e) => e.toString()).toList();
  if (v is Map) return v.values.map((e) => e.toString()).toList();
  return const [];
}

NoteCatalogMigrationPlan planNoteCatalogMigration({
  required dynamic products,
  required dynamic categories,
  required dynamic productNotes,
  required dynamic noteGroups,
  required dynamic toppingGroups,
}) {
  final prods = _rec(products);
  final cats = _rec(categories);
  final notes = _rec(productNotes);
  final existingNotes = _rec(noteGroups);
  final existingTops = _rec(toppingGroups);
  final updates = <String, Object?>{};
  final summary = <String>[];
  var newNote = 0, newTop = 0, attach = 0;

  String nameOf(Map<String, dynamic> p, String key) => (p['name']?.toString().trim().isNotEmpty ?? false) ? p['name'].toString().trim() : key;
  String catOf(dynamic p) => p is Map ? (p['category']?.toString().trim() ?? '') : '';

  // --- bảng giá topping từ món Topping
  final toppingProds = <Map<String, Object>>[];
  final priceByName = <String, int>{};
  final priceByRef = <String, int>{}; // id / mã -> giá
  final nameByRef = <String, String>{};
  final sortedKeys = prods.keys.toList()..sort();
  for (final k in sortedKeys) {
    final p = _rec(prods[k]);
    final name = nameOf(p, k);
    final price = (p['price'] as num?)?.toInt() ?? 0;
    final isTop = p['isTopping'] == true || catOf(p).toLowerCase().contains('topping');
    priceByName[name.toLowerCase()] = price;
    final id = p['id']?.toString();
    if (id != null && id.isNotEmpty) {
      priceByRef[id] = price;
      nameByRef[id] = name;
    }
    final code = p['code']?.toString();
    if (code != null && code.isNotEmpty) {
      priceByRef[code.toLowerCase()] = price;
      nameByRef[code.toLowerCase()] = name;
    }
    if (isTop) toppingProds.add({'name': name, 'price': price < 0 ? 0 : price});
  }
  for (final d in kLegacyDefaultToppings) {
    priceByName.putIfAbsent((d['name'] as String).toLowerCase(), () => d['price'] as int);
  }

  List<Map<String, Object>> itemsOf(List<Map<String, Object>> src) =>
      [for (var i = 0; i < src.length; i++) {'id': 't${i + 1}', 'name': src[i]['name']!, 'price': src[i]['price']!}];

  Map<String, Object> toppingGroup(String name, int order, List<Map<String, Object>> items) =>
      {'name': name, 'sortOrder': order, 'active': true, 'multi': true, 'max': 0, 'items': itemsOf(items)};

  Map<String, Object> resolveRef(String ref) {
    final r = ref.trim();
    final byRef = priceByRef[r] ?? priceByRef[r.toLowerCase()];
    if (byRef != null) return {'name': nameByRef[r] ?? nameByRef[r.toLowerCase()] ?? r, 'price': byRef};
    return {'name': r, 'price': priceByName[r.toLowerCase()] ?? 5000};
  }

  void addTopGroup(String id, Map<String, Object> g, String label) {
    if (existingTops.containsKey(id) || updates.containsKey('topping_groups/$id')) return;
    updates['topping_groups/$id'] = g;
    newTop++;
    summary.add('Nhóm topping "$label" (${(g['items'] as List).length} topping)');
  }

  // 1. nhóm topping chung
  final shared = toppingProds.isNotEmpty ? toppingProds : kLegacyDefaultToppings.map((e) => Map<String, Object>.from(e)).toList();
  final catKeys = cats.keys.toList()..sort();
  final needShared = catKeys.any((k) {
    final c = _rec(cats[k]);
    final cname = c['name']?.toString() ?? k;
    return _strList(c['allowedToppingIds']).isEmpty && c['toppingGroupIds'] == null && isDrinkCategoryName(cname);
  });
  if (needShared) addTopGroup('legacy_toppings', toppingGroup('Topping', 1, shared), 'Topping');

  // 4. nhóm note
  final noteKeys = notes.keys.toList()..sort();
  final noteItems = <Map<String, Object>>[];
  for (final k in noteKeys) {
    final v = notes[k];
    final text = (v is Map ? (v['text'] ?? v['name']) : v)?.toString().trim() ?? '';
    if (text.isNotEmpty) noteItems.add({'id': k, 'text': text});
  }
  var attachNotes = false;
  if (noteItems.isNotEmpty) {
    attachNotes = true;
    if (!existingNotes.containsKey('legacy_notes')) {
      updates['note_groups/legacy_notes'] = {'name': 'Ghi chú nhanh', 'sortOrder': 1, 'active': true, 'items': noteItems};
      newNote++;
      summary.add('Nhóm note "Ghi chú nhanh" (${noteItems.length} câu)');
    }
  }

  // 2. gắn theo nhóm món
  final catAllowed = <String, bool>{};
  for (final k in catKeys) {
    final c = _rec(cats[k]);
    final cname = (c['name']?.toString().trim().isNotEmpty ?? false) ? c['name'].toString().trim() : k;
    final allowed = _strList(c['allowedToppingIds']);
    catAllowed[cname.toLowerCase()] = allowed.isNotEmpty;
    final drink = isDrinkCategoryName(cname);
    if (c['toppingGroupIds'] == null) {
      if (allowed.isNotEmpty) {
        final gid = 'legacy_cat_${_sanitizeKey(k)}';
        final seen = <String>{};
        final items = [for (final a in allowed) resolveRef(a)].where((e) => seen.add((e['name'] as String).toLowerCase())).toList();
        addTopGroup(gid, toppingGroup('Topping - $cname', 2, items), 'Topping - $cname');
        updates['categories/$k/toppingGroupIds'] = [gid];
        attach++;
      } else if (drink) {
        updates['categories/$k/toppingGroupIds'] = ['legacy_toppings'];
        attach++;
      }
    }
    if (attachNotes && drink && c['noteGroupIds'] == null) {
      updates['categories/$k/noteGroupIds'] = ['legacy_notes'];
      attach++;
    }
  }

  // 3. gắn theo món (allowedToppings riêng)
  for (final k in sortedKeys) {
    final p = _rec(prods[k]);
    final own = _strList(p['allowedToppings']);
    if (own.isEmpty || p['toppingGroupIds'] != null) continue;
    if (catAllowed[catOf(p).toLowerCase()] == true) continue; // nhóm món đã có cấu hình topping riêng (ưu tiên như cũ)
    final seen = <String>{};
    final items = [for (final a in own) resolveRef(a)].where((e) => seen.add((e['name'] as String).toLowerCase())).toList();
    items.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    final gid = 'legacy_set_${legacyHash(items.map((e) => e['name']).join('|'))}';
    addTopGroup(gid, toppingGroup('Topping riêng (${items.map((e) => e['name']).take(2).join(', ')}...)', 3, items), gid);
    updates['products/$k/toppingGroupIds'] = [gid];
    attach++;
  }

  if (attach > 0) summary.add('Gắn danh mục vào $attach nhóm món/món');
  return NoteCatalogMigrationPlan(updates, summary, newNote, newTop, attach);
}

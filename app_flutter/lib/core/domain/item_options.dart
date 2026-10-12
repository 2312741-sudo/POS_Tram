// lib/core/domain/item_options.dart
//
// Danh mục note & topping gắn theo nhóm món / món — LOGIC THUẦN (không đụng Firebase).
// Bản TypeScript song song: web/lib/item-options.ts (giữ hai bản cùng quy tắc). Xem docs/NOTE_CATALOG.md.
//
// Dữ liệu mỗi chi nhánh:
//  - stores/{s}/note_groups/{id}    = {name, sortOrder, active, items:[{id,text}]}
//  - stores/{s}/topping_groups/{id} = {name, sortOrder, active, multi, max, items:[{id,name,price}]}
//  - categories/{nhóm}.noteGroupIds[] / .toppingGroupIds[] và cùng hai trường trên products/{món}.
//
// Quy tắc áp dụng:
//  - Món có trường (kể cả "không có") -> DÙNG CỦA MÓN (ghi đè). Món không có trường -> kế thừa nhóm món.
//    Nhóm món cũng không có -> KHÔNG có gì (chỉ còn ô ghi chú tự do).
//  - RTDB không lưu mảng rỗng nên "ghi đè = không có" được ghi là [kNoGroups] ('__none__').
//  - Chi nhánh CHƯA có note_groups lẫn topping_groups (chưa cấu hình) -> [legacy] = true: giữ cách hiển thị cũ.

/// Dấu "ghi đè = không áp dụng nhóm nào" (RTDB không lưu mảng rỗng).
const String kNoGroups = '__none__';

class NoteTemplate {
  final String id;
  final String text;
  const NoteTemplate({required this.id, required this.text});

  factory NoteTemplate.fromMap(dynamic v, [String fallbackId = '']) {
    if (v is String) return NoteTemplate(id: fallbackId, text: v);
    if (v is Map) {
      return NoteTemplate(
        id: v['id']?.toString() ?? fallbackId,
        text: (v['text'] ?? v['name'] ?? '').toString(),
      );
    }
    return NoteTemplate(id: fallbackId, text: '');
  }

  Map<String, dynamic> toMap() => {'id': id, 'text': text};
}

class NoteGroup {
  final String id;
  final String name;
  final int sortOrder;
  final bool active;
  final List<NoteTemplate> items;
  const NoteGroup({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.active = true,
    this.items = const [],
  });

  factory NoteGroup.fromMap(String id, dynamic v) {
    final m = v is Map ? v : const {};
    return NoteGroup(
      id: id,
      name: (m['name'] ?? id).toString(),
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      active: m['active'] != false,
      items: _listOf(m['items'])
          .asMap()
          .entries
          .map((e) => NoteTemplate.fromMap(e.value, '${e.key}'))
          .where((n) => n.text.trim().isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'sortOrder': sortOrder,
        'active': active,
        'items': items.map((e) => e.toMap()).toList(),
      };

  NoteGroup copyWith({String? name, int? sortOrder, bool? active, List<NoteTemplate>? items}) => NoteGroup(
        id: id,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        active: active ?? this.active,
        items: items ?? this.items,
      );
}

class ToppingItem {
  final String id;
  final String name;
  final int price;
  const ToppingItem({required this.id, required this.name, this.price = 0});

  factory ToppingItem.fromMap(dynamic v, [String fallbackId = '']) {
    final m = v is Map ? v : const {};
    final price = (m['price'] as num?)?.toInt() ?? 0;
    return ToppingItem(
      id: m['id']?.toString() ?? fallbackId,
      name: (m['name'] ?? '').toString(),
      price: price < 0 ? 0 : price,
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'price': price};
}

class ToppingGroup {
  final String id;
  final String name;
  final int sortOrder;
  final bool active;

  /// true = chọn nhiều topping trong nhóm; false = chỉ chọn một
  final bool multi;

  /// Số topping tối đa được chọn trong nhóm (0 = không giới hạn)
  final int max;
  final List<ToppingItem> items;
  const ToppingGroup({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.active = true,
    this.multi = true,
    this.max = 0,
    this.items = const [],
  });

  factory ToppingGroup.fromMap(String id, dynamic v) {
    final m = v is Map ? v : const {};
    final mx = (m['max'] as num?)?.toInt() ?? 0;
    return ToppingGroup(
      id: id,
      name: (m['name'] ?? id).toString(),
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      active: m['active'] != false,
      multi: m['multi'] != false,
      max: mx < 0 ? 0 : mx,
      items: _listOf(m['items'])
          .asMap()
          .entries
          .map((e) => ToppingItem.fromMap(e.value, '${e.key}'))
          .where((t) => t.name.trim().isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'sortOrder': sortOrder,
        'active': active,
        'multi': multi,
        'max': max,
        'items': items.map((e) => e.toMap()).toList(),
      };

  ToppingGroup copyWith({
    String? name,
    int? sortOrder,
    bool? active,
    bool? multi,
    int? max,
    List<ToppingItem>? items,
  }) =>
      ToppingGroup(
        id: id,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        active: active ?? this.active,
        multi: multi ?? this.multi,
        max: max ?? this.max,
        items: items ?? this.items,
      );
}

/// RTDB có thể trả mảng hoặc map {"0":..,"2":..} cho danh sách
List<dynamic> _listOf(dynamic v) {
  if (v is List) return v.where((e) => e != null).toList();
  if (v is Map) {
    final keys = v.keys.toList()..sort((a, b) => (int.tryParse('$a') ?? 1 << 30).compareTo(int.tryParse('$b') ?? 1 << 30));
    return keys.map((k) => v[k]).where((e) => e != null).toList();
  }
  return const [];
}

/// Đọc trường danh sách id nhóm: null = trường không tồn tại (kế thừa)
List<String>? parseGroupIds(dynamic v) {
  if (v == null) return null;
  final list = _listOf(v).map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  // Có trường nhưng rỗng (bộ nhớ) = ghi đè "không có"
  return list;
}

/// Chuẩn bị giá trị ghi lên RTDB: null = xóa trường (kế thừa); rỗng -> [kNoGroups].
dynamic encodeGroupIds(List<String>? ids) {
  if (ids == null) return null;
  final clean = ids.where((s) => s.isNotEmpty && s != kNoGroups).toList();
  return clean.isEmpty ? [kNoGroups] : clean;
}

/// Toàn bộ danh mục của chi nhánh
class ItemCatalog {
  final List<NoteGroup> noteGroups;
  final List<ToppingGroup> toppingGroups;
  const ItemCatalog({this.noteGroups = const [], this.toppingGroups = const []});

  /// Chưa cấu hình gì (kể cả nhóm đã tắt) -> hành vi cũ
  bool get isLegacy => noteGroups.isEmpty && toppingGroups.isEmpty;
}

enum OptionSource { product, category, none }

class ResolvedItemOptions {
  final List<NoteGroup> noteGroups;
  final List<ToppingGroup> toppingGroups;
  final bool legacy;
  final OptionSource noteSource;
  final OptionSource toppingSource;
  const ResolvedItemOptions({
    this.noteGroups = const [],
    this.toppingGroups = const [],
    this.legacy = false,
    this.noteSource = OptionSource.none,
    this.toppingSource = OptionSource.none,
  });

  /// Các câu note nhanh (đã bỏ trùng, giữ thứ tự)
  List<String> get noteChips {
    final seen = <String>{};
    final out = <String>[];
    for (final g in noteGroups) {
      for (final n in g.items) {
        final t = n.text.trim();
        if (t.isNotEmpty && seen.add(t.toLowerCase())) out.add(t);
      }
    }
    return out;
  }

  /// Tên topping -> đơn giá (nhóm đứng trước thắng khi trùng tên)
  Map<String, int> get toppingPrices {
    final out = <String, int>{};
    for (final g in toppingGroups) {
      for (final t in g.items) {
        out.putIfAbsent(t.name, () => t.price);
      }
    }
    return out;
  }
}

List<T> _pick<T>(List<String> ids, Map<String, T> byId) {
  final out = <T>[];
  final seen = <String>{};
  for (final id in ids) {
    final g = byId[id];
    if (g != null && seen.add(id)) out.add(g);
  }
  return out;
}

/// Quy tắc chọn trường: món có -> món; không thì nhóm món; không thì rỗng.
(List<String>, OptionSource) _effectiveIds(List<String>? productIds, List<String>? categoryIds) {
  if (productIds != null) return (productIds, OptionSource.product);
  if (categoryIds != null) return (categoryIds, OptionSource.category);
  return (const <String>[], OptionSource.none);
}

/// Hàm thuần: món + nhóm món + danh mục -> các nhóm note/topping được hiển thị.
ResolvedItemOptions resolveItemOptions({
  List<String>? productNoteGroupIds,
  List<String>? productToppingGroupIds,
  List<String>? categoryNoteGroupIds,
  List<String>? categoryToppingGroupIds,
  required ItemCatalog catalog,
}) {
  if (catalog.isLegacy) return const ResolvedItemOptions(legacy: true);
  final (noteIds, noteSrc) = _effectiveIds(productNoteGroupIds, categoryNoteGroupIds);
  final (topIds, topSrc) = _effectiveIds(productToppingGroupIds, categoryToppingGroupIds);
  final notesById = {for (final g in catalog.noteGroups.where((g) => g.active)) g.id: g};
  final topsById = {for (final g in catalog.toppingGroups.where((g) => g.active)) g.id: g};
  return ResolvedItemOptions(
    noteGroups: _pick(noteIds, notesById).where((g) => g.items.isNotEmpty).toList(),
    toppingGroups: _pick(topIds, topsById).where((g) => g.items.isNotEmpty).toList(),
    noteSource: noteSrc,
    toppingSource: topSrc,
  );
}

/// Bật/tắt một topping theo luật nhóm (chọn một / tối đa N). Trả danh sách mới, không sửa [selected].
List<String> toggleTopping({
  required List<String> selected,
  required ToppingGroup group,
  required String name,
}) {
  final next = List<String>.from(selected);
  if (next.contains(name)) {
    next.remove(name);
    return next;
  }
  final groupNames = group.items.map((t) => t.name).toSet();
  if (!group.multi) {
    next.removeWhere(groupNames.contains);
  } else if (group.max > 0) {
    final inGroup = next.where(groupNames.contains).length;
    if (inGroup >= group.max) return next; // đã đủ -> không thêm
  }
  next.add(name);
  return next;
}

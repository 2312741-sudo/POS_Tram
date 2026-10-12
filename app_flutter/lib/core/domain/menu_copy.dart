// lib/core/domain/menu_copy.dart
//
// Sao chép thực đơn giữa các chi nhánh — LOGIC THUẦN (không đụng Firebase).
// Bản TypeScript song song: web/lib/menu-copy.ts (giữ hai bản cùng quy tắc).
//
// Quy tắc cấp mã món ở chi nhánh đích (không bao giờ trùng):
//  - Đích CHƯA có món nào (preserveIds) -> giữ id/khóa nguồn khi còn trống.
//  - Ngược lại mỗi món mới nhận id = (id số lớn nhất ở đích + các id đã cấp) + 1.
//  - Ghi đè giữ nguyên khóa và id món đang có ở đích.
//  - [CopyPlan.idMap] (id nguồn -> id đích) để nối công thức/kho nếu cần.
// Không bao giờ xóa gì ở đích: kế hoạch chỉ gồm các đường dẫn ghi.

import 'item_options.dart' show kNoGroups;

/// Các trường trạng thái báo hết món — không sao chép sang chi nhánh khác.
const List<String> soldOutFields = ['soldOutAt', 'soldOutBy', 'soldOutUntil'];

enum ConflictPolicy { skip, overwrite, duplicate }

enum ProductAction { create, overwrite, skip, duplicate }

class MenuSnapshot {
  final Map<String, dynamic> products;
  final Map<String, dynamic> categories;
  final Map<String, dynamic> notes;

  /// Danh mục note & topping (note_groups / topping_groups)
  final Map<String, dynamic> noteGroups;
  final Map<String, dynamic> toppingGroups;
  const MenuSnapshot({
    this.products = const {},
    this.categories = const {},
    this.notes = const {},
    this.noteGroups = const {},
    this.toppingGroups = const {},
  });
}

class CopyOptions {
  final bool copyCategories;
  final bool copyOptions;
  final bool copyNotes;

  /// Sao chép danh mục note/topping và phần gắn vào nhóm món / món (đổi lại id nhóm ở đích)
  final bool copyCatalog;
  final bool copyImages;
  final ConflictPolicy conflict;

  /// null = chỉ giữ id nguồn khi đích chưa có món nào
  final bool? preserveIds;
  final String duplicateSuffix;

  const CopyOptions({
    this.copyCategories = true,
    this.copyOptions = true,
    this.copyNotes = true,
    this.copyCatalog = true,
    this.copyImages = true,
    this.conflict = ConflictPolicy.skip,
    this.preserveIds,
    this.duplicateSuffix = ' (bản sao)',
  });
}

class CopySelection {
  /// true hoặc không chọn gì = tất cả món
  final bool all;
  final List<String> categories;
  final List<String> productKeys;
  const CopySelection({this.all = false, this.categories = const [], this.productKeys = const []});
  static const everything = CopySelection(all: true);
}

class ProductOp {
  final ProductAction action;
  final String sourceKey;
  final int? sourceId;
  final String name;
  final String category;
  final String? targetKey;
  final int? targetId;
  final String? reason;
  const ProductOp({
    required this.action,
    required this.sourceKey,
    required this.sourceId,
    required this.name,
    required this.category,
    required this.targetKey,
    required this.targetId,
    this.reason,
  });
}

class CategoryOp {
  final String name;
  final bool create;
  const CategoryOp(this.name, {required this.create});
}

class CopyPlan {
  final List<ProductOp> productOps;
  final List<CategoryOp> categoryOps;
  final int notesToAdd;

  /// Số nhóm note/topping được thêm ở đích
  final int groupsToAdd;

  /// Đường dẫn ghi, tương đối theo stores/{đích}
  final Map<String, Object?> updates;
  final Map<int, int> idMap;

  const CopyPlan({
    required this.productOps,
    required this.categoryOps,
    required this.notesToAdd,
    this.groupsToAdd = 0,
    required this.updates,
    required this.idMap,
  });

  int _count(ProductAction a) => productOps.where((p) => p.action == a).length;
  int get created => _count(ProductAction.create);
  int get overwritten => _count(ProductAction.overwrite);
  int get skipped => _count(ProductAction.skip);
  int get duplicated => _count(ProductAction.duplicate);
  int get categoriesCreated => categoryOps.where((c) => c.create).length;

  /// Số món thực sự ghi (tạo + bản sao + ghi đè)
  int get copiedCount => created + duplicated + overwritten;
}

class MenuCopy {
  MenuCopy._();

  static const _imageFields = ['imageBase64', 'imageResourceName', 'imageUrl', 'image'];
  static const _optionFields = ['sizes', 'allowedToppings', 'hasIceSugarOptions'];

  static const String _accented =
      'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  static final String _plain =
      '${'a' * 17}${'e' * 11}${'i' * 5}${'o' * 17}${'u' * 11}${'y' * 5}d';
  static final Map<String, String> _fold = {
    for (var i = 0; i < _accented.length; i++) _accented[i]: _plain[i],
  };

  /// Chuẩn hóa tên để so khớp: bỏ dấu tiếng Việt, đ->d, thường hóa, gộp khoảng trắng/ký tự lạ.
  static String normalizeName(Object? s) {
    final lower = (s?.toString() ?? '').toLowerCase().replaceAll(RegExp('[̀-ͯ]'), '');
    final sb = StringBuffer();
    for (final ch in lower.split('')) {
      sb.write(_fold[ch] ?? ch);
    }
    return sb.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  /// Khóa RTDB hợp lệ (cấm . # $ [ ] / và ký tự điều khiển) — cùng cách khóa món của POS.
  static String sanitizeKey(String s) =>
      s.replaceAll(RegExp(r'[.#$\[\]/\u0000-\u001f\u007f]'), '_').trim();

  static Map<String, dynamic> toRecord(Object? v) {
    if (v is List) {
      final out = <String, dynamic>{};
      for (var i = 0; i < v.length; i++) {
        if (v[i] != null) out['$i'] = v[i];
      }
      return out;
    }
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return <String, dynamic>{};
  }

  static int? _positiveInt(Object? v) {
    if (v is num && v == v.toInt() && v > 0) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v.trim());
      if (n != null && n > 0) return n;
    }
    return null;
  }

  static Map<String, dynamic>? _obj(Object? v) => v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : null;

  static String _productName(Object? node, String key) {
    final m = _obj(node);
    final n = m?['name']?.toString().trim() ?? '';
    return n.isNotEmpty ? n : key;
  }

  static String _productCategory(Object? node) => _obj(node)?['category']?.toString().trim() ?? '';

  static String _categoryName(Object? node, String key) {
    if (node is String) return node.trim().isEmpty ? key : node.trim();
    final n = _obj(node)?['name']?.toString().trim() ?? '';
    return n.isNotEmpty ? n : key;
  }

  static String _noteText(Object? node) {
    if (node is String) return node.trim();
    final m = _obj(node);
    if (m == null) return '';
    return (m['text'] ?? m['name'] ?? '').toString().trim();
  }

  static bool matchesSelection(CopySelection sel, String key, Object? node) {
    if (sel.all || (sel.categories.isEmpty && sel.productKeys.isEmpty)) return true;
    if (sel.productKeys.contains(key)) return true;
    if (sel.categories.isNotEmpty) {
      final cat = normalizeName(_productCategory(node));
      return sel.categories.any((c) => normalizeName(c) == cat);
    }
    return false;
  }

  static CopyPlan buildPlan({
    required MenuSnapshot source,
    required MenuSnapshot target,
    CopySelection selection = CopySelection.everything,
    CopyOptions options = const CopyOptions(),
    String Function(int index)? noteKey,
  }) {
    final srcProducts = toRecord(source.products);
    final tgtProducts = toRecord(target.products);
    final srcCats = toRecord(source.categories);
    final tgtCats = toRecord(target.categories);
    final preserveIds = options.preserveIds ?? tgtProducts.isEmpty;
    final suffix = options.duplicateSuffix;

    final usedKeys = tgtProducts.keys.toSet();
    final usedIds = <int>{};
    var maxId = 0;
    tgtProducts.forEach((k, node) {
      for (final n in [_positiveInt(_obj(node)?['id']), _positiveInt(k)]) {
        if (n != null) {
          usedIds.add(n);
          if (n > maxId) maxId = n;
        }
      }
    });
    int allocId() {
      var n = maxId + 1;
      while (usedIds.contains(n)) {
        n++;
      }
      maxId = n;
      usedIds.add(n);
      return n;
    }

    final tgtCatByNorm = <String, String>{};
    tgtCats.forEach((k, node) => tgtCatByNorm[normalizeName(_categoryName(node, k))] = _categoryName(node, k));
    for (final node in tgtProducts.values) {
      final c = _productCategory(node);
      if (c.isNotEmpty) tgtCatByNorm.putIfAbsent(normalizeName(c), () => c);
    }
    final srcCatByNorm = <String, MapEntry<String, Object?>>{};
    srcCats.forEach((k, node) => srcCatByNorm[normalizeName(_categoryName(node, k))] = MapEntry(_categoryName(node, k), node));

    final tgtByIdentity = <String, String>{};
    tgtProducts.forEach((k, node) {
      tgtByIdentity.putIfAbsent('${normalizeName(_productName(node, k))}|${normalizeName(_productCategory(node))}', () => k);
    });

    final updates = <String, Object?>{};

    // --- Danh mục note & topping: gộp theo tên (không ghi đè nhóm có sẵn), nhóm mới giữ id nguồn nếu còn trống
    var groupsToAdd = 0;
    Map<String, String> planGroups(String node, Map<String, dynamic> src, Map<String, dynamic> tgt) {
      final map = <String, String>{};
      if (!options.copyCatalog) return map;
      final used = tgt.keys.toSet();
      final byName = <String, String>{};
      tgt.forEach((k, v) => byName.putIfAbsent(normalizeName(_obj(v)?['name'] ?? k), () => k));
      final keys = src.keys.toList()..sort();
      for (final k in keys) {
        final v = _obj(src[k]);
        if (v == null) continue;
        final norm = normalizeName(v['name'] ?? k);
        final hit = byName[norm];
        if (hit != null) {
          map[k] = hit;
          continue;
        }
        var id = sanitizeKey(k);
        if (id.isEmpty) id = 'group';
        var n = 1;
        while (used.contains(id)) {
          n++;
          id = '${sanitizeKey(k)}_$n';
        }
        used.add(id);
        byName[norm] = id;
        map[k] = id;
        updates['$node/$id'] = v;
        groupsToAdd++;
      }
      return map;
    }

    final noteGroupMap = planGroups('note_groups', toRecord(source.noteGroups), toRecord(target.noteGroups));
    final toppingGroupMap = planGroups('topping_groups', toRecord(source.toppingGroups), toRecord(target.toppingGroups));

    /// Đổi id nhóm nguồn -> đích; null = không có trường. Id nguồn không còn tồn tại = bỏ; hết sạch -> "không có".
    List<String>? remapGroupIds(Object? raw, Map<String, String> map) {
      if (raw == null || !options.copyCatalog) return null;
      final ids = raw is List ? raw.map((e) => e.toString()).toList() : (raw is Map ? raw.values.map((e) => e.toString()).toList() : <String>[]);
      if (ids.isEmpty) return null;
      final out = <String>[];
      for (final i in ids) {
        final m = i == kNoGroups ? null : map[i];
        if (m != null && !out.contains(m)) out.add(m);
      }
      return out.isEmpty ? [kNoGroups] : out;
    }

    final tgtCatKeyByNorm = <String, String>{};
    tgtCats.forEach((k, node) => tgtCatKeyByNorm[normalizeName(_categoryName(node, k))] = k);

    final idMap = <int, int>{};
    final productOps = <ProductOp>[];
    final categoryOps = <CategoryOp>[];
    final seenIdentity = <String>{};

    String ensureCategory(String srcCatName) {
      if (srcCatName.isEmpty) return '';
      final norm = normalizeName(srcCatName);
      final existing = tgtCatByNorm[norm];
      if (existing != null) {
        if (!categoryOps.any((c) => normalizeName(c.name) == norm)) {
          categoryOps.add(CategoryOp(existing, create: false));
          // Nhóm món có sẵn ở đích: chỉ bổ sung phần gắn note/topping nếu ở đích chưa có
          final tKey = tgtCatKeyByNorm[norm];
          final tNode = tKey == null ? null : _obj(tgtCats[tKey]);
          final sNode = _obj(srcCatByNorm[norm]?.value);
          if (tKey != null && tNode != null && sNode != null) {
            final n = remapGroupIds(sNode['noteGroupIds'], noteGroupMap);
            final t = remapGroupIds(sNode['toppingGroupIds'], toppingGroupMap);
            if (n != null && tNode['noteGroupIds'] == null) updates['categories/${sanitizeKey(tKey)}/noteGroupIds'] = n;
            if (t != null && tNode['toppingGroupIds'] == null) updates['categories/${sanitizeKey(tKey)}/toppingGroupIds'] = t;
          }
        }
        return existing;
      }
      if (!options.copyCategories) return srcCatName;
      final srcNode = srcCatByNorm[norm];
      final name = srcNode?.key ?? srcCatName;
      final payload = <String, Object?>{'name': name};
      final allowed = _obj(srcNode?.value)?['allowedToppingIds'];
      if (allowed != null) payload['allowedToppingIds'] = allowed;
      final cn = remapGroupIds(_obj(srcNode?.value)?['noteGroupIds'], noteGroupMap);
      final ct = remapGroupIds(_obj(srcNode?.value)?['toppingGroupIds'], toppingGroupMap);
      if (cn != null) payload['noteGroupIds'] = cn;
      if (ct != null) payload['toppingGroupIds'] = ct;
      updates['categories/${sanitizeKey(name)}'] = payload;
      tgtCatByNorm[norm] = name;
      categoryOps.add(CategoryOp(name, create: true));
      return name;
    }

    final entries = srcProducts.entries
        .where((e) => _obj(e.value) != null && matchesSelection(selection, e.key, e.value))
        .toList()
      ..sort((a, b) => _productName(a.value, a.key).toLowerCase().compareTo(_productName(b.value, b.key).toLowerCase()));

    Map<String, Object?> buildPayload(Map<String, dynamic> node, String name, String category, int targetId) {
      final out = <String, Object?>{...node};
      out.remove('storeCode');
      out.remove('storeName');
      if (!options.copyImages) {
        for (final f in _imageFields) {
          out.remove(f);
        }
      }
      if (!options.copyOptions) {
        for (final f in _optionFields) {
          out.remove(f);
        }
      }
      out['id'] = targetId;
      out['name'] = name;
      out['category'] = category;
      // Phần gắn note/topping: đổi sang id nhóm ở đích (không sao chép danh mục thì bỏ hẳn, vì id vô nghĩa ở đích)
      for (final f in const ['noteGroupIds', 'toppingGroupIds']) {
        final mapped = remapGroupIds(node[f], f == 'noteGroupIds' ? noteGroupMap : toppingGroupMap);
        if (mapped == null) {
          out.remove(f);
        } else {
          out[f] = mapped;
        }
      }
      // Món sao chép luôn ở trạng thái còn bán: bỏ trạng thái "báo hết" của chi nhánh nguồn.
      out['isAvailable'] = true;
      for (final f in soldOutFields) {
        out.remove(f);
      }
      return out;
    }

    for (final e in entries) {
      final key = e.key;
      final node = _obj(e.value)!;
      final name = _productName(node, key);
      final srcCat = _productCategory(node);
      final sourceId = _positiveInt(node['id']) ?? _positiveInt(key);
      final identityNorm = '${normalizeName(name)}|${normalizeName(srcCat)}';
      final mappedCat = srcCat.isEmpty ? null : tgtCatByNorm[normalizeName(srcCat)];
      final identity = '${normalizeName(name)}|${normalizeName(mappedCat ?? srcCat)}';
      final existingKey = tgtByIdentity[identity] ?? tgtByIdentity[identityNorm];

      ProductOp op(ProductAction a, String? tk, int? tid, {String? reason}) => ProductOp(
            action: a, sourceKey: key, sourceId: sourceId, name: name, category: srcCat, targetKey: tk, targetId: tid, reason: reason);

      if (!seenIdentity.add(identity)) {
        productOps.add(op(ProductAction.skip, null, null, reason: 'Trùng món khác trong danh sách chọn'));
        continue;
      }

      if (existingKey != null && options.conflict == ConflictPolicy.skip) {
        final tNode = _obj(tgtProducts[existingKey]);
        productOps.add(op(ProductAction.skip, existingKey, _positiveInt(tNode?['id']) ?? _positiveInt(existingKey),
            reason: 'Đã có ở chi nhánh đích'));
        continue;
      }

      if (existingKey != null && options.conflict == ConflictPolicy.overwrite) {
        final tNode = _obj(tgtProducts[existingKey]);
        final tId = _positiveInt(tNode?['id']) ?? _positiveInt(existingKey) ?? allocId();
        final cat = ensureCategory(srcCat);
        final tName = (tNode?['name']?.toString().isNotEmpty ?? false) ? tNode!['name'].toString() : name;
        buildPayload(node, tName, cat, tId).forEach((f, v) {
          if (v != null) updates['products/$existingKey/$f'] = v;
        });
        // Xóa dấu vết "báo hết" còn sót ở món đích (null = xóa trường trong update đa đường dẫn).
        for (final f in soldOutFields) {
          updates['products/$existingKey/$f'] = null;
        }
        if (sourceId != null) idMap[sourceId] = tId;
        productOps.add(op(ProductAction.overwrite, existingKey, tId));
        continue;
      }

      final isDup = existingKey != null;
      var finalName = name;
      if (isDup) {
        bool taken(String c) => tgtByIdentity.containsKey('${normalizeName(c)}|${normalizeName(mappedCat ?? srcCat)}');
        var n = 1;
        finalName = '$name$suffix';
        while (taken(finalName)) {
          n++;
          finalName = '$name${suffix.replaceAll(RegExp(r'\)$'), '')} $n)';
        }
      }
      final cat = ensureCategory(srcCat);

      int targetId;
      if (preserveIds && !isDup && sourceId != null && !usedIds.contains(sourceId)) {
        targetId = sourceId;
        usedIds.add(sourceId);
        if (sourceId > maxId) maxId = sourceId;
      } else {
        targetId = allocId();
      }

      String targetKey;
      if (isDup) {
        targetKey = sanitizeKey(finalName);
      } else if (_positiveInt(key) != null) {
        targetKey = '$targetId';
      } else {
        targetKey = sanitizeKey(key).isNotEmpty ? sanitizeKey(key) : sanitizeKey(finalName);
      }
      if (targetKey.isEmpty || usedKeys.contains(targetKey)) {
        final base = targetKey.isEmpty ? (sanitizeKey(finalName).isEmpty ? 'mon' : sanitizeKey(finalName)) : targetKey;
        final alt = '${base}_$targetId';
        targetKey = usedKeys.contains(alt) ? '${alt}_${usedKeys.length}' : alt;
      }
      usedKeys.add(targetKey);
      tgtByIdentity['${normalizeName(finalName)}|${normalizeName(cat)}'] = targetKey;

      final payload = buildPayload(node, finalName, cat, targetId);
      if (isDup && (payload['code']?.toString().isNotEmpty ?? false)) payload['code'] = '';
      payload.removeWhere((_, v) => v == null);
      updates['products/$targetKey'] = payload;
      if (sourceId != null) idMap[sourceId] = targetId;
      productOps.add(op(isDup ? ProductAction.duplicate : ProductAction.create, targetKey, targetId));
    }

    var notesToAdd = 0;
    if (options.copyNotes) {
      final existing = toRecord(target.notes);
      final have = existing.values.map((n) => normalizeName(_noteText(n))).toSet();
      final usedNoteKeys = existing.keys.toSet();
      final gen = noteKey ?? ((int i) => 'note_${DateTime.now().millisecondsSinceEpoch}_$i');
      var i = 0;
      for (final n in toRecord(source.notes).values) {
        final text = _noteText(n);
        if (text.isEmpty || !have.add(normalizeName(text))) continue;
        var k = gen(i++);
        while (usedNoteKeys.contains(k)) {
          k = gen(i++);
        }
        usedNoteKeys.add(k);
        updates['product_notes/${sanitizeKey(k)}'] = {'text': text};
        notesToAdd++;
      }
    }

    return CopyPlan(
      productOps: productOps,
      categoryOps: categoryOps,
      notesToAdd: notesToAdd,
      groupsToAdd: groupsToAdd,
      updates: updates,
      idMap: idMap,
    );
  }

  /// Chia các đường dẫn thành lô <= [maxPaths].
  static List<Map<String, Object?>> chunkUpdates(Map<String, Object?> updates, {int maxPaths = 400}) {
    final keys = updates.keys.toList();
    final step = maxPaths < 1 ? 1 : maxPaths;
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < keys.length; i += step) {
      out.add({for (final k in keys.skip(i).take(step)) k: updates[k]});
    }
    return out;
  }

  /// Bản ghi nhật ký COPY_MENU cho chi nhánh đích (khớp rules audit_logs).
  static Map<String, Object?> auditEntry({
    required String sourceStore,
    required String targetStore,
    required int created,
    required int overwritten,
    required int skipped,
    required String username,
    String fullName = '',
    String role = '',
    required int now,
    bool failed = false,
  }) =>
      {
        'timestamp': now,
        'action': 'COPY_MENU',
        'targetType': 'MENU',
        'targetId': targetStore,
        'username': username.isEmpty ? 'unknown' : username,
        'userFullName': fullName,
        'userRole': role,
        'details': 'Sao chép ${created + overwritten} món từ $sourceStore sang $targetStore${failed ? ' (có lỗi, chưa hoàn tất)' : ''}',
        'sourceStore': sourceStore,
        'targetStore': targetStore,
        'created': created,
        'overwritten': overwritten,
        'skipped': skipped,
      };

  /// Ai được sao chép thực đơn: Chủ / Quản lý (khớp rules) VÀ có quyền sửa thực đơn.
  /// Khi mã quyền COPY_MENU vào danh mục quyền chỉ cần đổi hàm này.
  static bool canCopyMenu({required bool isOwnerOrManager, required bool canEditMenu}) => isOwnerOrManager && canEditMenu;
}

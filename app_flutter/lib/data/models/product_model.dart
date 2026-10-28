import '../../core/domain/item_options.dart';

// ==================== PRODUCT MODEL (KIOTVIET FNB) ====================
class ProductModel {
  final int id;
  final String name;
  final String code; // Mã món KiotViet SKU
  final int price;
  final int? costPrice;
  final String unit;
  final String category;
  final String? imageBase64;
  final String? imageResourceName;
  final bool isAvailable;
  // Báo hết món (bếp/nhân viên): thời điểm báo, người báo, và mốc tự bật lại (epoch ms).
  final int? soldOutAt;
  final String? soldOutBy;
  final int? soldOutUntil;
  /// Khóa nút products/{dbKey} thật trong RTDB (Flutter: tên món; món tạo từ web: push id). Không ghi ngược.
  final String? dbKey;
  final Map<String, int> sizes; // Ví dụ: {'M': 0, 'L': 5000}
  final List<String> allowedToppings; // Danh sách topping được phép thêm
  final bool hasIceSugarOptions; // Hỗ trợ chọn % đá, đường
  final bool isTopping; // Cờ đánh dấu món là Topping
  // Danh mục note/topping áp dụng cho món: null = kế thừa nhóm món; [] = ghi đè "không có" (xem item_options.dart)
  final List<String>? noteGroupIds;
  final List<String>? toppingGroupIds;

  ProductModel({
    this.id = 0,
    required this.name,
    this.code = '',
    required this.price,
    this.costPrice,
    required this.unit,
    required this.category,
    this.imageBase64,
    this.imageResourceName,
    this.isAvailable = true,
    this.soldOutAt,
    this.soldOutBy,
    this.soldOutUntil,
    this.dbKey,
    this.sizes = const {},
    this.allowedToppings = const [],
    this.hasIceSugarOptions = false,
    this.isTopping = false,
    this.noteGroupIds,
    this.toppingGroupIds,
  });

  String? get assetPath {
    if (imageResourceName == null || imageResourceName!.trim().isEmpty) {
      return null;
    }
    final res = imageResourceName!.trim();
    if (res.startsWith('assets/')) {
      return res;
    }
    if (res.contains('.')) {
      return 'assets/images/products/$res';
    }
    return 'assets/images/products/$res.jpg';
  }

  bool get hasImage =>
      (imageBase64 != null && imageBase64!.trim().isNotEmpty) ||
      (imageResourceName != null && imageResourceName!.trim().isNotEmpty);

  static int _stablePositiveHash(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return 0;
    int h = 0;
    for (int i = 0; i < trimmed.length; i++) {
      h = ((h * 31) + trimmed.codeUnitAt(i)) & 0x3fffffff;
    }
    return h == 0 ? 1 : h;
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is num) return v.isNaN || v.isInfinite ? null : v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s) ?? num.tryParse(s)?.toInt();
  }

  /// Mã số định danh ổn định để làm khóa Map<int, ProductModel> ngay cả khi món tạo từ Web chưa có id nguyên dương.
  int get effectiveId {
    if (id > 0) return id;
    if (dbKey != null && dbKey!.trim().isNotEmpty) return _stablePositiveHash(dbKey!);
    if (code.trim().isNotEmpty) return _stablePositiveHash(code);
    if (name.trim().isNotEmpty) return _stablePositiveHash(name);
    return 0;
  }

  factory ProductModel.fromMap(dynamic val, [String? key]) {
    if (val is Map) {
      final map = Map<dynamic, dynamic>.from(val);
      Map<String, int> sizesMap = {};
      if (map['sizes'] is Map) {
        (map['sizes'] as Map).forEach((k, v) {
          sizesMap[k.toString()] = _asInt(v) ?? 0;
        });
      }
      List<String> toppings = [];
      if (map['allowedToppings'] is List) {
        toppings = (map['allowedToppings'] as List).where((e) => e != null).map((e) => e.toString()).toList();
      } else if (map['allowedToppings'] is Map) {
        toppings = (map['allowedToppings'] as Map).values.where((e) => e != null).map((e) => e.toString()).toList();
      }

      final cat = map['category']?.toString() ?? 'Khác';
      final isDrink = cat.contains('Trà') || cat.contains('CAFE') || cat.contains('Sữa') || cat.contains('Bơ');
      if (sizesMap.isEmpty && isDrink) {
        sizesMap = {'S': 0, 'M': 5000, 'L': 10000};
      }
      if (toppings.isEmpty && isDrink) {
        toppings = ['Trân châu đen', 'Trân châu trắng', 'Thạch phô mai', 'Kem Cheese'];
      }
      final bool hasIceSugar = map['hasIceSugarOptions'] == true || (map['hasIceSugarOptions'] == null && isDrink);
      final bool isTop = map['isTopping'] == true || cat.toLowerCase().contains('topping') || cat.toLowerCase() == 'topping';

      final rawId = map['id'];
      int resolvedId = _asInt(rawId) ?? 0;
      if (resolvedId <= 0 && rawId != null && rawId.toString().trim().isNotEmpty && rawId.toString().trim() != '0') {
        resolvedId = _stablePositiveHash(rawId.toString());
      }

      return ProductModel(
        id: resolvedId,
        name: map['name']?.toString() ?? key ?? '',
        code: map['code']?.toString() ?? '',
        price: _asInt(map['price']) ?? 0,
        costPrice: _asInt(map['costPrice']),
        unit: map['unit']?.toString() ?? 'Phần',
        category: cat,
        imageBase64: map['imageBase64']?.toString(),
        imageResourceName: map['imageResourceName']?.toString(),
        isAvailable: map['isAvailable'] != false,
        soldOutAt: _asInt(map['soldOutAt']),
        soldOutBy: map['soldOutBy']?.toString(),
        soldOutUntil: _asInt(map['soldOutUntil']),
        dbKey: key,
        sizes: sizesMap,
        allowedToppings: toppings,
        hasIceSugarOptions: hasIceSugar,
        isTopping: isTop,
        noteGroupIds: parseGroupIds(map['noteGroupIds']),
        toppingGroupIds: parseGroupIds(map['toppingGroupIds']),
      );
    }
    return ProductModel(name: key ?? '', price: 0, unit: 'Phần', category: 'Khác');
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'code': code,
    'price': price,
    if (costPrice != null) 'costPrice': costPrice,
    'unit': unit,
    'category': category,
    'imageBase64': imageBase64,
    'imageResourceName': imageResourceName,
    'isAvailable': isAvailable,
    if (soldOutAt != null) 'soldOutAt': soldOutAt,
    if (soldOutBy != null) 'soldOutBy': soldOutBy,
    if (soldOutUntil != null) 'soldOutUntil': soldOutUntil,
    if (sizes.isNotEmpty) 'sizes': sizes,
    if (allowedToppings.isNotEmpty) 'allowedToppings': allowedToppings,
    'hasIceSugarOptions': hasIceSugarOptions,
    'isTopping': isTopping,
    if (noteGroupIds != null) 'noteGroupIds': encodeGroupIds(noteGroupIds),
    if (toppingGroupIds != null) 'toppingGroupIds': encodeGroupIds(toppingGroupIds),
  };

  ProductModel copyWith({
    int? id,
    String? name,
    String? code,
    int? price,
    int? costPrice,
    String? unit,
    String? category,
    String? imageBase64,
    String? imageResourceName,
    bool? isAvailable,
    int? soldOutAt,
    String? soldOutBy,
    int? soldOutUntil,
    String? dbKey,
    Map<String, int>? sizes,
    List<String>? allowedToppings,
    bool? hasIceSugarOptions,
    bool? isTopping,
    List<String>? noteGroupIds,
    List<String>? toppingGroupIds,
    bool clearNoteGroupIds = false,
    bool clearToppingGroupIds = false,
  }) => ProductModel(
    id: id ?? this.id,
    name: name ?? this.name,
    code: code ?? this.code,
    price: price ?? this.price,
    costPrice: costPrice ?? this.costPrice,
    unit: unit ?? this.unit,
    category: category ?? this.category,
    imageBase64: imageBase64 ?? this.imageBase64,
    imageResourceName: imageResourceName ?? this.imageResourceName,
    isAvailable: isAvailable ?? this.isAvailable,
    soldOutAt: soldOutAt ?? this.soldOutAt,
    soldOutBy: soldOutBy ?? this.soldOutBy,
    soldOutUntil: soldOutUntil ?? this.soldOutUntil,
    dbKey: dbKey ?? this.dbKey,
    sizes: sizes ?? this.sizes,
    allowedToppings: allowedToppings ?? this.allowedToppings,
    hasIceSugarOptions: hasIceSugarOptions ?? this.hasIceSugarOptions,
    isTopping: isTopping ?? this.isTopping,
    noteGroupIds: clearNoteGroupIds ? null : (noteGroupIds ?? this.noteGroupIds),
    toppingGroupIds: clearToppingGroupIds ? null : (toppingGroupIds ?? this.toppingGroupIds),
  );

  static String stripAccents(String str) {
    var result = str;
    const from =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const to =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    for (int i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result;
  }

  /// Kiểm tra xem món này có khớp với [target] (ID số, Tên món, Mã SKU, hoặc RTDB Key).
  bool matchesTarget(String target) {
    final t = target.trim().toLowerCase();
    if (t.isEmpty) return false;
    if (id.toString() == t) return true;
    if (name.trim().toLowerCase() == t) return true;
    if (code.trim().toLowerCase() == t) return true;
    if (dbKey != null && dbKey!.trim().toLowerCase() == t) return true;
    final tAscii = stripAccents(t);
    if (stripAccents(name.trim().toLowerCase()) == tAscii) return true;
    return false;
  }

  /// Kiểm tra xem món này có khớp với bất kỳ mục nào trong [targets].
  bool matchesAnyTarget(Iterable<String> targets) {
    return targets.any((t) => matchesTarget(t));
  }
}

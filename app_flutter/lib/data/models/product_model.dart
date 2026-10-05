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
  final Map<String, int> sizes; // Ví dụ: {'M': 0, 'L': 5000}
  final List<String> allowedToppings; // Danh sách topping được phép thêm
  final bool hasIceSugarOptions; // Hỗ trợ chọn % đá, đường

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
    this.sizes = const {},
    this.allowedToppings = const [],
    this.hasIceSugarOptions = false,
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

  factory ProductModel.fromMap(dynamic val, [String? key]) {
    if (val is Map) {
      final map = Map<dynamic, dynamic>.from(val);
      Map<String, int> sizesMap = {};
      if (map['sizes'] is Map) {
        (map['sizes'] as Map).forEach((k, v) {
          sizesMap[k.toString()] = (v as num?)?.toInt() ?? 0;
        });
      }
      List<String> toppings = [];
      if (map['allowedToppings'] is List) {
        toppings = List<String>.from(map['allowedToppings']);
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

      return ProductModel(
        id: (map['id'] as num?)?.toInt() ?? 0,
        name: map['name']?.toString() ?? key ?? '',
        code: map['code']?.toString() ?? '',
        price: (map['price'] as num?)?.toInt() ?? 0,
        costPrice: (map['costPrice'] as num?)?.toInt(),
        unit: map['unit']?.toString() ?? 'Phần',
        category: cat,
        imageBase64: map['imageBase64']?.toString(),
        imageResourceName: map['imageResourceName']?.toString(),
        isAvailable: map['isAvailable'] ?? true,
        sizes: sizesMap,
        allowedToppings: toppings,
        hasIceSugarOptions: hasIceSugar,
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
    if (sizes.isNotEmpty) 'sizes': sizes,
    if (allowedToppings.isNotEmpty) 'allowedToppings': allowedToppings,
    'hasIceSugarOptions': hasIceSugarOptions,
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
    Map<String, int>? sizes,
    List<String>? allowedToppings,
    bool? hasIceSugarOptions,
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
    sizes: sizes ?? this.sizes,
    allowedToppings: allowedToppings ?? this.allowedToppings,
    hasIceSugarOptions: hasIceSugarOptions ?? this.hasIceSugarOptions,
  );
}

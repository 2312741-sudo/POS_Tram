// ==================== ORDER ITEM MODEL (KIOTVIET FNB) ====================
class OrderItemModel {
  final int productId;
  final String name;
  final int price;
  int quantity;
  String note;
  bool isSentKitchen;
  int discountAmount;

  // Thuộc tính KiotViet FnB (Size, Đường, Đá, Topping)
  String selectedSize;
  int sizeExtraPrice;
  String selectedSugar;
  String selectedIce;
  List<String> selectedToppings;
  int toppingPrice;

  // Người nhận order món này (Phục vụ / Waiter)
  String orderedBy; // username
  String orderedByName; // Họ tên nhân viên nhận order món
  int? orderedAt; // Thời điểm nhận order món

  OrderItemModel({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.note = '',
    this.isSentKitchen = false,
    this.discountAmount = 0,
    this.selectedSize = '',
    this.sizeExtraPrice = 0,
    this.selectedSugar = '',
    this.selectedIce = '',
    this.selectedToppings = const [],
    this.toppingPrice = 0,
    this.orderedBy = '',
    this.orderedByName = '',
    this.orderedAt,
  });

  factory OrderItemModel.fromMap(Map<dynamic, dynamic> map) {
    List<String> toppings = [];
    if (map['selectedToppings'] is List) {
      toppings = List<String>.from(map['selectedToppings']);
    }

    return OrderItemModel(
      productId: (map['productId'] as num?)?.toInt() ?? (map['id'] as num?)?.toInt() ?? 0,
      name: map['name']?.toString() ?? '',
      price: (map['price'] as num?)?.toInt() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      note: map['note']?.toString() ?? '',
      isSentKitchen: map['isSentKitchen'] == true,
      discountAmount: (map['discountAmount'] as num?)?.toInt() ?? 0,
      selectedSize: map['selectedSize']?.toString() ?? '',
      sizeExtraPrice: (map['sizeExtraPrice'] as num?)?.toInt() ?? 0,
      selectedSugar: map['selectedSugar']?.toString() ?? '',
      selectedIce: map['selectedIce']?.toString() ?? '',
      selectedToppings: toppings,
      toppingPrice: (map['toppingPrice'] as num?)?.toInt() ?? 0,
      orderedBy: map['orderedBy']?.toString() ?? '',
      orderedByName: map['orderedByName']?.toString() ?? '',
      orderedAt: (map['orderedAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'name': name,
    'price': price,
    'quantity': quantity,
    'note': note,
    'isSentKitchen': isSentKitchen,
    'discountAmount': discountAmount,
    if (selectedSize.isNotEmpty) 'selectedSize': selectedSize,
    if (sizeExtraPrice > 0) 'sizeExtraPrice': sizeExtraPrice,
    if (selectedSugar.isNotEmpty) 'selectedSugar': selectedSugar,
    if (selectedIce.isNotEmpty) 'selectedIce': selectedIce,
    if (selectedToppings.isNotEmpty) 'selectedToppings': selectedToppings,
    if (toppingPrice > 0) 'toppingPrice': toppingPrice,
    if (orderedBy.isNotEmpty) 'orderedBy': orderedBy,
    if (orderedByName.isNotEmpty) 'orderedByName': orderedByName,
    if (orderedAt != null) 'orderedAt': orderedAt,
  };

  /// Đơn giá một phần bao gồm Size và Toppings
  int get unitPrice => price + sizeExtraPrice + toppingPrice;

  /// Tổng tiền của dòng món
  int get itemTotal => (unitPrice * quantity) - discountAmount;

  /// Mô tả ngắn các thuộc tính (VD: "Size L • 50% Đường • Ít Đá • Trân Châu Trắng")
  String get optionsSummary {
    final List<String> parts = [];
    if (selectedSize.isNotEmpty) parts.add('Size $selectedSize');
    if (selectedSugar.isNotEmpty) parts.add(selectedSugar);
    if (selectedIce.isNotEmpty) parts.add(selectedIce);
    if (selectedToppings.isNotEmpty) parts.addAll(selectedToppings);
    return parts.join(' • ');
  }

  OrderItemModel copyWith({
    int? quantity,
    String? note,
    bool? isSentKitchen,
    int? discountAmount,
    String? selectedSize,
    int? sizeExtraPrice,
    String? selectedSugar,
    String? selectedIce,
    List<String>? selectedToppings,
    int? toppingPrice,
    String? orderedBy,
    String? orderedByName,
    int? orderedAt,
  }) => OrderItemModel(
    productId: productId,
    name: name,
    price: price,
    quantity: quantity ?? this.quantity,
    note: note ?? this.note,
    isSentKitchen: isSentKitchen ?? this.isSentKitchen,
    discountAmount: discountAmount ?? this.discountAmount,
    selectedSize: selectedSize ?? this.selectedSize,
    sizeExtraPrice: sizeExtraPrice ?? this.sizeExtraPrice,
    selectedSugar: selectedSugar ?? this.selectedSugar,
    selectedIce: selectedIce ?? this.selectedIce,
    selectedToppings: selectedToppings ?? this.selectedToppings,
    toppingPrice: toppingPrice ?? this.toppingPrice,
    orderedBy: orderedBy ?? this.orderedBy,
    orderedByName: orderedByName ?? this.orderedByName,
    orderedAt: orderedAt ?? this.orderedAt,
  );
}

// ==================== ORDER ITEM MODEL (KIOTVIET FNB) ====================
//
// GIẢM GIÁ THEO MÓN (line discount) — giảm theo TỪNG PHẦN được chọn:
// - `discountedQuantity` (0..quantity): số phần trong dòng được giảm
//   (VD: 5 ly A, chỉ giảm 2 ly).
// - Chế độ giảm cho MỖI phần được giảm:
//     PERCENT: `discountPercent` % trên đơn giá (đã gồm size + topping)
//     AMOUNT : `discountUnitAmount` đ / phần
// - Tổng giảm của dòng = round(unitPrice × % × discountedQuantity / 100)
//   hoặc min(discountUnitAmount, unitPrice) × discountedQuantity,
//   luôn bị chặn trong [0, unitPrice × quantity].
// - Tổng giảm của dòng được LƯU TƯỜNG MINH: `lineDiscountTotal` (trường mới)
//   và `discountAmount` (giữ cùng giá trị cho client cũ — client cũ coi
//   discountAmount là giảm giá CẢ DÒNG).
//
// DỮ LIỆU CŨ (không có `discountedQuantity`): `discountAmount` luôn là giảm
// giá CẢ DÒNG (app Flutter cũ: % → round(tiền dòng × %); số tiền → nhập thẳng
// số tiền giảm cho cả dòng). Khi đọc lại: lineDiscountTotal = discountAmount,
// discountedQuantity = quantity (nếu có giảm), KHÔNG tính lại → tổng tiền đã
// thu giữ nguyên. Dòng cũ giảm theo số tiền (không có đơn giá giảm/phần) được
// coi là chế độ FIXED: số tiền cố định cho cả dòng.
class OrderItemModel {
  final int productId;
  final String name;
  final int price;
  int quantity;
  String note;
  bool isSentKitchen;

  /// Tổng tiền giảm của CẢ DÒNG (đã lưu, nguồn sự thật khi đọc lại hóa đơn).
  /// Ghi ra RTDB dưới cả `discountAmount` và `lineDiscountTotal`.
  int discountAmount;

  /// % giảm cho mỗi phần được giảm (chế độ PERCENT)
  int discountPercent;

  /// Số tiền giảm cho mỗi phần được giảm (chế độ AMOUNT)
  int discountUnitAmount;

  /// Số phần trong dòng được giảm giá (0..quantity)
  int discountedQuantity;
  String discountReason;

  // Người duyệt giảm giá dòng bằng PIN quản lý (verifyManagerPin) — khớp web
  // withApprovalMeta. Rỗng/null khi nhân viên tự có quyền DISCOUNT_ITEM.
  String discountApprovedBy; // uid người duyệt
  String discountApprovedByName;
  String discountApprovalId;
  int? discountApprovedAt;

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
    this.discountPercent = 0,
    this.discountUnitAmount = 0,
    int? discountedQuantity,
    this.discountReason = '',
    this.discountApprovedBy = '',
    this.discountApprovedByName = '',
    this.discountApprovalId = '',
    this.discountApprovedAt,
    this.selectedSize = '',
    this.sizeExtraPrice = 0,
    this.selectedSugar = '',
    this.selectedIce = '',
    this.selectedToppings = const [],
    this.toppingPrice = 0,
    this.orderedBy = '',
    this.orderedByName = '',
    this.orderedAt,
  }) : discountedQuantity = (discountedQuantity ??
                ((discountAmount > 0 || discountPercent > 0 || discountUnitAmount > 0) ? quantity : 0))
            .clamp(0, quantity < 0 ? 0 : quantity);

  factory OrderItemModel.fromMap(Map<dynamic, dynamic> map) {
    List<String> toppings = [];
    if (map['selectedToppings'] is List) {
      toppings = List<String>.from(map['selectedToppings']);
    }

    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
    final quantity = asInt(map['quantity']) ?? 1;
    // Ưu tiên tổng giảm đã lưu tường minh; dữ liệu cũ: discountAmount = giảm CẢ DÒNG.
    final storedLineDiscount = asInt(map['lineDiscountTotal']) ?? asInt(map['discountAmount']) ?? 0;
    final percent = asInt(map['discountPercent']) ?? 0;
    final unitAmount = asInt(map['discountUnitAmount']) ?? 0;
    // Dòng cũ không có discountedQuantity: coi như giảm toàn bộ các phần (nếu có giảm).
    final dq = asInt(map['discountedQuantity']) ??
        ((storedLineDiscount > 0 || percent > 0 || unitAmount > 0) ? quantity : 0);

    return OrderItemModel(
      productId: (map['productId'] as num?)?.toInt() ?? (map['id'] as num?)?.toInt() ?? 0,
      name: map['name']?.toString() ?? '',
      price: (map['price'] as num?)?.toInt() ?? 0,
      quantity: quantity,
      note: map['note']?.toString() ?? '',
      isSentKitchen: map['isSentKitchen'] == true,
      discountAmount: storedLineDiscount,
      discountPercent: percent,
      discountUnitAmount: unitAmount,
      discountedQuantity: dq,
      discountReason: map['discountReason']?.toString() ?? '',
      discountApprovedBy: map['discountApprovedBy']?.toString() ?? '',
      discountApprovedByName: map['discountApprovedByName']?.toString() ?? '',
      discountApprovalId: map['discountApprovalId']?.toString() ?? '',
      discountApprovedAt: asInt(map['discountApprovedAt']),
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
    // discountAmount = lineDiscountTotal = tổng giảm CẢ DÒNG (xem chú thích đầu file)
    'discountAmount': lineDiscountTotal,
    'lineDiscountTotal': lineDiscountTotal,
    'discountedQuantity': discountedQuantity,
    if (discountPercent > 0) 'discountPercent': discountPercent,
    if (discountUnitAmount > 0) 'discountUnitAmount': discountUnitAmount,
    if (discountReason.isNotEmpty) 'discountReason': discountReason,
    if (hasDiscount && discountApprovedBy.isNotEmpty) 'discountApprovedBy': discountApprovedBy,
    if (hasDiscount && discountApprovedByName.isNotEmpty) 'discountApprovedByName': discountApprovedByName,
    if (hasDiscount && discountApprovalId.isNotEmpty) 'discountApprovalId': discountApprovalId,
    if (hasDiscount && discountApprovedAt != null) 'discountApprovedAt': discountApprovedAt,
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

  /// Tiền gốc của dòng (chưa giảm)
  int get lineGross => unitPrice * quantity;

  /// Tổng tiền giảm của dòng, luôn nằm trong [0, lineGross]
  int get lineDiscountTotal {
    final gross = lineGross < 0 ? 0 : lineGross;
    return discountAmount.clamp(0, gross);
  }

  /// Tổng tiền của dòng món (sau giảm giá món)
  int get itemTotal => lineGross - lineDiscountTotal;

  /// Chế độ giảm giá dòng: NONE | PERCENT | AMOUNT | FIXED (dữ liệu cũ: số tiền cố định cả dòng)
  String get discountMode {
    if (discountPercent > 0) return 'PERCENT';
    if (discountUnitAmount > 0) return 'AMOUNT';
    if (discountAmount > 0) return 'FIXED';
    return 'NONE';
  }

  bool get hasDiscount => lineDiscountTotal > 0;

  /// Tính tổng giảm của dòng theo số phần được giảm (hàm thuần, dùng chung app/test).
  static int computeLineDiscount({
    required int unitPrice,
    required int quantity,
    required int discountedQuantity,
    int percent = 0,
    int unitAmount = 0,
  }) {
    if (quantity <= 0 || unitPrice <= 0) return 0;
    final gross = unitPrice * quantity;
    final dq = discountedQuantity.clamp(0, quantity);
    int d = 0;
    if (percent > 0) {
      d = ((unitPrice * percent.clamp(0, 100) * dq) / 100).round();
    } else if (unitAmount > 0) {
      d = unitAmount.clamp(0, unitPrice) * dq;
    }
    return d.clamp(0, gross);
  }

  /// Tổng giảm tính lại từ cấu hình hiện tại. Chế độ FIXED (dữ liệu cũ) giữ
  /// số tiền đã lưu, chỉ chặn trên theo tiền dòng.
  int get recomputedLineDiscount {
    switch (discountMode) {
      case 'PERCENT':
      case 'AMOUNT':
        return computeLineDiscount(
          unitPrice: unitPrice,
          quantity: quantity,
          discountedQuantity: discountedQuantity,
          percent: discountPercent,
          unitAmount: discountUnitAmount,
        );
      case 'FIXED':
        // Giữ số tiền đã lưu; lineDiscountTotal sẽ chặn theo tiền dòng hiện tại.
        return discountAmount;
      default:
        return 0;
    }
  }

  /// Áp dụng giảm giá dòng mới: [percent] (%/phần) hoặc [unitAmount] (đ/phần)
  /// cho [discountedQuantity] phần. Trả về bản sao đã tính lại tổng giảm.
  OrderItemModel withLineDiscount({
    int percent = 0,
    int unitAmount = 0,
    required int discountedQuantity,
    String reason = '',
    String approvedBy = '',
    String approvedByName = '',
    String approvalId = '',
    int? approvedAt,
  }) {
    final pct = percent.clamp(0, 100);
    final amt = pct > 0 ? 0 : (unitAmount < 0 ? 0 : unitAmount);
    final dq = (pct > 0 || amt > 0) ? discountedQuantity.clamp(0, quantity) : 0;
    final next = copyWith(
      discountPercent: pct,
      discountUnitAmount: amt,
      discountedQuantity: dq,
      discountReason: (pct > 0 || amt > 0) && dq > 0 ? reason : '',
      discountAmount: 0,
      discountApprovedBy: approvedBy,
      discountApprovedByName: approvedByName,
      discountApprovalId: approvalId,
      discountApprovedAt: approvedAt,
      clearApproval: approvedAt == null,
    );
    next.discountAmount = next.recomputedLineDiscount;
    if (next.discountAmount == 0) {
      next.discountPercent = 0;
      next.discountUnitAmount = 0;
      next.discountedQuantity = 0;
      next.discountReason = '';
      next.clearApprovalMeta();
    }
    return next;
  }

  /// Bỏ giảm giá dòng
  OrderItemModel withoutLineDiscount() => copyWith(
        discountAmount: 0,
        discountPercent: 0,
        discountUnitAmount: 0,
        discountedQuantity: 0,
        discountReason: '',
        clearApproval: true,
      );

  /// Xóa thông tin người duyệt giảm giá
  void clearApprovalMeta() {
    discountApprovedBy = '';
    discountApprovedByName = '';
    discountApprovalId = '';
    discountApprovedAt = null;
  }

  /// Tách [takeQty] phần ra khỏi dòng (tách hóa đơn). Các phần được giảm được
  /// chia sang phần tách trước; tổng giảm 2 phần cộng lại đúng bằng tổng giảm cũ.
  /// Trả về (phần tách, phần còn lại) — phần nào có số lượng 0 thì là null.
  (OrderItemModel?, OrderItemModel?) splitQuantity(int takeQty) {
    final take = takeQty.clamp(0, quantity);
    final rest = quantity - take;
    if (take == 0) return (null, copyWith());
    if (rest == 0) return (copyWith(), null);
    final total = lineDiscountTotal;
    final takeDq = discountedQuantity.clamp(0, take);
    final restDq = (discountedQuantity - takeDq).clamp(0, rest);
    int takeDiscount;
    if (discountMode == 'FIXED') {
      takeDiscount = (total * take) ~/ quantity;
    } else if (discountedQuantity <= 0) {
      takeDiscount = 0;
    } else {
      takeDiscount = computeLineDiscount(
        unitPrice: unitPrice,
        quantity: take,
        discountedQuantity: takeDq,
        percent: discountPercent,
        unitAmount: discountUnitAmount,
      ).clamp(0, total);
    }
    final a = copyWith(quantity: take, discountedQuantity: takeDq, discountAmount: takeDiscount);
    final b = copyWith(quantity: rest, discountedQuantity: restDq, discountAmount: total - takeDiscount);
    return (a, b);
  }

  /// Mô tả giảm giá dòng, VD: "Giảm 10% × 2/5 món", "Giảm 5.000 đ × 2/5 món",
  /// "Giảm 10.000 đ" (dữ liệu cũ, cả dòng). [fmt] định dạng tiền.
  String discountDescription(String Function(int) fmt) {
    if (!hasDiscount) return '';
    final part = discountedQuantity < quantity ? ' × $discountedQuantity/$quantity món' : (quantity > 1 ? ' × $quantity món' : '');
    switch (discountMode) {
      case 'PERCENT':
        return 'Giảm $discountPercent%$part';
      case 'AMOUNT':
        return 'Giảm ${fmt(discountUnitAmount)}$part';
      default:
        return 'Giảm ${fmt(lineDiscountTotal)}';
    }
  }

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
    int? discountPercent,
    int? discountUnitAmount,
    int? discountedQuantity,
    String? discountReason,
    String? discountApprovedBy,
    String? discountApprovedByName,
    String? discountApprovalId,
    int? discountApprovedAt,
    bool clearApproval = false,
    String? selectedSize,
    int? sizeExtraPrice,
    String? selectedSugar,
    String? selectedIce,
    List<String>? selectedToppings,
    int? toppingPrice,
    String? orderedBy,
    String? orderedByName,
    int? orderedAt,
  }) {
    final nextQty = quantity ?? this.quantity;
    final next = OrderItemModel(
      productId: productId,
      name: name,
      price: price,
      quantity: nextQty,
      note: note ?? this.note,
      isSentKitchen: isSentKitchen ?? this.isSentKitchen,
      discountAmount: discountAmount ?? this.discountAmount,
      discountPercent: discountPercent ?? this.discountPercent,
      discountUnitAmount: discountUnitAmount ?? this.discountUnitAmount,
      // Đổi số lượng dòng: số phần được giảm bị chặn trong [0, số lượng mới].
      // Tăng số lượng KHÔNG tự giảm cho phần mới (giảm giá cần quản lý duyệt).
      discountedQuantity: (discountedQuantity ?? this.discountedQuantity).clamp(0, nextQty < 0 ? 0 : nextQty),
      discountReason: discountReason ?? this.discountReason,
      discountApprovedBy: discountApprovedBy ?? (clearApproval ? '' : this.discountApprovedBy),
      discountApprovedByName: discountApprovedByName ?? (clearApproval ? '' : this.discountApprovedByName),
      discountApprovalId: discountApprovalId ?? (clearApproval ? '' : this.discountApprovalId),
      discountApprovedAt: discountApprovedAt ?? (clearApproval ? null : this.discountApprovedAt),
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
    // Số lượng / đơn giá / cấu hình giảm thay đổi mà không truyền tổng giảm
    // tường minh → tính lại tổng giảm của dòng.
    final pricingChanged = (quantity != null && quantity != this.quantity) ||
        (sizeExtraPrice != null && sizeExtraPrice != this.sizeExtraPrice) ||
        (toppingPrice != null && toppingPrice != this.toppingPrice) ||
        (discountPercent != null && discountPercent != this.discountPercent) ||
        (discountUnitAmount != null && discountUnitAmount != this.discountUnitAmount) ||
        (discountedQuantity != null && discountedQuantity != this.discountedQuantity);
    if (discountAmount == null && pricingChanged) {
      next.discountAmount = next.recomputedLineDiscount;
    }
    return next;
  }
}

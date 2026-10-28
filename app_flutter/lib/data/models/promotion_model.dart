import 'order_item_model.dart';

// ==================== PROMOTION & DISCOUNT MODELS ====================
enum PromotionType {
  percentBill, // Giảm % trên tổng hóa đơn
  fixedBill,   // Giảm số tiền cố định (VND) trên hóa đơn
  percentItem, // Giảm % trên món nhất định
  fixedItem,   // Giảm tiền cố định trên món
  voucherCode, // Nhập code giảm giá
}

class PromotionModel {
  final String id;
  final String code; // Mã voucher (nếu có)
  final String name;
  final String description;
  final String type; // PERCENT_BILL, FIXED_BILL, PERCENT_ITEM, FIXED_ITEM, VOUCHER
  final int value;   // % hoặc số tiền VND
  final int maxDiscountAmount; // Giới hạn tiền giảm tối đa (nếu tính theo %)
  final int minBillAmount;     // Hóa đơn tối thiểu để áp dụng
  final String? targetCategory; // Áp dụng cho danh mục nào
  final int? targetProductId;   // Áp dụng cho món nào
  final List<String> includedItemIds; // Món áp dụng
  final List<String> includedGroupIds; // Nhóm món áp dụng
  final int startDate;
  final int endDate;
  final bool isActive;
  final int usageCount;
  final int maxUsage; // Giới hạn số lần dùng toàn hệ thống
  final bool requireStaffNote; // Bắt buộc nhân viên nhập ghi chú khi dùng mã

  PromotionModel({
    required this.id,
    this.code = '',
    required this.name,
    this.description = '',
    required this.type,
    required this.value,
    this.maxDiscountAmount = 0,
    this.minBillAmount = 0,
    this.targetCategory,
    this.targetProductId,
    this.includedItemIds = const [],
    this.includedGroupIds = const [],
    required this.startDate,
    required this.endDate,
    this.isActive = true,
    this.usageCount = 0,
    this.maxUsage = 0,
    this.requireStaffNote = false,
  });

  factory PromotionModel.fromMap(Map<dynamic, dynamic> map, String id) {
    int? asInt(Object? v) {
      if (v == null) return null;
      if (v is num) return v.isNaN || v.isInfinite ? null : v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return int.tryParse(s) ?? num.tryParse(s)?.toInt();
    }

    List<String> asStringList(Object? v) {
      if (v is List) return v.where((e) => e != null).map((e) => e.toString()).toList();
      if (v is Map) return v.values.where((e) => e != null).map((e) => e.toString()).toList();
      return const [];
    }

    return PromotionModel(
      id: id,
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      type: map['type']?.toString() ?? 'PERCENT_BILL',
      value: asInt(map['value']) ?? 0,
      maxDiscountAmount: asInt(map['maxDiscountAmount']) ?? 0,
      minBillAmount: asInt(map['minBillAmount']) ?? 0,
      targetCategory: map['targetCategory']?.toString(),
      targetProductId: asInt(map['targetProductId']),
      includedItemIds: asStringList(map['includedItemIds']),
      includedGroupIds: asStringList(map['includedGroupIds']),
      startDate: asInt(map['startDate']) ?? 0,
      endDate: asInt(map['endDate']) ?? 0,
      isActive: map['isActive'] != false,
      usageCount: asInt(map['usageCount']) ?? 0,
      maxUsage: asInt(map['maxUsage']) ?? 0,
      requireStaffNote: map['requireStaffNote'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'description': description,
    'type': type,
    'value': value,
    'maxDiscountAmount': maxDiscountAmount,
    'minBillAmount': minBillAmount,
    if (targetCategory != null) 'targetCategory': targetCategory,
    if (targetProductId != null) 'targetProductId': targetProductId,
    if (includedItemIds.isNotEmpty) 'includedItemIds': includedItemIds,
    if (includedGroupIds.isNotEmpty) 'includedGroupIds': includedGroupIds,
    'startDate': startDate,
    'endDate': endDate,
    'isActive': isActive,
    'usageCount': usageCount,
    'maxUsage': maxUsage,
    'requireStaffNote': requireStaffNote,
  };

  PromotionModel copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? type,
    int? value,
    int? maxDiscountAmount,
    int? minBillAmount,
    String? targetCategory,
    int? targetProductId,
    List<String>? includedItemIds,
    List<String>? includedGroupIds,
    int? startDate,
    int? endDate,
    bool? isActive,
    int? usageCount,
    int? maxUsage,
    bool? requireStaffNote,
  }) {
    return PromotionModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      value: value ?? this.value,
      maxDiscountAmount: maxDiscountAmount ?? this.maxDiscountAmount,
      minBillAmount: minBillAmount ?? this.minBillAmount,
      targetCategory: targetCategory ?? this.targetCategory,
      targetProductId: targetProductId ?? this.targetProductId,
      includedItemIds: includedItemIds ?? this.includedItemIds,
      includedGroupIds: includedGroupIds ?? this.includedGroupIds,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      usageCount: usageCount ?? this.usageCount,
      maxUsage: maxUsage ?? this.maxUsage,
      requireStaffNote: requireStaffNote ?? this.requireStaffNote,
    );
  }

  /// Kiểm tra khuyến mãi có đang còn hiệu lực hay không
  bool isValid(int subTotal) {
    if (!isActive) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (startDate > 0 && now < startDate) return false;
    if (endDate > 0) {
      var end = endDate;
      final endDt = DateTime.fromMillisecondsSinceEpoch(end, isUtc: true).add(const Duration(hours: 7));
      if (endDt.hour == 0 && endDt.minute == 0 && endDt.second == 0 && endDt.millisecond == 0) {
        end += 86399999;
      }
      if (now > end) return false;
    }
    if (maxUsage > 0 && usageCount >= maxUsage) return false;
    if (minBillAmount > 0 && subTotal < minBillAmount) return false;
    return true;
  }

  /// Tính số tiền giảm giá thực tế cho hóa đơn
  int calculateDiscount(int subTotal, List<OrderItemModel> items) {
    if (!isValid(subTotal)) return 0;

    switch (type) {
      case 'PERCENT_BILL':
      case 'VOUCHER':
        int discount = (subTotal * value / 100).round();
        if (maxDiscountAmount > 0 && discount > maxDiscountAmount) {
          discount = maxDiscountAmount;
        }
        return discount;

      case 'FIXED_BILL':
        return value > subTotal ? subTotal : value;

      case 'PERCENT_ITEM':
        int targetSubtotal = 0;
        for (final item in items) {
          if (targetProductId != null && item.productId == targetProductId) {
            targetSubtotal += item.price * item.quantity;
          }
        }
        int discount = (targetSubtotal * value / 100).round();
        if (maxDiscountAmount > 0 && discount > maxDiscountAmount) {
          discount = maxDiscountAmount;
        }
        return discount;

      case 'FIXED_ITEM':
        int count = 0;
        for (final item in items) {
          if (targetProductId != null && item.productId == targetProductId) {
            count += item.quantity;
          }
        }
        return count * value;

      default:
        return 0;
    }
  }

  String get typeDisplay {
    switch (type) {
      case 'PERCENT_BILL': return 'Giảm % hóa đơn';
      case 'FIXED_BILL': return 'Giảm tiền mặt hóa đơn';
      case 'PERCENT_ITEM': return 'Giảm % theo món';
      case 'FIXED_ITEM': return 'Giảm tiền theo món';
      case 'VOUCHER': return 'Mã voucher';
      default: return type;
    }
  }
}

class BillDiscountModel {
  final String? promoId;
  final String? promoCode;
  final String description;
  final int amount;
  final String? staffNote;

  // Thông tin chương trình khuyến mãi (CampaignModel) - dùng cho báo cáo.
  // promoId/promoCode giữ nguyên để tương thích dữ liệu cũ.
  final String? campaignId;
  final String? campaignName;
  final String? programCode;
  final String? campaignType;
  final String? voucherCode;
  final int? comboCount; // Số lượng combo được hưởng (ví dụ: 1 bánh + 1 nước = 1 combo, 3 bánh = 3 combo)

  BillDiscountModel({
    this.promoId,
    this.promoCode,
    required this.description,
    required this.amount,
    this.staffNote,
    this.campaignId,
    this.campaignName,
    this.programCode,
    this.campaignType,
    this.voucherCode,
    this.comboCount,
  });

  factory BillDiscountModel.fromMap(Map<dynamic, dynamic> map) {
    String? str(String k) {
      final v = map[k]?.toString();
      return (v == null || v.isEmpty) ? null : v;
    }

    int? asInt(Object? v) {
      if (v == null) return null;
      if (v is num) return v.isNaN || v.isInfinite ? null : v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return int.tryParse(s) ?? num.tryParse(s)?.toInt();
    }

    return BillDiscountModel(
      promoId: map['promoId']?.toString(),
      promoCode: map['promoCode']?.toString(),
      description: map['description']?.toString() ?? '',
      amount: asInt(map['amount']) ?? 0,
      staffNote: map['staffNote']?.toString(),
      campaignId: str('campaignId'),
      campaignName: str('campaignName'),
      programCode: str('programCode'),
      campaignType: str('campaignType'),
      voucherCode: str('voucherCode'),
      comboCount: asInt(map['comboCount']),
    );
  }

  Map<String, dynamic> toMap() => {
    if (promoId != null) 'promoId': promoId,
    if (promoCode != null) 'promoCode': promoCode,
    'description': description,
    'amount': amount,
    if (staffNote != null) 'staffNote': staffNote,
    if (campaignId != null) 'campaignId': campaignId,
    if (campaignName != null) 'campaignName': campaignName,
    if (programCode != null) 'programCode': programCode,
    if (campaignType != null) 'campaignType': campaignType,
    if (voucherCode != null) 'voucherCode': voucherCode,
    if (comboCount != null && comboCount! > 0) 'comboCount': comboCount,
  };

  BillDiscountModel copyWith({
    int? amount,
    String? description,
    String? campaignName,
    int? comboCount,
  }) => BillDiscountModel(
        promoId: promoId,
        promoCode: promoCode,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        staffNote: staffNote,
        campaignId: campaignId,
        campaignName: campaignName ?? this.campaignName,
        programCode: programCode,
        campaignType: campaignType,
        voucherCode: voucherCode,
        comboCount: comboCount ?? this.comboCount,
      );
}

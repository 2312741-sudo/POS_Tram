import '../../core/domain/business_day.dart';
import 'customer_model.dart';

// ==================== STORE INFO MODEL ====================
class StoreInfoModel {
  final String storeCode;
  final String storeName;
  final String address;
  final String phone;
  final String wifiName;
  final String bankId;
  final String bankAccount;
  final String accountName;
  final bool allowStackPromotions;
  final double defaultVatRate;
  final String kitchenPrinterIp;
  final String billPrinterIp;
  final String printerType; // 'LAN' or 'BLUETOOTH'
  final bool allowStaffViewShiftDifference; // Bật/tắt cho phép nhân viên xem chênh lệch tiền két khi kết ca
  final bool autoPrintBill; // Bật/tắt tự động in bill khi thanh toán
  final String ownerId;
  final int pointRedeemRate; // Tỷ lệ quy đổi điểm ra tiền chiết khấu (VD: 1.000đ/điểm)
  final double pointEarnRate; // Tỷ lệ tích điểm % trên doanh thu thực (VD: 1.0%)
  // Chỉ đọc trên POS: Chủ quán đặt trên Web Admin; KHÔNG đưa vào toMap() để update() không ghi đè
  final List<LoyaltyTier> loyaltyTiers;
  final bool sharedLoyaltyEnabled;
  // Giờ bắt đầu ngày kinh doanh (phút từ 0h). KHÔNG đưa vào toMap(): chỉ ghi qua màn Cài đặt cửa hàng
  // (saveBusinessDayStart) để các nơi khác gọi saveStoreInfo không vô tình ghi đè về 0.
  final int businessDayStartMinute;
  // Chỉ để hiển thị — do máy chủ ghi khi liên kết Chấm Công Trạm; KHÔNG đưa vào toMap()
  final String chamCongStoreId;
  final String chamCongStoreName;
  // KHÔNG còn managerPin: PIN duyệt quản lý lưu băm phía máy chủ (manager_pins/…),
  // rules từ chối ghi storeInfo/managerPin.

  StoreInfoModel({
    required this.storeCode,
    required this.storeName,
    this.ownerId = '',
    this.address = '',
    this.phone = '',
    this.wifiName = '',
    this.bankId = 'MB',
    this.bankAccount = '0987654321',
    this.accountName = 'NGUYEN THANH TAM',
    this.allowStackPromotions = true,
    this.defaultVatRate = 0.0,
    this.kitchenPrinterIp = '192.168.1.200',
    this.billPrinterIp = '192.168.1.201',
    this.printerType = 'LAN',
    this.allowStaffViewShiftDifference = true,
    this.autoPrintBill = true,
    this.pointRedeemRate = 1000,
    this.pointEarnRate = 1.0,
    this.loyaltyTiers = LoyaltyTier.defaults,
    this.sharedLoyaltyEnabled = false,
    this.businessDayStartMinute = 0,
    this.chamCongStoreId = '',
    this.chamCongStoreName = '',
  });

  bool get isChamCongLinked => chamCongStoreId.isNotEmpty;

  factory StoreInfoModel.fromMap(Map<dynamic, dynamic> map, String storeCode) {
    int? asInt(Object? v) {
      if (v == null) return null;
      if (v is num) return v.isNaN || v.isInfinite ? null : v.toInt();
      return int.tryParse(v.toString().trim()) ?? num.tryParse(v.toString().trim())?.toInt();
    }

    double? asDouble(Object? v) {
      if (v == null) return null;
      if (v is num) return v.isNaN || v.isInfinite ? null : v.toDouble();
      return double.tryParse(v.toString().trim());
    }

    final rawVat = asDouble(map['defaultVatRate']) ?? 0.0;
    return StoreInfoModel(
      storeCode: map['storeCode']?.toString() ?? storeCode,
      storeName: map['storeName']?.toString() ?? 'POS Trạm',
      ownerId: map['ownerId']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      wifiName: map['wifiName']?.toString() ?? '',
      bankId: map['bankId']?.toString() ?? 'MB',
      bankAccount: map['bankAccount']?.toString() ?? '0987654321',
      accountName: map['accountName']?.toString() ?? 'CHU CUA HANG',
      allowStackPromotions: map['allowStackPromotions'] != false,
      defaultVatRate: rawVat == 8.0 ? 0.0 : rawVat,
      kitchenPrinterIp: map['kitchenPrinterIp']?.toString() ?? '192.168.1.200',
      billPrinterIp: map['billPrinterIp']?.toString() ?? '192.168.1.201',
      printerType: map['printerType']?.toString() ?? 'LAN',
      allowStaffViewShiftDifference: map['allowStaffViewShiftDifference'] != false,
      autoPrintBill: map['autoPrintBill'] != false,
      pointRedeemRate: asInt(map['pointRedeemRate']) ?? 1000,
      pointEarnRate: asDouble(map['pointEarnRate']) ?? 1.0,
      loyaltyTiers: LoyaltyTier.parseList(map['loyaltyTiers']),
      sharedLoyaltyEnabled: map['sharedLoyalty'] is Map && (map['sharedLoyalty'] as Map)['enabled'] == true,
      businessDayStartMinute: BusinessDay.normalize(map['businessDayStartMinute']),
      chamCongStoreId: map['chamCongStoreId']?.toString() ?? '',
      chamCongStoreName: map['chamCongStoreName']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'storeCode': storeCode,
    'storeName': storeName,
    'address': address,
    'phone': phone,
    'wifiName': wifiName,
    'bankId': bankId,
    'bankAccount': bankAccount,
    'accountName': accountName,
    'allowStackPromotions': allowStackPromotions,
    'defaultVatRate': defaultVatRate,
    'kitchenPrinterIp': kitchenPrinterIp,
    'billPrinterIp': billPrinterIp,
    'printerType': printerType,
    'allowStaffViewShiftDifference': allowStaffViewShiftDifference,
    'autoPrintBill': autoPrintBill,
    'pointRedeemRate': pointRedeemRate,
    'pointEarnRate': pointEarnRate,
  };

  StoreInfoModel copyWith({
    String? storeCode,
    String? storeName,
    String? ownerId,
    String? address,
    String? phone,
    String? wifiName,
    String? bankId,
    String? bankAccount,
    String? accountName,
    bool? allowStackPromotions,
    double? defaultVatRate,
    String? kitchenPrinterIp,
    String? billPrinterIp,
    String? printerType,
    bool? allowStaffViewShiftDifference,
    bool? autoPrintBill,
    int? pointRedeemRate,
    double? pointEarnRate,
    List<LoyaltyTier>? loyaltyTiers,
  }) {
    return StoreInfoModel(
      storeCode: storeCode ?? this.storeCode,
      storeName: storeName ?? this.storeName,
      ownerId: ownerId ?? this.ownerId,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      wifiName: wifiName ?? this.wifiName,
      bankId: bankId ?? this.bankId,
      bankAccount: bankAccount ?? this.bankAccount,
      accountName: accountName ?? this.accountName,
      allowStackPromotions: allowStackPromotions ?? this.allowStackPromotions,
      defaultVatRate: defaultVatRate ?? this.defaultVatRate,
      kitchenPrinterIp: kitchenPrinterIp ?? this.kitchenPrinterIp,
      billPrinterIp: billPrinterIp ?? this.billPrinterIp,
      printerType: printerType ?? this.printerType,
      allowStaffViewShiftDifference: allowStaffViewShiftDifference ?? this.allowStaffViewShiftDifference,
      autoPrintBill: autoPrintBill ?? this.autoPrintBill,
      pointRedeemRate: pointRedeemRate ?? this.pointRedeemRate,
      pointEarnRate: pointEarnRate ?? this.pointEarnRate,
      loyaltyTiers: loyaltyTiers ?? this.loyaltyTiers,
      sharedLoyaltyEnabled: sharedLoyaltyEnabled,
      businessDayStartMinute: businessDayStartMinute,
      chamCongStoreId: chamCongStoreId,
      chamCongStoreName: chamCongStoreName,
    );
  }

  /// Cấu hình điểm TOÀN CHUỖI (RTDB loyalty_config, do Chủ đặt) ghi đè cấu hình riêng của chi nhánh;
  /// trường nào chuỗi chưa đặt thì giữ giá trị của chi nhánh (fallback). Mốc hạng không có giá trị mặc định.
  StoreInfoModel withChainLoyalty(Object? chain) {
    if (chain is! Map) return this;
    final earn = chain['pointEarnRate'];
    final redeem = chain['pointRedeemRate'];
    final tiersRaw = chain['loyaltyTiers'];
    return copyWith(
      pointEarnRate: earn is num ? earn.toDouble() : null,
      pointRedeemRate: redeem is num && redeem > 0 ? redeem.toInt() : null,
      loyaltyTiers: tiersRaw != null ? LoyaltyTier.parseList(tiersRaw) : null,
    );
  }
}

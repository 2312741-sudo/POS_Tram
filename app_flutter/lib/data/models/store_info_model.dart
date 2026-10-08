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
  final String managerPin; // Mã PIN quản lý duyệt giảm giá món

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
    this.managerPin = '1234',
  });

  factory StoreInfoModel.fromMap(Map<dynamic, dynamic> map, String storeCode) {
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
      allowStackPromotions: map['allowStackPromotions'] ?? true,
      defaultVatRate: ((map['defaultVatRate'] as num?)?.toDouble() ?? 0.0) == 8.0 ? 0.0 : ((map['defaultVatRate'] as num?)?.toDouble() ?? 0.0),
      kitchenPrinterIp: map['kitchenPrinterIp']?.toString() ?? '192.168.1.200',
      billPrinterIp: map['billPrinterIp']?.toString() ?? '192.168.1.201',
      printerType: map['printerType']?.toString() ?? 'LAN',
      allowStaffViewShiftDifference: map['allowStaffViewShiftDifference'] ?? true,
      autoPrintBill: map['autoPrintBill'] ?? true,
      pointRedeemRate: (map['pointRedeemRate'] as num?)?.toInt() ?? 1000,
      pointEarnRate: (map['pointEarnRate'] as num?)?.toDouble() ?? 1.0,
      managerPin: map['managerPin']?.toString() ?? '1234',
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
    'managerPin': managerPin,
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
    String? managerPin,
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
      managerPin: managerPin ?? this.managerPin,
    );
  }
}

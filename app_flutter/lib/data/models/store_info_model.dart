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
      defaultVatRate: (map['defaultVatRate'] as num?)?.toDouble() ?? 0.0,
      kitchenPrinterIp: map['kitchenPrinterIp']?.toString() ?? '192.168.1.200',
      billPrinterIp: map['billPrinterIp']?.toString() ?? '192.168.1.201',
      printerType: map['printerType']?.toString() ?? 'LAN',
      allowStaffViewShiftDifference: map['allowStaffViewShiftDifference'] ?? true,
      autoPrintBill: map['autoPrintBill'] ?? true,
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
  };
}

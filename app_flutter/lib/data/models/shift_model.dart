// ==================== CASH SHIFT MODEL (KIOTVIET KÉT TIỀN CA) ====================
class CashShiftModel {
  final String id;
  final String shiftCode;
  String shiftName;
  final String storeCode;
  /// uid Firebase Auth của chủ ca (ca cũ trước khi tách theo tài khoản: rỗng → nhận diện theo staffUsername)
  final String staffUid;
  final String staffUsername;
  final String staffFullName;
  final String staffEmployeeCode; // Mã nhân viên mở ca
  final int openedAt;
  int? closedAt;
  final int initialCash; // Tiền mặt đầu ca
  int totalCashSales; // Doanh số tiền mặt
  int totalQrSales;   // Doanh số chuyển khoản VietQR
  int totalCardSales; // Doanh số thẻ / ví
  int cashIn;         // Tiền mặt nộp thêm vào két
  int cashOut;        // Tiền mặt chi vặt trong ca
  int? actualCash;    // Tiền mặt kiểm đếm thực tế khi chốt két
  int? difference;    // Chênh lệch thừa / thiếu
  String status;      // 'OPEN', 'CLOSED'
  String notes;

  CashShiftModel({
    required this.id,
    String? shiftCode,
    this.shiftName = '',
    required this.storeCode,
    this.staffUid = '',
    required this.staffUsername,
    required this.staffFullName,
    this.staffEmployeeCode = '',
    required this.openedAt,
    this.closedAt,
    int? initialCash,
    int? initialBalance,
    int totalCashSales = 0,
    int? cashSales,
    int totalQrSales = 0,
    int? qrSales,
    int totalCardSales = 0,
    int? cardSales,
    int cashIn = 0,
    int? inAdjustments,
    int cashOut = 0,
    int? outAdjustments,
    int? actualCash,
    int? actualBalance,
    this.difference,
    this.status = 'OPEN',
    this.notes = '',
    int? totalBills,
  }) : shiftCode = shiftCode ?? id,
       initialCash = initialBalance ?? initialCash ?? 0,
       totalCashSales = cashSales ?? totalCashSales,
       totalQrSales = qrSales ?? totalQrSales,
       totalCardSales = cardSales ?? totalCardSales,
       cashIn = inAdjustments ?? cashIn,
       cashOut = outAdjustments ?? cashOut,
       actualCash = actualBalance ?? actualCash;

  factory CashShiftModel.fromMap(Map<dynamic, dynamic> map, String id) {
    int? asInt(Object? v) {
      if (v == null) return null;
      if (v is num) return v.isNaN || v.isInfinite ? null : v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return int.tryParse(s) ?? num.tryParse(s)?.toInt();
    }

    int? asEpochMs(Object? v) {
      final n = asInt(v);
      if (n != null && n > 0) return n;
      if (v is String && v.trim().isNotEmpty) {
        final dt = DateTime.tryParse(v.trim());
        if (dt != null) return dt.millisecondsSinceEpoch;
      }
      return n;
    }

    return CashShiftModel(
      id: id,
      shiftCode: map['shiftCode']?.toString() ?? id,
      shiftName: map['shiftName']?.toString() ?? '',
      storeCode: map['storeCode']?.toString() ?? '',
      staffUid: map['staffUid']?.toString() ?? '',
      staffUsername: map['staffUsername']?.toString() ?? '',
      staffFullName: map['staffFullName']?.toString() ?? '',
      staffEmployeeCode: (map['staffEmployeeCode'] ?? map['staffCode'] ?? '').toString(),
      openedAt: asEpochMs(map['openedAt']) ?? 0,
      closedAt: asEpochMs(map['closedAt']),
      initialCash: asInt(map['initialCash']) ?? asInt(map['initialBalance']) ?? 0,
      totalCashSales: asInt(map['totalCashSales']) ?? asInt(map['cashSales']) ?? 0,
      totalQrSales: asInt(map['totalQrSales']) ?? asInt(map['qrSales']) ?? 0,
      totalCardSales: asInt(map['totalCardSales']) ?? asInt(map['cardSales']) ?? 0,
      cashIn: asInt(map['cashIn']) ?? asInt(map['inAdjustments']) ?? 0,
      cashOut: asInt(map['cashOut']) ?? asInt(map['outAdjustments']) ?? 0,
      actualCash: asInt(map['actualCash']) ?? asInt(map['actualBalance']),
      difference: asInt(map['difference']),
      status: map['status']?.toString() ?? (map['closedAt'] != null ? 'CLOSED' : 'OPEN'),
      notes: map['notes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'shiftCode': shiftCode,
    'shiftName': shiftName,
    'storeCode': storeCode,
    if (staffUid.isNotEmpty) 'staffUid': staffUid,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    if (staffEmployeeCode.isNotEmpty) 'staffEmployeeCode': staffEmployeeCode,
    'openedAt': openedAt,
    if (closedAt != null) 'closedAt': closedAt,
    'initialCash': initialCash,
    'totalCashSales': totalCashSales,
    'totalQrSales': totalQrSales,
    'totalCardSales': totalCardSales,
    'cashIn': cashIn,
    'cashOut': cashOut,
    if (actualCash != null) 'actualCash': actualCash,
    if (difference != null) 'difference': difference,
    'status': status,
    'notes': notes,
  };

  /// Tiền mặt kỳ vọng trên hệ thống = Đầu ca + Tiền mặt bán + Nộp thêm - Chi vặt
  int get expectedCash => initialCash + totalCashSales + cashIn - cashOut;

  /// Tổng doanh thu tất cả phương thức trong ca
  int get totalRevenue => totalCashSales + totalQrSales + totalCardSales;

  bool get isOpen => (status.toUpperCase().trim() == 'OPEN') && closedAt == null && openedAt > 0;

  // Convenience getters
  int get initialBalance => initialCash;
  int get cashSales => totalCashSales;
  int get qrSales => totalQrSales;
  int get cardSales => totalCardSales;
  int get inAdjustments => cashIn;
  int get outAdjustments => cashOut;
  int get actualBalance => actualCash ?? 0;
  int get calculatedBalance => expectedCash;
  int get variance => (actualCash != null) ? (actualCash! - expectedCash) : 0;
  int get totalSales => totalRevenue;
}

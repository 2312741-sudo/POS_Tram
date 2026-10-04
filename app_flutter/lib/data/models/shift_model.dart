// ==================== CASH SHIFT MODEL (KIOTVIET KÉT TIỀN CA) ====================
class CashShiftModel {
  final String id;
  final String shiftCode;
  String shiftName;
  final String storeCode;
  final String staffUsername;
  final String staffFullName;
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
    required this.staffUsername,
    required this.staffFullName,
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
    return CashShiftModel(
      id: id,
      shiftCode: map['shiftCode']?.toString() ?? id,
      shiftName: map['shiftName']?.toString() ?? '',
      storeCode: map['storeCode']?.toString() ?? '',
      staffUsername: map['staffUsername']?.toString() ?? '',
      staffFullName: map['staffFullName']?.toString() ?? '',
      openedAt: (map['openedAt'] as num?)?.toInt() ?? 0,
      closedAt: (map['closedAt'] as num?)?.toInt(),
      initialCash: (map['initialCash'] as num?)?.toInt() ?? 0,
      totalCashSales: (map['totalCashSales'] as num?)?.toInt() ?? 0,
      totalQrSales: (map['totalQrSales'] as num?)?.toInt() ?? 0,
      totalCardSales: (map['totalCardSales'] as num?)?.toInt() ?? 0,
      cashIn: (map['cashIn'] as num?)?.toInt() ?? 0,
      cashOut: (map['cashOut'] as num?)?.toInt() ?? 0,
      actualCash: (map['actualCash'] as num?)?.toInt(),
      difference: (map['difference'] as num?)?.toInt(),
      status: map['status']?.toString() ?? (map['closedAt'] != null ? 'CLOSED' : 'OPEN'),
      notes: map['notes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'shiftCode': shiftCode,
    'shiftName': shiftName,
    'storeCode': storeCode,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
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

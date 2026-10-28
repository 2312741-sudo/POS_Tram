// ==================== ORDER ACTION LOG MODEL (LỊCH SỬ THAO TÁC ĐƠN HÀNG) ====================
class OrderActionLogModel {
  final int timestamp;
  final String staffUsername;
  final String staffFullName;
  final String action; // 'ADD_ITEMS', 'CANCEL_ITEM', 'SEND_KITCHEN', 'DISCOUNT', 'PAY_BILL'
  final String details; // VD: "Bạn A nhập món Cà phê (x2), Bánh lăn (x1)"

  OrderActionLogModel({
    required this.timestamp,
    required this.staffUsername,
    required this.staffFullName,
    required this.action,
    required this.details,
  });

  factory OrderActionLogModel.fromMap(Map<dynamic, dynamic> map) {
    int parseTs(Object? v) {
      if (v == null) return 0;
      if (v is num) return v.isNaN || v.isInfinite ? 0 : v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) return 0;
      final n = int.tryParse(s) ?? num.tryParse(s)?.toInt();
      if (n != null) return n;
      return DateTime.tryParse(s)?.millisecondsSinceEpoch ?? 0;
    }

    return OrderActionLogModel(
      timestamp: parseTs(map['timestamp']),
      staffUsername: map['staffUsername']?.toString() ?? map['username']?.toString() ?? '',
      staffFullName: map['staffFullName']?.toString() ?? map['userFullName']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    'action': action,
    'details': details,
  };
}

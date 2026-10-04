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
    return OrderActionLogModel(
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      staffUsername: map['staffUsername']?.toString() ?? '',
      staffFullName: map['staffFullName']?.toString() ?? '',
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

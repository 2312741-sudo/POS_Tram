// ==================== AUDIT LOG MODEL ====================
class AuditLogModel {
  final String? logId;
  final int timestamp;
  final String username;
  final String userFullName;
  final String userRole;
  final String action;
  final String targetType; // 'BILL', 'ITEM', 'PROMOTION', 'USER', 'TABLE', 'AUTH', 'SETTING'
  final String targetId;
  final String details;
  final Map<String, dynamic>? beforeState;
  final Map<String, dynamic>? afterState;
  final bool isSuspicious;
  final String? storeCode;

  /// Trường cấu trúc bổ sung, ghi phẳng vào bản ghi (VD DELETE_ITEM: productName,
  /// quantity, amount, reason, tableName, orderCode).
  final Map<String, dynamic>? extra;

  static const List<String> extraKeys = ['productName', 'quantity', 'amount', 'reason', 'tableName', 'orderCode'];

  AuditLogModel({
    this.logId,
    required this.timestamp,
    required this.username,
    required this.userFullName,
    required this.userRole,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.details,
    this.beforeState,
    this.afterState,
    this.isSuspicious = false,
    this.storeCode,
    this.extra,
  });

  factory AuditLogModel.fromMap(Map<dynamic, dynamic> map, {String? logId}) {
    Map<String, dynamic>? before;
    if (map['beforeState'] != null && map['beforeState'] is Map) {
      before = Map<String, dynamic>.from(map['beforeState']);
    }
    Map<String, dynamic>? after;
    if (map['afterState'] != null && map['afterState'] is Map) {
      after = Map<String, dynamic>.from(map['afterState']);
    }

    return AuditLogModel(
      logId: logId ?? map['logId']?.toString(),
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      username: map['username']?.toString() ?? '',
      userFullName: map['userFullName']?.toString() ?? '',
      userRole: map['userRole']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      targetType: map['targetType']?.toString() ?? '',
      targetId: map['targetId']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
      beforeState: before,
      afterState: after,
      isSuspicious: map['isSuspicious'] == true,
      storeCode: map['storeCode']?.toString(),
      extra: () {
        final e = <String, dynamic>{
          for (final k in extraKeys)
            if (map[k] != null) k: map[k],
        };
        return e.isEmpty ? null : e;
      }(),
    );
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp,
    'username': username,
    'userFullName': userFullName,
    'userRole': userRole,
    'action': action,
    'targetType': targetType,
    'targetId': targetId,
    'details': details,
    if (beforeState != null) 'beforeState': beforeState,
    if (afterState != null) 'afterState': afterState,
    'isSuspicious': isSuspicious,
    if (storeCode != null) 'storeCode': storeCode,
    if (extra != null) ...extra!,
  };

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}

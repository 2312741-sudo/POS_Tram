import 'dart:convert';
import '../../core/utils/format_utils.dart';
import 'order_item_model.dart';
import 'order_action_log_model.dart';

// ==================== TABLE MODEL (KIOTVIET FNB) ====================
class TableModel {
  final String name;
  final String zone;
  bool inUse;
  String currentOrderJson;
  String? mergedIntoTable; // Name of parent table if merged
  String? currentBillId; // Mã hóa đơn thanh toán (HD-yyMMdd-HHmmss)
  String? currentOrderCode; // Mã đặt món / gọi món kiểm soát (OD-yyMMdd-HHmmss)

  // Đặt bàn trước KiotViet (Reservations)
  bool isReserved;
  String? reservationCustomer;
  String? reservationPhone;
  String? reservationTime;
  int reservationDeposit;
  int capacity;
  int? openedAt; // Thời điểm khách vào ngồi
  int? guestCount; // Số lượng khách tại bàn do nhân viên nhập
  String? actionLogsJson; // Lịch sử thao tác đơn hàng (Audit trail)

  TableModel({
    required this.name,
    required this.zone,
    this.inUse = false,
    this.currentOrderJson = '',
    this.mergedIntoTable,
    this.currentBillId,
    this.currentOrderCode,
    this.isReserved = false,
    this.reservationCustomer,
    this.reservationPhone,
    this.reservationTime,
    this.reservationDeposit = 0,
    this.capacity = 4,
    this.openedAt,
    this.guestCount,
    this.actionLogsJson,
  });

  factory TableModel.fromMap(Map<dynamic, dynamic> map, [String? key]) {
    String name = map['name']?.toString() ?? '';
    String zone = map['zone']?.toString() ?? '';

    // Auto-recover zone and name from key if missing (e.g. key: "Khu A_A1")
    if ((name.isEmpty || zone.isEmpty) && key != null && key.contains('_')) {
      final parts = key.split('_');
      if (zone.isEmpty) zone = parts.first;
      if (name.isEmpty) name = parts.sublist(1).join('_');
    } else if (name.isEmpty && key != null && key.isNotEmpty) {
      name = key;
    }
    if (zone.isEmpty) zone = 'Khu A';

    final rawInUse = map['inUse'];
    final inUse = rawInUse == true || rawInUse == 1 || rawInUse?.toString().toLowerCase() == 'true';

    // Robust parsing for openedAt (int timestamp or ISO 8601 string)
    int? openedAt;
    if (map['openedAt'] != null) {
      if (map['openedAt'] is num) {
        openedAt = (map['openedAt'] as num).toInt();
      } else {
        final str = map['openedAt'].toString();
        openedAt = int.tryParse(str) ?? DateTime.tryParse(str)?.millisecondsSinceEpoch;
      }
    }

    // Robust parsing for guestCount
    int? guestCount;
    if (map['guestCount'] != null) {
      if (map['guestCount'] is num) {
        guestCount = (map['guestCount'] as num).toInt();
      } else {
        guestCount = int.tryParse(map['guestCount'].toString());
      }
    }

    // Robust parsing for reservationDeposit
    int reservationDeposit = 0;
    if (map['reservationDeposit'] != null) {
      if (map['reservationDeposit'] is num) {
        reservationDeposit = (map['reservationDeposit'] as num).toInt();
      } else {
        reservationDeposit = int.tryParse(map['reservationDeposit'].toString()) ?? 0;
      }
    }

    // Robust parsing for capacity
    int capacity = 4;
    if (map['capacity'] != null) {
      if (map['capacity'] is num) {
        capacity = (map['capacity'] as num).toInt();
      } else {
        capacity = int.tryParse(map['capacity'].toString()) ?? 4;
      }
    }

    final rawIsReserved = map['isReserved'];
    final isReserved = rawIsReserved == true || rawIsReserved?.toString().toLowerCase() == 'true';

    return TableModel(
      name: name,
      zone: zone,
      inUse: inUse,
      currentOrderJson: map['currentOrderJson']?.toString() ?? '',
      mergedIntoTable: map['mergedIntoTable']?.toString(),
      currentBillId: map['currentBillId']?.toString(),
      currentOrderCode: map['currentOrderCode']?.toString(),
      isReserved: isReserved,
      reservationCustomer: map['reservationCustomer']?.toString(),
      reservationPhone: map['reservationPhone']?.toString(),
      reservationTime: map['reservationTime']?.toString(),
      reservationDeposit: reservationDeposit,
      capacity: capacity,
      openedAt: openedAt,
      guestCount: guestCount,
      actionLogsJson: map['actionLogsJson']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'zone': zone,
    'inUse': inUse,
    'currentOrderJson': currentOrderJson,
    if (mergedIntoTable != null) 'mergedIntoTable': mergedIntoTable,
    if (currentBillId != null) 'currentBillId': currentBillId,
    if (currentOrderCode != null) 'currentOrderCode': currentOrderCode,
    'isReserved': isReserved,
    if (reservationCustomer != null) 'reservationCustomer': reservationCustomer,
    if (reservationPhone != null) 'reservationPhone': reservationPhone,
    if (reservationTime != null) 'reservationTime': reservationTime,
    'reservationDeposit': reservationDeposit,
    'capacity': capacity,
    if (openedAt != null) 'openedAt': openedAt,
    if (guestCount != null) 'guestCount': guestCount,
    if (actionLogsJson != null) 'actionLogsJson': actionLogsJson,
  };

  List<OrderActionLogModel> get actionLogs {
    if (actionLogsJson == null || actionLogsJson!.isEmpty) return [];
    try {
      final List list = jsonDecode(actionLogsJson!);
      return list.map((e) => OrderActionLogModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  void addActionLog(OrderActionLogModel log) {
    final list = actionLogs;
    list.add(log);
    actionLogsJson = jsonEncode(list.map((e) => e.toMap()).toList());
  }

  List<OrderItemModel> get currentItems {
    if (currentOrderJson.isEmpty) return [];
    try {
      final List list = jsonDecode(currentOrderJson);
      return list.map((e) => OrderItemModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  int get currentTotal => currentItems.fold(0, (s, p) => s + p.itemTotal);
  String get firebaseKey => '${zone}_$name';
  bool get isMerged => mergedIntoTable != null && mergedIntoTable!.isNotEmpty;

  /// Thời gian khách đã ngồi (Duration)
  Duration? get durationInUse {
    if (!inUse || openedAt == null) return null;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(openedAt!));
  }

  /// Đảm bảo luôn có đầy đủ cả Mã Hóa Đơn (HD-...) và Mã Đặt Món (OD-...)
  void ensureCodes() {
    // 1. Phục hồi hoặc sinh Mã Hóa Đơn chính thức (HD-...)
    if (currentBillId == null || currentBillId!.isEmpty) {
      currentBillId = FormatUtils.billCode();
    } else if (currentBillId!.startsWith('OD-')) {
      // Nếu dữ liệu cũ lưu nhầm OD- vào currentBillId thì chuyển sang currentOrderCode
      if (currentOrderCode == null || currentOrderCode!.isEmpty) {
        currentOrderCode = currentBillId;
      }
      currentBillId = FormatUtils.billCode();
    }

    // 2. Phục hồi hoặc sinh Mã Đặt Món kiểm soát (OD-...)
    if (currentOrderCode == null || currentOrderCode!.isEmpty) {
      currentOrderCode = FormatUtils.orderCode();
    }
  }

  /// Đưa bàn về trạng thái hoàn toàn TRỐNG (sạch sẽ, xóa giỏ hàng và cả 2 mã đơn)
  void clearTable() {
    inUse = false;
    currentOrderJson = '';
    openedAt = null;
    guestCount = null;
    currentBillId = null;
    currentOrderCode = null;
    mergedIntoTable = null;
    actionLogsJson = null;
  }
}

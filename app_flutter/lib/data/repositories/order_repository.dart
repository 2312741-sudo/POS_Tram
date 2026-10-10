import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/domain/order_integrity.dart';
import '../../core/domain/deleted_items.dart';
import '../../core/utils/format_utils.dart';
import '../models/app_models.dart';
import '../services/inventory_service.dart';
import '../services/campaign_service.dart';
import '../services/loyalty_service.dart';
import '../../core/services/auth_service.dart';
import 'seed_data.dart';

class OrderRepository {
  final DatabaseReference Function() _getRoot;
  final String Function() _getCurrentStoreCode;
  final DatabaseReference Function() _getTablesRef;
  final DatabaseReference Function() _getBillsRef;
  final DatabaseReference Function() _getPromotionsRef;
  final DatabaseReference Function() _getZonesRef;
  final DatabaseReference Function() _getKitchenOrdersRef;
  final DatabaseReference Function() _getOnlineOrdersRef;
  final Future<void> Function(AuditLogModel log) _logAction;
  final Future<void> Function(String paymentMethod, int amount)? _onDeductCashShift;

  OrderRepository({
    required DatabaseReference Function() getRoot,
    required String Function() getCurrentStoreCode,
    required DatabaseReference Function() getTablesRef,
    required DatabaseReference Function() getBillsRef,
    required DatabaseReference Function() getPromotionsRef,
    required DatabaseReference Function() getZonesRef,
    required DatabaseReference Function() getKitchenOrdersRef,
    required DatabaseReference Function() getOnlineOrdersRef,
    required Future<void> Function(AuditLogModel log) logAction,
    Future<void> Function(String paymentMethod, int amount)? onDeductCashShift,
  })  : _getRoot = getRoot,
        _getCurrentStoreCode = getCurrentStoreCode,
        _getTablesRef = getTablesRef,
        _getBillsRef = getBillsRef,
        _getPromotionsRef = getPromotionsRef,
        _getZonesRef = getZonesRef,
        _getKitchenOrdersRef = getKitchenOrdersRef,
        _getOnlineOrdersRef = getOnlineOrdersRef,
        _logAction = logAction,
        _onDeductCashShift = onDeductCashShift;

  DatabaseReference get _root => _getRoot();
  String get _currentStoreCode => _getCurrentStoreCode();
  DatabaseReference get tablesRef => _getTablesRef();
  DatabaseReference get billsRef => _getBillsRef();
  DatabaseReference get promotionsRef => _getPromotionsRef();
  DatabaseReference get zonesRef => _getZonesRef();
  DatabaseReference get kitchenOrdersRef => _getKitchenOrdersRef();
  DatabaseReference get onlineOrdersRef => _getOnlineOrdersRef();

  // Parsing helper
  List<T> _parseList<T>(dynamic raw, T Function(dynamic key, dynamic val) mapper) {
    if (raw == null) return [];
    final list = <T>[];
    if (raw is Map) {
      for (final e in raw.entries) {
        try {
          list.add(mapper(e.key, e.value));
        } catch (_) {}
      }
      return list;
    } else if (raw is List) {
      for (int i = 0; i < raw.length; i++) {
        if (raw[i] != null) {
          try {
            list.add(mapper(i.toString(), raw[i]));
          } catch (_) {}
        }
      }
      return list;
    }
    return [];
  }

  // ==================== GHI DỮ LIỆU AN TOÀN ====================
  static const Duration _writeAckTimeout = Duration(seconds: 6);
  static const Duration _readTimeout = Duration(seconds: 3);
  static const Duration _txnTimeout = Duration(seconds: 4);

  /// Chờ server xác nhận một thao tác ghi.
  /// - true: server đã xác nhận.
  /// - false: quá thời gian chờ (mất mạng) - dữ liệu đã nằm trong bộ đệm cục bộ và
  ///   Firebase SDK sẽ tự đồng bộ (nguyên tử) khi có mạng lại.
  /// - Lỗi thật (VD: permission-denied) được ném ra dạng [DataWriteException].
  Future<bool> _commitWrite(Future<void> write, String what) async {
    try {
      await write.timeout(_writeAckTimeout);
      return true;
    } on TimeoutException {
      debugPrint('[OrderRepository] Chưa có xác nhận từ server cho "$what" - đang chờ đồng bộ.');
      unawaited(write.catchError((Object e) {
        debugPrint('[OrderRepository] Ghi "$what" thất bại khi đồng bộ: $e');
        _safeLog(AuditLogModel(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          username: 'system',
          userFullName: 'Hệ thống',
          userRole: 'SYSTEM',
          action: 'SYNC_WRITE_FAILED',
          targetType: 'DATA',
          targetId: what,
          details: 'Ghi "$what" bị từ chối khi đồng bộ: $e',
          isSuspicious: true,
        ));
      }));
      return false;
    } catch (e) {
      throw DataWriteException('Không lưu được $what: $e', e);
    }
  }

  /// Ghi audit log nhưng không bao giờ ném lỗi (dùng cho tác vụ phụ)
  Future<void> _safeLog(AuditLogModel log) async {
    try {
      await _logAction(log).timeout(_writeAckTimeout);
    } catch (e) {
      debugPrint('[OrderRepository] Không ghi được audit log ${log.action}: $e');
    }
  }

  final Map<String, String> _storeNameCache = {};

  /// Tên cửa hàng thật từ stores/{code}/storeInfo/storeName (có cache, fallback = mã cửa hàng)
  Future<String> _resolveStoreName(String storeCode) async {
    Future<String?> fetch() async {
      try {
        final snap = await _root.child('stores/$storeCode/storeInfo/storeName').get().timeout(_readTimeout);
        final name = snap.value?.toString().trim();
        if (name != null && name.isNotEmpty) {
          _storeNameCache[storeCode] = name;
          return name;
        }
      } catch (_) {}
      return null;
    }

    final cached = _storeNameCache[storeCode];
    if (cached != null) {
      unawaited(fetch()); // làm mới nền
      return cached;
    }
    return await fetch() ?? storeCode;
  }

  // ==================== TABLES ====================
  /// Danh sách bàn realtime. DB trống -> danh sách rỗng (bàn mẫu chỉ được tạo khi khởi tạo
  /// cửa hàng). Lỗi (VD: không có quyền) được đẩy ra stream để UI hiển thị, không trả bàn giả.
  Stream<List<TableModel>> tablesStream() {
    return tablesRef.onValue.map<List<TableModel>>((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final list = _parseList<TableModel>(
          event.snapshot.value,
          (k, v) => TableModel.fromMap(v is Map ? v : {'name': k}, k.toString()),
        );
        return list..sort(compareTables);
      }
      return <TableModel>[];
    });
  }

  /// Lưu bàn. Lỗi thật được ném ra ([DataWriteException]); nếu mất mạng thì dữ liệu được
  /// giữ cục bộ và tự đồng bộ sau (không ném lỗi).
  Future<void> saveTable(TableModel table) async {
    await _commitWrite(
      tablesRef.child(table.firebaseKey).set(table.toMap()),
      'bàn ${table.name}',
    );
  }

  Future<void> deleteTable(TableModel table) async {
    await tablesRef.child(table.firebaseKey).remove();
  }

  TableModel _copyTable(TableModel t) => TableModel.fromMap(t.toMap(), t.firebaseKey);

  void _applyTableState(TableModel dst, TableModel src) {
    dst.inUse = src.inUse;
    dst.currentOrderJson = src.currentOrderJson;
    dst.mergedIntoTable = src.mergedIntoTable;
    dst.currentBillId = src.currentBillId;
    dst.currentOrderCode = src.currentOrderCode;
    dst.openedAt = src.openedAt;
    dst.guestCount = src.guestCount;
    dst.actionLogsJson = src.actionLogsJson;
    dst.deletedItemsJson = src.deletedItemsJson;
    // Gán SAU currentOrderJson (setter có thể xóa cờ tạm tính khi món đổi).
    dst.prePrintedAt = src.prePrintedAt;
    dst.prePrintedBy = src.prePrintedBy;
  }

  /// Gộp bàn: chỉ cộng dồn các dòng món có cấu hình giống hệt nhau (size, topping, đường,
  /// đá, ghi chú, giá...). Ghi cả 2 bàn trong 1 lệnh multi-path (không thể áp dụng một nửa).
  Future<void> mergeTables(TableModel sourceTable, TableModel targetTable, {String? staffName, String? staffUsername}) async {
    if (sourceTable.firebaseKey == targetTable.firebaseKey) return;
    final sourceItems = sourceTable.currentItems;
    final combined = OrderLineMerger.merge(targetTable.currentItems, sourceItems);

    final sourceItemNames = sourceItems.map((e) => "${e.name} (x${e.quantity})").join(", ");
    final target = _copyTable(targetTable);
    target.inUse = true;
    target.currentOrderJson = jsonEncode(combined.map((e) => e.toMap()).toList());
    // Đơn gộp đã khác phiếu tạm tính cũ → bàn đích quay về "Có khách".
    target.clearPrePrint();
    // Món đã xóa của bàn nguồn được nối vào bàn đích (vẫn được tính khi chốt đơn).
    if (sourceTable.deletedItems.isNotEmpty) {
      target.deletedItemsJson = DeletedItemsLogic.append(target.deletedItemsJson, sourceTable.deletedItems);
    }
    final int combinedGuests = (target.guestCount ?? 0) + (sourceTable.guestCount ?? 0);
    target.guestCount = combinedGuests > 0 ? combinedGuests : null;
    if (target.openedAt == null || (sourceTable.openedAt != null && sourceTable.openedAt! < target.openedAt!)) {
      target.openedAt = sourceTable.openedAt ?? target.openedAt ?? DateTime.now().millisecondsSinceEpoch;
    }
    target.addActionLog(OrderActionLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      staffUsername: staffUsername ?? 'staff',
      staffFullName: staffName ?? 'Nhân viên',
      action: 'MERGE_TABLE',
      details: 'Gộp ${sourceTable.name} vào ${target.name}: chuyển ${sourceItems.length} món ($sourceItemNames)',
    ));

    final source = _copyTable(sourceTable);
    source.clearTable();
    source.mergedIntoTable = target.name;

    await _commitWrite(
      tablesRef.update({
        target.firebaseKey: target.toMap(),
        source.firebaseKey: source.toMap(),
      }),
      'gộp bàn ${sourceTable.name} -> ${targetTable.name}',
    );
    _applyTableState(targetTable, target);
    _applyTableState(sourceTable, source);

    await _safeLog(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: staffUsername ?? 'staff',
      userFullName: staffName ?? 'Nhân viên',
      userRole: 'STAFF',
      action: 'MERGE_TABLE',
      targetType: 'TABLE',
      targetId: '${sourceTable.name} -> ${targetTable.name}',
      details: '${staffName ?? "Nhân viên"} gộp ${sourceTable.name} vào ${targetTable.name} (chuyển ${sourceItems.length} món: $sourceItemNames sang ${targetTable.name})',
    ));
  }

  /// Chuyển bàn: ghi bàn đích và dọn bàn nguồn trong 1 lệnh multi-path.
  Future<void> transferTable(TableModel sourceTable, TableModel targetTable, {String? staffName, String? staffUsername}) async {
    if (sourceTable.firebaseKey == targetTable.firebaseKey) return;
    final itemCount = sourceTable.currentItems.length;
    final itemNames = sourceTable.currentItems.map((e) => "${e.name} (x${e.quantity})").join(", ");
    final target = _copyTable(targetTable);
    target.inUse = true;
    target.currentOrderJson = sourceTable.currentOrderJson;
    target.openedAt = sourceTable.openedAt;
    target.guestCount = sourceTable.guestCount;
    target.currentBillId = sourceTable.currentBillId;
    target.currentOrderCode = sourceTable.currentOrderCode;
    target.actionLogsJson = sourceTable.actionLogsJson;
    target.deletedItemsJson = sourceTable.deletedItemsJson;
    // Trạng thái "Chờ thanh toán" đi theo đơn sang bàn đích.
    target.prePrintedAt = sourceTable.prePrintedAt;
    target.prePrintedBy = sourceTable.prePrintedBy;
    target.addActionLog(OrderActionLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      staffUsername: staffUsername ?? 'staff',
      staffFullName: staffName ?? 'Nhân viên',
      action: 'TRANSFER_TABLE',
      details: 'Chuyển toàn bộ món từ ${sourceTable.name} sang ${target.name}',
    ));

    final source = _copyTable(sourceTable);
    source.clearTable();

    await _commitWrite(
      tablesRef.update({
        target.firebaseKey: target.toMap(),
        source.firebaseKey: source.toMap(),
      }),
      'chuyển bàn ${sourceTable.name} -> ${targetTable.name}',
    );
    _applyTableState(targetTable, target);
    _applyTableState(sourceTable, source);

    await _safeLog(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: staffUsername ?? 'staff',
      userFullName: staffName ?? 'Nhân viên',
      userRole: 'STAFF',
      action: 'TRANSFER_TABLE',
      targetType: 'TABLE',
      targetId: '${sourceTable.name} -> ${targetTable.name}',
      details: '${staffName ?? "Nhân viên"} chuyển bàn từ ${sourceTable.name} sang ${targetTable.name} ($itemCount món: $itemNames)',
    ));
  }

  Future<void> reserveTable({
    required TableModel table,
    required String customerName,
    required String phone,
    required String time,
    required int deposit,
  }) async {
    table.isReserved = true;
    table.reservationCustomer = customerName;
    table.reservationPhone = phone;
    table.reservationTime = time;
    table.reservationDeposit = deposit;
    await saveTable(table);
  }

  Future<void> cancelReservation(TableModel table) async {
    table.isReserved = false;
    table.reservationCustomer = null;
    table.reservationPhone = null;
    table.reservationTime = null;
    table.reservationDeposit = 0;
    await saveTable(table);
  }

  // ==================== BILLS ====================
  Stream<List<BillModel>> billsStream() {
    return billsRef.onValue.map<List<BillModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <BillModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
          .map((e) => BillModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }).handleError((_) => <BillModel>[]);
  }

  Future<BillModel?> getBill(String billId) async {
    try {
      final snap = await billsRef.child(billId).get().timeout(const Duration(seconds: 2));
      if (!snap.exists || snap.value == null) return null;
      return BillModel.fromMap(Map<dynamic, dynamic>.from(snap.value as Map), billId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBill(BillModel bill) async {
    await billsRef.child(bill.id).set(bill.toMap());
  }

  // ==================== MÃ HÓA ĐƠN TUẦN TỰ ====================
  /// Cấp mã hóa đơn tuần tự HD-yyMMdd-NNNN bằng transaction trên
  /// stores/{store}/counters/bill_seq/{yyMMdd}. Nếu offline / lỗi thì dùng mã dự phòng
  /// (thời gian + hậu tố ngẫu nhiên) để không bao giờ chặn bán hàng.
  Future<String> allocateBillCode({String? storeCode, DateTime? at}) async {
    final now = at ?? DateTime.now();
    final sc = storeCode ?? _currentStoreCode;
    final day = BillCodeGenerator.dayKey(now);
    try {
      final result = await _root.child('stores/$sc/counters/bill_seq/$day').runTransaction((Object? current) {
        final n = current is num ? current.toInt() : 0;
        return Transaction.success(n + 1);
      }).timeout(_txnTimeout);
      final v = result.snapshot.value;
      if (result.committed && v is num && v > 0) {
        return BillCodeGenerator.sequential(v.toInt(), at: now);
      }
    } catch (e) {
      debugPrint('[OrderRepository] Không cấp được số hóa đơn tuần tự, dùng mã dự phòng: $e');
    }
    return BillCodeGenerator.fallback(at: now);
  }

  // ==================== THANH TOÁN ====================
  /// Thanh toán & đóng bàn.
  ///
  /// 1. Cấp mã hóa đơn tuần tự (bill.billCode được cập nhật tại chỗ).
  /// 2. Giữ lượt dùng khuyến mãi/voucher bằng transaction có kiểm tra giới hạn
  ///    (ném [PromotionLimitExceededException] nếu vượt).
  /// 3. Ghi NGUYÊN TỬ 1 lệnh multi-path: bills/{id}, history/{id}, tables/{key}.
  ///    Lỗi được ném ra ([DataWriteException]) và lượt khuyến mãi được hoàn tác.
  /// 2b. Đổi điểm khách (nếu có) bằng transaction trên customers/{id}, idempotent theo hóa đơn.
  ///    Không đủ điểm → ném [InsufficientPointsException] TRƯỚC khi ghi hóa đơn
  ///    (lượt khuyến mãi đã giữ được hoàn tác).
  /// 4. Tác vụ phụ chạy nền (trừ kho, tích điểm, audit log) - lỗi được ghi audit log, không bị nuốt.
  ///
  /// [pointEarnRate] (% doanh thu) / [pointRedeemRate] (đ/điểm): cấu hình tích điểm; nếu không
  /// truyền sẽ đọc từ storeInfo.
  ///
  /// Trả về true nếu server đã xác nhận, false nếu đang chờ đồng bộ (mất mạng,
  /// dữ liệu đã lưu cục bộ và sẽ tự đồng bộ).
  Future<bool> closeAndPayBill(BillModel bill, TableModel table, {double? pointEarnRate, int? pointRedeemRate}) async {
    final storeCode = _currentStoreCode;
    if (!BillCodeGenerator.isSequential(bill.billCode)) {
      bill.billCode = await allocateBillCode(storeCode: storeCode);
    }
    bill.status = 'PAID';
    bill.closedAt = DateTime.now().millisecondsSinceEpoch;
    if (bill.deletedItems.isEmpty && table.deletedItems.isNotEmpty) {
      bill.deletedItems = table.deletedItems;
    }

    final lateProblems = <String>[];
    void onLate(String msg) {
      _safeLog(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: bill.staffUsername,
        userFullName: bill.staffFullName,
        userRole: 'CASHIER',
        action: 'PROMO_SYNC_FAILED',
        targetType: 'BILL',
        targetId: bill.billCode,
        details: 'Khuyến mãi của HĐ ${bill.billCode}: $msg',
        isSuspicious: true,
      ));
    }

    final promo = await _reservePromotions(bill, storeCode, onLate, lateProblems);

    // Đổi điểm: phải thành công (hoặc đang chờ đồng bộ) trước khi ghi hóa đơn
    final customerId = bill.customerId?.trim() ?? '';
    bool pointsRedeemed = false;
    if (customerId.isNotEmpty && bill.pointsUsed > 0) {
      try {
        await _loyalty.redeemForBill(
          storeCode: storeCode,
          customerId: customerId,
          billId: bill.id,
          billCode: bill.billCode,
          points: bill.pointsUsed,
          by: bill.staffUsername,
          timeout: _txnTimeout,
          onLate: (msg) => _logLoyaltyProblem(bill, msg),
        );
        pointsRedeemed = true;
      } catch (e) {
        final rollbackErrors = await _rollbackPromotions(promo, storeCode);
        if (rollbackErrors.isNotEmpty) {
          onLate('Hoàn tác khuyến mãi sau khi đổi điểm lỗi thất bại: ${rollbackErrors.join("; ")}');
        }
        rethrow;
      }
    }

    final storeName = await _resolveStoreName(storeCode);
    final record = BillRecordBuilder.build(bill, storeCode: storeCode, storeName: storeName, guestCount: table.guestCount);
    final cleared = _copyTable(table)..clearTable();

    final bool synced;
    try {
      synced = await _commitWrite(
        _root.child('stores/$storeCode').update({
          'bills/${bill.id}': record,
          'history/${bill.id}': record,
          'tables/${table.firebaseKey}': cleared.toMap(),
        }),
        'hóa đơn ${bill.billCode}',
      );
    } catch (e) {
      final rollbackErrors = await _rollbackPromotions(promo, storeCode);
      if (rollbackErrors.isNotEmpty) {
        onLate('Hoàn tác khuyến mãi sau khi ghi hóa đơn lỗi thất bại: ${rollbackErrors.join("; ")}');
      }
      if (pointsRedeemed) {
        try {
          await _loyalty.refundRedeem(
            storeCode: storeCode,
            customerId: customerId,
            billId: bill.id,
            billCode: bill.billCode,
            points: bill.pointsUsed,
            by: bill.staffUsername,
            timeout: _txnTimeout,
            onLate: (msg) => _logLoyaltyProblem(bill, msg),
          );
        } catch (re) {
          _logLoyaltyProblem(bill, 'Hoàn điểm đã đổi (${bill.pointsUsed}) sau khi ghi hóa đơn lỗi thất bại: $re');
        }
      }
      rethrow;
    }
    table.clearTable();

    unawaited(_runPaymentFollowUps(
      bill,
      storeCode,
      [...promo.notes, ...lateProblems],
      synced,
      pointEarnRate: pointEarnRate,
      pointRedeemRate: pointRedeemRate,
    ));
    return synced;
  }

  late final LoyaltyService _loyalty = LoyaltyService(() => _root);

  /// Lỗi điểm phát sinh muộn (khi đồng bộ) → audit log, không nuốt lỗi.
  void _logLoyaltyProblem(BillModel bill, String msg) {
    _safeLog(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: bill.staffUsername,
      userFullName: bill.staffFullName,
      userRole: 'CASHIER',
      action: 'LOYALTY_SYNC_FAILED',
      targetType: 'BILL',
      targetId: bill.id,
      details: 'Điểm khách của HĐ ${bill.billCode}: $msg',
      isSuspicious: true,
    ));
  }

  Future<({double earnRate, int redeemRate})> _loyaltyConfig(String storeCode, double? earnRate, int? redeemRate) async {
    if (earnRate != null && redeemRate != null) return (earnRate: earnRate, redeemRate: redeemRate);
    double e = earnRate ?? 1.0;
    int r = redeemRate ?? 1000;
    try {
      final snap = await _root.child('stores/$storeCode/storeInfo').get().timeout(_readTimeout);
      if (snap.value is Map) {
        final m = snap.value as Map;
        if (earnRate == null && m['pointEarnRate'] is num) e = (m['pointEarnRate'] as num).toDouble();
        if (redeemRate == null && m['pointRedeemRate'] is num) r = (m['pointRedeemRate'] as num).toInt();
      }
    } catch (_) {}
    return (earnRate: e, redeemRate: r);
  }

  /// Trừ kho cho hóa đơn (idempotent - gọi lại chỉ trừ các dòng còn thiếu).
  /// Khi lỗi, hóa đơn được ghi vào stock_retry_queue để [retryPendingStock] chạy lại.
  Future<void> applyStockForBill(BillModel bill, {String? storeCode}) async {
    await InventoryService().consumeStockForBill(
      bill.items,
      bill.id,
      bill.staffUsername,
      storeCode: storeCode ?? _currentStoreCode,
      billCode: bill.billCode,
    );
  }

  /// Chạy lại hàng đợi trừ kho (stock_retry_queue) của chi nhánh; ghi audit log kết quả.
  Future<StockRetrySummary> retryPendingStock({String? storeCode, required String username, String? userFullName, String? userRole}) async {
    final sc = storeCode ?? _currentStoreCode;
    final summary = await InventoryService().retryPendingStock(storeCode: sc, username: username);
    if (summary.succeeded.isNotEmpty) {
      await _safeLog(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: username,
        userFullName: userFullName ?? username,
        userRole: userRole ?? 'CASHIER',
        action: 'STOCK_RETRY_APPLIED',
        targetType: 'INVENTORY',
        targetId: sc,
        details: 'Đã trừ kho bù cho ${summary.succeeded.length} hóa đơn: ${summary.succeeded.join(", ")}',
      ));
    }
    if (summary.failed.isNotEmpty) {
      await _safeLog(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: username,
        userFullName: userFullName ?? username,
        userRole: userRole ?? 'CASHIER',
        action: 'STOCK_RETRY_FAILED',
        targetType: 'INVENTORY',
        targetId: sc,
        details: 'Trừ kho bù còn lỗi: ${summary.failed.entries.map((e) => "${e.key}: ${e.value}").join(" | ")}',
        isSuspicious: true,
      ));
    }
    return summary;
  }

  Future<void> _runPaymentFollowUps(
    BillModel bill,
    String storeCode,
    List<String> problems,
    bool synced, {
    double? pointEarnRate,
    int? pointRedeemRate,
  }) async {
    try {
      await applyStockForBill(bill, storeCode: storeCode);
    } catch (e) {
      problems.add('Trừ kho chưa hoàn tất (đã đưa vào hàng đợi stock_retry_queue để thử lại): $e');
    }

    // Tích điểm (idempotent theo hóa đơn) - lỗi được ghi vào PAY_BILL_FOLLOWUP_FAILED
    final customerId = bill.customerId?.trim() ?? '';
    if (customerId.isNotEmpty && bill.finalAmount > 0) {
      try {
        final cfg = await _loyaltyConfig(storeCode, pointEarnRate, pointRedeemRate);
        final r = await _loyalty.awardForBill(
          storeCode: storeCode,
          customerId: customerId,
          billId: bill.id,
          billCode: bill.billCode,
          billAmount: bill.finalAmount,
          earnRatePercent: cfg.earnRate,
          redeemRate: cfg.redeemRate,
          by: bill.staffUsername,
          timeout: const Duration(seconds: 10),
          onLate: (msg) => _logLoyaltyProblem(bill, msg),
        );
        problems.addAll(r.notes);
      } catch (e) {
        problems.add('Tích điểm cho khách $customerId thất bại: $e');
      }
    }

    await _safeLog(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: bill.staffUsername,
      userFullName: bill.staffFullName,
      userRole: 'CASHIER',
      action: 'PAY_BILL',
      targetType: 'BILL',
      targetId: bill.billCode,
      details: 'Thanh toán hóa đơn ${bill.billCode} bàn ${bill.tableName}: ${bill.finalAmount}đ (${bill.paymentMethod})${synced ? "" : " [chờ đồng bộ]"}',
    ));

    if (problems.isNotEmpty) {
      await _safeLog(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: bill.staffUsername,
        userFullName: bill.staffFullName,
        userRole: 'CASHIER',
        action: 'PAY_BILL_FOLLOWUP_FAILED',
        targetType: 'BILL',
        targetId: bill.id,
        details: 'HĐ ${bill.billCode}: ${problems.join(" | ")}',
        isSuspicious: true,
      ));
    }
  }

  /// Giữ lượt dùng cho mọi khuyến mãi trên hóa đơn; nếu 1 khuyến mãi vượt giới hạn thì
  /// hoàn tác những cái đã giữ và ném lỗi.
  Future<_PromoCommit> _reservePromotions(
    BillModel bill,
    String storeCode,
    void Function(String) onLate,
    List<String> problems,
  ) async {
    final out = _PromoCommit();
    final cs = CampaignService();
    try {
      for (final d in bill.discounts) {
        final code = d.promoCode?.trim().toUpperCase() ?? '';
        final promoId = d.promoId?.trim() ?? '';
        String? campaignId;
        String? voucherCode;

        if (code.isNotEmpty) {
          try {
            final lookup = await _root.child('stores/$storeCode/voucher_lookup/$code').get().timeout(_readTimeout);
            if (lookup.value is Map) {
              campaignId = (lookup.value as Map)['campaignId']?.toString();
              voucherCode = code;
            }
          } catch (_) {
            // Mất mạng: giả định là voucher của chương trình promoId, để transaction chạy nền
            if (promoId.isNotEmpty) {
              campaignId = promoId;
              voucherCode = code;
            }
            out.notes.add('Không tra được voucher $code lúc thanh toán (mất mạng)');
          }
        }
        if (campaignId == null && promoId.isNotEmpty) {
          try {
            final snap = await _root.child('stores/$storeCode/campaigns/$promoId').get().timeout(_readTimeout);
            if (snap.exists) campaignId = promoId;
          } catch (_) {
            out.notes.add('Không đọc được khuyến mãi $promoId lúc thanh toán (mất mạng)');
          }
        }

        if (campaignId != null && campaignId.isNotEmpty) {
          final r = await cs.reservePromotionUsage(
            campaignId: campaignId,
            discountMoney: d.amount,
            customerId: bill.customerId,
            voucherCode: voucherCode,
            staffNote: d.staffNote,
            billId: bill.id,
            username: bill.staffUsername,
            billCode: bill.billCode,
            tableName: bill.tableName,
            staffName: bill.staffFullName,
            storeCode: storeCode,
            timeout: _txnTimeout,
            onLateFailure: onLate,
          );
          out.campaigns.add(r);
          if (r.unverified) out.notes.add('Lượt dùng khuyến mãi $campaignId chưa được server xác nhận (đang đồng bộ)');
        } else if (promoId.isNotEmpty) {
          final ok = await _changeLegacyPromotionUsage(storeCode, promoId, 1, onLate: onLate);
          if (ok == false) {
            throw PromotionLimitExceededException('Khuyến mãi "${d.description}" đã hết lượt sử dụng');
          }
          if (ok == true) out.legacyIds.add(promoId);
        }
      }
    } catch (e) {
      final errors = await _rollbackPromotions(out, storeCode);
      problems.addAll(errors);
      if (errors.isNotEmpty) onLate('Hoàn tác khuyến mãi lỗi: ${errors.join("; ")}');
      rethrow;
    }
    return out;
  }

  Future<List<String>> _rollbackPromotions(_PromoCommit promo, String storeCode) async {
    final errors = <String>[];
    for (final r in promo.campaigns) {
      errors.addAll(await CampaignService().rollbackPromotionUsage(r, timeout: _txnTimeout));
    }
    for (final id in promo.legacyIds) {
      final ok = await _changeLegacyPromotionUsage(storeCode, id, -1);
      if (ok != true) errors.add('Hoàn tác lượt dùng khuyến mãi $id chưa xác nhận');
    }
    promo.campaigns.clear();
    promo.legacyIds.clear();
    return errors;
  }

  /// Tăng/giảm usageCount của khuyến mãi cũ (promotions/{id}) bằng transaction,
  /// kiểm tra maxUsage trong transaction khi tăng.
  /// true = đã ghi; false = vượt giới hạn; null = khuyến mãi không tồn tại hoặc chưa xác nhận (offline).
  Future<bool?> _changeLegacyPromotionUsage(String storeCode, String promoId, int delta, {void Function(String)? onLate}) async {
    final ref = _root.child('stores/$storeCode/promotions/$promoId');
    final fut = ref.runTransaction((Object? current) {
      // Cache có thể trống: ghi null để server trả về dữ liệu thật rồi chạy lại
      if (current == null) return Transaction.success(null);
      final m = Map<String, dynamic>.from(current as Map);
      final maxUsage = (m['maxUsage'] as num?)?.toInt() ?? 0;
      final next = PromotionUsageMath.applyLegacyUsage(m['usageCount'], delta: delta, maxUsage: maxUsage);
      if (next == null) return Transaction.abort();
      m['usageCount'] = next;
      return Transaction.success(m);
    });
    try {
      final res = await fut.timeout(_txnTimeout);
      if (!res.committed) return false;
      return res.snapshot.value == null ? null : true;
    } on TimeoutException {
      unawaited(fut.then((res) {
        if (!res.committed) onLate?.call('Khuyến mãi $promoId vượt giới hạn khi đồng bộ');
      }, onError: (Object e) {
        onLate?.call('Cập nhật lượt dùng khuyến mãi $promoId lỗi: $e');
      }));
      return null;
    }
  }

  Future<void> cancelActiveBill(
    TableModel table, {
    required String reason,
    required String staffUsername,
    required String staffFullName,
    required String staffRole,
  }) async {
    final storeCode = _currentStoreCode;
    final items = table.currentItems;
    final totalAmount = items.fold(0, (sum, i) => sum + i.itemTotal);
    final billCode = (table.currentBillId != null && table.currentBillId!.startsWith('HD-'))
        ? table.currentBillId!
        : FormatUtils.billCode();
    final orderCode = table.currentOrderCode ?? FormatUtils.orderCode();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cancelBillId = 'BILL_CANCELLED_$now';
    final deleted = table.deletedItems;
    final deletedSummary = DeletedItemsLogic.summarize(deleted);
    final cancelLog = OrderActionLogModel(
      timestamp: now,
      staffUsername: staffUsername,
      staffFullName: staffFullName,
      action: 'CANCEL_BILL',
      details: '$staffFullName hủy hóa đơn bàn ${table.name}. Lý do: $reason',
    ).toMap();

    final billRecord = {
      'id': cancelBillId,
      'billCode': billCode,
      'orderCode': orderCode,
      'tableName': table.name,
      'zone': table.zone,
      'storeCode': storeCode,
      'storeName': await _resolveStoreName(storeCode),
      'totalAmount': totalAmount,
      'subTotal': totalAmount,
      'discountAmount': 0,
      'totalDiscount': 0,
      'finalAmount': 0,
      'status': 'CANCELLED',
      'cancellationReason': reason,
      'cancelReason': reason,
      'timestamp': now,
      'createdAt': table.openedAt ?? now,
      'closedAt': now,
      'staffUsername': staffUsername,
      'staffFullName': staffFullName,
      'orderStaff': staffFullName,
      'items': items.map((i) => i.toMap()).toList(),
      'itemsJson': jsonEncode(items.map((i) => i.toMap()).toList()),
      'actionLogs': [...table.actionLogs.map((l) => l.toMap()), cancelLog],
      'actionLogsJson': jsonEncode([...table.actionLogs.map((l) => l.toMap()), cancelLog]),
      'deletedItems': deleted.map((e) => e.toMap()).toList(),
      'deletedItemsCount': deletedSummary.count,
      'deletedItemsAmount': deletedSummary.amount,
    };
    final cleared = _copyTable(table)..clearTable();

    await _commitWrite(
      _root.child('stores/$storeCode').update({
        'history/$cancelBillId': billRecord,
        'bills/$cancelBillId': billRecord,
        'tables/${table.firebaseKey}': cleared.toMap(),
      }),
      'hủy hóa đơn bàn ${table.name}',
    );
    table.clearTable();

    await _safeLog(AuditLogModel(
      timestamp: now,
      username: staffUsername,
      userFullName: staffFullName,
      userRole: staffRole,
      action: 'CANCEL_BILL',
      targetType: 'TABLE',
      targetId: table.name,
      details: 'Hủy hóa đơn $billCode (Mã đơn: $orderCode) bàn ${table.name} (${items.length} món, ${FormatUtils.vnd(totalAmount)}). Lý do: $reason',
      isSuspicious: true,
    ));
  }

  Future<void> cancelPaidBill({
    required BillModel bill,
    required String reason,
    required String staffUsername,
    required String staffFullName,
    required String staffRole,
  }) async {
    final storeCode = _currentStoreCode;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cancelLog = OrderActionLogModel(
      timestamp: now,
      staffUsername: staffUsername,
      staffFullName: staffFullName,
      action: 'CANCEL_BILL',
      details: '$staffFullName hủy hóa đơn ${bill.billCode}. Lý do: $reason',
    );
    final previousStatus = bill.status;
    final previousLogs = bill.actionLogs;
    bill.status = 'CANCELLED';
    bill.actionLogs = [...bill.actionLogs, cancelLog];

    final record = BillRecordBuilder.build(
      bill,
      storeCode: storeCode,
      storeName: await _resolveStoreName(storeCode),
      extra: {
        'cancelReason': reason,
        'cancellationReason': reason,
        'cancelledAt': now,
        'cancelledBy': staffFullName,
      },
    );
    try {
      await _commitWrite(
        _root.child('stores/$storeCode').update({
          'bills/${bill.id}': record,
          'history/${bill.id}': record,
        }),
        'hủy hóa đơn ${bill.billCode}',
      );
    } catch (_) {
      bill.status = previousStatus;
      bill.actionLogs = previousLogs;
      rethrow;
    }

    if (_onDeductCashShift != null) {
      await _onDeductCashShift(bill.paymentMethod, bill.finalAmount);
    }

    await _safeLog(AuditLogModel(
      timestamp: now,
      username: staffUsername,
      userFullName: staffFullName,
      userRole: staffRole,
      action: 'CANCEL_BILL',
      targetType: 'BILL',
      targetId: bill.billCode,
      details: 'Hủy hóa đơn ${bill.billCode} (Mã đơn: ${bill.orderCode ?? bill.billCode}) bàn ${bill.tableName} (${FormatUtils.vnd(bill.finalAmount)}). Lý do: $reason',
      isSuspicious: true,
    ));
  }

  Future<void> deleteBill({
    required BillModel bill,
    required String reason,
    required String staffUsername,
    required String staffFullName,
    required String staffRole,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _commitWrite(
      _root.child('stores/$_currentStoreCode').update({
        'bills/${bill.id}': null,
        'history/${bill.id}': null,
      }),
      'xóa hóa đơn ${bill.billCode}',
    );

    if (bill.status == 'PAID' && _onDeductCashShift != null) {
      await _onDeductCashShift(bill.paymentMethod, bill.finalAmount);
    }

    await _safeLog(AuditLogModel(
      timestamp: now,
      username: staffUsername,
      userFullName: staffFullName,
      userRole: staffRole,
      action: 'DELETE_BILL',
      targetType: 'BILL',
      targetId: bill.billCode,
      details: 'Xóa vĩnh viễn hóa đơn ${bill.billCode} (Mã đơn: ${bill.orderCode ?? bill.billCode}) bàn ${bill.tableName} (${FormatUtils.vnd(bill.finalAmount)}). Lý do: $reason',
      isSuspicious: true,
    ));
  }

  // ==================== PROMOTIONS ====================
  Stream<List<PromotionModel>> promotionsStream() {
    return promotionsRef.onValue.map<List<PromotionModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <PromotionModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
          .map((e) => PromotionModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList();
    }).handleError((_) => <PromotionModel>[]);
  }

  Future<List<PromotionModel>> getPromotions() async {
    try {
      final snap = await promotionsRef.get().timeout(const Duration(seconds: 2));
      if (!snap.exists || snap.value == null) return [];
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      return map.entries
          .map((e) => PromotionModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePromotion(PromotionModel promo) async {
    await promotionsRef.child(promo.id).set(promo.toMap());
  }

  Future<void> deletePromotion(String promoId) async {
    await promotionsRef.child(promoId).remove();
  }

  /// Tăng lượt dùng khuyến mãi (transaction, kiểm tra maxUsage).
  /// true = đã tăng; false = đã hết lượt; null = không tồn tại / chưa xác nhận (offline).
  Future<bool?> incrementPromotionUsage(String promoId) =>
      _changeLegacyPromotionUsage(_currentStoreCode, promoId, 1);

  // ==================== PRODUCTS & CATEGORIES ====================
  DatabaseReference getProductsRef([String? storeCode]) {
    final sc = (storeCode != null && storeCode.trim().isNotEmpty)
        ? storeCode.trim().toUpperCase()
        : _currentStoreCode;
    return _root.child('stores').child(sc).child('products');
  }

  DatabaseReference getCategoriesRef([String? storeCode]) {
    final sc = (storeCode != null && storeCode.trim().isNotEmpty)
        ? storeCode.trim().toUpperCase()
        : _currentStoreCode;
    return _root.child('stores').child(sc).child('categories');
  }

  Stream<List<ProductModel>> productsStream({String? storeCode}) {
    final ref = getProductsRef(storeCode);
    return ref.onValue.map<List<ProductModel>>((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        return _parseList<ProductModel>(event.snapshot.value, (k, v) => ProductModel.fromMap(v, k.toString()))
          ..sort((a, b) => a.name.compareTo(b.name));
      }
      return <ProductModel>[];
    }).handleError((_) => <ProductModel>[]);
  }

  Future<List<ProductModel>> getProducts({String? storeCode}) async {
    try {
      final ref = getProductsRef(storeCode);
      final snap = await ref.get().timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null) {
        return _parseList<ProductModel>(snap.value, (k, v) => ProductModel.fromMap(v, k.toString()))
          ..sort((a, b) => a.name.compareTo(b.name));
      }
      return <ProductModel>[];
    } catch (_) {
      return <ProductModel>[];
    }
  }

  Future<void> saveProduct(ProductModel product, {String? storeCode}) async {
    final ref = getProductsRef(storeCode);
    final key = product.name.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    await ref.child(key).set(product.toMap());
  }

  Future<void> deleteProduct(ProductModel product, {String? storeCode}) async {
    final ref = getProductsRef(storeCode);
    final key = product.name.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    await ref.child(key).remove();
  }

  Stream<List<CategoryModel>> categoriesStream({String? storeCode}) {
    final ref = getCategoriesRef(storeCode);
    return ref.onValue.map<List<CategoryModel>>((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        return _parseList<CategoryModel>(event.snapshot.value, (k, v) => CategoryModel.fromMap(v, k.toString()))
          ..sort((a, b) => a.name.compareTo(b.name));
      }
      return <CategoryModel>[];
    }).handleError((_) => <CategoryModel>[]);
  }

  Future<List<CategoryModel>> getCategories({String? storeCode}) async {
    try {
      final ref = getCategoriesRef(storeCode);
      final snap = await ref.get().timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null) {
        return _parseList<CategoryModel>(snap.value, (k, v) => CategoryModel.fromMap(v, k.toString()))
          ..sort((a, b) => a.name.compareTo(b.name));
      }
      return <CategoryModel>[];
    } catch (_) {
      return <CategoryModel>[];
    }
  }

  Future<void> saveCategory(CategoryModel category, {String? storeCode}) async {
    final ref = getCategoriesRef(storeCode);
    await ref.child(category.name).set(category.toMap());
  }

  Future<void> deleteCategory(CategoryModel category, {String? storeCode}) async {
    final ref = getCategoriesRef(storeCode);
    await ref.child(category.name).remove();
  }

  // ==================== PRODUCT NOTES (GHI CHÚ MẪU) ====================
  DatabaseReference getProductNotesRef([String? storeCode]) {
    final sc = (storeCode != null && storeCode.trim().isNotEmpty)
        ? storeCode.trim().toUpperCase()
        : _currentStoreCode;
    return _root.child('stores').child(sc).child('product_notes');
  }

  Stream<List<Map<String, dynamic>>> productNotesStream({String? storeCode}) {
    final ref = getProductNotesRef(storeCode);
    return ref.onValue.map<List<Map<String, dynamic>>>((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final val = event.snapshot.value;
        if (val is Map) {
          final list = <Map<String, dynamic>>[];
          val.forEach((k, v) {
            if (v is Map) {
              list.add({'id': k.toString(), ...Map<String, dynamic>.from(v)});
            } else if (v is String) {
              list.add({'id': k.toString(), 'text': v});
            }
          });
          return list;
        }
      }
      return <Map<String, dynamic>>[];
    }).handleError((_) => <Map<String, dynamic>>[]);
  }

  Future<void> saveProductNote(String noteId, Map<String, dynamic> data, {String? storeCode}) async {
    final ref = getProductNotesRef(storeCode);
    await ref.child(noteId).set(data);
  }

  Future<void> deleteProductNote(String noteId, {String? storeCode}) async {
    final ref = getProductNotesRef(storeCode);
    await ref.child(noteId).remove();
  }

  Future<int> copyMenuBetweenStores({
    required String fromStoreCode,
    required String toStoreCode,
    List<String>? selectedCategories,
  }) async {
    final sourceProducts = await getProducts(storeCode: fromStoreCode);
    final sourceCategories = await getCategories(storeCode: fromStoreCode);
    int copiedCount = 0;

    for (final cat in sourceCategories) {
      if (selectedCategories == null || selectedCategories.contains(cat.name)) {
        await saveCategory(cat, storeCode: toStoreCode);
      }
    }

    for (final prod in sourceProducts) {
      if (selectedCategories == null || selectedCategories.contains(prod.category)) {
        await saveProduct(prod, storeCode: toStoreCode);
        copiedCount++;
      }
    }
    return copiedCount;
  }

  Future<void> clearStoreMenu(String storeCode) async {
    await getProductsRef(storeCode).remove();
    await getCategoriesRef(storeCode).remove();
  }

  Stream<List<ZoneModel>> zonesStream() {
    return zonesRef.onValue.map<List<ZoneModel>>((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final list = _parseList<ZoneModel>(event.snapshot.value, (k, v) => ZoneModel.fromMap(v is Map ? v : {'name': k}));
        if (list.isNotEmpty) return list;
      }
      return SeedData.defaultZones;
    }).handleError((_) => SeedData.defaultZones);
  }

  Future<void> saveZone(ZoneModel zone) async {
    await zonesRef.child(zone.name).set(zone.toMap());
  }

  Future<void> deleteZone(ZoneModel zone) async {
    await zonesRef.child(zone.name).remove();
  }

  // ==================== KITCHEN ORDERS & ONLINE ORDERS ====================
  Stream<List<KitchenOrderModel>> kitchenOrdersStream() {
    return kitchenOrdersRef.onValue.map<List<KitchenOrderModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <KitchenOrderModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
          .map((e) => KitchenOrderModel.fromMap(Map<dynamic, dynamic>.from(e.value), key: e.key.toString()))
          .where((o) => !o.isDone)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }).handleError((_) => <KitchenOrderModel>[]);
  }

  /// Gửi phiếu bếp. Lỗi thật được ném ra ([DataWriteException]); mất mạng thì phiếu được
  /// giữ cục bộ và tự đồng bộ.
  Future<void> sendKitchenOrder(KitchenOrderModel order) async {
    final key = kitchenOrdersRef.push().key ?? DateTime.now().millisecondsSinceEpoch.toString();
    await _commitWrite(kitchenOrdersRef.child(key).set(order.toMap()), 'phiếu bếp bàn ${order.tableName}');
  }

  Future<void> sendOrderToKitchen({
    required TableModel table,
    required List<OrderItemModel> items,
    String? note,
    String? orderedBy,
    String? orderedByName,
  }) async {
    final unsent = items.where((i) => !i.isSentKitchen).toList();
    if (unsent.isEmpty) return;

    final currentUser = AuthService().currentUser;
    final staffUser = orderedBy ?? currentUser?.username;
    final staffName = orderedByName ?? currentUser?.fullName;

    final kitchenOrder = KitchenOrderModel(
      tableName: table.name,
      orderCode: table.currentOrderCode,
      billCode: table.currentBillId,
      itemsJson: jsonEncode(unsent.map((e) => e.toMap()).toList()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      note: note,
      orderedBy: staffUser,
      orderedByName: staffName,
    );

    await sendKitchenOrder(kitchenOrder);

    final updatedItems = items.map((i) => i.copyWith(isSentKitchen: true)).toList();
    table.currentOrderJson = jsonEncode(updatedItems.map((e) => e.toMap()).toList());
    table.inUse = true;
    await saveTable(table);
  }

  Future<void> markKitchenOrderDone(String key) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await kitchenOrdersRef.child(key).update({
      'isDone': true,
      'doneAt': now,
      'pickedUp': false,
    });
  }

  Future<void> markKitchenOrderPickedUp(String key, {String? pickedUpBy}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final staff = pickedUpBy ?? AuthService().currentUser?.fullName ?? AuthService().currentUser?.username;
    await kitchenOrdersRef.child(key).update({
      'pickedUp': true,
      'pickedUpAt': now,
      if (staff != null) 'pickedUpBy': staff,
    });
  }

  /// Lắng nghe các đơn món bếp đã nấu xong và chưa được nhân viên mang ra bàn trong 1-2 tiếng qua.
  Stream<List<KitchenOrderModel>> readyToServeKitchenOrdersStream({Duration maxAge = const Duration(hours: 2)}) {
    return kitchenOrdersRef.onValue.map<List<KitchenOrderModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <KitchenOrderModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final now = DateTime.now().millisecondsSinceEpoch;
      final maxAgeMs = maxAge.inMilliseconds;
      return map.entries
          .map((e) => KitchenOrderModel.fromMap(Map<dynamic, dynamic>.from(e.value), key: e.key.toString()))
          .where((o) {
            if (!o.isDone || o.pickedUp) return false;
            final itemTime = o.doneAt ?? o.timestamp;
            return (now - itemTime) <= maxAgeMs;
          })
          .toList()
        ..sort((a, b) => (b.doneAt ?? b.timestamp).compareTo(a.doneAt ?? a.timestamp));
    }).handleError((_) => <KitchenOrderModel>[]);
  }

  Stream<List<OnlineOrderModel>> onlineOrdersStream() {
    return onlineOrdersRef.onValue.map<List<OnlineOrderModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <OnlineOrderModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
          .map((e) => OnlineOrderModel.fromMap(Map<dynamic, dynamic>.from(e.value), key: e.key.toString()))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }).handleError((_) => <OnlineOrderModel>[]);
  }

  Future<void> updateOnlineOrderStatus(String key, String status) async {
    await onlineOrdersRef.child(key).update({'status': status});
  }

  int compareTables(TableModel a, TableModel b) {
    if (a.zone != b.zone) {
      return a.zone.toLowerCase().compareTo(b.zone.toLowerCase());
    }
    return compareNatural(a.name, b.name);
  }

  int compareNatural(String a, String b) {
    final regex = RegExp(r'(\d+)|(\D+)');
    final matchesA = regex.allMatches(a).map((m) => m.group(0)!).toList();
    final matchesB = regex.allMatches(b).map((m) => m.group(0)!).toList();
    final minLen = matchesA.length < matchesB.length ? matchesA.length : matchesB.length;
    for (int i = 0; i < minLen; i++) {
      final partA = matchesA[i];
      final partB = matchesB[i];
      final numA = int.tryParse(partA);
      final numB = int.tryParse(partB);
      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
      } else {
        final cmp = partA.toLowerCase().compareTo(partB.toLowerCase());
        if (cmp != 0) return cmp;
      }
    }
    return matchesA.length.compareTo(matchesB.length);
  }
}

/// Các lượt khuyến mãi đã giữ cho 1 hóa đơn (để hoàn tác nếu ghi hóa đơn thất bại)
class _PromoCommit {
  final List<PromotionUsageReservation> campaigns = [];
  final List<String> legacyIds = [];
  final List<String> notes = [];
}

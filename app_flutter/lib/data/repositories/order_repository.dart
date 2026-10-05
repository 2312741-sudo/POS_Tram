import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import '../../core/utils/format_utils.dart';
import '../models/app_models.dart';
import '../services/inventory_service.dart';
import '../services/campaign_service.dart';
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

  // ==================== TABLES ====================
  Stream<List<TableModel>> tablesStream() {
    return tablesRef.onValue.asyncMap<List<TableModel>>((event) async {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final list = _parseList<TableModel>(
          event.snapshot.value,
          (k, v) => TableModel.fromMap(v is Map ? v : {'name': k}, k.toString()),
        );
        if (list.isNotEmpty) {
          return list..sort(compareTables);
        }
      }
      // Check root /tables fallback
      try {
        final rootSnap = await _root.child('tables').get().timeout(const Duration(seconds: 2));
        if (rootSnap.exists && rootSnap.value != null) {
          final rootList = _parseList<TableModel>(
            rootSnap.value,
            (k, v) => TableModel.fromMap(v is Map ? v : {'name': k}, k.toString()),
          );
          if (rootList.isNotEmpty) {
            return rootList..sort(compareTables);
          }
        }
      } catch (_) {}
      return SeedData.defaultTables;
    }).handleError((_) => SeedData.defaultTables);
  }

  Future<void> saveTable(TableModel table) async {
    try {
      await tablesRef.child(table.firebaseKey).set(table.toMap()).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> deleteTable(TableModel table) async {
    await tablesRef.child(table.firebaseKey).remove();
  }

  Future<void> mergeTables(TableModel sourceTable, TableModel targetTable, {String? staffName, String? staffUsername}) async {
    final sourceItems = sourceTable.currentItems;
    final targetItems = targetTable.currentItems;

    final Map<int, OrderItemModel> combined = {};
    for (final item in targetItems) {
      combined[item.productId] = item;
    }
    for (final item in sourceItems) {
      if (combined.containsKey(item.productId)) {
        final existing = combined[item.productId]!;
        combined[item.productId] = existing.copyWith(
          quantity: existing.quantity + item.quantity,
          note: '${existing.note} ${item.note}'.trim(),
        );
      } else {
        combined[item.productId] = item;
      }
    }

    final sourceItemNames = sourceItems.map((e) => "${e.name} (x${e.quantity})").join(", ");
    targetTable.inUse = true;
    targetTable.currentOrderJson = jsonEncode(combined.values.map((e) => e.toMap()).toList());
    final int combinedGuests = (targetTable.guestCount ?? 0) + (sourceTable.guestCount ?? 0);
    targetTable.guestCount = combinedGuests > 0 ? combinedGuests : null;
    if (targetTable.openedAt == null || (sourceTable.openedAt != null && sourceTable.openedAt! < targetTable.openedAt!)) {
      targetTable.openedAt = sourceTable.openedAt ?? targetTable.openedAt ?? DateTime.now().millisecondsSinceEpoch;
    }
    targetTable.addActionLog(OrderActionLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      staffUsername: staffUsername ?? 'staff',
      staffFullName: staffName ?? 'Nhân viên',
      action: 'MERGE_TABLE',
      details: 'Gộp ${sourceTable.name} vào ${targetTable.name}: chuyển ${sourceItems.length} món ($sourceItemNames)',
    ));
    await saveTable(targetTable);

    sourceTable.inUse = false;
    sourceTable.currentOrderJson = '';
    sourceTable.openedAt = null;
    sourceTable.guestCount = null;
    sourceTable.currentBillId = null;
    sourceTable.mergedIntoTable = targetTable.name;
    sourceTable.actionLogsJson = null;
    await saveTable(sourceTable);

    await _logAction(AuditLogModel(
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

  Future<void> transferTable(TableModel sourceTable, TableModel targetTable, {String? staffName, String? staffUsername}) async {
    final itemNames = sourceTable.currentItems.map((e) => "${e.name} (x${e.quantity})").join(", ");
    targetTable.inUse = true;
    targetTable.currentOrderJson = sourceTable.currentOrderJson;
    targetTable.openedAt = sourceTable.openedAt;
    targetTable.guestCount = sourceTable.guestCount;
    targetTable.currentBillId = sourceTable.currentBillId;
    targetTable.actionLogsJson = sourceTable.actionLogsJson;
    targetTable.addActionLog(OrderActionLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      staffUsername: staffUsername ?? 'staff',
      staffFullName: staffName ?? 'Nhân viên',
      action: 'TRANSFER_TABLE',
      details: 'Chuyển toàn bộ món từ ${sourceTable.name} sang ${targetTable.name}',
    ));
    await saveTable(targetTable);

    sourceTable.inUse = false;
    sourceTable.currentOrderJson = '';
    sourceTable.openedAt = null;
    sourceTable.guestCount = null;
    sourceTable.currentBillId = null;
    sourceTable.mergedIntoTable = null;
    sourceTable.actionLogsJson = null;
    await saveTable(sourceTable);

    await _logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: staffUsername ?? 'staff',
      userFullName: staffName ?? 'Nhân viên',
      userRole: 'STAFF',
      action: 'TRANSFER_TABLE',
      targetType: 'TABLE',
      targetId: '${sourceTable.name} -> ${targetTable.name}',
      details: '${staffName ?? "Nhân viên"} chuyển bàn từ ${sourceTable.name} sang ${targetTable.name} (${sourceTable.currentItems.length} món: $itemNames)',
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

  Future<void> closeAndPayBill(BillModel bill, TableModel table) async {
    bill.status = 'PAID';
    bill.closedAt = DateTime.now().millisecondsSinceEpoch;
    await saveBill(bill);

    final historyMap = {
      'id': bill.id,
      'storeCode': _currentStoreCode,
      'storeName': _currentStoreCode == 'TRAM01' ? 'POS Trạm - Trụ sở 01 (Đà Lạt)' : 'POS Trạm - Chi nhánh $_currentStoreCode',
      'billCode': bill.billCode,
      'orderCode': bill.orderCode ?? bill.billCode,
      'tableName': bill.tableName,
      'zone': bill.zone,
      'totalAmount': bill.finalAmount,
      'subTotal': bill.subTotal,
      'discountAmount': bill.totalDiscount,
      'paymentMethod': bill.paymentMethod,
      'status': 'PAID',
      'timestamp': bill.closedAt ?? bill.createdAt,
      'createdAt': bill.createdAt,
      'closedAt': bill.closedAt,
      'staffUsername': bill.staffUsername,
      'staffFullName': bill.staffFullName,
      'cashierName': bill.staffFullName.isNotEmpty ? bill.staffFullName : bill.staffUsername,
      'orderStaff': bill.orderStaffSummary,
      'items': bill.items.map((i) => i.toMap()).toList(),
      'itemsJson': jsonEncode(bill.items.map((i) => i.toMap()).toList()),
      'actionLogs': bill.actionLogs.map((a) => a.toMap()).toList(),
      'actionLogsJson': jsonEncode(bill.actionLogs.map((a) => a.toMap()).toList()),
    };
    billsRef.child(bill.id).set(historyMap).catchError((_) {});
    _root.child('stores/$_currentStoreCode/history').child(bill.id).set(historyMap).catchError((_) {});

    table.clearTable();
    await saveTable(table);

    for (final d in bill.discounts) {
      if (d.promoId != null) {
        incrementPromotionUsage(d.promoId!);
      }
    }

    try {
      await InventoryService().consumeStockForBill(
        bill.items,
        bill.id,
        bill.staffUsername,
      );
    } catch (_) {}

    try {
      for (final d in bill.discounts) {
        if (d.promoCode != null && d.promoCode!.isNotEmpty) {
          final v = await CampaignService().lookupVoucherByCode(d.promoCode!);
          if (v != null) {
            await CampaignService().commitPromotionUsage(
              campaignId: v.campaignId,
              discountMoney: d.amount,
              billId: bill.id,
              username: bill.staffUsername,
              voucherCode: d.promoCode,
              customerId: null,
            );
            continue;
          }
        }
        if (d.promoId != null && d.promoId!.isNotEmpty) {
          final cam = await CampaignService().getCampaign(d.promoId!);
          if (cam != null) {
            await CampaignService().commitPromotionUsage(
              campaignId: cam.campaignId,
              discountMoney: d.amount,
              billId: bill.id,
              username: bill.staffUsername,
              voucherCode: d.promoCode,
              customerId: null,
            );
          }
        }
      }
    } catch (_) {}

    await _logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: bill.staffUsername,
      userFullName: bill.staffFullName,
      userRole: 'CASHIER',
      action: 'PAY_BILL',
      targetType: 'BILL',
      targetId: bill.billCode,
      details: 'Thanh toán hóa đơn ${bill.billCode} bàn ${bill.tableName}: ${bill.finalAmount}đ (${bill.paymentMethod})',
    ));
  }

  Future<void> cancelActiveBill(
    TableModel table, {
    required String reason,
    required String staffUsername,
    required String staffFullName,
    required String staffRole,
  }) async {
    final items = table.currentItems;
    final totalAmount = items.fold(0, (sum, i) => sum + i.itemTotal);
    final billCode = (table.currentBillId != null && table.currentBillId!.startsWith('HD-'))
        ? table.currentBillId!
        : FormatUtils.billCode();
    final orderCode = table.currentOrderCode ?? FormatUtils.orderCode();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cancelBillId = 'BILL_CANCELLED_$now';

    final billRecord = {
      'id': cancelBillId,
      'billCode': billCode,
      'orderCode': orderCode,
      'tableName': table.name,
      'zone': table.zone,
      'storeCode': _currentStoreCode,
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
      'actionLogs': [
        OrderActionLogModel(
          timestamp: now,
          staffUsername: staffUsername,
          staffFullName: staffFullName,
          action: 'CANCEL_BILL',
          details: '$staffFullName hủy hóa đơn bàn ${table.name}. Lý do: $reason',
        ).toMap(),
      ],
      'actionLogsJson': jsonEncode([
        OrderActionLogModel(
          timestamp: now,
          staffUsername: staffUsername,
          staffFullName: staffFullName,
          action: 'CANCEL_BILL',
          details: '$staffFullName hủy hóa đơn bàn ${table.name}. Lý do: $reason',
        ).toMap(),
      ]),
    };
    _root.child('stores/$_currentStoreCode/history').child(cancelBillId).set(billRecord).catchError((_) {});
    billsRef.child(cancelBillId).set(billRecord).catchError((_) {});

    table.clearTable();
    await saveTable(table);

    await _logAction(AuditLogModel(
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
    final now = DateTime.now().millisecondsSinceEpoch;
    bill.status = 'CANCELLED';
    final cancelLog = OrderActionLogModel(
      timestamp: now,
      staffUsername: staffUsername,
      staffFullName: staffFullName,
      action: 'CANCEL_BILL',
      details: '$staffFullName hủy hóa đơn ${bill.billCode}. Lý do: $reason',
    );
    bill.actionLogs.add(cancelLog);

    await billsRef.child(bill.id).set(bill.toMap());

    final historyMap = {
      'id': bill.id,
      'storeCode': _currentStoreCode,
      'storeName': _currentStoreCode == 'TRAM01' ? 'POS Trạm - Trụ sở 01 (Đà Lạt)' : 'POS Trạm - Chi nhánh $_currentStoreCode',
      'billCode': bill.billCode,
      'orderCode': bill.orderCode ?? bill.billCode,
      'tableName': bill.tableName,
      'zone': bill.zone,
      'totalAmount': bill.finalAmount,
      'subTotal': bill.subTotal,
      'discountAmount': bill.totalDiscount,
      'paymentMethod': bill.paymentMethod,
      'status': 'CANCELLED',
      'cancelReason': reason,
      'cancelledAt': now,
      'cancelledBy': staffFullName,
      'timestamp': bill.closedAt ?? bill.createdAt,
      'createdAt': bill.createdAt,
      'closedAt': bill.closedAt,
      'staffUsername': bill.staffUsername,
      'staffFullName': bill.staffFullName,
      'cashierName': bill.staffFullName.isNotEmpty ? bill.staffFullName : bill.staffUsername,
      'orderStaff': bill.orderStaffSummary,
      'items': bill.items.map((i) => i.toMap()).toList(),
      'itemsJson': jsonEncode(bill.items.map((i) => i.toMap()).toList()),
      'actionLogs': bill.actionLogs.map((a) => a.toMap()).toList(),
      'actionLogsJson': jsonEncode(bill.actionLogs.map((a) => a.toMap()).toList()),
    };
    billsRef.child(bill.id).set(historyMap).catchError((_) {});
    _root.child('stores/$_currentStoreCode/history').child(bill.id).set(historyMap).catchError((_) {});

    if (_onDeductCashShift != null) {
      await _onDeductCashShift(bill.paymentMethod, bill.finalAmount);
    }

    await _logAction(AuditLogModel(
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

    await billsRef.child(bill.id).remove();
    await _root.child('stores/$_currentStoreCode/history').child(bill.id).remove().catchError((_) {});

    if (bill.status == 'PAID' && _onDeductCashShift != null) {
      await _onDeductCashShift(bill.paymentMethod, bill.finalAmount);
    }

    await _logAction(AuditLogModel(
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

  Future<void> incrementPromotionUsage(String promoId) async {
    try {
      final snap = await promotionsRef.child(promoId).child('usageCount').get().timeout(const Duration(seconds: 2));
      final count = (snap.value as num?)?.toInt() ?? 0;
      await promotionsRef.child(promoId).child('usageCount').set(count + 1);
    } catch (_) {}
  }

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
    return zonesRef.onValue.asyncMap<List<ZoneModel>>((event) async {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final list = _parseList<ZoneModel>(event.snapshot.value, (k, v) => ZoneModel.fromMap(v is Map ? v : {'name': k}));
        if (list.isNotEmpty) return list;
      }
      try {
        final rootSnap = await _root.child('zones').get().timeout(const Duration(seconds: 2));
        if (rootSnap.exists && rootSnap.value != null) {
          final rootList = _parseList<ZoneModel>(rootSnap.value, (k, v) => ZoneModel.fromMap(v is Map ? v : {'name': k}));
          if (rootList.isNotEmpty) return rootList;
        }
      } catch (_) {}
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

  Future<void> sendKitchenOrder(KitchenOrderModel order) async {
    final key = kitchenOrdersRef.push().key ?? DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await kitchenOrdersRef.child(key).set(order.toMap()).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> sendOrderToKitchen({
    required TableModel table,
    required List<OrderItemModel> items,
    String? note,
  }) async {
    final unsent = items.where((i) => !i.isSentKitchen).toList();
    if (unsent.isEmpty) return;

    final kitchenOrder = KitchenOrderModel(
      tableName: table.name,
      itemsJson: jsonEncode(unsent.map((e) => e.toMap()).toList()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      note: note,
    );

    await sendKitchenOrder(kitchenOrder);

    final updatedItems = items.map((i) => i.copyWith(isSentKitchen: true)).toList();
    table.currentOrderJson = jsonEncode(updatedItems.map((e) => e.toMap()).toList());
    table.inUse = true;
    await saveTable(table);
  }

  Future<void> markKitchenOrderDone(String key) async {
    await kitchenOrdersRef.child(key).child('isDone').set(true);
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

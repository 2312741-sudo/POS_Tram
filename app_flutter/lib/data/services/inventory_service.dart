import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import '../../data/models/inventory_models.dart';
import '../../core/domain/order_integrity.dart';

/// Dịch vụ xử lý các thao tác Firebase RTDB cho phân hệ kho (Inventory/Warehouse)
class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  InventoryService._internal();

  final _db = FirebaseDatabase.instance;
  String _currentStoreCode = 'TRAM01';

  DatabaseReference get _storeRef => _db.ref('stores/$_currentStoreCode');
  DatabaseReference get storeRef => _storeRef;
  String get currentStoreCode => _currentStoreCode;
  DatabaseReference storeRefFor(String storeCode) => _db.ref('stores/$storeCode');

  /// Chuyển đổi chi nhánh
  void switchStore(String storeCode) {
    if (storeCode.isNotEmpty) {
      _currentStoreCode = storeCode.toUpperCase().trim();
    }
  }

  Future<void> saveCatalogItemToBranch(String branchCode, CatalogItemModel item) async {
    await _db.ref('stores/$branchCode/catalog_items/${item.itemId}').set(item.toMap());
  }

  Future<void> saveStockBalance(StockBalanceModel balance) async {
    await _storeRef.child('stock_balances/${balance.balanceId}').set(balance.toMap());
  }

  Future<void> saveStockBalanceToBranch(String branchCode, StockBalanceModel balance) async {
    await _db.ref('stores/$branchCode/stock_balances/${balance.balanceId}').set(balance.toMap());
  }

  // ==================== HÀNG KHO (CATALOG ITEMS) ====================

  /// Stream danh sách hàng kho real-time
  Stream<List<CatalogItemModel>> catalogItemsStream() {
    return _storeRef.child('catalog_items').onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      return map.values.map((e) => CatalogItemModel.fromMap(Map<String, dynamic>.from(e))).toList();
    });
  }

  /// Lấy danh sách hàng kho (một lần)
  Future<List<CatalogItemModel>> getCatalogItems() async {
    final snapshot = await _storeRef.child('catalog_items').get();
    if (snapshot.value == null) return [];
    final Map<dynamic, dynamic> map = snapshot.value as Map<dynamic, dynamic>;
    return map.values.map((e) => CatalogItemModel.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  /// Lấy thông tin một hàng kho
  Future<CatalogItemModel?> getCatalogItem(String itemId) async {
    final snapshot = await _storeRef.child('catalog_items/$itemId').get();
    if (snapshot.value == null) return null;
    return CatalogItemModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
  }

  /// Thêm hoặc cập nhật hàng kho
  Future<void> saveCatalogItem(CatalogItemModel item) async {
    await _storeRef.child('catalog_items/${item.itemId}').set(item.toMap());
  }

  /// Xóa mềm hàng kho (chuyển trạng thái DISCONTINUED)
  Future<void> deleteCatalogItem(String itemId) async {
    final item = await getCatalogItem(itemId);
    if (item != null) {
      final updated = item.copyWith(status: 'DISCONTINUED');
      await saveCatalogItem(updated);
    }
  }

  /// Tạo ID mới cho hàng kho
  String generateItemId() {
    return 'ITM_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  /// Tạo mã SKU
  String generateSku(int sequence) {
    return 'NVL${sequence.toString().padLeft(4, '0')}';
  }

  // ==================== NHÀ CUNG CẤP (SUPPLIERS) ====================

  /// Stream danh sách nhà cung cấp
  Stream<List<SupplierModel>> suppliersStream() {
    return _storeRef.child('suppliers').onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      return map.values.map((e) => SupplierModel.fromMap(Map<String, dynamic>.from(e))).toList();
    });
  }

  /// Lấy danh sách nhà cung cấp một lần
  Future<List<SupplierModel>> getSuppliers() async {
    final snapshot = await _storeRef.child('suppliers').get();
    if (snapshot.value == null) return [];
    final Map<dynamic, dynamic> map = snapshot.value as Map<dynamic, dynamic>;
    return map.values.map((e) => SupplierModel.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  /// Thêm hoặc cập nhật nhà cung cấp
  Future<void> saveSupplier(SupplierModel supplier) async {
    await _storeRef.child('suppliers/${supplier.supplierId}').set(supplier.toMap());
  }

  /// Xóa mềm nhà cung cấp (chuyển trạng thái INACTIVE)
  Future<void> deleteSupplier(String supplierId) async {
    final snapshot = await _storeRef.child('suppliers/$supplierId').get();
    if (snapshot.value != null) {
      final supplier = SupplierModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
      final updated = supplier.copyWith(status: 'INACTIVE');
      await saveSupplier(updated);
    }
  }

  /// Tạo ID mới cho nhà cung cấp
  String generateSupplierId() {
    return 'SUP_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  /// Tạo mã NCC
  String generateSupplierCode(int sequence) {
    return 'NCC${sequence.toString().padLeft(4, '0')}';
  }

  // ==================== SỐ DƯ TỒN KHO (STOCK BALANCES) ====================

  /// Stream tồn kho của chi nhánh hiện tại
  Stream<List<StockBalanceModel>> stockBalancesStream() {
    return _storeRef.child('stock_balances').orderByChild('branchId').equalTo(_currentStoreCode).onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      return map.values.map((e) => StockBalanceModel.fromMap(Map<String, dynamic>.from(e))).toList();
    });
  }

  /// Lấy danh sách tồn kho một lần
  Future<List<StockBalanceModel>> getStockBalances() async {
    final snapshot = await _storeRef.child('stock_balances').get();
    if (snapshot.value == null) return [];
    final Map<dynamic, dynamic> map = snapshot.value as Map<dynamic, dynamic>;
    return map.values.map((e) => StockBalanceModel.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  /// Lấy số dư tồn của 1 mặt hàng tại chi nhánh hiện tại
  Future<StockBalanceModel?> getStockBalance(String itemId) async {
    final balanceId = '${_currentStoreCode}_$itemId';
    final snapshot = await _storeRef.child('stock_balances/$balanceId').get();
    if (snapshot.value == null) return null;
    return StockBalanceModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
  }

  /// Cập nhật số dư kho (Nội bộ) - dùng transaction để các giao dịch đồng thời không ghi đè nhau
  Future<void> _updateStockBalance(String itemId, int qtyDelta, int valueDelta) async {
    final balanceId = '${_currentStoreCode}_$itemId';
    final branchId = _currentStoreCode;
    final res = await _storeRef.child('stock_balances/$balanceId').runTransaction((Object? current) {
      final now = DateTime.now().millisecondsSinceEpoch;
      int toInt(Object? v) => v is num ? v.toInt() : 0;
      if (current == null) {
        final unitCostScaled = qtyDelta > 0 ? ((valueDelta / qtyDelta) * 100).round() : 0;
        return Transaction.success(StockBalanceModel(
          balanceId: balanceId,
          branchId: branchId,
          itemId: itemId,
          onHandQty: qtyDelta,
          inventoryValue: valueDelta,
          averageCostScaled: unitCostScaled,
          lastEventSeq: 0,
          updatedAt: now,
        ).toMap());
      }
      final data = Map<String, dynamic>.from(current as Map);
      final oldQty = toInt(data['onHandQty']);
      int newAvgCostScaled = toInt(data['averageCostScaled']);
      // Cập nhật giá vốn bình quân nếu là nhập kho (qtyDelta > 0)
      if (qtyDelta > 0) {
        final unitCostScaled = ((valueDelta / qtyDelta) * 100).round();
        newAvgCostScaled = calculateNewAverageCost(oldQty, newAvgCostScaled, qtyDelta, unitCostScaled);
      }
      data['onHandQty'] = oldQty + qtyDelta;
      data['inventoryValue'] = toInt(data['inventoryValue']) + valueDelta;
      data['averageCostScaled'] = newAvgCostScaled;
      data['updatedAt'] = now;
      data['version'] = toInt(data['version']) + 1;
      return Transaction.success(data);
    });
    if (!res.committed) {
      throw Exception('Không cập nhật được tồn kho $itemId');
    }
  }

  /// Cập nhật giá vốn bình quân gia quyền khi nhập hàng
  /// newAvgCost = (oldQty * oldAvgCost + newQty * newUnitCost) / (oldQty + newQty)
  int calculateNewAverageCost(int oldQty, int oldAvgCostScaled, int newQty, int newUnitCostScaled) {
    if (oldQty + newQty == 0) return 0;
    return ((oldQty * oldAvgCostScaled + newQty * newUnitCostScaled) / (oldQty + newQty)).round();
  }

  // ==================== SỔ KHO (STOCK EVENTS) ====================

  /// Stream biến động kho, tùy chọn lọc theo mặt hàng
  Stream<List<StockEventModel>> stockEventsStream({String? itemId, int? limit}) {
    Query query = _storeRef.child('stock_events');
    if (itemId != null) {
      query = query.orderByChild('itemId').equalTo(itemId);
    }
    if (limit != null) {
      query = query.limitToLast(limit);
    }
    return query.onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      final list = map.values.map((e) => StockEventModel.fromMap(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return list;
    });
  }

  /// Ghi nhận biến động kho mới
  Future<void> _appendStockEvent(StockEventModel event) async {
    await _storeRef.child('stock_events/${event.eventId}').set(event.toMap());
  }

  // ==================== PHIẾU KHO (INVENTORY DOCUMENTS) ====================

  /// Stream danh sách phiếu kho
  Stream<List<InventoryDocumentModel>> inventoryDocumentsStream({String? docType}) {
    Query query = _storeRef.child('inventory_documents');
    if (docType != null) {
      query = query.orderByChild('docType').equalTo(docType);
    }
    return query.onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      final list = map.values.map((e) => InventoryDocumentModel.fromMap(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Lấy phiếu kho theo ID
  Future<InventoryDocumentModel?> getInventoryDocument(String docId) async {
    final snapshot = await _storeRef.child('inventory_documents/$docId').get();
    if (snapshot.value == null) return null;
    return InventoryDocumentModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
  }

  /// Lưu bản nháp phiếu kho
  Future<void> saveInventoryDocumentDraft(InventoryDocumentModel doc) async {
    await _storeRef.child('inventory_documents/${doc.documentId}').set(doc.toMap());
  }

  /// Hoàn thành phiếu kho, xử lý biến động và công nợ
  Future<void> completeInventoryDocument(InventoryDocumentModel doc) async {
    if (doc.status != 'DRAFT') {
      throw Exception('Chỉ có thể hoàn thành phiếu nháp.');
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    List<String> eventIds = [];

    for (var line in doc.lines) {
      // 1. Tính toán quantityBase
      int qtyBase = (line.quantity * line.conversionNumerator / line.conversionDenominator).round();

      // 2. Tạo StockEvent
      int qtyDeltaBase = 0;
      if (doc.docType == 'PURCHASE_RECEIPT' || doc.docType == 'PRODUCTION_OUTPUT' || doc.docType == 'OPENING' || doc.docType == 'TRANSFER_RECEIVE') {
        qtyDeltaBase = qtyBase;
      } else {
        qtyDeltaBase = -qtyBase;
      }

      int valueDeltaMoney = 0;
      int unitCostSnapshot = 0;
      final balance = await getStockBalance(line.itemId);
      
      if (qtyDeltaBase > 0) {
        valueDeltaMoney = line.lineNetMoney; 
      } else {
        if (balance != null && balance.averageCostScaled > 0) {
          valueDeltaMoney = -((qtyBase * balance.averageCostScaled) / 100).round();
        }
      }
      if (balance != null) {
        unitCostSnapshot = balance.averageCostScaled;
      }

      final eventId = 'EVT_${now}_${Random().nextInt(10000)}';
      final event = StockEventModel(
        eventId: eventId,
        commandId: doc.idempotencyKey,
        documentId: doc.documentId,
        documentType: doc.docType,
        documentLineId: line.lineId,
        branchId: _currentStoreCode,
        itemId: line.itemId,
        qtyDeltaBase: qtyDeltaBase,
        valueDeltaMoney: valueDeltaMoney,
        unitCostSnapshot: unitCostSnapshot,
        occurredAt: now,
        committedAt: now,
        actorId: doc.createdBy,
        sequence: now,
      );

      await _appendStockEvent(event);
      eventIds.add(eventId);

      // 3. Cập nhật StockBalance
      await _updateStockBalance(line.itemId, qtyDeltaBase, valueDeltaMoney);
    }

    // 4 & 5. Tạo SupplierLedgerEntry
    if (doc.docType == 'PURCHASE_RECEIPT' && doc.supplierId != null) {
      final entryId = 'LED_${now}_${Random().nextInt(10000)}';
      final entry = SupplierLedgerEntryModel(
        entryId: entryId,
        supplierId: doc.supplierId!,
        branchId: _currentStoreCode,
        entryType: 'PURCHASE',
        amountMoney: doc.totalNetMoney,
        referenceDocId: doc.documentId,
        referenceDocType: doc.docType,
        occurredAt: now,
        committedAt: now,
        actorId: doc.createdBy,
      );
      await _storeRef.child('supplier_ledger/$entryId').set(entry.toMap());
    } else if (doc.docType == 'PURCHASE_RETURN' && doc.supplierId != null) {
      final entryId = 'LED_${now}_${Random().nextInt(10000)}';
      final entry = SupplierLedgerEntryModel(
        entryId: entryId,
        supplierId: doc.supplierId!,
        branchId: _currentStoreCode,
        entryType: 'RETURN',
        amountMoney: -doc.totalNetMoney,
        referenceDocId: doc.documentId,
        referenceDocType: doc.docType,
        occurredAt: now,
        committedAt: now,
        actorId: doc.createdBy,
      );
      await _storeRef.child('supplier_ledger/$entryId').set(entry.toMap());
    }

    // Cập nhật trạng thái phiếu kho
    final updatedDoc = doc.copyWith(
      status: 'COMPLETED',
      completedAt: now,
      completedBy: doc.createdBy,
      completedByName: doc.createdByName,
      committedEventIds: eventIds,
    );
    await _storeRef.child('inventory_documents/${doc.documentId}').set(updatedDoc.toMap());
  }

  /// Hủy phiếu kho nháp
  Future<void> cancelInventoryDocument(String docId, String reason, String username) async {
    final snapshot = await _storeRef.child('inventory_documents/$docId').get();
    if (snapshot.value != null) {
      final doc = InventoryDocumentModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
      if (doc.status == 'DRAFT') {
        final updatedDoc = doc.copyWith(
          status: 'CANCELLED',
          cancelledAt: DateTime.now().millisecondsSinceEpoch,
          cancelReason: reason,
        );
        await _storeRef.child('inventory_documents/$docId').set(updatedDoc.toMap());
      }
    }
  }

  /// Tạo ID phiếu kho
  String generateDocumentId() {
    return 'DOC_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  /// Tạo mã phiếu kho theo tiền tố
  String generateDocumentCode(String prefix) {
    final now = DateTime.now();
    final dateStr = '${(now.year % 100).toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final randomStr = Random().nextInt(1000).toString().padLeft(3, '0');
    return '$prefix-$dateStr-$randomStr';
  }

  // ==================== CÔNG THỨC (RECIPES) ====================

  /// Stream danh sách công thức
  Stream<List<RecipeVersionModel>> recipesStream({String? outputItemId}) {
    Query query = _storeRef.child('recipes');
    if (outputItemId != null) {
      query = query.orderByChild('outputItemId').equalTo(outputItemId);
    }
    return query.onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      return map.values.map((e) => RecipeVersionModel.fromMap(Map<String, dynamic>.from(e))).toList();
    });
  }

  /// Lưu công thức
  Future<void> saveRecipe(RecipeVersionModel recipe) async {
    await _storeRef.child('recipes/${recipe.recipeId}').set(recipe.toMap());
  }

  /// Xóa công thức
  Future<void> deleteRecipe(String recipeId) async {
    final snapshot = await _storeRef.child('recipes/$recipeId').get();
    if (snapshot.value != null) {
      final recipe = RecipeVersionModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
      final updated = recipe.copyWith(status: 'ARCHIVED');
      await saveRecipe(updated);
    }
  }

  // ==================== TIÊU HAO KHO (STOCK CONSUMPTION) ====================

  /// Tiêu hao kho khi bán hàng.
  ///
  /// - Idempotent: đánh dấu stores/{s}/bill_stock_applied/{billId} = true (chỉ tạo mới);
  ///   gọi lại cho cùng hóa đơn sẽ bỏ qua, không trừ kho 2 lần.
  /// - Trừ số dư bằng transaction trên stock_balances/{id} (an toàn khi bán đồng thời).
  /// - Trừ cả topping nếu topping có hàng kho (trùng tên) và công thức.
  /// - Tải công thức + hàng kho 1 lần mỗi lần gọi.
  /// [billItems] nhận List<OrderItemModel> hoặc List<Map> (khóa productId / product_id).
  /// Ném [StockConsumptionException] nếu có dòng trừ kho thất bại.
  Future<StockConsumptionResult> consumeStockForBill(
    List<dynamic> billItems,
    String billId,
    String username, {
    String? storeCode,
  }) async {
    final sc = (storeCode != null && storeCode.trim().isNotEmpty) ? storeCode.trim().toUpperCase() : _currentStoreCode;
    final store = storeRefFor(sc);
    final lines = billItems.map(StockSaleLine.from).whereType<StockSaleLine>().toList();
    if (lines.isEmpty) return StockConsumptionResult(applied: false, alreadyApplied: false);

    // 1. Tải công thức + hàng kho (1 lần cho cả hóa đơn)
    final recipeSnap = await store.child('recipes').get();
    final recipes = <RecipeVersionModel>[];
    if (recipeSnap.value is Map) {
      for (final e in (recipeSnap.value as Map).values) {
        if (e is Map) {
          try {
            recipes.add(RecipeVersionModel.fromMap(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
    }
    if (recipes.isEmpty) return StockConsumptionResult(applied: false, alreadyApplied: false);

    final catalogSnap = await store.child('catalog_items').get();
    final byLegacy = <int, String>{};
    final byName = <String, String>{};
    if (catalogSnap.value is Map) {
      for (final e in (catalogSnap.value as Map).values) {
        if (e is! Map) continue;
        try {
          final item = CatalogItemModel.fromMap(Map<String, dynamic>.from(e));
          if (item.status == 'DISCONTINUED') continue;
          if (item.legacyProductId != null) byLegacy.putIfAbsent(item.legacyProductId!, () => item.itemId);
          byName.putIfAbsent(StockConsumptionPlanner.normalizeName(item.name), () => item.itemId);
        } catch (_) {}
      }
    }

    final plan = StockConsumptionPlanner.plan(
      lines: lines,
      recipes: recipes,
      catalogIdByLegacyProductId: byLegacy,
      catalogIdByName: byName,
      branchId: sc,
    );
    if (plan.qtyByItem.isEmpty) {
      return StockConsumptionResult(applied: false, alreadyApplied: false, unmapped: plan.unmapped);
    }

    // 2. Đánh dấu idempotent (chỉ tạo mới - nếu đã có thì bỏ qua)
    final marker = await store.child('bill_stock_applied/$billId').runTransaction((Object? current) {
      if (current != null) return Transaction.abort();
      return Transaction.success(true);
    });
    if (!marker.committed) {
      return StockConsumptionResult(applied: false, alreadyApplied: true, unmapped: plan.unmapped);
    }

    // 3. Trừ từng nguyên liệu bằng transaction + ghi sổ kho (ID xác định theo hóa đơn)
    final failures = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in plan.qtyByItem.entries) {
      final itemId = entry.key;
      final qty = entry.value;
      final balanceId = '${sc}_$itemId';
      try {
        int avgCost = 0;
        int valueDelta = 0;
        final res = await store.child('stock_balances/$balanceId').runTransaction((Object? current) {
          final next = StockConsumptionPlanner.applyConsumption(
            current,
            balanceId: balanceId,
            branchId: sc,
            itemId: itemId,
            consumeQty: qty,
            now: now,
          );
          avgCost = (next['averageCostScaled'] as num).toInt();
          valueDelta = (next['inventoryValue'] as num).toInt() -
              ((current is Map ? (current['inventoryValue'] as num?)?.toInt() : null) ?? 0);
          return Transaction.success(next);
        });
        if (!res.committed) throw Exception('transaction không được commit');

        final event = StockEventModel(
          eventId: 'EVT_SALE_${billId}_$itemId',
          commandId: 'BILL_$billId',
          documentId: billId,
          documentType: 'SALE',
          branchId: sc,
          itemId: itemId,
          qtyDeltaBase: -qty,
          valueDeltaMoney: valueDelta,
          unitCostSnapshot: avgCost,
          occurredAt: now,
          committedAt: now,
          actorId: username,
          sequence: now,
        );
        await store.child('stock_events/${event.eventId}').set(event.toMap());
      } catch (e) {
        failures.add('$itemId (-$qty): $e');
      }
    }
    if (failures.isNotEmpty) {
      throw StockConsumptionException(billId, failures);
    }
    return StockConsumptionResult(applied: true, alreadyApplied: false, unmapped: plan.unmapped);
  }

  // ==================== CÔNG NỢ NHÀ CUNG CẤP (SUPPLIER LEDGER) ====================

  /// Stream sổ công nợ nhà cung cấp
  Stream<List<SupplierLedgerEntryModel>> supplierLedgerStream(String supplierId) {
    return _storeRef.child('supplier_ledger').orderByChild('supplierId').equalTo(supplierId).onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      final list = map.values.map((e) => SupplierLedgerEntryModel.fromMap(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return list;
    });
  }

  /// Ghi nhận thanh toán cho NCC
  Future<void> recordSupplierPayment(String supplierId, int amount, String paymentMethod, String username) async {
    final entry = SupplierLedgerEntryModel(
      entryId: 'LED_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}',
      supplierId: supplierId,
      branchId: _currentStoreCode,
      entryType: 'PAYMENT',
      amountMoney: -amount,
      paymentMethod: paymentMethod,
      occurredAt: DateTime.now().millisecondsSinceEpoch,
      committedAt: DateTime.now().millisecondsSinceEpoch,
      actorId: username,
    );
    await _storeRef.child('supplier_ledger/${entry.entryId}').set(entry.toMap());
  }

  /// Lấy tổng công nợ hiện tại của NCC
  Future<int> getSupplierDebt(String supplierId) async {
    final snapshot = await _storeRef.child('supplier_ledger').orderByChild('supplierId').equalTo(supplierId).get();
    if (snapshot.value == null) return 0;
    final Map<dynamic, dynamic> map = snapshot.value as Map<dynamic, dynamic>;
    int totalDebt = 0;
    for (final e in map.values) {
      final entry = SupplierLedgerEntryModel.fromMap(Map<String, dynamic>.from(e));
      totalDebt += entry.amountMoney;
    }
    return totalDebt;
  }
}

class StockConsumptionResult {
  final bool applied;
  final bool alreadyApplied;
  final List<String> unmapped;
  StockConsumptionResult({required this.applied, required this.alreadyApplied, this.unmapped = const []});
}

/// Một số nguyên liệu không trừ được kho cho hóa đơn (đã đánh dấu bill_stock_applied).
class StockConsumptionException implements Exception {
  final String billId;
  final List<String> failures;
  StockConsumptionException(this.billId, this.failures);
  @override
  String toString() => 'Trừ kho lỗi cho HĐ $billId: ${failures.join('; ')}';
}

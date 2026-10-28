// lib/data/services/firebase_service.dart
import '../../core/domain/shift_scope.dart';
import '../../core/domain/customer_search.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/app_models.dart';
import '../repositories/seed_data.dart';
import '../repositories/auth_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/report_repository.dart';
import 'export_service.dart';
import 'inventory_service.dart';
import 'campaign_service.dart';
import '../../core/domain/order_integrity.dart' show StockRetryPlanner;
import '../../core/domain/item_options.dart';
import '../../core/domain/menu_copy.dart';
import '../../core/domain/zone_plan.dart';

export '../repositories/seed_data.dart';
export '../repositories/auth_repository.dart';
export '../repositories/order_repository.dart';
export '../repositories/report_repository.dart';
export 'export_service.dart';
export '../../core/domain/order_integrity.dart'
    show DataWriteException, PromotionLimitExceededException, InsufficientPointsException, LoyaltyException;
export 'inventory_service.dart' show StockRetrySummary, StockRetryEntry;

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal() {
    _authRepo = AuthRepository(
      getRoot: () => _root,
      getUsersRef: () => usersRef,
      getRolesRef: () => rolesRef,
    );
    _reportRepo = ReportRepository(
      getRoot: () => _root,
      getCurrentStoreCode: () => _currentStoreCode,
      getStoreRef: () => storeRef,
      getStoreInfoRef: () => storeInfoRef,
      getAuditLogsRef: () => auditLogsRef,
      getCashShiftsRef: () => _root.child('stores').child(_currentStoreCode).child('cash_shifts'),
      onSwitchStore: (code) => switchStore(code),
    );
    _orderRepo = OrderRepository(
      getRoot: () => _root,
      getCurrentStoreCode: () => _currentStoreCode,
      getTablesRef: () => tablesRef,
      getBillsRef: () => billsRef,
      getPromotionsRef: () => promotionsRef,
      getZonesRef: () => zonesRef,
      getKitchenOrdersRef: () => kitchenOrdersRef,
      getOnlineOrdersRef: () => onlineOrdersRef,
      logAction: (log) => _reportRepo.logAction(log),
      onDeductCashShift: (method, amount) => _reportRepo.deductCashShiftSale(method, amount),
    );
  }

  String _currentStoreCode = 'TRAM01';
  String get currentStoreCode => _currentStoreCode;

  late DatabaseReference _root;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  late final AuthRepository _authRepo;
  late final OrderRepository _orderRepo;
  late final ReportRepository _reportRepo;
  final ExportService _exportService = ExportService();

  AuthRepository get authRepo => _authRepo;
  OrderRepository get orderRepo => _orderRepo;
  ReportRepository get reportRepo => _reportRepo;
  ExportService get exportService => _exportService;

  void init({String? storeCode}) {
    if (storeCode != null && storeCode.isNotEmpty) {
      _currentStoreCode = storeCode.toUpperCase().trim();
    }
    _syncDependentServices();
    try {
      final dbInstance = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app',
      );
      _root = dbInstance.ref();
      try {
        dbInstance.setPersistenceEnabled(true);
        dbInstance.setPersistenceCacheSizeBytes(10000000);
      } catch (_) {}
    } catch (_) {
      _root = FirebaseDatabase.instance.ref();
    }
    _initialized = true;
    try {
      _authSub ??= FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null) _scheduleStockRetry();
      });
    } catch (_) {}
  }

  void clearSession() {
    _currentStoreCode = 'TRAM01';
    _reportRepo.clearSession();
    _syncDependentServices();
  }

  void switchStore(String storeCode) {
    _currentStoreCode = storeCode.toUpperCase().trim();
    _reportRepo.clearShiftCache();
    _syncDependentServices();
    _scheduleStockRetry();
  }

  /// Đồng bộ chi nhánh cho các service kho / khuyến mãi (trước đây luôn dùng TRAM01)
  void _syncDependentServices() {
    try {
      InventoryService().switchStore(_currentStoreCode);
      CampaignService().switchStore(_currentStoreCode);
    } catch (_) {}
  }

  // ==================== DEFAULT FALLBACK DATA ====================
  List<TableModel> get defaultTables => SeedData.defaultTables;
  List<CategoryModel> get defaultCategories => SeedData.defaultCategories;
  List<ZoneModel> get defaultZones => SeedData.defaultZones;
  List<ProductModel> get defaultProducts => SeedData.defaultProducts;

  // Multi-tenant scoped references under /stores/{storeCode}/...
  DatabaseReference get storeRef => _root.child('stores').child(_currentStoreCode);
  DatabaseReference get storeInfoRef => storeRef.child('storeInfo');
  DatabaseReference get tablesRef => storeRef.child('tables');
  DatabaseReference get billsRef => storeRef.child('bills');
  DatabaseReference get promotionsRef => storeRef.child('promotions');
  DatabaseReference get rolesRef => storeRef.child('roles');
  DatabaseReference get usersRef => storeRef.child('users');
  DatabaseReference get productsRef => storeRef.child('products');
  DatabaseReference get categoriesRef => storeRef.child('categories');
  DatabaseReference get zonesRef => storeRef.child('zones');
  DatabaseReference get kitchenOrdersRef => storeRef.child('kitchen_orders');
  DatabaseReference get onlineOrdersRef => storeRef.child('online_orders');
  DatabaseReference get auditLogsRef => storeRef.child('audit_logs');
  DatabaseReference get cashShiftsRef => _reportRepo.cashShiftsRef;
  DatabaseReference get customersRef => _reportRepo.customersRef;

  // ==================== STORE INITIALIZATION & SEEDER ====================
  Future<bool> checkStoreExists(String code) => _reportRepo.checkStoreExists(code);

  Future<void> initializeDefaultStoreData(String storeCode, String storeName) =>
      _reportRepo.initializeDefaultStoreData(storeCode, storeName);

  // ==================== AUTH ====================
  Future<UserModel?> login(String username, String password) =>
      _authRepo.login(username, password);

  // ==================== STORE INFO ====================
  Stream<StoreInfoModel> storeInfoStream() => _reportRepo.storeInfoStream();

  Future<StoreInfoModel> getStoreInfo() => _reportRepo.getStoreInfo();

  Future<void> saveStoreInfo(StoreInfoModel info) => _reportRepo.saveStoreInfo(info);
  Future<void> saveStoreSettings(StoreInfoModel info, {required int businessDayStartMinute}) =>
      _reportRepo.saveStoreSettings(info, businessDayStartMinute: businessDayStartMinute);

  Future<void> updateStoreShiftDifferenceSetting(bool allow, {String? storeCode}) =>
      _reportRepo.updateStoreShiftDifferenceSetting(allow, storeCode: storeCode);

  // ==================== ALL STORES ====================
  Stream<List<StoreInfoModel>> storesStream() => _reportRepo.storesStream();

  Future<List<StoreInfoModel>> getAllStores() => _reportRepo.getAllStores();

  // ==================== ROLES ====================
  Stream<List<RoleModel>> rolesStream() => _authRepo.rolesStream();

  Future<List<RoleModel>> getRoles() => _authRepo.getRoles();

  Future<void> saveRole(RoleModel role) => _authRepo.saveRole(role);

  Future<void> deleteRole(String roleId) => _authRepo.deleteRole(roleId);

  // ==================== USERS ====================
  Stream<List<UserModel>> usersStream() => _authRepo.usersStream();

  Future<List<UserModel>> getUsers() => _authRepo.getUsers();

  Future<void> saveUser(UserModel user) => _authRepo.saveUser(user);

  Future<void> deleteUser(String username) => _authRepo.deleteUser(username);

  // ==================== TABLES ====================
  Stream<List<TableModel>> tablesStream() => _orderRepo.tablesStream();

  Future<void> saveTable(TableModel table) => _orderRepo.saveTable(table);

  Future<({TableModel targetTable, bool wasSplit, String? occupiedBy})> claimOrSplitTableForOrdering(
    TableModel requestedTable, {
    Iterable<TableModel>? knownTables,
    required String staffUsername,
    required String staffName,
  }) =>
      _orderRepo.claimOrSplitTableForOrdering(
        requestedTable,
        knownTables: knownTables,
        staffUsername: staffUsername,
        staffName: staffName,
      );

  Future<void> releaseTableOrderingClaim(TableModel table, {String? staffUsername}) =>
      _orderRepo.releaseTableOrderingClaim(table, staffUsername: staffUsername);

  Future<({TableModel savedTable, bool wasSplit})> saveTableOrderSafe(
    TableModel table, {
    required String? sessionBillId,
    required bool isNewOrderSession,
  }) =>
      _orderRepo.saveTableOrderSafe(
        table,
        sessionBillId: sessionBillId,
        isNewOrderSession: isNewOrderSession,
      );

  Future<void> deleteTable(TableModel table) => _orderRepo.deleteTable(table);

  Future<void> mergeTables(TableModel sourceTable, TableModel targetTable, {String? staffName, String? staffUsername}) =>
      _orderRepo.mergeTables(sourceTable, targetTable, staffName: staffName, staffUsername: staffUsername);

  Future<void> transferTable(TableModel sourceTable, TableModel targetTable, {String? staffName, String? staffUsername}) =>
      _orderRepo.transferTable(sourceTable, targetTable, staffName: staffName, staffUsername: staffUsername);

  Future<({TableModel updatedSource, TableModel updatedTarget})> splitTableItems({
    required TableModel sourceTable,
    required List<OrderItemModel> splitItems,
    required List<OrderItemModel> remainingItems,
    required TableModel targetTable,
    required bool mergeIntoTarget,
    String? staffUsername,
    String? staffName,
    String? staffRole,
  }) =>
      _orderRepo.splitTableItems(
        sourceTable: sourceTable,
        splitItems: splitItems,
        remainingItems: remainingItems,
        targetTable: targetTable,
        mergeIntoTarget: mergeIntoTarget,
        staffUsername: staffUsername,
        staffName: staffName,
        staffRole: staffRole,
      );

  Future<({BillModel paidBill, TableModel updatedSource, bool synced})> paySplitItemsNow({
    required TableModel sourceTable,
    required List<OrderItemModel> splitItems,
    required List<OrderItemModel> remainingItems,
    required String paymentMethod,
    String? shiftId,
    String? staffUid,
    String? staffUsername,
    String? staffFullName,
    String? staffRole,
    double? pointEarnRate,
    int? pointRedeemRate,
  }) =>
      _orderRepo.paySplitItemsNow(
        sourceTable: sourceTable,
        splitItems: splitItems,
        remainingItems: remainingItems,
        paymentMethod: paymentMethod,
        shiftId: shiftId,
        staffUid: staffUid,
        staffUsername: staffUsername,
        staffFullName: staffFullName,
        staffRole: staffRole,
        pointEarnRate: pointEarnRate,
        pointRedeemRate: pointRedeemRate,
      );

  // ==================== BILLS ====================
  Stream<List<BillModel>> billsStream() => _orderRepo.billsStream();

  /// Hóa đơn tài khoản hiện tại được phép thấy: nhân viên chỉ thấy HĐ của mình (người thu tiền hoặc
  /// người tạo/thêm món); chủ/quản lý (VIEW_ALL_BILLS_HISTORY) thấy tất cả. Lọc phía client.
  Stream<List<BillModel>> myBillsStream() => _orderRepo.billsStream().map((b) => scopeVisibleBills(b));

  List<BillModel> scopeVisibleBills(Iterable<BillModel> bills, {String? filterUsername}) {
    final id = _reportRepo.shiftIdentity;
    return scopeBills(bills, uid: id.uid, username: id.username, canViewAll: id.canViewAllBills, filterUsername: filterUsername);
  }

  Future<BillModel?> getBill(String billId) => _orderRepo.getBill(billId);

  Future<void> saveBill(BillModel bill) => _orderRepo.saveBill(bill);

  /// Trả về true nếu server đã xác nhận, false nếu đang chờ đồng bộ (mất mạng).
  /// Ném [DataWriteException] / [PromotionLimitExceededException] /
  /// [InsufficientPointsException] khi thất bại (trước khi hóa đơn được ghi).
  /// Đổi điểm (bill.pointsUsed) và tích điểm cho bill.customerId được xử lý bên trong
  /// (transaction, idempotent theo hóa đơn).
  Future<bool> closeAndPayBill(BillModel bill, TableModel table, {double? pointEarnRate, int? pointRedeemRate}) =>
      _orderRepo.closeAndPayBill(bill, table, pointEarnRate: pointEarnRate, pointRedeemRate: pointRedeemRate);

  Future<void> applyStockForBill(BillModel bill) => _orderRepo.applyStockForBill(bill);

  // ==================== HÀNG ĐỢI TRỪ KHO LẠI ====================
  /// Hóa đơn đang chờ trừ kho lại (stock_retry_queue) - dùng cho màn hình quản lý.
  Future<List<StockRetryEntry>> pendingStockRetries() =>
      InventoryService().pendingStockRetries(storeCode: _currentStoreCode);

  /// Chạy lại hàng đợi trừ kho cho chi nhánh hiện tại (người đăng nhập phải là Thu ngân trở lên).
  Future<StockRetrySummary> retryPendingStockDeductions() async {
    final user = await _currentStaffForRetry();
    if (user == null) return StockRetrySummary();
    return _orderRepo.retryPendingStock(
      storeCode: _currentStoreCode,
      username: user.username,
      userFullName: user.fullName,
      userRole: user.roleId,
    );
  }

  Timer? _stockRetryTimer;
  bool _stockRetryRunning = false;
  StreamSubscription<User?>? _authSub;

  /// Hẹn chạy hàng đợi trừ kho sau khi mở app / đăng nhập / đổi chi nhánh.
  void _scheduleStockRetry() {
    if (!_initialized) return;
    _stockRetryTimer?.cancel();
    _stockRetryTimer = Timer(const Duration(seconds: 8), () async {
      if (_stockRetryRunning) return;
      _stockRetryRunning = true;
      try {
        await retryPendingStockDeductions();
      } catch (_) {
        // Không chặn luồng chính; lần mở app sau sẽ thử lại
      } finally {
        _stockRetryRunning = false;
      }
    });
  }

  Future<({String username, String fullName, String roleId})?> _currentStaffForRetry() async {
    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) return null;
      final snap = await usersRef.child(fbUser.uid).get().timeout(const Duration(seconds: 5));
      if (snap.value is! Map) return null;
      final m = snap.value as Map;
      if (m['isActive'] == false) return null;
      final roleId = m['roleId']?.toString() ?? '';
      if (!StockRetryPlanner.canRunRetry(roleId, isRootOwner: m['isRootOwner'] == true)) return null;
      return (
        username: m['username']?.toString() ?? fbUser.uid,
        fullName: m['fullName']?.toString() ?? '',
        roleId: roleId,
      );
    } catch (_) {
      return null;
    }
  }

  // ==================== CANCEL ACTIVE BILL ====================
  Future<void> cancelActiveBill(
    TableModel table, {
    required String reason,
    required String staffUsername,
    required String staffFullName,
    required String staffRole,
  }) => _orderRepo.cancelActiveBill(
    table,
    reason: reason,
    staffUsername: staffUsername,
    staffFullName: staffFullName,
    staffRole: staffRole,
  );

  // ==================== CANCEL OR DELETE PAID BILL ====================
  Future<void> cancelPaidBill({
    required BillModel bill,
    required String reason,
    required String staffUsername,
    required String staffFullName,
    required String staffRole,
  }) => _orderRepo.cancelPaidBill(
    bill: bill,
    reason: reason,
    staffUsername: staffUsername,
    staffFullName: staffFullName,
    staffRole: staffRole,
  );

  Future<void> deleteBill({
    required BillModel bill,
    required String reason,
    required String staffUsername,
    required String staffFullName,
    required String staffRole,
  }) => _orderRepo.deleteBill(
    bill: bill,
    reason: reason,
    staffUsername: staffUsername,
    staffFullName: staffFullName,
    staffRole: staffRole,
  );

  // ==================== PROMOTIONS ====================
  Stream<List<PromotionModel>> promotionsStream() => _orderRepo.promotionsStream();

  Future<List<PromotionModel>> getPromotions() => _orderRepo.getPromotions();

  Future<void> savePromotion(PromotionModel promo) => _orderRepo.savePromotion(promo);

  Future<void> deletePromotion(String promoId) => _orderRepo.deletePromotion(promoId);

  Future<bool?> incrementPromotionUsage(String promoId) => _orderRepo.incrementPromotionUsage(promoId);

  // ==================== AUDIT LOGS ====================
  Stream<List<AuditLogModel>> auditLogsStream() => _reportRepo.auditLogsStream();

  Future<void> logAction(AuditLogModel log) => _reportRepo.logAction(log);

  // ==================== PRODUCTS & CATEGORIES ====================
  DatabaseReference getProductsRef([String? storeCode]) => _orderRepo.getProductsRef(storeCode);

  DatabaseReference getCategoriesRef([String? storeCode]) => _orderRepo.getCategoriesRef(storeCode);

  Stream<List<ProductModel>> productsStream({String? storeCode}) =>
      _orderRepo.productsStream(storeCode: storeCode);

  Future<void> updateProductAvailability(ProductModel product, Map<String, Object?> patch, {String? storeCode}) =>
      _orderRepo.updateProductAvailability(product, patch, storeCode: storeCode);

  Future<List<ProductModel>> getProducts({String? storeCode}) =>
      _orderRepo.getProducts(storeCode: storeCode);

  Future<void> saveProduct(ProductModel product, {String? storeCode}) =>
      _orderRepo.saveProduct(product, storeCode: storeCode);

  Future<void> deleteProduct(ProductModel product, {String? storeCode}) =>
      _orderRepo.deleteProduct(product, storeCode: storeCode);

  Stream<List<CategoryModel>> categoriesStream({String? storeCode}) =>
      _orderRepo.categoriesStream(storeCode: storeCode);

  Future<List<CategoryModel>> getCategories({String? storeCode}) =>
      _orderRepo.getCategories(storeCode: storeCode);

  Future<void> saveCategory(CategoryModel category, {String? storeCode}) =>
      _orderRepo.saveCategory(category, storeCode: storeCode);

  Future<void> deleteCategory(CategoryModel category, {String? storeCode}) =>
      _orderRepo.deleteCategory(category, storeCode: storeCode);

  Stream<List<Map<String, dynamic>>> productNotesStream({String? storeCode}) =>
      _orderRepo.productNotesStream(storeCode: storeCode);

  Future<void> saveProductNote(String noteId, Map<String, dynamic> data, {String? storeCode}) =>
      _orderRepo.saveProductNote(noteId, data, storeCode: storeCode);

  Future<void> deleteProductNote(String noteId, {String? storeCode}) =>
      _orderRepo.deleteProductNote(noteId, storeCode: storeCode);

  // Danh mục note & topping (note_groups / topping_groups)
  Stream<ItemCatalog> itemCatalogStream({String? storeCode}) => _orderRepo.itemCatalogStream(storeCode: storeCode);

  Future<void> saveNoteGroup(NoteGroup g, {String? storeCode}) => _orderRepo.saveNoteGroup(g, storeCode: storeCode);

  Future<void> deleteNoteGroup(String id, {String? storeCode}) => _orderRepo.deleteNoteGroup(id, storeCode: storeCode);

  Future<void> saveToppingGroup(ToppingGroup g, {String? storeCode}) => _orderRepo.saveToppingGroup(g, storeCode: storeCode);

  Future<void> deleteToppingGroup(String id, {String? storeCode}) => _orderRepo.deleteToppingGroup(id, storeCode: storeCode);

  Future<void> updateStorePaths(Map<String, Object?> updates, {String? storeCode}) =>
      _orderRepo.updateStorePaths(updates, storeCode: storeCode);

  Future<Map<String, dynamic>> loadLegacyNoteConfig({String? storeCode}) =>
      _orderRepo.loadLegacyNoteConfig(storeCode: storeCode);

  Future<int> copyMenuBetweenStores({
    required String fromStoreCode,
    required String toStoreCode,
    List<String>? selectedCategories,
  }) => _orderRepo.copyMenuBetweenStores(
    fromStoreCode: fromStoreCode,
    toStoreCode: toStoreCode,
    selectedCategories: selectedCategories,
  );

  Future<MenuSnapshot> loadMenuSnapshot(String storeCode) => _orderRepo.loadMenuSnapshot(storeCode);

  Future<CopyPlan> planMenuCopy({
    required MenuSnapshot source,
    required String toStoreCode,
    CopySelection selection = CopySelection.everything,
    CopyOptions options = const CopyOptions(),
  }) => _orderRepo.planMenuCopy(source: source, toStoreCode: toStoreCode, selection: selection, options: options);

  Future<void> applyMenuCopyPlan({
    required String fromStoreCode,
    required String toStoreCode,
    required CopyPlan plan,
    String username = '',
    String fullName = '',
    String role = '',
    void Function(int done, int total)? onProgress,
  }) => _orderRepo.applyMenuCopyPlan(
    fromStoreCode: fromStoreCode,
    toStoreCode: toStoreCode,
    plan: plan,
    username: username,
    fullName: fullName,
    role: role,
    onProgress: onProgress,
  );

  Future<void> clearStoreMenu(String storeCode) => _orderRepo.clearStoreMenu(storeCode);

  Stream<List<ZoneModel>> zonesStream() => _orderRepo.zonesStream();

  Future<ZonePlan> createZone({required String name, required String prefix, required int count, required ZoneAuditActor actor}) =>
      _orderRepo.createZone(name: name, prefix: prefix, count: count, actor: actor);

  Future<ZonePlan> renameZone({required String oldName, required String newName, required ZoneAuditActor actor}) =>
      _orderRepo.renameZone(oldName: oldName, newName: newName, actor: actor);

  Future<ZonePlan> addTablesToZone({required String zone, required String prefix, required int count, required ZoneAuditActor actor}) =>
      _orderRepo.addTablesToZone(zone: zone, prefix: prefix, count: count, actor: actor);

  Future<void> setCategoryOrder(List<String> names, {String? storeCode}) => _orderRepo.setCategoryOrder(names, storeCode: storeCode);
  Future<void> setZonePinned(String zone, bool pinned) => _orderRepo.setZonePinned(zone, pinned);
  Future<void> setZoneOrder(List<String> names) => _orderRepo.setZoneOrder(names);
  Future<ZonePlan> deleteZone({required String zone, required ZoneAuditActor actor}) =>
      _orderRepo.deleteZone(zone: zone, actor: actor);

  Future<ZonePlan> deleteTableByName({
    required String zone,
    required String tableName,
    required ZoneAuditActor actor,
  }) =>
      _orderRepo.deleteTableByName(zone: zone, tableName: tableName, actor: actor);

  Future<ZonePlan> dedupeTables({required ZoneAuditActor actor}) => _orderRepo.dedupeTables(actor: actor);

  Stream<List<KitchenOrderModel>> kitchenOrdersStream() => _orderRepo.kitchenOrdersStream();

  Stream<List<KitchenOrderModel>> readyToServeKitchenOrdersStream({Duration maxAge = const Duration(hours: 2)}) =>
      _orderRepo.readyToServeKitchenOrdersStream(maxAge: maxAge);

  Future<void> sendKitchenOrder(KitchenOrderModel order) => _orderRepo.sendKitchenOrder(order);

  Future<void> sendOrderToKitchen({
    required TableModel table,
    required List<OrderItemModel> items,
    String? note,
    String? orderedBy,
    String? orderedByName,
  }) => _orderRepo.sendOrderToKitchen(
        table: table,
        items: items,
        note: note,
        orderedBy: orderedBy,
        orderedByName: orderedByName,
      );

  Future<void> markKitchenOrderDone(String key) => _orderRepo.markKitchenOrderDone(key);

  Future<void> markKitchenOrderPickedUp(String key, {String? pickedUpBy}) =>
      _orderRepo.markKitchenOrderPickedUp(key, pickedUpBy: pickedUpBy);

  Stream<List<OnlineOrderModel>> onlineOrdersStream() => _orderRepo.onlineOrdersStream();

  Future<void> updateOnlineOrderStatus(String key, String status) =>
      _orderRepo.updateOnlineOrderStatus(key, status);

  Future<bool> confirmOnlineOrderAndAddToTable(
    OnlineOrderModel order, {
    String? staffUsername,
    String? staffFullName,
  }) =>
      _orderRepo.confirmOnlineOrderAndAddToTable(
        order,
        staffUsername: staffUsername,
        staffFullName: staffFullName,
      );

  // ==================== KIOTVIET CASH SHIFT ====================
  CashShiftModel? get activeShiftCache => _reportRepo.activeShiftCache;

  /// AuthService đăng ký danh tính (uid, username, quyền xem mọi ca) để ca/két tách theo tài khoản.
  void setShiftIdentityProvider(({String uid, String username, bool canViewAll, bool canViewAllBills}) Function() provider) {
    _reportRepo.shiftIdentityProvider = provider;
  }

  ({String uid, String username, bool canViewAll, bool canViewAllBills}) get shiftIdentity => _reportRepo.shiftIdentity;

  /// Ca đang mở của TÀI KHOẢN HIỆN TẠI trong danh sách [shifts] (không bao giờ trả ca của người khác).
  CashShiftModel? ownOpenShiftIn(Iterable<CashShiftModel> shifts) => _reportRepo.ownOpenShiftIn(shifts);

  List<CashShiftModel> scopeVisibleShifts(Iterable<CashShiftModel> shifts, {String? filterOwner}) =>
      _reportRepo.scopeVisibleShifts(shifts, filterOwner: filterOwner);

  List<CashShiftModel>? get cachedCashShiftsList => _reportRepo.cachedCashShiftsList;

  Stream<List<CashShiftModel>> cashShiftsStream() => _reportRepo.cashShiftsStream();

  Future<List<CashShiftModel>> getRecentCashShifts({int limit = 50, bool forceRefresh = false}) =>
      _reportRepo.getRecentCashShifts(limit: limit, forceRefresh: forceRefresh);

  Future<CashShiftModel?> getCurrentOpenShift({bool forceRefresh = false}) =>
      _reportRepo.getCurrentOpenShift(forceRefresh: forceRefresh);

  Future<void> openCashShift(CashShiftModel shift) => _reportRepo.openCashShift(shift);

  Stream<List<BillModel>> storeBillsStream({String? storeCode}) =>
      _reportRepo.storeBillsStream(storeCode: storeCode);

  Future<List<BillModel>> getStoreBills({String? storeCode, DateTime? startDate, DateTime? endDate}) =>
      _reportRepo.getStoreBills(storeCode: storeCode, startDate: startDate, endDate: endDate);

  Future<Map<int, ProductModel>> getProductsMap({String? storeCode}) =>
      _reportRepo.getProductsMap(storeCode: storeCode);

  Future<List<BillModel>> getBillsForShift(CashShiftModel shift, {String? storeCode}) =>
      _reportRepo.getBillsForShift(shift, storeCode: storeCode);

  Future<void> recordCashShiftSale({
    required int cashAmount,
    required int qrAmount,
    required int cardAmount,
    String? shiftId,
  }) => _reportRepo.recordCashShiftSale(
    cashAmount: cashAmount,
    qrAmount: qrAmount,
    cardAmount: cardAmount,
    shiftId: shiftId,
  );

  Future<void> addCashShiftAdjustment({
    required String shiftId,
    required int amount,
    required bool isCashIn,
    required String reason,
  }) => _reportRepo.addCashShiftAdjustment(
    shiftId: shiftId,
    amount: amount,
    isCashIn: isCashIn,
    reason: reason,
  );

  Future<void> closeCashShift(CashShiftModel shift, int actualCash, String notes) =>
      _reportRepo.closeCashShift(shift, actualCash, notes);

  // ==================== KIOTVIET CUSTOMER LOYALTY ====================
  Future<KmtCustomerModel?> lookupCustomer(String query) => _reportRepo.lookupCustomer(query);

  Future<void> saveCustomer(KmtCustomerModel customer) => _reportRepo.saveCustomer(customer);

  // awardPoints / redeemCustomerPoints (ghi điểm trực tiếp vào Firestore) đã gỡ bỏ:
  // điểm chỉ đổi qua closeAndPayBill (LoyaltyService, RTDB), Firestore do Cloud Function đồng bộ.
  Future<List<CustomerCandidate>> getBranchCandidates() => _reportRepo.getBranchCandidates();

  Future<List<KmtCustomerModel>> getAllCustomers() => _reportRepo.getAllCustomers();

  // ==================== KIOTVIET TABLE RESERVATIONS ====================
  Future<void> reserveTable({
    required TableModel table,
    required String customerName,
    required String phone,
    required String time,
    required int deposit,
  }) => _orderRepo.reserveTable(
    table: table,
    customerName: customerName,
    phone: phone,
    time: time,
    deposit: deposit,
  );

  Future<void> cancelReservation(TableModel table) => _orderRepo.cancelReservation(table);

  // ==================== EXCEL EXPORT ====================
  static String sanitizeFileName(String input) => ExportService.sanitizeFileName(input);

  Future<String?> exportReportExcel({
    required String reportType,
    required String storeName,
    List<String>? headers,
    List<List<dynamic>>? rows,
    List<BillModel>? bills,
  }) => _exportService.exportReportExcel(
    reportType: reportType,
    storeName: storeName,
    headers: headers,
    rows: rows,
    bills: bills,
  );

  // ==================== AUTO PAYMENT BOT INTEGRATION ====================
  DatabaseReference get paymentEventsRef => _root.child('stores').child(_currentStoreCode).child('payment_events');

  Stream<DatabaseEvent> listenPaymentEvents({int? sinceTimestamp}) {
    Query query = paymentEventsRef.orderByChild('timestamp');
    if (sinceTimestamp != null) {
      query = query.startAt(sinceTimestamp);
    }
    return query.onChildAdded;
  }

  Future<void> markPaymentEventProcessed(String eventId, {String? billCode}) async {
    try {
      await paymentEventsRef.child(eventId).update({
        'status': 'PROCESSED',
        'processedAt': ServerValue.timestamp,
        if (billCode != null) 'billCode': billCode,
      });
    } catch (_) {}
  }
}

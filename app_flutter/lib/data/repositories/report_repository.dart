import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/app_models.dart';
import 'seed_data.dart';

class ReportRepository {
  final DatabaseReference Function() _getRoot;
  final String Function() _getCurrentStoreCode;
  final DatabaseReference Function() _getStoreRef;
  final DatabaseReference Function() _getStoreInfoRef;
  final DatabaseReference Function() _getAuditLogsRef;
  final DatabaseReference Function() _getCashShiftsRef;
  final void Function(String storeCode)? _onSwitchStore;

  CashShiftModel? activeShiftCache;

  Stream<List<CashShiftModel>>? _cachedCashShiftsStream;
  String? _cachedCashShiftsStoreCode;

  ReportRepository({
    required DatabaseReference Function() getRoot,
    required String Function() getCurrentStoreCode,
    required DatabaseReference Function() getStoreRef,
    required DatabaseReference Function() getStoreInfoRef,
    required DatabaseReference Function() getAuditLogsRef,
    required DatabaseReference Function() getCashShiftsRef,
    void Function(String storeCode)? onSwitchStore,
  })  : _getRoot = getRoot,
        _getCurrentStoreCode = getCurrentStoreCode,
        _getStoreRef = getStoreRef,
        _getStoreInfoRef = getStoreInfoRef,
        _getAuditLogsRef = getAuditLogsRef,
        _getCashShiftsRef = getCashShiftsRef,
        _onSwitchStore = onSwitchStore;

  DatabaseReference get _root => _getRoot();
  String get _currentStoreCode => _getCurrentStoreCode();
  DatabaseReference get storeRef => _getStoreRef();
  DatabaseReference get storeInfoRef => _getStoreInfoRef();
  DatabaseReference get auditLogsRef => _getAuditLogsRef();
  DatabaseReference get cashShiftsRef => _getCashShiftsRef();
  DatabaseReference get customersRef => _root.child('kmt_customers');

  void clearShiftCache() {
    activeShiftCache = null;
    _cachedCashShiftsStream = null;
    _cachedCashShiftsStoreCode = null;
  }

  // ==================== STORE INFO ====================
  Stream<StoreInfoModel> storeInfoStream() {
    return storeInfoRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return StoreInfoModel(
          storeCode: _currentStoreCode,
          storeName: _currentStoreCode == 'TRAM02'
              ? 'POS Trạm - Chi nhánh 02 (Sài Gòn)'
              : (_currentStoreCode == 'TRAM01' ? 'POS Trạm - Trụ sở 01 (Đà Lạt)' : 'POS Trạm - $_currentStoreCode'),
        );
      }
      return StoreInfoModel.fromMap(
        Map<dynamic, dynamic>.from(event.snapshot.value as Map),
        _currentStoreCode,
      );
    }).handleError((_) => StoreInfoModel(
      storeCode: _currentStoreCode,
      storeName: _currentStoreCode == 'TRAM02'
          ? 'POS Trạm - Chi nhánh 02 (Sài Gòn)'
          : (_currentStoreCode == 'TRAM01' ? 'POS Trạm - Trụ sở 01 (Đà Lạt)' : 'POS Trạm - $_currentStoreCode'),
    ));
  }

  Future<StoreInfoModel> getStoreInfo() async {
    try {
      final snap = await storeInfoRef.get().timeout(const Duration(seconds: 2));
      if (!snap.exists || snap.value == null) {
        return StoreInfoModel(
          storeCode: _currentStoreCode,
          storeName: _currentStoreCode == 'TRAM02'
              ? 'POS Trạm - Chi nhánh 02 (Sài Gòn)'
              : (_currentStoreCode == 'TRAM01' ? 'POS Trạm - Trụ sở 01 (Đà Lạt)' : 'POS Trạm - $_currentStoreCode'),
        );
      }
      return StoreInfoModel.fromMap(Map<dynamic, dynamic>.from(snap.value as Map), _currentStoreCode);
    } catch (_) {
      return StoreInfoModel(
        storeCode: _currentStoreCode,
        storeName: _currentStoreCode == 'TRAM02'
            ? 'POS Trạm - Chi nhánh 02 (Sài Gòn)'
            : (_currentStoreCode == 'TRAM01' ? 'POS Trạm - Trụ sở 01 (Đà Lạt)' : 'POS Trạm - $_currentStoreCode'),
      );
    }
  }

  Future<void> saveStoreInfo(StoreInfoModel info) async {
    await storeInfoRef.set(info.toMap());
  }

  Future<void> updateStoreShiftDifferenceSetting(bool allow, {String? storeCode}) async {
    final targetRef = storeCode != null && storeCode.isNotEmpty
        ? _root.child('stores').child(storeCode).child('storeInfo')
        : storeInfoRef;
    await targetRef.update({'allowStaffViewShiftDifference': allow});
  }

  // ==================== ALL STORES ====================
  Stream<List<StoreInfoModel>> storesStream() {
    return _root.child('stores').onValue.map<List<StoreInfoModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return [StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm - Trụ sở 01')];
      }
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final list = <StoreInfoModel>[];
      map.forEach((code, val) {
        if (val is Map) {
          final sVal = Map<dynamic, dynamic>.from(val);
          final sInfo = sVal['storeInfo'] != null && sVal['storeInfo'] is Map
              ? Map<dynamic, dynamic>.from(sVal['storeInfo'])
              : sVal;
          list.add(StoreInfoModel.fromMap(sInfo, code.toString()));
        }
      });
      list.sort((a, b) => a.storeCode.compareTo(b.storeCode));
      return list.isNotEmpty
          ? list
          : [StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm - Trụ sở 01')];
    }).handleError((_) => [StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm - Trụ sở 01')]);
  }

  Future<List<StoreInfoModel>> getAllStores() async {
    try {
      final snap = await _root.child('stores').get().timeout(const Duration(seconds: 3));
      if (!snap.exists || snap.value == null) {
        return [StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm - Trụ sở 01')];
      }
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      final list = <StoreInfoModel>[];
      map.forEach((code, val) {
        if (val is Map) {
          final sVal = Map<dynamic, dynamic>.from(val);
          final sInfo = sVal['storeInfo'] != null && sVal['storeInfo'] is Map
              ? Map<dynamic, dynamic>.from(sVal['storeInfo'])
              : sVal;
          list.add(StoreInfoModel.fromMap(sInfo, code.toString()));
        }
      });
      list.sort((a, b) => a.storeCode.compareTo(b.storeCode));
      return list.isNotEmpty ? list : [StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm - Trụ sở 01')];
    } catch (_) {
      return [StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm - Trụ sở 01')];
    }
  }

  // ==================== STORE INITIALIZATION & SEEDER ====================
  Future<bool> checkStoreExists(String code) async {
    try {
      final snap = await _root.child('stores').child(code.toUpperCase().trim()).get().timeout(const Duration(seconds: 2));
      return snap.exists && snap.value != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> initializeDefaultStoreData(String storeCode, String storeName) async {
    final code = storeCode.toUpperCase().trim();
    if (_onSwitchStore != null) {
      _onSwitchStore(code);
    }

    try {
      final info = StoreInfoModel(
        storeCode: code,
        storeName: storeName,
        address: 'Đà Lạt, Lâm Đồng',
        phone: '0987654321',
        wifiName: 'Tram_WiFi_Free',
        bankId: 'MB',
        bankAccount: '0987654321',
        accountName: 'CHU QUAN FNB',
        allowStackPromotions: true,
        defaultVatRate: 8.0,
      );
      await storeRef.child('storeInfo').set(info.toMap()).timeout(const Duration(seconds: 2));

      for (final t in SeedData.defaultTables) {
        storeRef.child('tables').child(t.firebaseKey).set(t.toMap()).catchError((_) {});
      }
      for (final p in SeedData.defaultProducts) {
        final key = p.name.replaceAll(RegExp(r'[.#$\[\]]'), '_');
        storeRef.child('products').child(key).set(p.toMap()).catchError((_) {});
      }
      for (final c in SeedData.defaultCategories) {
        storeRef.child('categories').child(c.name).set({'name': c.name}).catchError((_) {});
      }
      for (final z in SeedData.defaultZones) {
        storeRef.child('zones').child(z.name).set({'name': z.name}).catchError((_) {});
      }
    } catch (_) {}
  }

  // ==================== AUDIT LOGS ====================
  Stream<List<AuditLogModel>> auditLogsStream() {
    return auditLogsRef.limitToLast(150).onValue.map<List<AuditLogModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <AuditLogModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
          .map((e) => AuditLogModel.fromMap(Map<dynamic, dynamic>.from(e.value), logId: e.key.toString()))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }).handleError((_) => <AuditLogModel>[]);
  }

  Future<void> logAction(AuditLogModel log) async {
    try {
      final key = auditLogsRef.push().key ?? DateTime.now().millisecondsSinceEpoch.toString();
      final map = log.toMap();
      map['storeCode'] ??= _currentStoreCode;
      await auditLogsRef.child(key).set(map);
      _root.child('audit_logs').child(key).set(map).catchError((_) {});
    } catch (_) {
      try {
        final key = DateTime.now().millisecondsSinceEpoch.toString();
        final map = log.toMap();
        map['storeCode'] ??= _currentStoreCode;
        _root.child('audit_logs').child(key).set(map).catchError((_) {});
      } catch (_) {}
    }
  }

  // ==================== KIOTVIET CASH SHIFT (QUẢN LÝ KÉT TIỀN CA) ====================
  Stream<List<CashShiftModel>> cashShiftsStream() {
    if (_cachedCashShiftsStream != null && _cachedCashShiftsStoreCode == _currentStoreCode) {
      return _cachedCashShiftsStream!;
    }
    _cachedCashShiftsStoreCode = _currentStoreCode;
    _cachedCashShiftsStream = cashShiftsRef.onValue.map<List<CashShiftModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        activeShiftCache = null;
        return <CashShiftModel>[];
      }
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final list = map.entries
          .map((e) => CashShiftModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .where((s) => s.openedAt > 0)
          .toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
      final openOne = list.where((s) => s.isOpen).firstOrNull;
      activeShiftCache = openOne;
      return list;
    }).handleError((_) => (activeShiftCache != null && activeShiftCache!.isOpen) ? [activeShiftCache!] : <CashShiftModel>[]).asBroadcastStream();
    return _cachedCashShiftsStream!;
  }

  Future<CashShiftModel?> getCurrentOpenShift({bool forceRefresh = false}) async {
    if (!forceRefresh && activeShiftCache != null && activeShiftCache!.isOpen) {
      return activeShiftCache;
    }
    try {
      final snap = await cashShiftsRef.get().timeout(const Duration(seconds: 5));
      if (!snap.exists || snap.value == null) {
        activeShiftCache = null;
        return null;
      }
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      CashShiftModel? foundOpen;
      for (final entry in map.entries) {
        final shift = CashShiftModel.fromMap(Map<dynamic, dynamic>.from(entry.value), entry.key.toString());
        if (shift.isOpen && shift.openedAt > 0) {
          foundOpen = shift;
          break;
        }
      }
      activeShiftCache = foundOpen;
      return foundOpen;
    } catch (_) {
      return (activeShiftCache != null && activeShiftCache!.isOpen) ? activeShiftCache : null;
    }
  }

  Future<void> openCashShift(CashShiftModel shift) async {
    activeShiftCache = shift;
    try {
      // Đảm bảo không có ca cũ nào bị treo ở trạng thái OPEN
      final snap = await cashShiftsRef.get().timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in map.entries) {
          final s = CashShiftModel.fromMap(Map<dynamic, dynamic>.from(entry.value), entry.key.toString());
          if (s.isOpen && s.id != shift.id) {
            s.status = 'CLOSED';
            s.closedAt = shift.openedAt;
            await cashShiftsRef.child(s.id).set(s.toMap()).catchError((_) {});
          }
        }
      }
    } catch (_) {}
    try {
      await cashShiftsRef.child(shift.id).set(shift.toMap());
    } catch (_) {}
    logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: shift.staffUsername,
      userFullName: shift.staffFullName,
      userRole: 'CASHIER',
      action: 'OPEN_SHIFT',
      targetType: 'SHIFT',
      targetId: shift.shiftCode,
      details: 'Mở ca bán hàng ${shift.shiftCode}, tiền đầu ca: ${shift.initialCash}đ',
    ));
  }

  Future<void> recordCashShiftSale({
    required int cashAmount,
    required int qrAmount,
    required int cardAmount,
    String? shiftId,
  }) async {
    try {
      CashShiftModel? shift;
      if (shiftId != null && activeShiftCache != null && activeShiftCache!.id == shiftId) {
        shift = activeShiftCache;
      } else if (shiftId != null) {
        final snap = await cashShiftsRef.child(shiftId).get();
        if (snap.exists && snap.value != null) {
          shift = CashShiftModel.fromMap(Map<dynamic, dynamic>.from(snap.value as Map), shiftId);
        }
      }
      shift ??= await getCurrentOpenShift();
      if (shift != null) {
        shift.totalCashSales += cashAmount;
        shift.totalQrSales += qrAmount;
        shift.totalCardSales += cardAmount;
        activeShiftCache = shift;
        await cashShiftsRef.child(shift.id).set(shift.toMap());
      }
    } catch (_) {}
  }

  Future<void> addCashShiftAdjustment({
    required String shiftId,
    required int amount,
    required bool isCashIn,
    required String reason,
  }) async {
    try {
      CashShiftModel? shift;
      if (activeShiftCache != null && activeShiftCache!.id == shiftId) {
        shift = activeShiftCache;
      } else {
        final snap = await cashShiftsRef.child(shiftId).get();
        if (snap.exists && snap.value == null) return;
        if (snap.exists && snap.value != null) {
          shift = CashShiftModel.fromMap(Map<dynamic, dynamic>.from(snap.value as Map), shiftId);
        }
      }
      if (shift == null) return;
      if (isCashIn) {
        shift.cashIn += amount;
      } else {
        shift.cashOut += amount;
      }
      activeShiftCache = shift;
      await cashShiftsRef.child(shiftId).set(shift.toMap());
    } catch (_) {}
  }

  Future<void> closeCashShift(CashShiftModel shift, int actualCash, String notes) async {
    activeShiftCache = null;
    shift.status = 'CLOSED';
    shift.closedAt = DateTime.now().millisecondsSinceEpoch;
    shift.actualCash = actualCash;
    shift.difference = actualCash - shift.expectedCash;
    shift.notes = notes;
    try {
      await cashShiftsRef.child(shift.id).set(shift.toMap());
    } catch (_) {}
    logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: shift.staffUsername,
      userFullName: shift.staffFullName,
      userRole: 'CASHIER',
      action: 'CLOSE_SHIFT',
      targetType: 'SHIFT',
      targetId: shift.shiftCode,
      details: 'Chốt ca ${shift.shiftCode}: Doanh số ${shift.totalRevenue}đ, Lệch: ${shift.difference}đ',
    ));
  }

  Future<void> deductCashShiftSale(String paymentMethod, int amount) async {
    try {
      final shift = activeShiftCache ?? await getCurrentOpenShift();
      if (shift != null && shift.isOpen) {
        final m = paymentMethod.toUpperCase();
        if (m.contains('CASH') || m.contains('TIỀN MẶT')) {
          shift.totalCashSales = (shift.totalCashSales - amount).clamp(0, 999999999);
        } else if (m.contains('QR') || m.contains('TRANSFER')) {
          shift.totalQrSales = (shift.totalQrSales - amount).clamp(0, 999999999);
        } else if (m.contains('CARD') || m.contains('THẺ')) {
          shift.totalCardSales = (shift.totalCardSales - amount).clamp(0, 999999999);
        }
        activeShiftCache = shift;
        await cashShiftsRef.child(shift.id).set(shift.toMap()).catchError((_) {});
      }
    } catch (_) {}
  }

  // ==================== KIOTVIET CUSTOMER LOYALTY (CRM) ====================
  Future<KmtCustomerModel?> lookupCustomer(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    try {
      // 1. Try Firestore
      try {
        final firestoreSnap = await FirebaseFirestore.instance
            .collection('kmt_customers')
            .where('phone', isEqualTo: clean)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 2));
        if (firestoreSnap.docs.isNotEmpty) {
          final doc = firestoreSnap.docs.first;
          return KmtCustomerModel.fromMap(doc.data(), doc.id);
        }
      } catch (_) {}

      // 2. Fallback RTDB
      final snap = await customersRef.get().timeout(const Duration(seconds: 2));
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in map.entries) {
          final c = KmtCustomerModel.fromMap(Map<dynamic, dynamic>.from(entry.value), entry.key.toString());
          if (c.phone == clean || c.code.toLowerCase() == clean.toLowerCase()) {
            return c;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCustomer(KmtCustomerModel customer) async {
    await customersRef.child(customer.id).set(customer.toMap());
    try {
      await FirebaseFirestore.instance.collection('kmt_customers').doc(customer.id).set(customer.toMap());
    } catch (_) {}
  }

  Future<void> awardPoints({required String customerId, required int billAmount, double rate = 1.0}) async {
    try {
      final pointsToAdd = (billAmount * (rate / 100) / 1000).round();
      if (pointsToAdd <= 0) return;
      final snap = await customersRef.child(customerId).get();
      if (snap.exists && snap.value != null) {
        final c = KmtCustomerModel.fromMap(Map<dynamic, dynamic>.from(snap.value as Map), customerId);
        c.currentPoints += pointsToAdd;
        c.totalPoints += pointsToAdd;
        await saveCustomer(c);
      }
    } catch (_) {}
  }

  Future<void> redeemCustomerPoints({required String customerId, required int points}) async {
    try {
      final snap = await customersRef.child(customerId).get();
      if (snap.exists && snap.value != null) {
        final c = KmtCustomerModel.fromMap(Map<dynamic, dynamic>.from(snap.value as Map), customerId);
        c.currentPoints = (c.currentPoints - points) > 0 ? (c.currentPoints - points) : 0;
        await saveCustomer(c);
      }
    } catch (_) {}
  }
}

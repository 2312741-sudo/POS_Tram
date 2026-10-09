import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_database/firebase_database.dart';
import '../../core/reports/report_calculator.dart';
import '../../core/reports/report_date_utils.dart';
import '../../core/reports/report_models.dart';
import '../models/app_models.dart';
import 'seed_data.dart';
import '../services/customer_import_service.dart';

class ReportRepository {
  final DatabaseReference Function() _getRoot;
  final String Function() _getCurrentStoreCode;
  final DatabaseReference Function() _getStoreRef;
  final DatabaseReference Function() _getStoreInfoRef;
  final DatabaseReference Function() _getAuditLogsRef;
  final DatabaseReference Function() _getCashShiftsRef;
  final void Function(String storeCode)? _onSwitchStore;

  CashShiftModel? activeShiftCache;

  List<CashShiftModel>? _cachedCashShiftsList;
  Stream<List<CashShiftModel>>? _cachedCashShiftsStream;
  Stream<List<CashShiftModel>>? _underlyingBroadcastStream;
  StreamSubscription<List<CashShiftModel>>? _underlyingCashShiftsSub;
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
  DatabaseReference get customersRef => storeRef.child('customers');

  /// Cờ cấu hình truy vấn Firestore CRM kế thừa.
  /// Mặc định: false (POS hoàn toàn dùng Realtime Database tại stores/{storeCode}/customers).
  static bool useFirestoreCustomers = false;

  void clearShiftCache() {
    activeShiftCache = null;
    _cachedCashShiftsList = null;
    _underlyingCashShiftsSub?.cancel();
    _underlyingCashShiftsSub = null;
    _underlyingBroadcastStream = null;
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
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      if (map['defaultVatRate'] == 8 || map['defaultVatRate'] == 8.0) {
        map['defaultVatRate'] = 0.0;
        storeInfoRef.update({'defaultVatRate': 0.0}).catchError((_) {});
      }
      return StoreInfoModel.fromMap(map, _currentStoreCode);
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
    return storeInfoRef.onValue.map<List<StoreInfoModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return [StoreInfoModel(storeCode: _currentStoreCode, storeName: 'POS Trạm - $_currentStoreCode')];
      }
      final sInfo = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return [StoreInfoModel.fromMap(sInfo, _currentStoreCode)];
    }).handleError((_) => [StoreInfoModel(storeCode: _currentStoreCode, storeName: 'POS Trạm - $_currentStoreCode')]);
  }

  Future<List<StoreInfoModel>> getAllStores() async {
    try {
      final snap = await storeInfoRef.get().timeout(const Duration(seconds: 2));
      if (!snap.exists || snap.value == null) {
        return [StoreInfoModel(storeCode: _currentStoreCode, storeName: 'POS Trạm - $_currentStoreCode')];
      }
      final sInfo = Map<dynamic, dynamic>.from(snap.value as Map);
      return [StoreInfoModel.fromMap(sInfo, _currentStoreCode)];
    } catch (_) {
      return [StoreInfoModel(storeCode: _currentStoreCode, storeName: 'POS Trạm - $_currentStoreCode')];
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
        defaultVatRate: 0.0,
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
    } catch (_) {}
  }

  // ==================== KIOTVIET CASH SHIFT (QUẢN LÝ KÉT TIỀN CA) ====================
  List<CashShiftModel>? get cachedCashShiftsList => _cachedCashShiftsList;

  Stream<List<CashShiftModel>> cashShiftsStream() {
    if (_cachedCashShiftsStream != null && _cachedCashShiftsStoreCode == _currentStoreCode) {
      return _cachedCashShiftsStream!;
    }
    _cachedCashShiftsStoreCode = _currentStoreCode;
    _underlyingCashShiftsSub?.cancel();

    final rawStream = cashShiftsRef.onValue.map<List<CashShiftModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        activeShiftCache = null;
        _cachedCashShiftsList = <CashShiftModel>[];
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
      _cachedCashShiftsList = list;
      return list;
    }).handleError((_) => (activeShiftCache != null && activeShiftCache!.isOpen)
        ? [activeShiftCache!]
        : (_cachedCashShiftsList ?? <CashShiftModel>[]));

    final broadcast = rawStream.asBroadcastStream();
    _underlyingBroadcastStream = broadcast;
    _underlyingCashShiftsSub = broadcast.listen((list) {
      _cachedCashShiftsList = list;
    }, onError: (_) {});

    _cachedCashShiftsStream = Stream<List<CashShiftModel>>.multi((controller) {
      // Replay ngay lập tức dữ liệu cache nếu có cho listener mới (tránh việc listener mới bị kẹt không nhận được dữ liệu ban đầu)
      if (_cachedCashShiftsList != null && _cachedCashShiftsStoreCode == _currentStoreCode) {
        controller.add(_cachedCashShiftsList!);
      }
      final sub = broadcast.listen(
        (data) => controller.add(data),
        onError: (err, st) => controller.addError(err, st),
        onDone: () => controller.close(),
      );
      controller.onCancel = () {
        sub.cancel();
      };
    }, isBroadcast: true);

    return _cachedCashShiftsStream!;
  }

  Future<List<CashShiftModel>> getRecentCashShifts({int limit = 50, bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedCashShiftsList != null &&
        _cachedCashShiftsList!.isNotEmpty &&
        _cachedCashShiftsStoreCode == _currentStoreCode) {
      return _cachedCashShiftsList!;
    }
    try {
      final snap = await cashShiftsRef.limitToLast(limit).get().timeout(const Duration(seconds: 4));
      if (!snap.exists || snap.value == null) {
        if (_cachedCashShiftsStoreCode == _currentStoreCode && _cachedCashShiftsList != null) {
          return _cachedCashShiftsList!;
        }
        return <CashShiftModel>[];
      }
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      final list = map.entries
          .map((e) => CashShiftModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .where((s) => s.openedAt > 0)
          .toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
      _cachedCashShiftsList = list;
      _cachedCashShiftsStoreCode = _currentStoreCode;
      final openOne = list.where((s) => s.isOpen).firstOrNull;
      if (openOne != null) {
        activeShiftCache = openOne;
      }
      return list;
    } catch (_) {
      return _cachedCashShiftsList ?? <CashShiftModel>[];
    }
  }

  Future<CashShiftModel?> getCurrentOpenShift({bool forceRefresh = false}) async {
    if (!forceRefresh && activeShiftCache != null && activeShiftCache!.isOpen) {
      return activeShiftCache;
    }
    if (!forceRefresh && _cachedCashShiftsList != null && _cachedCashShiftsStoreCode == _currentStoreCode) {
      final found = _cachedCashShiftsList!.where((s) => s.isOpen && s.openedAt > 0).firstOrNull;
      if (found != null) {
        activeShiftCache = found;
        return found;
      }
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
    if (_cachedCashShiftsList != null) {
      _cachedCashShiftsList = [shift, ..._cachedCashShiftsList!.where((s) => s.id != shift.id)];
    }
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
    // Lỗi ghi ca được ném ra cho UI (mất mạng: dữ liệu giữ cục bộ, tự đồng bộ)
    await _awaitWrite(cashShiftsRef.child(shift.id).set(shift.toMap()), 'mở ca ${shift.shiftCode}');
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

  /// Chờ server xác nhận ghi; quá thời gian (mất mạng) thì coi như đã xếp hàng đồng bộ,
  /// lỗi thật (VD: permission-denied) được ném ra.
  Future<void> _awaitWrite(Future<void> write, String what) async {
    try {
      await write.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      unawaited(write.catchError((Object e) => _logSyncFailure(what, e)));
    } catch (e) {
      throw Exception('Không lưu được $what: $e');
    }
  }

  void _logSyncFailure(String what, Object e) {
    logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: 'system',
      userFullName: 'Hệ thống',
      userRole: 'SYSTEM',
      action: 'SYNC_WRITE_FAILED',
      targetType: 'SHIFT',
      targetId: what,
      details: 'Ghi "$what" thất bại: $e',
      isSuspicious: true,
    ));
  }

  /// Cộng dồn số liệu ca bằng transaction (nhiều máy cùng ca không ghi đè nhau).
  /// Trả về ca sau khi cập nhật (null nếu ca không tồn tại / chưa xác nhận do mất mạng).
  Future<CashShiftModel?> _incrementShift(
    String shiftId, {
    int cash = 0,
    int qr = 0,
    int card = 0,
    int cashIn = 0,
    int cashOut = 0,
    required String what,
  }) async {
    final fut = cashShiftsRef.child(shiftId).runTransaction((Object? current) {
      if (current == null) return Transaction.success(null);
      final m = Map<String, dynamic>.from(current as Map);
      int add(String k, int d) {
        final v = ((m[k] as num?)?.toInt() ?? 0) + d;
        return v < 0 ? 0 : v;
      }
      m['totalCashSales'] = add('totalCashSales', cash);
      m['totalQrSales'] = add('totalQrSales', qr);
      m['totalCardSales'] = add('totalCardSales', card);
      m['cashIn'] = add('cashIn', cashIn);
      m['cashOut'] = add('cashOut', cashOut);
      return Transaction.success(m);
    });
    try {
      final res = await fut.timeout(const Duration(seconds: 6));
      final v = res.snapshot.value;
      if (!res.committed || v == null) return null;
      final updated = CashShiftModel.fromMap(Map<dynamic, dynamic>.from(v as Map), shiftId);
      if (activeShiftCache == null || activeShiftCache!.id == shiftId) {
        activeShiftCache = updated.isOpen ? updated : activeShiftCache;
      }
      if (_cachedCashShiftsList != null) {
        _cachedCashShiftsList = _cachedCashShiftsList!.map((s) => s.id == shiftId ? updated : s).toList();
      }
      return updated;
    } on TimeoutException {
      unawaited(fut.then((_) {}, onError: (Object e) => _logSyncFailure(what, e)));
      return null;
    }
  }

  Future<void> recordCashShiftSale({
    required int cashAmount,
    required int qrAmount,
    required int cardAmount,
    String? shiftId,
  }) async {
    final targetId = shiftId ?? (activeShiftCache ?? await getCurrentOpenShift())?.id;
    if (targetId == null) return;
    try {
      await _incrementShift(targetId,
          cash: cashAmount, qr: qrAmount, card: cardAmount, what: 'doanh số ca $targetId');
    } catch (e) {
      _logSyncFailure('doanh số ca $targetId (+$cashAmount TM, +$qrAmount QR, +$cardAmount thẻ)', e);
      rethrow;
    }
  }

  Future<void> addCashShiftAdjustment({
    required String shiftId,
    required int amount,
    required bool isCashIn,
    required String reason,
  }) async {
    await _incrementShift(
      shiftId,
      cashIn: isCashIn ? amount : 0,
      cashOut: isCashIn ? 0 : amount,
      what: '${isCashIn ? "nộp" : "chi"} $amount ca $shiftId',
    );
  }

  Future<void> closeCashShift(CashShiftModel shift, int actualCash, String notes) async {
    activeShiftCache = null;
    shift.status = 'CLOSED';
    shift.closedAt = DateTime.now().millisecondsSinceEpoch;
    shift.actualCash = actualCash;
    shift.difference = actualCash - shift.expectedCash;
    shift.notes = notes;
    if (_cachedCashShiftsList != null) {
      _cachedCashShiftsList = _cachedCashShiftsList!.map((s) => s.id == shift.id ? shift : s).toList();
    }
    // Chỉ cập nhật các trường chốt ca (không ghi đè doanh số do máy khác cộng dồn)
    await _awaitWrite(
      cashShiftsRef.child(shift.id).update({
        'status': shift.status,
        'closedAt': shift.closedAt,
        'actualCash': shift.actualCash,
        'difference': shift.difference,
        'notes': shift.notes,
      }),
      'chốt ca ${shift.shiftCode}',
    );
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
    final shift = activeShiftCache ?? await getCurrentOpenShift();
    if (shift == null || !shift.isOpen) return;
    final m = paymentMethod.toUpperCase();
    int cash = 0, qr = 0, card = 0;
    if (m.contains('CASH') || m.contains('TIỀN MẶT')) {
      cash = -amount;
    } else if (m.contains('QR') || m.contains('TRANSFER')) {
      qr = -amount;
    } else if (m.contains('CARD') || m.contains('THẺ')) {
      card = -amount;
    }
    try {
      await _incrementShift(shift.id, cash: cash, qr: qr, card: card, what: 'trừ doanh số ca ${shift.id}');
    } catch (e) {
      // Không chặn thao tác hủy/xóa hóa đơn, nhưng ghi nhận để đối soát
      _logSyncFailure('trừ doanh số ca ${shift.id} ($paymentMethod -$amount)', e);
    }
  }

  // ==================== KIOTVIET CUSTOMER LOYALTY (CRM) ====================
  Future<KmtCustomerModel?> lookupCustomer(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    final normalizedPhone = clean.replaceAll(RegExp(r'[^0-9]'), '');

    try {
      // 1. Tra cứu Firestore kmt_customers (Hệ sinh thái Khuyến Mãi Trạm)
      try {
        // A. Tra cứu theo so_dien_thoai
        if (normalizedPhone.isNotEmpty) {
          final phoneSnap = await FirebaseFirestore.instance
              .collection('kmt_customers')
              .where('so_dien_thoai', isEqualTo: normalizedPhone)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 2));
          if (phoneSnap.docs.isNotEmpty) {
            final doc = phoneSnap.docs.first;
            return await _preferRtdb(KmtCustomerModel.fromMap(doc.data(), doc.id));
          }

          final legacyPhoneSnap = await FirebaseFirestore.instance
              .collection('kmt_customers')
              .where('phone', isEqualTo: clean)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 2));
          if (legacyPhoneSnap.docs.isNotEmpty) {
            final doc = legacyPhoneSnap.docs.first;
            return await _preferRtdb(KmtCustomerModel.fromMap(doc.data(), doc.id));
          }
        }

        // B. Tra cứu theo ma_khach_hang (Doc ID hoặc field)
        final docSnap = await FirebaseFirestore.instance
            .collection('kmt_customers')
            .doc(clean.toUpperCase())
            .get()
            .timeout(const Duration(seconds: 2));
        if (docSnap.exists && docSnap.data() != null) {
          return await _preferRtdb(KmtCustomerModel.fromMap(docSnap.data()!, docSnap.id));
        }

        final codeSnap = await FirebaseFirestore.instance
            .collection('kmt_customers')
            .where('ma_khach_hang', isEqualTo: clean.toUpperCase())
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 2));
        if (codeSnap.docs.isNotEmpty) {
          final doc = codeSnap.docs.first;
          return await _preferRtdb(KmtCustomerModel.fromMap(doc.data(), doc.id));
        }
      } catch (_) {}

      // 2. Tra cứu dự phòng từ RTDB stores/{storeCode}/customers
      final snap = await customersRef.get().timeout(const Duration(seconds: 2));
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in map.entries) {
          final c = KmtCustomerModel.fromMap(Map<dynamic, dynamic>.from(entry.value), entry.key.toString());
          if (c.phone == clean ||
              (normalizedPhone.isNotEmpty && c.phone.replaceAll(RegExp(r'[^0-9]'), '') == normalizedPhone) ||
              c.code.toLowerCase() == clean.toLowerCase()) {
            return c;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// RTDB là nguồn chuẩn của điểm: khách tìm thấy trên Firestore mà đã có ở RTDB thì dùng bản RTDB.
  Future<KmtCustomerModel> _preferRtdb(KmtCustomerModel fromFirestore) async {
    try {
      final snap = await customersRef.child(fromFirestore.id).get().timeout(const Duration(seconds: 2));
      if (snap.exists && snap.value is Map) {
        return KmtCustomerModel.fromMap(Map<dynamic, dynamic>.from(snap.value as Map), fromFirestore.id);
      }
    } catch (_) {}
    return fromFirestore;
  }

  static const Set<String> _pointFields = {'diem_hien_tai', 'currentPoints', 'totalPoints'};

  /// Lưu thông tin khách vào RTDB stores/{storeCode}/customers (nguồn chuẩn).
  /// - KHÔNG ghi Firestore: Cloud Function mirrorCustomerToFirestore đồng bộ sang kmt_customers.
  /// - KHÔNG đổi điểm: điểm chỉ thay đổi qua LoyaltyService (thao tác hóa đơn) hoặc Quản lý.
  /// - Khách mới có điểm (lấy từ Firestore) → nhập qua importCustomerToStore để giữ số dư thật.
  Future<void> saveCustomer(KmtCustomerModel customer) async {
    try {
      final ref = customersRef.child(customer.id);
      final info = Map<String, dynamic>.from(customer.toMap())..removeWhere((k, _) => _pointFields.contains(k));
      final snap = await ref.get().timeout(const Duration(seconds: 3));
      if (snap.exists) {
        await ref.update(info);
        return;
      }
      if (customer.currentPoints == 0 && customer.totalPoints == 0) {
        await ref.set(customer.toMap());
        return;
      }
      await CustomerImportService.importToStore(storeCode: _currentStoreCode, customerId: customer.id);
      await ref.update(info);
    } catch (_) {}
  }

  /// Lấy toàn bộ danh sách khách hàng để xem báo cáo CRM và xuất file Excel
  Future<List<KmtCustomerModel>> getAllCustomers() async {
    final Map<String, KmtCustomerModel> map = {};

    // 1. Đọc từ Firestore kmt_customers
    try {
      final snap = await FirebaseFirestore.instance
          .collection('kmt_customers')
          .get()
          .timeout(const Duration(seconds: 4));
      for (final doc in snap.docs) {
        final c = KmtCustomerModel.fromMap(doc.data(), doc.id);
        map[c.id] = c;
      }
    } catch (_) {}

    // 2. Đọc RTDB (ưu tiên hơn Firestore)
    try {
      final snap = await customersRef.get().timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null) {
        final rawMap = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in rawMap.entries) {
          final id = entry.key.toString();
          // RTDB là nguồn chuẩn của điểm → ghi đè bản Firestore (có thể trễ)
          map[id] = KmtCustomerModel.fromMap(Map<dynamic, dynamic>.from(entry.value), id);
        }
      }
    } catch (_) {}

    final list = map.values.toList();
    list.sort((a, b) => b.currentPoints.compareTo(a.currentPoints));
    return list;
  }

  // ==================== REPORT DATA QUERIES ====================
  DatabaseReference _getStoreBillsRef(String? storeCode) {
    final code = (storeCode != null && storeCode.isNotEmpty) ? storeCode : _currentStoreCode;
    return _root.child('stores').child(code).child('bills');
  }

  DatabaseReference _getStoreProductsRef(String? storeCode) {
    final code = (storeCode != null && storeCode.isNotEmpty) ? storeCode : _currentStoreCode;
    return _root.child('stores').child(code).child('products');
  }

  Stream<List<BillModel>> storeBillsStream({String? storeCode}) {
    return _getStoreBillsRef(storeCode).onValue.map<List<BillModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <BillModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final list = map.entries
          .map((e) => ReportBillModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList();
      return ReportCalculator.deduplicateBills(list);
    }).handleError((_) => <BillModel>[]);
  }

  Future<List<BillModel>> getStoreBills({String? storeCode, DateTime? startDate, DateTime? endDate}) async {
    try {
      final snap = await _getStoreBillsRef(storeCode).get().timeout(const Duration(seconds: 4));
      if (!snap.exists || snap.value == null) return <BillModel>[];
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      final list = map.entries
          .map((e) => ReportBillModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList();
      final deduped = ReportCalculator.deduplicateBills(list);
      if (startDate != null && endDate != null) {
        return deduped.where((b) {
          final dt = ReportDateUtils.getBillDateTime(b.closedAt, b.createdAt, b.status);
          return ReportDateUtils.isInRange(dt, startDate, endDate);
        }).toList();
      }
      return deduped;
    } catch (_) {
      return <BillModel>[];
    }
  }

  Future<List<BillModel>> getBillsForShift(CashShiftModel shift, {String? storeCode}) async {
    try {
      final billsRef = _getStoreBillsRef(storeCode);
      final start = shift.openedAt - (10 * 60 * 1000);
      final end = (shift.closedAt ?? DateTime.now().millisecondsSinceEpoch) + (10 * 60 * 1000);
      try {
        final snap = await billsRef.orderByChild('createdAt').startAt(start).endAt(end).get().timeout(const Duration(seconds: 4));
        if (snap.exists && snap.value != null) {
          final map = Map<dynamic, dynamic>.from(snap.value as Map);
          final list = map.entries
              .map((e) => ReportBillModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
              .toList();
          final deduped = ReportCalculator.deduplicateBills(list);
          return deduped.where((b) {
            if (b.shiftId != null && b.shiftId!.isNotEmpty) {
              return b.shiftId == shift.id || b.shiftId == shift.shiftCode;
            }
            final closeT = shift.closedAt ?? 9999999999999;
            return b.createdAt >= shift.openedAt && b.createdAt <= closeT;
          }).toList();
        }
      } catch (_) {
        final startDt = DateTime.fromMillisecondsSinceEpoch(shift.openedAt);
        final endDt = DateTime.fromMillisecondsSinceEpoch(shift.closedAt ?? DateTime.now().millisecondsSinceEpoch);
        final all = await getStoreBills(
          storeCode: storeCode,
          startDate: startDt.subtract(const Duration(hours: 1)),
          endDate: endDt.add(const Duration(hours: 1)),
        );
        return all.where((b) {
          if (b.shiftId != null && b.shiftId!.isNotEmpty) {
            return b.shiftId == shift.id || b.shiftId == shift.shiftCode;
          }
          final closeT = shift.closedAt ?? 9999999999999;
          return b.createdAt >= shift.openedAt && b.createdAt <= closeT;
        }).toList();
      }
    } catch (_) {
      return <BillModel>[];
    }
    return <BillModel>[];
  }

  Future<Map<int, ProductModel>> getProductsMap({String? storeCode}) async {
    try {
      final snap = await _getStoreProductsRef(storeCode).get().timeout(const Duration(seconds: 3));
      if (!snap.exists || snap.value == null) return <int, ProductModel>{};
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      final result = <int, ProductModel>{};
      map.forEach((k, v) {
        if (v is Map) {
          final p = ProductModel.fromMap(v, k.toString());
          if (p.id > 0) result[p.id] = p;
        }
      });
      return result;
    } catch (_) {
      return <int, ProductModel>{};
    }
  }
}

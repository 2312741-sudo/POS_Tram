// lib/data/services/firebase_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../core/utils/format_utils.dart';
import '../models/app_models.dart';
import 'inventory_service.dart';
import 'campaign_service.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  String _currentStoreCode = 'TRAM01';
  String get currentStoreCode => _currentStoreCode;

  late DatabaseReference _root;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  void init({String? storeCode}) {
    if (storeCode != null && storeCode.isNotEmpty) {
      _currentStoreCode = storeCode.toUpperCase().trim();
    }
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
  }

  void switchStore(String storeCode) {
    _currentStoreCode = storeCode.toUpperCase().trim();
    _activeShiftCache = null;
    _cachedCashShiftsStream = null;
  }

  // ==================== DEFAULT FALLBACK DATA (21 Real Tables, 5 Real Zones, 37 Products & 10 Categories) ====================
  List<TableModel> get defaultTables => [
    // Khu A
    TableModel(name: 'A1', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A2', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A3', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A4', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A5', zone: 'Khu A', capacity: 4),
    // Khu B
    TableModel(name: 'B1', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B2', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B3', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B4', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B5', zone: 'Khu B', capacity: 4),
    // Khu C
    TableModel(name: 'C1', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C2', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C3', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C4', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C5', zone: 'Khu C', capacity: 4),
    // Khu D
    TableModel(name: 'D1', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D2', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D3', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D4', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D5', zone: 'Khu D', capacity: 4),
    // Mang về
    TableModel(name: 'Mang về', zone: 'Mang về', capacity: 2),
  ];

  List<CategoryModel> get defaultCategories => [
    CategoryModel(name: "Bánh Lăn Nướng"),
    CategoryModel(name: "Bánh Tam Giác Nướng"),
    CategoryModel(name: "Bánh Tart"),
    CategoryModel(name: "Bánh Waffle"),
    CategoryModel(name: "Bơ Coco"),
    CategoryModel(name: "CAFE Việt Nam"),
    CategoryModel(name: "Sữa Hạt Tươi"),
    CategoryModel(name: "Topping"),
    CategoryModel(name: "Trà Olong Trái Cây"),
    CategoryModel(name: "Trà Sữa Tươi"),
  ];

  List<ZoneModel> get defaultZones => [
    ZoneModel(name: 'Khu A'),
    ZoneModel(name: 'Khu B'),
    ZoneModel(name: 'Khu C'),
    ZoneModel(name: 'Khu D'),
    ZoneModel(name: 'Mang về'),
  ];

  List<ProductModel> get defaultProducts => [
    ProductModel(id: 22, name: "Bánh lăn choco chip - Size 15", price: 15000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_22.jpg"),
    ProductModel(id: 23, name: "Bánh lăn choco chip - Size 30", price: 30000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_23.jpg"),
    ProductModel(id: 24, name: "Bánh lăn choco chip - Size 50", price: 50000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_24.jpg"),
    ProductModel(id: 25, name: "Bánh lăn cốm déo - Size 15", price: 15000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_25.jpg"),
    ProductModel(id: 26, name: "Bánh lăn cốm déo - Size 30", price: 30000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_26.jpg"),
    ProductModel(id: 27, name: "Bánh lăn cốm déo - Size 50", price: 50000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_27.jpg"),
    ProductModel(id: 19, name: "Bánh lăn phô mai chảy - Size 15", price: 15000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_19.jpg"),
    ProductModel(id: 20, name: "Bánh lăn phô mai chảy - Size 30", price: 30000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_20.jpg"),
    ProductModel(id: 21, name: "Bánh lăn phô mai chảy - Size 50", price: 50000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_21.jpg"),
    ProductModel(id: 17, name: "Bánh lăn truyền thống - Size 15", price: 15000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_17.jpg"),
    ProductModel(id: 18, name: "Bánh lăn truyền thống - Size 30", price: 30000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_18.jpg"),
    ProductModel(id: 29, name: "Bánh tart chuối choco", price: 20000, unit: "Cái", category: "Bánh Tart", imageResourceName: "assets/images/products/product_29.jpg"),
    ProductModel(id: 28, name: "Bánh tart trứng", price: 18000, unit: "Cái", category: "Bánh Tart", imageResourceName: "assets/images/products/product_28.jpg"),
    ProductModel(id: 35, name: "Bánh waffle bơ cay chà bông", price: 25000, unit: "Cái", category: "Bánh Waffle", imageResourceName: "assets/images/products/product_35.jpg"),
    ProductModel(id: 36, name: "Bánh waffle cốm dẻo", price: 25000, unit: "Cái", category: "Bánh Waffle", imageResourceName: "assets/images/products/product_36.jpg"),
    ProductModel(id: 37, name: "Bánh waffle kem choco", price: 25000, unit: "Cái", category: "Bánh Waffle", imageResourceName: "assets/images/products/product_37.jpg"),
    ProductModel(id: 34, name: "Bơ coco", price: 35000, unit: "Ly", category: "Bơ Coco", imageResourceName: "assets/images/products/product_34.jpg"),
    ProductModel(id: 32, name: "Bạc xỉu", price: 25000, unit: "Ly", category: "CAFE Việt Nam", imageResourceName: "assets/images/products/product_32.jpg"),
    ProductModel(id: 33, name: "Cà phê kem trứng", price: 30000, unit: "Ly", category: "CAFE Việt Nam", imageResourceName: "assets/images/products/product_33.jpg"),
    ProductModel(id: 31, name: "Cà phê sữa", price: 20000, unit: "Ly", category: "CAFE Việt Nam", imageResourceName: "assets/images/products/product_31.jpg"),
    ProductModel(id: 30, name: "Cà phê đen", price: 18000, unit: "Ly", category: "CAFE Việt Nam", imageResourceName: "assets/images/products/product_30.jpg"),
    ProductModel(id: 2, name: "Sữa bò tươi - Bí đỏ Đậu phộng", price: 18000, unit: "Ly", category: "Sữa Hạt Tươi", imageResourceName: "assets/images/products/product_2.jpg"),
    ProductModel(id: 4, name: "Sữa bò tươi - Bắp non", price: 18000, unit: "Ly", category: "Sữa Hạt Tươi", imageResourceName: "assets/images/products/product_4.png"),
    ProductModel(id: 3, name: "Sữa bò tươi - Cốm rang", price: 25000, unit: "Ly", category: "Sữa Hạt Tươi", imageResourceName: "assets/images/products/product_3.jpg"),
    ProductModel(id: 1, name: "Sữa bò tươi - Đậu nành hạt điều", price: 18000, unit: "Ly", category: "Sữa Hạt Tươi", imageResourceName: "assets/images/products/product_1.jpg"),
    ProductModel(id: 14, name: "Tam giác - nhân phô mai", price: 20000, unit: "Cái", category: "Bánh Tam Giác Nướng", imageResourceName: "assets/images/products/product_14.jpg"),
    ProductModel(id: 13, name: "Tam giác - nhân sữa", price: 20000, unit: "Cái", category: "Bánh Tam Giác Nướng", imageResourceName: "assets/images/products/product_13.jpg"),
    ProductModel(id: 15, name: "Tam giác - nhân trứng muối", price: 20000, unit: "Cái", category: "Bánh Tam Giác Nướng", imageResourceName: "assets/images/products/product_15.jpg"),
    ProductModel(id: 0, name: "Thạch chanh", price: 5000, unit: "Phần", category: "Topping", imageResourceName: "assets/images/products/product_0.jpg"),
    ProductModel(id: 7, name: "Trà Olong - Chanh dây", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_7.jpg"),
    ProductModel(id: 5, name: "Trà Olong - Chanh tươi", price: 20000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_5.jpg"),
    ProductModel(id: 45, name: "Trà Olong - Mãng cầu", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_45.jpg"),
    ProductModel(id: 8, name: "Trà Olong - Quả mọng", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_8.jpg"),
    ProductModel(id: 42, name: "Trà Olong - Xoài", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_42.jpg"),
    ProductModel(id: 10, name: "Trà Olong - Đào", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_10.jpg"),
    ProductModel(id: 12, name: "Trà sữa tươi - Olong gạo rang", price: 35000, unit: "Ly", category: "Trà Sữa Tươi", imageResourceName: "assets/images/products/product_12.jpg"),
    ProductModel(id: 11, name: "Trà sữa tươi - Olong matcha", price: 30000, unit: "Ly", category: "Trà Sữa Tươi", imageResourceName: "assets/images/products/product_11.jpg"),
  ];

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

  // ==================== PARSING HELPERS ====================
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
    switchStore(code);

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
      await storeInfoRef.set(info.toMap()).timeout(const Duration(seconds: 2));

      for (final t in defaultTables) {
        tablesRef.child(t.firebaseKey).set(t.toMap()).catchError((_) {});
      }
      for (final p in defaultProducts) {
        final key = p.name.replaceAll(RegExp(r'[.#$\[\]]'), '_');
        productsRef.child(key).set(p.toMap()).catchError((_) {});
      }
      for (final c in defaultCategories) {
        categoriesRef.child(c.name).set({'name': c.name}).catchError((_) {});
      }
      for (final z in defaultZones) {
        zonesRef.child(z.name).set({'name': z.name}).catchError((_) {});
      }
    } catch (_) {}
  }

  // ==================== AUTH ====================
  Future<UserModel?> login(String username, String password) async {
    try {
      final snap = await usersRef.child(username).get().timeout(const Duration(seconds: 3));
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        final user = UserModel.fromMap(map);
        if (user.password == password) return user;
      }
      final allSnap = await usersRef.get().timeout(const Duration(seconds: 3));
      if (allSnap.exists && allSnap.value != null) {
        final allMap = Map<dynamic, dynamic>.from(allSnap.value as Map);
        for (final entry in allMap.entries) {
          final u = UserModel.fromMap(Map<dynamic, dynamic>.from(entry.value));
          if (u.username.toLowerCase() == username.toLowerCase() && u.password == password) {
            return u;
          }
        }
      }
      // Check root /users fallback
      final rootSnap = await _root.child('users').child(username).get().timeout(const Duration(seconds: 2));
      if (rootSnap.exists && rootSnap.value != null) {
        final map = Map<dynamic, dynamic>.from(rootSnap.value as Map);
        final user = UserModel.fromMap(map);
        if (user.password == password) return user;
      }
      return null;
    } catch (_) {
      return null;
    }
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

  // ==================== ROLES ====================
  Stream<List<RoleModel>> rolesStream() {
    return rolesRef.onValue.map<List<RoleModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <RoleModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
          .map((e) => RoleModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList();
    }).handleError((_) => <RoleModel>[]);
  }

  Future<List<RoleModel>> getRoles() async {
    try {
      final snap = await rolesRef.get().timeout(const Duration(seconds: 2));
      if (!snap.exists || snap.value == null) return [];
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      return map.entries
          .map((e) => RoleModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRole(RoleModel role) async {
    await rolesRef.child(role.id).set(role.toMap());
  }

  Future<void> deleteRole(String roleId) async {
    await rolesRef.child(roleId).remove();
  }

  // ==================== USERS ====================
  Stream<List<UserModel>> usersStream() {
    return usersRef.onValue.map<List<UserModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <UserModel>[];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.values.map((e) => UserModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
    }).handleError((_) => <UserModel>[]);
  }

  Future<List<UserModel>> getUsers() async {
    try {
      final snap = await usersRef.get().timeout(const Duration(seconds: 2));
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        return map.values.map((e) => UserModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
      }
      // Fallback root /users
      final rootSnap = await _root.child('users').get().timeout(const Duration(seconds: 2));
      if (rootSnap.exists && rootSnap.value != null) {
        final map = Map<dynamic, dynamic>.from(rootSnap.value as Map);
        return map.values.map((e) => UserModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveUser(UserModel user) async {
    await usersRef.child(user.username).set(user.toMap());
  }

  Future<void> deleteUser(String username) async {
    await usersRef.child(username).remove();
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
          return list..sort(_compareTables);
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
            return rootList..sort(_compareTables);
          }
        }
      } catch (_) {}
      return defaultTables;
    }).handleError((_) => defaultTables);
  }

  Future<void> saveTable(TableModel table) async {
    try {
      await tablesRef.child(table.firebaseKey).set(table.toMap()).timeout(const Duration(seconds: 2));
    } catch (_) {}
    _root.child('tables').child(table.firebaseKey).set(table.toMap()).catchError((_) {});
  }

  Future<void> deleteTable(TableModel table) async {
    await tablesRef.child(table.firebaseKey).remove();
    _root.child('tables').child(table.firebaseKey).remove().catchError((_) {});
  }

  // Merge table B into table A
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

    await logAction(AuditLogModel(
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

  // Chuyển toàn bộ món từ bàn source sang bàn target (KiotViet chuyển bàn)
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

    await logAction(AuditLogModel(
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

    // Đồng bộ sang nhánh /history dùng chung cho Web Admin và POS
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
    _root.child('history').child(bill.id).set(historyMap).catchError((_) {});
    _root.child('stores/$_currentStoreCode/history').child(bill.id).set(historyMap).catchError((_) {});

    table.clearTable();
    await saveTable(table);

    for (final d in bill.discounts) {
      if (d.promoId != null) {
        incrementPromotionUsage(d.promoId!);
      }
    }

    // ── Kho: Trừ tồn kho theo công thức (nếu có recipe) ──
    try {
      await InventoryService().consumeStockForBill(
        bill.items,
        bill.id,
        bill.staffUsername,
      );
    } catch (_) {
      // Không block thanh toán nếu kho lỗi
    }

    // ── KM mới: Commit campaign usage & redeem voucher (nếu bill dùng campaign/voucher) ──
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
    } catch (_) {
      // Không block thanh toán nếu KM lỗi
    }

    await logAction(AuditLogModel(
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

  // ==================== CANCEL ACTIVE BILL ====================
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

    _root.child('history').child(cancelBillId).set(billRecord).catchError((_) {});
    _root.child('stores/$_currentStoreCode/history').child(cancelBillId).set(billRecord).catchError((_) {});
    billsRef.child(cancelBillId).set(billRecord).catchError((_) {});

    // Clear the table completely back to EMPTY state
    table.clearTable();
    await saveTable(table);

    // Audit log
    await logAction(AuditLogModel(
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

  // ==================== CANCEL OR DELETE PAID BILL ====================
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

    // 1. Cập nhật trạng thái trong nhánh bills của cửa hàng
    await billsRef.child(bill.id).set(bill.toMap());

    // 2. Đồng bộ trạng thái sang nhánh /history và store history
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
    _root.child('history').child(bill.id).set(historyMap).catchError((_) {});
    _root.child('stores/$_currentStoreCode/history').child(bill.id).set(historyMap).catchError((_) {});

    // 3. Trừ doanh thu khỏi ca bán hàng nếu ca còn mở
    try {
      final shift = _activeShiftCache ?? await getCurrentOpenShift();
      if (shift != null && shift.isOpen) {
        final m = bill.paymentMethod.toUpperCase();
        if (m.contains('CASH') || m.contains('TIỀN MẶT')) {
          shift.totalCashSales = (shift.totalCashSales - bill.finalAmount).clamp(0, 999999999);
        } else if (m.contains('QR') || m.contains('TRANSFER')) {
          shift.totalQrSales = (shift.totalQrSales - bill.finalAmount).clamp(0, 999999999);
        } else if (m.contains('CARD') || m.contains('THẺ')) {
          shift.totalCardSales = (shift.totalCardSales - bill.finalAmount).clamp(0, 999999999);
        }
        _activeShiftCache = shift;
        await cashShiftsRef.child(shift.id).set(shift.toMap()).catchError((_) {});
      }
    } catch (_) {}

    // 4. Ghi nhật ký kiểm toán (Audit Log)
    await logAction(AuditLogModel(
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

    // 1. Xóa khỏi nhánh bills của cửa hàng
    await billsRef.child(bill.id).remove();

    // 2. Xóa khỏi /history và store history
    await _root.child('history').child(bill.id).remove().catchError((_) {});
    await _root.child('stores/$_currentStoreCode/history').child(bill.id).remove().catchError((_) {});

    // 3. Nếu hóa đơn chưa bị hủy trước đó (tức còn đang tính doanh số), trừ doanh số ca
    if (bill.status == 'PAID') {
      try {
        final shift = _activeShiftCache ?? await getCurrentOpenShift();
        if (shift != null && shift.isOpen) {
          final m = bill.paymentMethod.toUpperCase();
          if (m.contains('CASH') || m.contains('TIỀN MẶT')) {
            shift.totalCashSales = (shift.totalCashSales - bill.finalAmount).clamp(0, 999999999);
          } else if (m.contains('QR') || m.contains('TRANSFER')) {
            shift.totalQrSales = (shift.totalQrSales - bill.finalAmount).clamp(0, 999999999);
          } else if (m.contains('CARD') || m.contains('THẺ')) {
            shift.totalCardSales = (shift.totalCardSales - bill.finalAmount).clamp(0, 999999999);
          }
          _activeShiftCache = shift;
          await cashShiftsRef.child(shift.id).set(shift.toMap()).catchError((_) {});
        }
      } catch (_) {}
    }

    // 4. Ghi nhật ký kiểm toán (Audit Log)
    await logAction(AuditLogModel(
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

  // ==================== PRODUCTS & CATEGORIES (Store-scoped, zero root fallback) ====================
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

  /// Sao chép toàn bộ hoặc một số món/danh mục từ chi nhánh nguồn sang chi nhánh đích
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

  /// Làm trống toàn bộ món và danh mục của một chi nhánh
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
      // Fallback root /zones
      try {
        final rootSnap = await _root.child('zones').get().timeout(const Duration(seconds: 2));
        if (rootSnap.exists && rootSnap.value != null) {
          final rootList = _parseList<ZoneModel>(rootSnap.value, (k, v) => ZoneModel.fromMap(v is Map ? v : {'name': k}));
          if (rootList.isNotEmpty) return rootList;
        }
      } catch (_) {}
      return defaultZones;
    }).handleError((_) => defaultZones);
  }

  Future<void> saveZone(ZoneModel zone) async {
    await zonesRef.child(zone.name).set(zone.toMap());
    _root.child('zones').child(zone.name).set(zone.toMap()).catchError((_) {});
  }

  Future<void> deleteZone(ZoneModel zone) async {
    await zonesRef.child(zone.name).remove();
    _root.child('zones').child(zone.name).remove().catchError((_) {});
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
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }).handleError((_) => <OnlineOrderModel>[]);
  }

  Future<void> updateOnlineOrderStatus(String key, String status) async {
    await onlineOrdersRef.child(key).update({'status': status});
    _root.child('online_orders').child(key).update({'status': status}).catchError((_) {});
  }

  // ==================== KIOTVIET CASH SHIFT (QUẢN LÝ KÉT TIỀN CA) ====================
  CashShiftModel? _activeShiftCache;
  CashShiftModel? get activeShiftCache => _activeShiftCache;

  DatabaseReference get cashShiftsRef => _root.child('stores').child(_currentStoreCode).child('cash_shifts');

  Stream<List<CashShiftModel>>? _cachedCashShiftsStream;
  String? _cachedCashShiftsStoreCode;

  Stream<List<CashShiftModel>> cashShiftsStream() {
    if (_cachedCashShiftsStream != null && _cachedCashShiftsStoreCode == _currentStoreCode) {
      return _cachedCashShiftsStream!;
    }
    _cachedCashShiftsStoreCode = _currentStoreCode;
    _cachedCashShiftsStream = cashShiftsRef.onValue.map<List<CashShiftModel>>((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        _activeShiftCache = null;
        return <CashShiftModel>[];
      }
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final list = map.entries
          .map((e) => CashShiftModel.fromMap(Map<dynamic, dynamic>.from(e.value), e.key.toString()))
          .where((s) => s.openedAt > 0)
          .toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
      final openOne = list.where((s) => s.isOpen).firstOrNull;
      _activeShiftCache = openOne;
      return list;
    }).handleError((_) => (_activeShiftCache != null && _activeShiftCache!.isOpen) ? [_activeShiftCache!] : <CashShiftModel>[]).asBroadcastStream();
    return _cachedCashShiftsStream!;
  }

  Future<CashShiftModel?> getCurrentOpenShift({bool forceRefresh = false}) async {
    if (!forceRefresh && _activeShiftCache != null && _activeShiftCache!.isOpen) {
      return _activeShiftCache;
    }
    try {
      final snap = await cashShiftsRef.get().timeout(const Duration(seconds: 5));
      if (!snap.exists || snap.value == null) {
        _activeShiftCache = null;
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
      _activeShiftCache = foundOpen;
      return foundOpen;
    } catch (_) {
      return (_activeShiftCache != null && _activeShiftCache!.isOpen) ? _activeShiftCache : null;
    }
  }

  Future<void> openCashShift(CashShiftModel shift) async {
    _activeShiftCache = shift;
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
      if (shiftId != null && _activeShiftCache != null && _activeShiftCache!.id == shiftId) {
        shift = _activeShiftCache;
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
        _activeShiftCache = shift;
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
      if (_activeShiftCache != null && _activeShiftCache!.id == shiftId) {
        shift = _activeShiftCache;
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
      _activeShiftCache = shift;
      await cashShiftsRef.child(shiftId).set(shift.toMap());
    } catch (_) {}
  }

  Future<void> closeCashShift(CashShiftModel shift, int actualCash, String notes) async {
    _activeShiftCache = null;
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

  // ==================== KIOTVIET CUSTOMER LOYALTY (CRM) ====================
  DatabaseReference get customersRef => _root.child('kmt_customers');

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

  // ==================== KIOTVIET TABLE RESERVATIONS ====================
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

  // ==================== EXCEL EXPORT (TRẠM ECOSYSTEM STANDARDS) ====================
  static String sanitizeFileName(String input) {
    const vietMap = {
      'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
      'đ': 'd', 'Đ': 'D'
    };
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      buffer.write(vietMap[input[i]] ?? input[i]);
    }
    return buffer.toString()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s_\-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  Future<String?> exportReportExcel({
    required String reportType,
    required String storeName,
    List<String>? headers,
    List<List<dynamic>>? rows,
    List<BillModel>? bills,
  }) async {
    try {
      final actualHeaders = headers ?? ['Mã HĐ', 'Bàn', 'Khu vực', 'Thu ngân', 'Thời gian', 'Tiền hàng', 'Giảm giá', 'Điểm dùng', 'VAT', 'Tổng tiền', 'HTTT', 'Khách hàng', 'SĐT'];
      final actualRows = rows ?? (bills?.map((b) => [
        b.billCode,
        b.tableName,
        b.zone,
        b.staffFullName.isNotEmpty ? b.staffFullName : b.staffUsername,
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b.createdAt)),
        b.subTotal,
        b.totalDiscount,
        b.pointsDiscount,
        b.vatAmount,
        b.finalAmount,
        b.paymentMethod,
        b.customerName ?? '',
        b.customerPhone ?? '',
      ]).toList() ?? []);

      final excel = Excel.createExcel();
      final sheet = excel['TongQuan'];
      excel.setDefaultSheet('TongQuan');

      // Title Row
      sheet.appendRow([TextCellValue('BÁO CÁO $reportType - ${storeName.toUpperCase()}')]);
      final nowStr = DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now());
      sheet.appendRow([TextCellValue('Thời gian xuất: $nowStr')]);
      sheet.appendRow([]);

      // Headers Row
      sheet.appendRow(actualHeaders.map((h) => TextCellValue(h)).toList());

      // Data Rows
      for (final row in actualRows) {
        sheet.appendRow(row.map((cell) {
          if (cell is num) {
            return DoubleCellValue(cell.toDouble());
          }
          return TextCellValue(cell.toString());
        }).toList());
      }

      // Xuất Sheet 2: Chi tiết món & người nhận order nếu có bills
      if (bills != null && bills.isNotEmpty) {
        final itemSheet = excel['ChiTietMon'];
        itemSheet.appendRow([
          TextCellValue('Mã HĐ'),
          TextCellValue('Bàn'),
          TextCellValue('Tên món'),
          TextCellValue('Tùy chọn (Size/Đường/Đá/Topping)'),
          TextCellValue('Ghi chú'),
          TextCellValue('Số lượng'),
          TextCellValue('Đơn giá (VNĐ)'),
          TextCellValue('Thành tiền (VNĐ)'),
          TextCellValue('Người nhận order món'),
          TextCellValue('Người thanh toán'),
          TextCellValue('Thời gian gọi món'),
        ]);

        for (final b in bills) {
          for (final item in b.items) {
            final orderTime = item.orderedAt != null
                ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.orderedAt!))
                : DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b.createdAt));
            itemSheet.appendRow([
              TextCellValue(b.billCode),
              TextCellValue(b.tableName),
              TextCellValue(item.name),
              TextCellValue(item.optionsSummary),
              TextCellValue(item.note),
              DoubleCellValue(item.quantity.toDouble()),
              DoubleCellValue(item.unitPrice.toDouble()),
              DoubleCellValue(item.itemTotal.toDouble()),
              TextCellValue(item.orderedByName.isNotEmpty ? item.orderedByName : b.orderStaffSummary),
              TextCellValue(b.staffFullName.isNotEmpty ? b.staffFullName : b.staffUsername),
              TextCellValue(orderTime),
            ]);
          }
        }

        // Xuất Sheet 3: Lịch sử thao tác từng đơn hàng
        final logSheet = excel['LichSuThaoTac'];
        logSheet.appendRow([
          TextCellValue('Mã HĐ'),
          TextCellValue('Bàn'),
          TextCellValue('Thời gian'),
          TextCellValue('Nhân viên thao tác'),
          TextCellValue('Hành động'),
          TextCellValue('Chi tiết thao tác'),
        ]);

        for (final b in bills) {
          if (b.actionLogs.isNotEmpty) {
            for (final l in b.actionLogs) {
              final logTime = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(l.timestamp));
              logSheet.appendRow([
                TextCellValue(b.billCode),
                TextCellValue(b.tableName),
                TextCellValue(logTime),
                TextCellValue(l.staffFullName.isNotEmpty ? l.staffFullName : l.staffUsername),
                TextCellValue(l.action),
                TextCellValue(l.details),
              ]);
            }
          } else {
            // Log mặc định nếu đơn cũ chưa có log
            logSheet.appendRow([
              TextCellValue(b.billCode),
              TextCellValue(b.tableName),
              TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b.createdAt))),
              TextCellValue(b.orderStaffSummary),
              TextCellValue('ORDER_ITEMS'),
              TextCellValue('Gọi ${b.items.length} món'),
            ]);
            logSheet.appendRow([
              TextCellValue(b.billCode),
              TextCellValue(b.tableName),
              TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt))),
              TextCellValue(b.staffFullName.isNotEmpty ? b.staffFullName : b.staffUsername),
              TextCellValue('PAY_BILL'),
              TextCellValue('Thanh toán ${b.finalAmount}đ (${b.paymentMethod})'),
            ]);
          }
        }
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final safeStore = sanitizeFileName(storeName);
      final safeType = sanitizeFileName(reportType);
      final fileName = 'BaoCao_${safeType}_${safeStore}_$dateStr.xlsx';

      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$fileName';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles([XFile(filePath)], text: 'Báo cáo $reportType - $storeName');
        return filePath;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  int _compareTables(TableModel a, TableModel b) {
    if (a.zone != b.zone) {
      return a.zone.toLowerCase().compareTo(b.zone.toLowerCase());
    }
    return _compareNatural(a.name, b.name);
  }

  int _compareNatural(String a, String b) {
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

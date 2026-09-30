// lib/data/services/firebase_service.dart
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import '../models/app_models.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  static const String _dbUrl = 'https://ungdungdidong-94edd-default-rtdb.firebaseio.com';
  
  late final DatabaseReference _root;
  
  void init() {
    _root = FirebaseDatabase.instance.ref();
  }

  DatabaseReference get tablesRef => _root.child('tables');
  DatabaseReference get kitchenOrdersRef => _root.child('kitchen_orders');
  DatabaseReference get onlineOrdersRef => _root.child('online_orders');
  DatabaseReference get historyRef => _root.child('history');
  DatabaseReference get usersRef => _root.child('users');
  DatabaseReference get productsRef => _root.child('products');
  DatabaseReference get categoriesRef => _root.child('categories');
  DatabaseReference get zonesRef => _root.child('zones');
  DatabaseReference get auditLogsRef => _root.child('audit_logs');

  // ==================== AUTH ====================
  Future<UserModel?> login(String username, String password) async {
    try {
      final snap = await usersRef.child(username).get();
      if (snap.exists && snap.value != null) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        final user = UserModel.fromMap(map);
        if (user.password == password) return user;
      }
      // Fallback: scan all users
      final allSnap = await usersRef.get();
      if (allSnap.exists && allSnap.value != null) {
        final allMap = Map<dynamic, dynamic>.from(allSnap.value as Map);
        for (final entry in allMap.entries) {
          final u = UserModel.fromMap(Map<dynamic, dynamic>.from(entry.value));
          if (u.username == username && u.password == password) return u;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ==================== TABLES ====================
  Stream<List<TableModel>> tablesStream() {
    return tablesRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries.map((e) => TableModel.fromMap(Map<dynamic, dynamic>.from(e.value))).toList()
        ..sort((a, b) => _compareNatural(a.name, b.name));
    });
  }

  Future<void> saveTable(TableModel table) async {
    await tablesRef.child(table.firebaseKey).set(table.toMap());
  }

  Future<void> deleteTable(TableModel table) async {
    await tablesRef.child(table.firebaseKey).remove();
  }

  Future<void> addTable(String name, String zone) async {
    final table = TableModel(name: name, zone: zone);
    await tablesRef.child(table.firebaseKey).set(table.toMap());
  }

  // ==================== PRODUCTS ====================
  Stream<List<ProductModel>> productsStream() {
    return productsRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.values.map((e) => ProductModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
    });
  }

  Future<List<ProductModel>> getProducts() async {
    final snap = await productsRef.get();
    if (!snap.exists || snap.value == null) return [];
    final map = Map<dynamic, dynamic>.from(snap.value as Map);
    return map.values.map((e) => ProductModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
  }

  Future<void> saveProduct(ProductModel product) async {
    final key = product.name.replaceAll(RegExp(r'[.#\$\[\]]'), '_');
    await productsRef.child(key).set(product.toMap());
  }

  Future<void> deleteProduct(ProductModel product) async {
    final key = product.name.replaceAll(RegExp(r'[.#\$\[\]]'), '_');
    await productsRef.child(key).remove();
  }

  // ==================== CATEGORIES ====================
  Stream<List<CategoryModel>> categoriesStream() {
    return categoriesRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.values.map((e) => CategoryModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
    });
  }

  Future<void> saveCategory(CategoryModel cat) async {
    final key = cat.name.replaceAll(RegExp(r'[.#\$\[\]]'), '_');
    await categoriesRef.child(key).set(cat.toMap());
  }

  Future<void> deleteCategory(CategoryModel cat) async {
    final key = cat.name.replaceAll(RegExp(r'[.#\$\[\]]'), '_');
    await categoriesRef.child(key).remove();
  }

  // ==================== ZONES ====================
  Stream<List<ZoneModel>> zonesStream() {
    return zonesRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.values.map((e) => ZoneModel.fromMap(Map<dynamic, dynamic>.from(e))).toList()
        ..sort((a, b) => _compareNatural(a.name, b.name));
    });
  }

  Future<void> saveZone(ZoneModel zone) async {
    final key = zone.name.replaceAll(RegExp(r'[.#\$\[\]]'), '_');
    await zonesRef.child(key).set(zone.toMap());
  }

  Future<void> deleteZone(ZoneModel zone) async {
    final key = zone.name.replaceAll(RegExp(r'[.#\$\[\]]'), '_');
    await zonesRef.child(key).remove();
  }

  // ==================== KITCHEN ORDERS ====================
  Stream<List<KitchenOrderModel>> kitchenOrdersStream() {
    return kitchenOrdersRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
        .map((e) => KitchenOrderModel.fromMap(Map<dynamic, dynamic>.from(e.value), key: e.key))
        .where((o) => !o.isDone)
        .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
  }

  Future<String?> sendKitchenOrder(KitchenOrderModel order) async {
    final ref = kitchenOrdersRef.push();
    await ref.set(order.toMap());
    return ref.key;
  }

  Future<void> markKitchenOrderDone(String firebaseKey) async {
    await kitchenOrdersRef.child(firebaseKey).child('isDone').set(true);
  }

  // ==================== ONLINE ORDERS ====================
  Stream<List<OnlineOrderModel>> onlineOrdersStream() {
    return onlineOrdersRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
        .map((e) => OnlineOrderModel.fromMap(Map<dynamic, dynamic>.from(e.value), key: e.key))
        .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  Future<void> updateOnlineOrderStatus(String firebaseKey, String status) async {
    await onlineOrdersRef.child(firebaseKey).child('status').set(status);
  }

  // ==================== ORDER HISTORY ====================
  Stream<List<OrderHistoryModel>> historyStream() {
    return historyRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.entries
        .map((e) => OrderHistoryModel.fromMap(Map<dynamic, dynamic>.from(e.value), key: e.key))
        .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  Future<void> saveHistory(OrderHistoryModel history) async {
    await historyRef.push().set(history.toMap());
  }

  Future<void> deleteHistory(String firebaseKey) async {
    await historyRef.child(firebaseKey).remove();
  }

  // ==================== USERS ====================
  Stream<List<UserModel>> usersStream() {
    return usersRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final map = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return map.values.map((e) => UserModel.fromMap(Map<dynamic, dynamic>.from(e))).toList();
    });
  }

  Future<void> saveUser(UserModel user) async {
    await usersRef.child(user.username).set(user.toMap());
  }

  Future<void> deleteUser(String username) async {
    await usersRef.child(username).remove();
  }

  // ==================== AUDIT LOGS ====================
  Future<void> logAction(AuditLogModel log) async {
    await auditLogsRef.push().set(log.toMap());
  }

  // ==================== UTILS ====================
  int _compareNatural(String a, String b) {
    final rNum = RegExp(r'(\d+)|(\D+)');
    final mA = rNum.allMatches(a).toList();
    final mB = rNum.allMatches(b).toList();
    for (int i = 0; i < mA.length && i < mB.length; i++) {
      final gA = mA[i].group(0)!;
      final gB = mB[i].group(0)!;
      final nA = int.tryParse(gA);
      final nB = int.tryParse(gB);
      if (nA != null && nB != null) {
        if (nA != nB) return nA.compareTo(nB);
      } else {
        final c = gA.toLowerCase().compareTo(gB.toLowerCase());
        if (c != 0) return c;
      }
    }
    return a.length.compareTo(b.length);
  }
}

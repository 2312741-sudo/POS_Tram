// lib/data/models/app_models.dart
import 'dart:convert';

// ==================== PRODUCT MODEL ====================
class ProductModel {
  final int id;
  final String name;
  final int price;
  final String unit;
  final String category;
  final String? imageBase64;
  int quantity;
  String note;

  ProductModel({
    this.id = 0,
    required this.name,
    required this.price,
    required this.unit,
    required this.category,
    this.imageBase64,
    this.quantity = 0,
    this.note = '',
  });

  factory ProductModel.fromMap(Map<dynamic, dynamic> map) {
    return ProductModel(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: map['name']?.toString() ?? '',
      price: (map['price'] as num?)?.toInt() ?? 0,
      unit: map['unit']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      imageBase64: map['imageBase64']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'price': price,
    'unit': unit,
    'category': category,
    'imageBase64': imageBase64,
  };

  ProductModel copyWith({int? quantity, String? note}) => ProductModel(
    id: id, name: name, price: price, unit: unit, category: category,
    imageBase64: imageBase64,
    quantity: quantity ?? this.quantity,
    note: note ?? this.note,
  );

  int get total => price * quantity;
}

// ==================== TABLE MODEL ====================
class TableModel {
  final String name;
  final String zone;
  bool inUse;
  String currentOrderJson;

  TableModel({
    required this.name,
    required this.zone,
    this.inUse = false,
    this.currentOrderJson = '',
  });

  factory TableModel.fromMap(Map<dynamic, dynamic> map) {
    return TableModel(
      name: map['name']?.toString() ?? '',
      zone: map['zone']?.toString() ?? '',
      inUse: map['inUse'] == true,
      currentOrderJson: map['currentOrderJson']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'zone': zone,
    'inUse': inUse,
    'currentOrderJson': currentOrderJson,
  };

  List<ProductModel> get currentOrder {
    if (currentOrderJson.isEmpty) return [];
    try {
      final List list = jsonDecode(currentOrderJson);
      return list.map((e) => ProductModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  int get currentTotal => currentOrder.fold(0, (s, p) => s + p.total);
  String get firebaseKey => '${zone}_$name';
}

// ==================== USER MODEL ====================
class UserModel {
  final String username;
  final String password;
  final String fullName;
  final String role; // MANAGER, STAFF, KITCHEN

  UserModel({
    required this.username,
    required this.password,
    required this.fullName,
    required this.role,
  });

  factory UserModel.fromMap(Map<dynamic, dynamic> map) {
    return UserModel(
      username: map['username']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      role: map['role']?.toString() ?? 'STAFF',
    );
  }

  Map<String, dynamic> toMap() => {
    'username': username,
    'password': password,
    'fullName': fullName,
    'role': role,
  };

  bool get isManager => role.toUpperCase() == 'MANAGER';
  bool get isStaff => role.toUpperCase() == 'STAFF';
  bool get isKitchen => role.toUpperCase() == 'KITCHEN';

  String get roleDisplay {
    switch (role.toUpperCase()) {
      case 'MANAGER': return 'Quản lý';
      case 'STAFF': return 'Nhân viên';
      case 'KITCHEN': return 'Đầu bếp';
      default: return role;
    }
  }
}

// ==================== ORDER HISTORY MODEL ====================
class OrderHistoryModel {
  final String? firebaseKey;
  final String orderCode;
  final String tableName;
  final int totalAmount;
  final String itemsJson;
  final String paymentMethod;
  final int timestamp;
  final String status;
  final String? staffUsername; // Anti-cheat: who processed

  OrderHistoryModel({
    this.firebaseKey,
    required this.orderCode,
    required this.tableName,
    required this.totalAmount,
    required this.itemsJson,
    required this.paymentMethod,
    required this.timestamp,
    this.status = 'Đã thanh toán',
    this.staffUsername,
  });

  factory OrderHistoryModel.fromMap(Map<dynamic, dynamic> map, {String? key}) {
    return OrderHistoryModel(
      firebaseKey: key,
      orderCode: map['orderCode']?.toString() ?? '',
      tableName: map['tableName']?.toString() ?? '',
      totalAmount: (map['totalAmount'] as num?)?.toInt() ?? 0,
      itemsJson: map['itemsJson']?.toString() ?? '[]',
      paymentMethod: map['paymentMethod']?.toString() ?? 'Tiền mặt',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? 'Đã thanh toán',
      staffUsername: map['staffUsername']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'orderCode': orderCode,
    'tableName': tableName,
    'totalAmount': totalAmount,
    'itemsJson': itemsJson,
    'paymentMethod': paymentMethod,
    'timestamp': timestamp,
    'status': status,
    if (staffUsername != null) 'staffUsername': staffUsername,
  };

  List<ProductModel> get items {
    try {
      final List list = jsonDecode(itemsJson);
      return list.map((e) => ProductModel.fromMap(e)).toList();
    } catch (_) { return []; }
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}

// ==================== KITCHEN ORDER MODEL ====================
class KitchenOrderModel {
  final String? firebaseKey;
  final String tableName;
  final String itemsJson;
  final int timestamp;
  bool isDone;

  KitchenOrderModel({
    this.firebaseKey,
    required this.tableName,
    required this.itemsJson,
    required this.timestamp,
    this.isDone = false,
  });

  factory KitchenOrderModel.fromMap(Map<dynamic, dynamic> map, {String? key}) {
    return KitchenOrderModel(
      firebaseKey: key,
      tableName: map['tableName']?.toString() ?? '',
      itemsJson: map['itemsJson']?.toString() ?? '[]',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      isDone: map['isDone'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'tableName': tableName,
    'itemsJson': itemsJson,
    'timestamp': timestamp,
    'isDone': isDone,
  };

  List<ProductModel> get items {
    try {
      final List list = jsonDecode(itemsJson);
      return list.map((e) => ProductModel.fromMap(e)).toList();
    } catch (_) { return []; }
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  Duration get waitingTime => DateTime.now().difference(dateTime);
}

// ==================== ONLINE ORDER MODEL ====================
class OnlineOrderModel {
  final String? firebaseKey;
  final String tableName;
  final String tableZone;
  final String itemsJson;
  String status; // PENDING, CONFIRMED, COMPLETED, CANCELLED
  final String type; // ORDER, CALL_WAITER
  final int timestamp;
  final String? notes;

  OnlineOrderModel({
    this.firebaseKey,
    required this.tableName,
    required this.tableZone,
    required this.itemsJson,
    required this.status,
    required this.type,
    required this.timestamp,
    this.notes,
  });

  factory OnlineOrderModel.fromMap(Map<dynamic, dynamic> map, {String? key}) {
    return OnlineOrderModel(
      firebaseKey: key,
      tableName: map['tableName']?.toString() ?? '',
      tableZone: map['tableZone']?.toString() ?? '',
      itemsJson: map['itemsJson']?.toString() ?? '[]',
      status: map['status']?.toString() ?? 'PENDING',
      type: map['type']?.toString() ?? 'ORDER',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      notes: map['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'tableName': tableName,
    'tableZone': tableZone,
    'itemsJson': itemsJson,
    'status': status,
    'type': type,
    'timestamp': timestamp,
    if (notes != null) 'notes': notes,
  };

  List<ProductModel> get items {
    if (itemsJson.isEmpty || type == 'CALL_WAITER') return [];
    try {
      final List list = jsonDecode(itemsJson);
      return list.map((e) => ProductModel.fromMap(e)).toList();
    } catch (_) { return []; }
  }

  bool get isPending => status == 'PENDING';
  bool get isCallWaiter => type == 'CALL_WAITER';
}

// ==================== CATEGORY MODEL ====================
class CategoryModel {
  final String name;
  CategoryModel({required this.name});
  factory CategoryModel.fromMap(Map map) => CategoryModel(name: map['name']?.toString() ?? '');
  Map<String, dynamic> toMap() => {'name': name};
}

// ==================== ZONE MODEL ====================
class ZoneModel {
  final String name;
  ZoneModel({required this.name});
  factory ZoneModel.fromMap(Map map) => ZoneModel(name: map['name']?.toString() ?? '');
  Map<String, dynamic> toMap() => {'name': name};
}

// ==================== AUDIT LOG MODEL ====================
class AuditLogModel {
  final String action;
  final String username;
  final String userRole;
  final int timestamp;
  final String details;
  final String? targetId;

  AuditLogModel({
    required this.action,
    required this.username,
    required this.userRole,
    required this.timestamp,
    required this.details,
    this.targetId,
  });

  Map<String, dynamic> toMap() => {
    'action': action,
    'username': username,
    'userRole': userRole,
    'timestamp': timestamp,
    'details': details,
    if (targetId != null) 'targetId': targetId,
  };

  factory AuditLogModel.fromMap(Map map) => AuditLogModel(
    action: map['action']?.toString() ?? '',
    username: map['username']?.toString() ?? '',
    userRole: map['userRole']?.toString() ?? '',
    timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    details: map['details']?.toString() ?? '',
    targetId: map['targetId']?.toString(),
  );

  // Anti-cheat: classify suspicious actions
  bool get isSuspicious =>
    action == 'CANCEL_ORDER' ||
    action == 'DELETE_HISTORY' ||
    action == 'PRICE_EDIT' ||
    action == 'DISCOUNT_APPLY';
}

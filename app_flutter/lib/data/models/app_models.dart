import 'dart:convert';
import '../../core/permissions/app_permissions.dart';
import '../../core/utils/format_utils.dart';

// ==================== STORE INFO MODEL ====================
class StoreInfoModel {
  final String storeCode;
  final String storeName;
  final String address;
  final String phone;
  final String wifiName;
  final String bankId;
  final String bankAccount;
  final String accountName;
  final bool allowStackPromotions;
  final double defaultVatRate;
  final String kitchenPrinterIp;
  final String billPrinterIp;
  final String printerType; // 'LAN' or 'BLUETOOTH'
  final bool allowStaffViewShiftDifference; // Bật/tắt cho phép nhân viên xem chênh lệch tiền két khi kết ca
  final bool autoPrintBill; // Bật/tắt tự động in bill khi thanh toán
  final String ownerId;

  StoreInfoModel({
    required this.storeCode,
    required this.storeName,
    this.ownerId = '',
    this.address = '',
    this.phone = '',
    this.wifiName = '',
    this.bankId = 'MB',
    this.bankAccount = '0987654321',
    this.accountName = 'NGUYEN THANH TAM',
    this.allowStackPromotions = true,
    this.defaultVatRate = 0.0,
    this.kitchenPrinterIp = '192.168.1.200',
    this.billPrinterIp = '192.168.1.201',
    this.printerType = 'LAN',
    this.allowStaffViewShiftDifference = true,
    this.autoPrintBill = true,
  });

  factory StoreInfoModel.fromMap(Map<dynamic, dynamic> map, String storeCode) {
    return StoreInfoModel(
      storeCode: map['storeCode']?.toString() ?? storeCode,
      storeName: map['storeName']?.toString() ?? 'POS Trạm',
      ownerId: map['ownerId']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      wifiName: map['wifiName']?.toString() ?? '',
      bankId: map['bankId']?.toString() ?? 'MB',
      bankAccount: map['bankAccount']?.toString() ?? '0987654321',
      accountName: map['accountName']?.toString() ?? 'CHU CUA HANG',
      allowStackPromotions: map['allowStackPromotions'] ?? true,
      defaultVatRate: (map['defaultVatRate'] as num?)?.toDouble() ?? 0.0,
      kitchenPrinterIp: map['kitchenPrinterIp']?.toString() ?? '192.168.1.200',
      billPrinterIp: map['billPrinterIp']?.toString() ?? '192.168.1.201',
      printerType: map['printerType']?.toString() ?? 'LAN',
      allowStaffViewShiftDifference: map['allowStaffViewShiftDifference'] ?? true,
      autoPrintBill: map['autoPrintBill'] ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'storeCode': storeCode,
    'storeName': storeName,
    'address': address,
    'phone': phone,
    'wifiName': wifiName,
    'bankId': bankId,
    'bankAccount': bankAccount,
    'accountName': accountName,
    'allowStackPromotions': allowStackPromotions,
    'defaultVatRate': defaultVatRate,
    'kitchenPrinterIp': kitchenPrinterIp,
    'billPrinterIp': billPrinterIp,
    'printerType': printerType,
    'allowStaffViewShiftDifference': allowStaffViewShiftDifference,
    'autoPrintBill': autoPrintBill,
  };
}

// ==================== ROLE MODEL ====================
class RoleModel {
  final String id;
  final String name;
  final String description;
  final List<String> permissions;
  final bool isSystemRole;

  RoleModel({
    required this.id,
    required this.name,
    this.description = '',
    required this.permissions,
    this.isSystemRole = false,
  });

  factory RoleModel.fromMap(Map<dynamic, dynamic> map, String id) {
    List<String> perms = [];
    if (map['permissions'] != null) {
      if (map['permissions'] is List) {
        perms = List<String>.from(map['permissions']);
      } else if (map['permissions'] is Map) {
        perms = (map['permissions'] as Map).keys.map((e) => e.toString()).toList();
      }
    }
    return RoleModel(
      id: id,
      name: map['name']?.toString() ?? id,
      description: map['description']?.toString() ?? '',
      permissions: perms,
      isSystemRole: map['isSystemRole'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'permissions': permissions,
    'isSystemRole': isSystemRole,
  };

  bool hasPermission(String permKey) => permissions.contains(permKey);
}

// ==================== USER MODEL ====================
class UserModel {
  final String username;
  final String fullName;
  final String password;
  final String roleId;
  final bool isRootOwner;
  final List<String> customPermissions; // Specific individual overrides
  final bool isActive;
  final String phone;
  final String uid;

  UserModel({
    required this.username,
    required this.fullName,
    required this.password,
    required this.roleId,
    this.isRootOwner = false,
    this.customPermissions = const [],
    this.isActive = true,
    this.phone = '',
    this.uid = '',
  });

  factory UserModel.fromMap(Map<dynamic, dynamic> map) {
    List<String> customPerms = [];
    if (map['customPermissions'] != null) {
      if (map['customPermissions'] is List) {
        customPerms = List<String>.from(map['customPermissions']);
      } else if (map['customPermissions'] is Map) {
        customPerms = (map['customPermissions'] as Map).keys.map((e) => e.toString()).toList();
      }
    }
    return UserModel(
      username: map['username']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      roleId: map['roleId']?.toString() ?? 'STAFF',
      isRootOwner: map['isRootOwner'] == true || (map['roleId']?.toString().toUpperCase() == 'OWNER'),
      customPermissions: customPerms,
      isActive: map['isActive'] ?? true,
      phone: map['phone']?.toString() ?? '',
      uid: map['uid']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'username': username,
    'fullName': fullName,
    'password': password,
    'roleId': roleId,
    'isRootOwner': isRootOwner,
    'customPermissions': customPermissions,
    'isActive': isActive,
    'phone': phone,
    'uid': uid,
  };

  UserRole get role => UserRole.fromString(roleId);
  bool get isOwner => isRootOwner || role.isOwner;
  bool get isManager => role.isManager;

  /// Kiểm tra có phải Chủ quán cửa hàng (Owner Sovereign Rule)
  bool isStoreOwner(String? storeOwnerId) {
    if (storeOwnerId != null && storeOwnerId.isNotEmpty && uid.isNotEmpty && uid == storeOwnerId) {
      return true;
    }
    return isRootOwner || role.isOwner;
  }

  /// Check permission considering Root Owner + Role permissions + Individual custom overrides
  bool can(String permKey, [List<RoleModel>? roles, String? storeOwnerId]) {
    if (isStoreOwner(storeOwnerId)) return true; // Nguyên tắc tối thượng bảo vệ Chủ quán
    if (customPermissions.contains(permKey)) return true;
    if (roles != null && roles.isNotEmpty) {
      final matchedRole = roles.where((r) => r.id == roleId).firstOrNull;
      if (matchedRole != null) return matchedRole.hasPermission(permKey);
    }
    return role.hasDefaultPermission(permKey);
  }
}

// ==================== PRODUCT MODEL (KIOTVIET FNB) ====================
class ProductModel {
  final int id;
  final String name;
  final String code; // Mã món KiotViet SKU
  final int price;
  final String unit;
  final String category;
  final String? imageBase64;
  final String? imageResourceName;
  final bool isAvailable;
  final Map<String, int> sizes; // Ví dụ: {'M': 0, 'L': 5000}
  final List<String> allowedToppings; // Danh sách topping được phép thêm
  final bool hasIceSugarOptions; // Hỗ trợ chọn % đá, đường

  ProductModel({
    this.id = 0,
    required this.name,
    this.code = '',
    required this.price,
    required this.unit,
    required this.category,
    this.imageBase64,
    this.imageResourceName,
    this.isAvailable = true,
    this.sizes = const {},
    this.allowedToppings = const [],
    this.hasIceSugarOptions = false,
  });

  factory ProductModel.fromMap(dynamic val, [String? key]) {
    if (val is Map) {
      final map = Map<dynamic, dynamic>.from(val);
      Map<String, int> sizesMap = {};
      if (map['sizes'] is Map) {
        (map['sizes'] as Map).forEach((k, v) {
          sizesMap[k.toString()] = (v as num?)?.toInt() ?? 0;
        });
      }
      List<String> toppings = [];
      if (map['allowedToppings'] is List) {
        toppings = List<String>.from(map['allowedToppings']);
      }

      final cat = map['category']?.toString() ?? 'Khác';
      final isDrink = cat.contains('Trà') || cat.contains('CAFE') || cat.contains('Sữa') || cat.contains('Bơ');
      if (sizesMap.isEmpty && isDrink) {
        sizesMap = {'S': 0, 'M': 5000, 'L': 10000};
      }
      if (toppings.isEmpty && isDrink) {
        toppings = ['Trân châu đen', 'Trân châu trắng', 'Thạch phô mai', 'Kem Cheese'];
      }
      final bool hasIceSugar = map['hasIceSugarOptions'] == true || (map['hasIceSugarOptions'] == null && isDrink);

      return ProductModel(
        id: (map['id'] as num?)?.toInt() ?? 0,
        name: map['name']?.toString() ?? key ?? '',
        code: map['code']?.toString() ?? '',
        price: (map['price'] as num?)?.toInt() ?? 0,
        unit: map['unit']?.toString() ?? 'Phần',
        category: cat,
        imageBase64: map['imageBase64']?.toString(),
        imageResourceName: map['imageResourceName']?.toString(),
        isAvailable: map['isAvailable'] ?? true,
        sizes: sizesMap,
        allowedToppings: toppings,
        hasIceSugarOptions: hasIceSugar,
      );
    }
    return ProductModel(name: key ?? '', price: 0, unit: 'Phần', category: 'Khác');
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'code': code,
    'price': price,
    'unit': unit,
    'category': category,
    'imageBase64': imageBase64,
    'imageResourceName': imageResourceName,
    'isAvailable': isAvailable,
    if (sizes.isNotEmpty) 'sizes': sizes,
    if (allowedToppings.isNotEmpty) 'allowedToppings': allowedToppings,
    'hasIceSugarOptions': hasIceSugarOptions,
  };
}

// ==================== CATEGORY & ZONE ====================
class CategoryModel {
  final String name;
  CategoryModel({required this.name});
  factory CategoryModel.fromMap(dynamic val, [String? key]) {
    if (val is Map) {
      return CategoryModel(name: val['name']?.toString() ?? key ?? '');
    } else if (val is String) {
      return CategoryModel(name: val);
    }
    return CategoryModel(name: key ?? '');
  }
  Map<String, dynamic> toMap() => {'name': name};
}

class ZoneModel {
  final String name;
  ZoneModel({required this.name});
  factory ZoneModel.fromMap(Map map) => ZoneModel(name: map['name']?.toString() ?? '');
  Map<String, dynamic> toMap() => {'name': name};
}

// ==================== ORDER ACTION LOG MODEL (LỊCH SỬ THAO TÁC ĐƠN HÀNG) ====================
class OrderActionLogModel {
  final int timestamp;
  final String staffUsername;
  final String staffFullName;
  final String action; // 'ADD_ITEMS', 'CANCEL_ITEM', 'SEND_KITCHEN', 'DISCOUNT', 'PAY_BILL'
  final String details; // VD: "Bạn A nhập món Cà phê (x2), Bánh lăn (x1)"

  OrderActionLogModel({
    required this.timestamp,
    required this.staffUsername,
    required this.staffFullName,
    required this.action,
    required this.details,
  });

  factory OrderActionLogModel.fromMap(Map<dynamic, dynamic> map) {
    return OrderActionLogModel(
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      staffUsername: map['staffUsername']?.toString() ?? '',
      staffFullName: map['staffFullName']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    'action': action,
    'details': details,
  };
}

// ==================== ORDER ITEM MODEL (KIOTVIET FNB) ====================
class OrderItemModel {
  final int productId;
  final String name;
  final int price;
  int quantity;
  String note;
  bool isSentKitchen;
  int discountAmount;

  // Thuộc tính KiotViet FnB (Size, Đường, Đá, Topping)
  String selectedSize;
  int sizeExtraPrice;
  String selectedSugar;
  String selectedIce;
  List<String> selectedToppings;
  int toppingPrice;

  // Người nhận order món này (Phục vụ / Waiter)
  String orderedBy; // username
  String orderedByName; // Họ tên nhân viên nhận order món
  int? orderedAt; // Thời điểm nhận order món

  OrderItemModel({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.note = '',
    this.isSentKitchen = false,
    this.discountAmount = 0,
    this.selectedSize = '',
    this.sizeExtraPrice = 0,
    this.selectedSugar = '',
    this.selectedIce = '',
    this.selectedToppings = const [],
    this.toppingPrice = 0,
    this.orderedBy = '',
    this.orderedByName = '',
    this.orderedAt,
  });

  factory OrderItemModel.fromMap(Map<dynamic, dynamic> map) {
    List<String> toppings = [];
    if (map['selectedToppings'] is List) {
      toppings = List<String>.from(map['selectedToppings']);
    }

    return OrderItemModel(
      productId: (map['productId'] as num?)?.toInt() ?? (map['id'] as num?)?.toInt() ?? 0,
      name: map['name']?.toString() ?? '',
      price: (map['price'] as num?)?.toInt() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      note: map['note']?.toString() ?? '',
      isSentKitchen: map['isSentKitchen'] == true,
      discountAmount: (map['discountAmount'] as num?)?.toInt() ?? 0,
      selectedSize: map['selectedSize']?.toString() ?? '',
      sizeExtraPrice: (map['sizeExtraPrice'] as num?)?.toInt() ?? 0,
      selectedSugar: map['selectedSugar']?.toString() ?? '',
      selectedIce: map['selectedIce']?.toString() ?? '',
      selectedToppings: toppings,
      toppingPrice: (map['toppingPrice'] as num?)?.toInt() ?? 0,
      orderedBy: map['orderedBy']?.toString() ?? '',
      orderedByName: map['orderedByName']?.toString() ?? '',
      orderedAt: (map['orderedAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'name': name,
    'price': price,
    'quantity': quantity,
    'note': note,
    'isSentKitchen': isSentKitchen,
    'discountAmount': discountAmount,
    if (selectedSize.isNotEmpty) 'selectedSize': selectedSize,
    if (sizeExtraPrice > 0) 'sizeExtraPrice': sizeExtraPrice,
    if (selectedSugar.isNotEmpty) 'selectedSugar': selectedSugar,
    if (selectedIce.isNotEmpty) 'selectedIce': selectedIce,
    if (selectedToppings.isNotEmpty) 'selectedToppings': selectedToppings,
    if (toppingPrice > 0) 'toppingPrice': toppingPrice,
    if (orderedBy.isNotEmpty) 'orderedBy': orderedBy,
    if (orderedByName.isNotEmpty) 'orderedByName': orderedByName,
    if (orderedAt != null) 'orderedAt': orderedAt,
  };

  /// Đơn giá một phần bao gồm Size và Toppings
  int get unitPrice => price + sizeExtraPrice + toppingPrice;

  /// Tổng tiền của dòng món
  int get itemTotal => (unitPrice * quantity) - discountAmount;

  /// Mô tả ngắn các thuộc tính (VD: "Size L • 50% Đường • Ít Đá • Trân Châu Trắng")
  String get optionsSummary {
    final List<String> parts = [];
    if (selectedSize.isNotEmpty) parts.add('Size $selectedSize');
    if (selectedSugar.isNotEmpty) parts.add(selectedSugar);
    if (selectedIce.isNotEmpty) parts.add(selectedIce);
    if (selectedToppings.isNotEmpty) parts.addAll(selectedToppings);
    return parts.join(' • ');
  }

  OrderItemModel copyWith({
    int? quantity,
    String? note,
    bool? isSentKitchen,
    int? discountAmount,
    String? selectedSize,
    int? sizeExtraPrice,
    String? selectedSugar,
    String? selectedIce,
    List<String>? selectedToppings,
    int? toppingPrice,
    String? orderedBy,
    String? orderedByName,
    int? orderedAt,
  }) => OrderItemModel(
    productId: productId,
    name: name,
    price: price,
    quantity: quantity ?? this.quantity,
    note: note ?? this.note,
    isSentKitchen: isSentKitchen ?? this.isSentKitchen,
    discountAmount: discountAmount ?? this.discountAmount,
    selectedSize: selectedSize ?? this.selectedSize,
    sizeExtraPrice: sizeExtraPrice ?? this.sizeExtraPrice,
    selectedSugar: selectedSugar ?? this.selectedSugar,
    selectedIce: selectedIce ?? this.selectedIce,
    selectedToppings: selectedToppings ?? this.selectedToppings,
    toppingPrice: toppingPrice ?? this.toppingPrice,
    orderedBy: orderedBy ?? this.orderedBy,
    orderedByName: orderedByName ?? this.orderedByName,
    orderedAt: orderedAt ?? this.orderedAt,
  );
}

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

// ==================== PROMOTION & DISCOUNT MODELS ====================
enum PromotionType {
  percentBill, // Giảm % trên tổng hóa đơn
  fixedBill,   // Giảm số tiền cố định (VND) trên hóa đơn
  percentItem, // Giảm % trên món nhất định
  fixedItem,   // Giảm tiền cố định trên món
  voucherCode, // Nhập code giảm giá
}

class PromotionModel {
  final String id;
  final String code; // Mã voucher (nếu có)
  final String name;
  final String description;
  final String type; // PERCENT_BILL, FIXED_BILL, PERCENT_ITEM, FIXED_ITEM, VOUCHER
  final int value;   // % hoặc số tiền VND
  final int maxDiscountAmount; // Giới hạn tiền giảm tối đa (nếu tính theo %)
  final int minBillAmount;     // Hóa đơn tối thiểu để áp dụng
  final String? targetCategory; // Áp dụng cho danh mục nào
  final int? targetProductId;   // Áp dụng cho món nào
  final int startDate;
  final int endDate;
  final bool isActive;
  final int usageCount;
  final int maxUsage; // Giới hạn số lần dùng toàn hệ thống

  PromotionModel({
    required this.id,
    this.code = '',
    required this.name,
    this.description = '',
    required this.type,
    required this.value,
    this.maxDiscountAmount = 0,
    this.minBillAmount = 0,
    this.targetCategory,
    this.targetProductId,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
    this.usageCount = 0,
    this.maxUsage = 0,
  });

  factory PromotionModel.fromMap(Map<dynamic, dynamic> map, String id) {
    return PromotionModel(
      id: id,
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      type: map['type']?.toString() ?? 'PERCENT_BILL',
      value: (map['value'] as num?)?.toInt() ?? 0,
      maxDiscountAmount: (map['maxDiscountAmount'] as num?)?.toInt() ?? 0,
      minBillAmount: (map['minBillAmount'] as num?)?.toInt() ?? 0,
      targetCategory: map['targetCategory']?.toString(),
      targetProductId: (map['targetProductId'] as num?)?.toInt(),
      startDate: (map['startDate'] as num?)?.toInt() ?? 0,
      endDate: (map['endDate'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] ?? true,
      usageCount: (map['usageCount'] as num?)?.toInt() ?? 0,
      maxUsage: (map['maxUsage'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'description': description,
    'type': type,
    'value': value,
    'maxDiscountAmount': maxDiscountAmount,
    'minBillAmount': minBillAmount,
    if (targetCategory != null) 'targetCategory': targetCategory,
    if (targetProductId != null) 'targetProductId': targetProductId,
    'startDate': startDate,
    'endDate': endDate,
    'isActive': isActive,
    'usageCount': usageCount,
    'maxUsage': maxUsage,
  };

  PromotionModel copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? type,
    int? value,
    int? maxDiscountAmount,
    int? minBillAmount,
    String? targetCategory,
    int? targetProductId,
    int? startDate,
    int? endDate,
    bool? isActive,
    int? usageCount,
    int? maxUsage,
  }) {
    return PromotionModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      value: value ?? this.value,
      maxDiscountAmount: maxDiscountAmount ?? this.maxDiscountAmount,
      minBillAmount: minBillAmount ?? this.minBillAmount,
      targetCategory: targetCategory ?? this.targetCategory,
      targetProductId: targetProductId ?? this.targetProductId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      usageCount: usageCount ?? this.usageCount,
      maxUsage: maxUsage ?? this.maxUsage,
    );
  }

  /// Kiểm tra khuyến mãi có đang còn hiệu lực hay không
  bool isValid(int subTotal) {
    if (!isActive) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (startDate > 0 && now < startDate) return false;
    if (endDate > 0 && now > endDate) return false;
    if (maxUsage > 0 && usageCount >= maxUsage) return false;
    if (minBillAmount > 0 && subTotal < minBillAmount) return false;
    return true;
  }

  /// Tính số tiền giảm giá thực tế cho hóa đơn
  int calculateDiscount(int subTotal, List<OrderItemModel> items) {
    if (!isValid(subTotal)) return 0;

    switch (type) {
      case 'PERCENT_BILL':
      case 'VOUCHER':
        int discount = (subTotal * value / 100).round();
        if (maxDiscountAmount > 0 && discount > maxDiscountAmount) {
          discount = maxDiscountAmount;
        }
        return discount;

      case 'FIXED_BILL':
        return value > subTotal ? subTotal : value;

      case 'PERCENT_ITEM':
        int targetSubtotal = 0;
        for (final item in items) {
          if (targetProductId != null && item.productId == targetProductId) {
            targetSubtotal += item.price * item.quantity;
          }
        }
        int discount = (targetSubtotal * value / 100).round();
        if (maxDiscountAmount > 0 && discount > maxDiscountAmount) {
          discount = maxDiscountAmount;
        }
        return discount;

      case 'FIXED_ITEM':
        int count = 0;
        for (final item in items) {
          if (targetProductId != null && item.productId == targetProductId) {
            count += item.quantity;
          }
        }
        return count * value;

      default:
        return 0;
    }
  }

  String get typeDisplay {
    switch (type) {
      case 'PERCENT_BILL': return 'Giảm % hóa đơn';
      case 'FIXED_BILL': return 'Giảm tiền mặt hóa đơn';
      case 'PERCENT_ITEM': return 'Giảm % theo món';
      case 'FIXED_ITEM': return 'Giảm tiền theo món';
      case 'VOUCHER': return 'Mã voucher';
      default: return type;
    }
  }
}

class BillDiscountModel {
  final String? promoId;
  final String? promoCode;
  final String description;
  final int amount;

  BillDiscountModel({
    this.promoId,
    this.promoCode,
    required this.description,
    required this.amount,
  });

  factory BillDiscountModel.fromMap(Map<dynamic, dynamic> map) {
    return BillDiscountModel(
      promoId: map['promoId']?.toString(),
      promoCode: map['promoCode']?.toString(),
      description: map['description']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    if (promoId != null) 'promoId': promoId,
    if (promoCode != null) 'promoCode': promoCode,
    'description': description,
    'amount': amount,
  };
}

// ==================== BILL MODEL ====================
class BillModel {
  final String id;
  final String billCode; // Mã hóa đơn chính thức (HD-yyMMdd-HHmmss)
  final String? orderCode; // Mã đặt món / gọi món kiểm soát (OD-yyMMdd-HHmmss)
  final String tableName;
  final String zone;
  final int createdAt;
  int? closedAt;
  String status; // 'OPEN', 'PAID', 'CANCELLED', 'REFUNDED'
  final String staffUsername;
  final String staffFullName;
  List<OrderItemModel> items;
  int subTotal;
  List<BillDiscountModel> discounts;
  int totalDiscount;
  double vatRate;
  int vatAmount;
  int finalAmount;
  String paymentMethod; // 'CASH', 'TRANSFER_QR', 'CARD'
  String notes;
  final String? parentBillId; // If split
  final List<String>? mergedTableNames;
  int pointsUsed;
  int pointsDiscount;
  String? customerId;
  String? customerName;
  String? customerPhone;
  String? shiftId;
  List<OrderActionLogModel> actionLogs;

  BillModel({
    required this.id,
    required this.billCode,
    this.orderCode,
    required this.tableName,
    required this.zone,
    required this.createdAt,
    this.closedAt,
    this.status = 'OPEN',
    required this.staffUsername,
    required this.staffFullName,
    required this.items,
    required this.subTotal,
    this.discounts = const [],
    this.totalDiscount = 0,
    this.vatRate = 0.0,
    this.vatAmount = 0,
    required this.finalAmount,
    this.paymentMethod = 'CASH',
    this.notes = '',
    this.parentBillId,
    this.mergedTableNames,
    this.pointsUsed = 0,
    this.pointsDiscount = 0,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.shiftId,
    this.actionLogs = const [],
  });

  factory BillModel.fromMap(Map<dynamic, dynamic> map, String id) {
    List<OrderItemModel> items = [];
    if (map['items'] != null) {
      if (map['items'] is List) {
        items = (map['items'] as List).map((e) => OrderItemModel.fromMap(e)).toList();
      } else if (map['items'] is String) {
        try {
          final List list = jsonDecode(map['items']);
          items = list.map((e) => OrderItemModel.fromMap(e)).toList();
        } catch (_) {}
      }
    }

    List<BillDiscountModel> discounts = [];
    if (map['discounts'] != null) {
      if (map['discounts'] is List) {
        discounts = (map['discounts'] as List).map((e) => BillDiscountModel.fromMap(e)).toList();
      }
    }

    List<String>? merged;
    if (map['mergedTableNames'] != null && map['mergedTableNames'] is List) {
      merged = List<String>.from(map['mergedTableNames']);
    }

    List<OrderActionLogModel> actionLogs = [];
    if (map['actionLogs'] != null && map['actionLogs'] is List) {
      actionLogs = (map['actionLogs'] as List).map((e) => OrderActionLogModel.fromMap(e)).toList();
    } else if (map['actionLogsJson'] != null && map['actionLogsJson'] is String && (map['actionLogsJson'] as String).isNotEmpty) {
      try {
        final List list = jsonDecode(map['actionLogsJson']);
        actionLogs = list.map((e) => OrderActionLogModel.fromMap(e)).toList();
      } catch (_) {}
    }

    final rawBillCode = map['billCode']?.toString();
    final rawOrderCode = map['orderCode']?.toString();

    String billCode;
    String? orderCode = rawOrderCode;

    if (rawBillCode != null && rawBillCode.isNotEmpty && !rawBillCode.startsWith('OD-')) {
      billCode = rawBillCode;
    } else if (rawOrderCode != null && rawOrderCode.startsWith('HD-')) {
      billCode = rawOrderCode;
    } else if (rawBillCode != null && rawBillCode.isNotEmpty) {
      billCode = rawBillCode;
    } else {
      billCode = rawOrderCode ?? id;
    }

    if (orderCode == null && rawBillCode != null && rawBillCode.startsWith('OD-')) {
      orderCode = rawBillCode;
    }

    return BillModel(
      id: id,
      billCode: billCode,
      orderCode: orderCode,
      tableName: map['tableName']?.toString() ?? '',
      zone: map['zone']?.toString() ?? '',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      closedAt: (map['closedAt'] as num?)?.toInt(),
      status: map['status']?.toString() ?? 'OPEN',
      staffUsername: map['staffUsername']?.toString() ?? '',
      staffFullName: map['staffFullName']?.toString() ?? '',
      items: items,
      subTotal: (map['subTotal'] as num?)?.toInt() ?? (map['totalAmount'] as num?)?.toInt() ?? 0,
      discounts: discounts,
      totalDiscount: (map['totalDiscount'] as num?)?.toInt() ?? (map['discountAmount'] as num?)?.toInt() ?? 0,
      vatRate: (map['vatRate'] as num?)?.toDouble() ?? 0.0,
      vatAmount: (map['vatAmount'] as num?)?.toInt() ?? 0,
      finalAmount: (map['finalAmount'] as num?)?.toInt() ?? (map['totalAmount'] as num?)?.toInt() ?? 0,
      paymentMethod: map['paymentMethod']?.toString() ?? 'CASH',
      notes: map['notes']?.toString() ?? map['note']?.toString() ?? '',
      parentBillId: map['parentBillId']?.toString(),
      mergedTableNames: merged,
      pointsUsed: (map['pointsUsed'] as num?)?.toInt() ?? 0,
      pointsDiscount: (map['pointsDiscount'] as num?)?.toInt() ?? 0,
      customerId: map['customerId']?.toString(),
      customerName: map['customerName']?.toString(),
      customerPhone: map['customerPhone']?.toString(),
      shiftId: map['shiftId']?.toString(),
      actionLogs: actionLogs,
    );
  }

  String get note => notes;

  /// Danh sách nhân viên đã nhận order các món trong đơn
  String get orderStaffSummary {
    final staffNames = <String>{};
    for (final it in items) {
      if (it.orderedByName.isNotEmpty) {
        staffNames.add(it.orderedByName);
      }
    }
    if (staffNames.isNotEmpty) return staffNames.join(', ');
    return staffFullName.isNotEmpty ? staffFullName : staffUsername;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'billCode': billCode,
    if (orderCode != null) 'orderCode': orderCode,
    'tableName': tableName,
    'zone': zone,
    'createdAt': createdAt,
    if (closedAt != null) 'closedAt': closedAt,
    'status': status,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    'cashierName': staffFullName.isNotEmpty ? staffFullName : staffUsername,
    'orderStaff': orderStaffSummary,
    'items': items.map((e) => e.toMap()).toList(),
    'subTotal': subTotal,
    'discounts': discounts.map((e) => e.toMap()).toList(),
    'totalDiscount': totalDiscount,
    'vatRate': vatRate,
    'vatAmount': vatAmount,
    'finalAmount': finalAmount,
    'paymentMethod': paymentMethod,
    'notes': notes,
    'note': notes,
    if (parentBillId != null) 'parentBillId': parentBillId,
    if (mergedTableNames != null) 'mergedTableNames': mergedTableNames,
    if (pointsUsed > 0) 'pointsUsed': pointsUsed,
    if (pointsDiscount > 0) 'pointsDiscount': pointsDiscount,
    if (customerId != null) 'customerId': customerId,
    if (customerName != null) 'customerName': customerName,
    if (customerPhone != null) 'customerPhone': customerPhone,
    if (shiftId != null) 'shiftId': shiftId,
    'actionLogs': actionLogs.map((e) => e.toMap()).toList(),
    'actionLogsJson': jsonEncode(actionLogs.map((e) => e.toMap()).toList()),
  };

  void recalculateTotals() {
    subTotal = items.fold(0, (s, i) => s + i.itemTotal);
    totalDiscount = discounts.fold(0, (s, d) => s + d.amount) + pointsDiscount;
    if (totalDiscount > subTotal) totalDiscount = subTotal;
    final afterDiscount = subTotal - totalDiscount;
    vatAmount = (afterDiscount * (vatRate / 100)).round();
    finalAmount = afterDiscount + vatAmount;
  }
}

// ==================== CASH SHIFT MODEL (KIOTVIET KÉT TIỀN CA) ====================
class CashShiftModel {
  final String id;
  final String shiftCode;
  String shiftName;
  final String storeCode;
  final String staffUsername;
  final String staffFullName;
  final int openedAt;
  int? closedAt;
  final int initialCash; // Tiền mặt đầu ca
  int totalCashSales; // Doanh số tiền mặt
  int totalQrSales;   // Doanh số chuyển khoản VietQR
  int totalCardSales; // Doanh số thẻ / ví
  int cashIn;         // Tiền mặt nộp thêm vào két
  int cashOut;        // Tiền mặt chi vặt trong ca
  int? actualCash;    // Tiền mặt kiểm đếm thực tế khi chốt két
  int? difference;    // Chênh lệch thừa / thiếu
  String status;      // 'OPEN', 'CLOSED'
  String notes;

  CashShiftModel({
    required this.id,
    String? shiftCode,
    this.shiftName = '',
    required this.storeCode,
    required this.staffUsername,
    required this.staffFullName,
    required this.openedAt,
    this.closedAt,
    int? initialCash,
    int? initialBalance,
    int totalCashSales = 0,
    int? cashSales,
    int totalQrSales = 0,
    int? qrSales,
    int totalCardSales = 0,
    int? cardSales,
    int cashIn = 0,
    int? inAdjustments,
    int cashOut = 0,
    int? outAdjustments,
    int? actualCash,
    int? actualBalance,
    this.difference,
    this.status = 'OPEN',
    this.notes = '',
    int? totalBills,
  }) : shiftCode = shiftCode ?? id,
       initialCash = initialBalance ?? initialCash ?? 0,
       totalCashSales = cashSales ?? totalCashSales,
       totalQrSales = qrSales ?? totalQrSales,
       totalCardSales = cardSales ?? totalCardSales,
       cashIn = inAdjustments ?? cashIn,
       cashOut = outAdjustments ?? cashOut,
       actualCash = actualBalance ?? actualCash;

  factory CashShiftModel.fromMap(Map<dynamic, dynamic> map, String id) {
    return CashShiftModel(
      id: id,
      shiftCode: map['shiftCode']?.toString() ?? id,
      shiftName: map['shiftName']?.toString() ?? '',
      storeCode: map['storeCode']?.toString() ?? '',
      staffUsername: map['staffUsername']?.toString() ?? '',
      staffFullName: map['staffFullName']?.toString() ?? '',
      openedAt: (map['openedAt'] as num?)?.toInt() ?? 0,
      closedAt: (map['closedAt'] as num?)?.toInt(),
      initialCash: (map['initialCash'] as num?)?.toInt() ?? 0,
      totalCashSales: (map['totalCashSales'] as num?)?.toInt() ?? 0,
      totalQrSales: (map['totalQrSales'] as num?)?.toInt() ?? 0,
      totalCardSales: (map['totalCardSales'] as num?)?.toInt() ?? 0,
      cashIn: (map['cashIn'] as num?)?.toInt() ?? 0,
      cashOut: (map['cashOut'] as num?)?.toInt() ?? 0,
      actualCash: (map['actualCash'] as num?)?.toInt(),
      difference: (map['difference'] as num?)?.toInt(),
      status: map['status']?.toString() ?? (map['closedAt'] != null ? 'CLOSED' : 'OPEN'),
      notes: map['notes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'shiftCode': shiftCode,
    'shiftName': shiftName,
    'storeCode': storeCode,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    'openedAt': openedAt,
    if (closedAt != null) 'closedAt': closedAt,
    'initialCash': initialCash,
    'totalCashSales': totalCashSales,
    'totalQrSales': totalQrSales,
    'totalCardSales': totalCardSales,
    'cashIn': cashIn,
    'cashOut': cashOut,
    if (actualCash != null) 'actualCash': actualCash,
    if (difference != null) 'difference': difference,
    'status': status,
    'notes': notes,
  };

  /// Tiền mặt kỳ vọng trên hệ thống = Đầu ca + Tiền mặt bán + Nộp thêm - Chi vặt
  int get expectedCash => initialCash + totalCashSales + cashIn - cashOut;

  /// Tổng doanh thu tất cả phương thức trong ca
  int get totalRevenue => totalCashSales + totalQrSales + totalCardSales;

  bool get isOpen => (status.toUpperCase().trim() == 'OPEN') && closedAt == null && openedAt > 0;

  // Convenience getters
  int get initialBalance => initialCash;
  int get cashSales => totalCashSales;
  int get qrSales => totalQrSales;
  int get cardSales => totalCardSales;
  int get inAdjustments => cashIn;
  int get outAdjustments => cashOut;
  int get actualBalance => actualCash ?? 0;
  int get calculatedBalance => expectedCash;
  int get variance => (actualCash != null) ? (actualCash! - expectedCash) : 0;
  int get totalSales => totalRevenue;
}

// ==================== KIOTVIET CUSTOMER LOYALTY MODEL ====================
class KmtCustomerModel {
  final String id;
  final String code; // Mã khách hàng KiotViet (KH000001...)
  final String name;
  final String phone;
  final String gender;
  final String birthday;
  int currentPoints; // Điểm tích lũy hiện tại
  int totalPoints;   // Tổng điểm lịch sử
  final int? createdAt;

  KmtCustomerModel({
    required this.id,
    this.code = '',
    String? name,
    String? fullName,
    required this.phone,
    this.gender = 'Khác',
    this.birthday = '',
    this.currentPoints = 0,
    this.totalPoints = 0,
    this.createdAt,
  }) : name = fullName ?? name ?? '';

  String get fullName => name;
  String get groupName => currentPoints >= 500 ? 'VIP' : (currentPoints >= 100 ? 'Thân thiết' : 'Thành viên');

  factory KmtCustomerModel.fromMap(Map<dynamic, dynamic> map, String id) {
    return KmtCustomerModel(
      id: id,
      code: map['code']?.toString() ?? map['maKhachHang']?.toString() ?? '',
      name: map['name']?.toString() ?? map['tenKhachHang']?.toString() ?? '',
      phone: map['phone']?.toString() ?? map['dienThoai']?.toString() ?? '',
      gender: map['gender']?.toString() ?? map['gioiTinh']?.toString() ?? 'Khác',
      birthday: map['birthday']?.toString() ?? map['ngaySinh']?.toString() ?? '',
      currentPoints: (map['currentPoints'] as num?)?.toInt() ?? (map['diemHienTai'] as num?)?.toInt() ?? 0,
      totalPoints: (map['totalPoints'] as num?)?.toInt() ?? (map['tongDiem'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'phone': phone,
    'gender': gender,
    'birthday': birthday,
    'currentPoints': currentPoints,
    'totalPoints': totalPoints,
  };

  /// Hạng thành viên KiotViet dựa trên tổng điểm tích lũy
  String get memberTier {
    if (totalPoints >= 1000) return 'Kim Cương';
    if (totalPoints >= 500) return 'Vàng';
    if (totalPoints >= 200) return 'Bạc';
    return 'Thành Viên';
  }
}

// ==================== AUDIT LOG MODEL ====================
class AuditLogModel {
  final String? logId;
  final int timestamp;
  final String username;
  final String userFullName;
  final String userRole;
  final String action;
  final String targetType; // 'BILL', 'ITEM', 'PROMOTION', 'USER', 'TABLE', 'AUTH', 'SETTING'
  final String targetId;
  final String details;
  final Map<String, dynamic>? beforeState;
  final Map<String, dynamic>? afterState;
  final bool isSuspicious;
  final String? storeCode;

  AuditLogModel({
    this.logId,
    required this.timestamp,
    required this.username,
    required this.userFullName,
    required this.userRole,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.details,
    this.beforeState,
    this.afterState,
    this.isSuspicious = false,
    this.storeCode,
  });

  factory AuditLogModel.fromMap(Map<dynamic, dynamic> map, {String? logId}) {
    Map<String, dynamic>? before;
    if (map['beforeState'] != null && map['beforeState'] is Map) {
      before = Map<String, dynamic>.from(map['beforeState']);
    }
    Map<String, dynamic>? after;
    if (map['afterState'] != null && map['afterState'] is Map) {
      after = Map<String, dynamic>.from(map['afterState']);
    }

    return AuditLogModel(
      logId: logId ?? map['logId']?.toString(),
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      username: map['username']?.toString() ?? '',
      userFullName: map['userFullName']?.toString() ?? '',
      userRole: map['userRole']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      targetType: map['targetType']?.toString() ?? '',
      targetId: map['targetId']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
      beforeState: before,
      afterState: after,
      isSuspicious: map['isSuspicious'] == true,
      storeCode: map['storeCode']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp,
    'username': username,
    'userFullName': userFullName,
    'userRole': userRole,
    'action': action,
    'targetType': targetType,
    'targetId': targetId,
    'details': details,
    if (beforeState != null) 'beforeState': beforeState,
    if (afterState != null) 'afterState': afterState,
    'isSuspicious': isSuspicious,
    if (storeCode != null) 'storeCode': storeCode,
  };

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}

// ==================== KITCHEN ORDER & ONLINE ORDER ====================
class KitchenOrderModel {
  final String? firebaseKey;
  final String tableName;
  final String? orderCode; // Mã đặt món (OD-...)
  final String? billCode; // Mã hóa đơn (HD-...)
  final String itemsJson;
  final int timestamp;
  bool isDone;
  final String? note;

  KitchenOrderModel({
    this.firebaseKey,
    required this.tableName,
    this.orderCode,
    this.billCode,
    required this.itemsJson,
    required this.timestamp,
    this.isDone = false,
    this.note,
  });

  factory KitchenOrderModel.fromMap(Map<dynamic, dynamic> map, {String? key}) {
    return KitchenOrderModel(
      firebaseKey: key,
      tableName: map['tableName']?.toString() ?? '',
      orderCode: map['orderCode']?.toString(),
      billCode: map['billCode']?.toString(),
      itemsJson: map['itemsJson']?.toString() ?? '[]',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      isDone: map['isDone'] == true,
      note: map['note']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'tableName': tableName,
    if (orderCode != null) 'orderCode': orderCode,
    if (billCode != null) 'billCode': billCode,
    'itemsJson': itemsJson,
    'timestamp': timestamp,
    'isDone': isDone,
    if (note != null) 'note': note,
  };

  List<OrderItemModel> get items {
    try {
      final List list = jsonDecode(itemsJson);
      return list.map((e) => OrderItemModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
  Duration get waitingTime => DateTime.now().difference(dateTime);
}

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

  List<OrderItemModel> get items {
    if (itemsJson.isEmpty || type == 'CALL_WAITER') return [];
    try {
      final List list = jsonDecode(itemsJson);
      return list.map((e) => OrderItemModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  bool get isPending => status == 'PENDING';
  bool get isCallWaiter => type == 'CALL_WAITER';
}

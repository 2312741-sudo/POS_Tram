// test/fnb_system_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/permissions/app_permissions.dart';
import 'package:tram_flutter/core/printer/receipt_printer.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/data/services/firebase_service.dart';

void main() {
  group('Trạm F&B System Core Logic Tests', () {
    test('Permission Matrix & RBAC Logic', () {
      final roleCashier = RoleModel(
        id: 'ROLE_CASHIER',
        name: 'Thu Ngân',
        permissions: [AppPermissions.createBill, AppPermissions.printBill],
      );

      final roleWaiter = RoleModel(
        id: 'ROLE_WAITER',
        name: 'Phục Vụ',
        permissions: [AppPermissions.openTable, AppPermissions.sendKitchen],
      );

      final roles = [roleCashier, roleWaiter];

      // 1. Root Owner always has all permissions
      final owner = UserModel(
        username: 'admin',
        fullName: 'Chủ Quán',
        password: '123',
        roleId: 'ROLE_OWNER',
        isRootOwner: true,
      );
      expect(owner.can(AppPermissions.manageUsers, roles), isTrue);
      expect(owner.can(AppPermissions.cancelKitchenItem, roles), isTrue);

      // 2. Regular Cashier has createBill and printBill, but NOT cancelBill
      final cashier = UserModel(
        username: 'thungan1',
        fullName: 'Nguyễn Thu Ngân',
        password: '123',
        roleId: 'ROLE_CASHIER',
      );
      expect(cashier.can(AppPermissions.createBill, roles), isTrue);
      expect(cashier.can(AppPermissions.cancelBill, roles), isFalse);

      // 3. Custom Individual Override: Cashier given manualDiscount specifically
      final cashierOverride = UserModel(
        username: 'thungan2',
        fullName: 'Trần Trưởng Ca',
        password: '123',
        roleId: 'ROLE_CASHIER',
        customPermissions: [AppPermissions.manualDiscount, AppPermissions.cancelBill],
      );
      expect(cashierOverride.can(AppPermissions.manualDiscount, roles), isTrue);
      expect(cashierOverride.can(AppPermissions.cancelBill, roles), isTrue);
      expect(cashierOverride.can(AppPermissions.manageUsers, roles), isFalse);
    });

    test('Promotions Calculation Engine', () {
      final items = [
        OrderItemModel(productId: 1, name: 'Trà chanh giã tay', price: 25000, quantity: 2),
        OrderItemModel(productId: 2, name: 'Bánh waffle', price: 50000, quantity: 1),
      ];
      const subTotal = 100000; // 25k*2 + 50k = 100,000đ

      // 1. Percentage promo: 20% with max 15,000đ
      final promoPercent = PromotionModel(
        id: 'P1',
        code: 'SALE20',
        name: 'Giảm 20%',
        type: 'PERCENT_BILL',
        value: 20,
        maxDiscountAmount: 15000,
        startDate: 0,
        endDate: 0,
      );
      // 20% of 100k is 20k, capped at 15k
      expect(promoPercent.calculateDiscount(subTotal, items), equals(15000));

      // 2. Fixed promo: 10,000đ
      final promoFixed = PromotionModel(
        id: 'P2',
        code: 'GIAM10K',
        name: 'Giảm 10k',
        type: 'FIXED_BILL',
        value: 10000,
        startDate: 0,
        endDate: 0,
      );
      expect(promoFixed.calculateDiscount(subTotal, items), equals(10000));
    });

    test('Bill Totals, Multi-Discounts & VAT Calculation', () {
      final items = [
        OrderItemModel(productId: 1, name: 'Trà sữa matcha', price: 40000, quantity: 2), // 80,000đ
        OrderItemModel(productId: 2, name: 'Bánh flan', price: 20000, quantity: 1),       // 20,000đ
      ];

      final discounts = [
        BillDiscountModel(promoCode: 'KM1', description: 'Giảm 10k', amount: 10000),
        BillDiscountModel(promoCode: 'KM2', description: 'Giảm 5k', amount: 5000),
      ];

      final bill = BillModel(
        id: 'B1',
        billCode: 'HD001',
        tableName: 'Bàn 01',
        zone: 'Tầng 1',
        createdAt: 1771900000000,
        staffUsername: 'thungan',
        staffFullName: 'Nguyễn Thu Ngân',
        items: items,
        subTotal: 100000,
        discounts: discounts,
        totalDiscount: 15000,
        vatRate: 8.0, // 8% VAT
        vatAmount: 0,
        finalAmount: 0,
      );

      bill.recalculateTotals();

      expect(bill.subTotal, equals(100000));
      expect(bill.totalDiscount, equals(15000));
      // after discount = 85,000. 8% of 85,000 = 6,800. Final = 91,800.
      expect(bill.vatAmount, equals(6800));
      expect(bill.finalAmount, equals(91800));
    });

    test('Receipt ESC/POS Bytes Generator', () {
      final store = StoreInfoModel(
        storeCode: 'TRAM01',
        storeName: 'Trạm Chanh Quán',
        address: '123 Phù Đổng Thiên Vương',
        phone: '0987654321',
        wifiName: 'TramChanh_Free',
      );

      final bill = BillModel(
        id: 'B1',
        billCode: 'HD-20260824-0001',
        tableName: 'Bàn 02',
        zone: 'Tầng 1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        staffUsername: 'thungan1',
        staffFullName: 'Nguyễn Thu Ngân',
        items: [
          OrderItemModel(productId: 1, name: 'Trà chanh giã tay', price: 25000, quantity: 2),
        ],
        subTotal: 50000,
        finalAmount: 50000,
      );

      final bytes = ReceiptPrinter.buildBillReceiptBytes(store: store, bill: bill);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(50));
    });

    test('UserRole.fromString Parser Resilience', () {
      expect(UserRole.fromString('owner'), equals(UserRole.owner));
      expect(UserRole.fromString('ROLE_OWNER'), equals(UserRole.owner));
      expect(UserRole.fromString('Chủ_Cửa_Hàng'), equals(UserRole.owner));
      expect(UserRole.fromString('admin'), equals(UserRole.owner));

      expect(UserRole.fromString('manager_1'), equals(UserRole.manager1));
      expect(UserRole.fromString('QL1'), equals(UserRole.manager1));
      expect(UserRole.fromString('quan_ly_1'), equals(UserRole.manager1));

      expect(UserRole.fromString('manager_2'), equals(UserRole.manager2));
      expect(UserRole.fromString('ql2'), equals(UserRole.manager2));

      expect(UserRole.fromString('staff'), equals(UserRole.employee));
      expect(UserRole.fromString('nhan_vien'), equals(UserRole.employee));
      expect(UserRole.fromString(''), equals(UserRole.employee));
      expect(UserRole.fromString(null), equals(UserRole.employee));
    });

    test('Owner Sovereign Rule', () {
      // Even if roleId is employee or empty, if uid == store.ownerId, it must be root owner
      final store = StoreInfoModel(
        storeCode: 'TRAM_01',
        storeName: 'Trạm Cafe',
        ownerId: 'UID_ROOT_OWNER_123',
      );

      final userWithOwnerUid = UserModel(
        username: 'tam_owner',
        fullName: 'Nguyễn Thành Tâm',
        password: '123',
        uid: 'UID_ROOT_OWNER_123',
        roleId: 'employee', // Marked as employee in database
      );

      expect(userWithOwnerUid.isStoreOwner(store.ownerId), isTrue);
      expect(userWithOwnerUid.can(AppPermissions.manageRolesPermissions, [], store.ownerId), isTrue);
      expect(userWithOwnerUid.can(AppPermissions.adjustCashShift, [], store.ownerId), isTrue);
    });

    test('CashShiftModel Accounting Calculation', () {
      final shift = CashShiftModel(
        id: 'SHIFT_01',
        storeCode: 'TRAM_01',
        shiftName: 'Ca Sáng',
        staffUsername: 'thungan1',
        staffFullName: 'Nguyễn Thu Ngân',
        openedAt: 1771900000000,
        initialBalance: 500000, // 500k tiền đầu ca
        cashSales: 1200000,     // 1.2M doanh thu tiền mặt
        qrSales: 800000,        // 800k VietQR
        cardSales: 200000,      // 200k quẹt thẻ
        totalBills: 15,
        inAdjustments: 100000,  // Nạp thêm 100k tiền lẻ
        outAdjustments: 50000,  // Chi 50k mua đá
        actualBalance: 1750000, // Đếm thực tế lúc kết ca
      );

      // calculatedBalance = 500,000 + 1,200,000 + 100,000 - 50,000 = 1,750,000đ
      expect(shift.calculatedBalance, equals(1750000));
      // variance = 1,750,000 - 1,750,000 = 0 (khớp két)
      expect(shift.variance, equals(0));
      // totalSales = 1.2M + 800k + 200k = 2.2M
      expect(shift.totalSales, equals(2200000));
    });

    test('OrderItemModel KiotViet Sizes & Toppings Total', () {
      final item = OrderItemModel(
        productId: 101,
        name: 'Trà Sữa Olong',
        price: 35000, // Giá gốc
        selectedSize: 'L',
        sizeExtraPrice: 10000, // Size L +10k
        selectedSugar: '70% đường',
        selectedIce: '50% đá',
        selectedToppings: ['Trân châu đen', 'Kem Cheese'],
        toppingPrice: 10000, // 2 topping +10k
        quantity: 3,
      );

      // unitPrice = 35k + 10k + 10k = 55k
      expect(item.unitPrice, equals(55000));
      // itemTotal = 55k * 3 = 165k
      expect(item.itemTotal, equals(165000));
    });

    test('Excel Export Filename Sanitization', () {
      final sanitized = FirebaseService.sanitizeFileName('Trạm Cà Phê & Trà Sữa #01!');
      expect(sanitized, equals('Tram_Ca_Phe_Tra_Sua_01'));
    });

    test('TableModel Guest Count, OpenedAt & Order Serialization', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final table = TableModel(
        name: 'A2',
        zone: 'Khu A',
        inUse: true,
        openedAt: now,
        guestCount: 3,
        currentOrderJson: jsonEncode([
          {'productId': 22, 'name': 'Bánh lăn choco chip', 'price': 15000, 'quantity': 2, 'isSentKitchen': true}
        ]),
      );

      final map = table.toMap();
      expect(map['guestCount'], equals(3));
      expect(map['openedAt'], equals(now));
      expect(map['inUse'], isTrue);

      final parsed = TableModel.fromMap(map);
      expect(parsed.guestCount, equals(3));
      expect(parsed.openedAt, equals(now));
      expect(parsed.currentItems.length, equals(1));
      expect(parsed.currentItems.first.quantity, equals(2));
      expect(parsed.currentTotal, equals(30000));
    });

    test('TableModel.fromMap handles ISO 8601 string openedAt, key recovery & Web Admin parity', () {
      // Simulating Firebase RTDB payload where openedAt is an ISO string (from Web)
      final webMap = {
        'inUse': true,
        'openedAt': '2026-09-30T02:15:00.000Z',
        'guestCount': '4',
        'capacity': '6',
        'currentOrderJson': '',
      };

      final parsed = TableModel.fromMap(webMap, 'Khu A_A2');
      expect(parsed.name, equals('A2'));
      expect(parsed.zone, equals('Khu A'));
      expect(parsed.inUse, isTrue);
      expect(parsed.guestCount, equals(4));
      expect(parsed.capacity, equals(6));
      expect(parsed.openedAt, equals(DateTime.parse('2026-09-30T02:15:00.000Z').millisecondsSinceEpoch));

      // Parity check: defaultTables has exactly 21 tables matching 5 zones
      final fb = FirebaseService();
      expect(fb.defaultTables.length, equals(21));
      expect(fb.defaultZones.length, equals(5));
      expect(fb.defaultZones.map((z) => z.name).toList(), containsAll(['Khu A', 'Khu B', 'Khu C', 'Khu D', 'Mang về']));
    });

    test('CashShiftModel status parser & open ca sales accumulation', () {
      final shift = CashShiftModel(
        id: 'SHIFT_123',
        shiftCode: 'CA-260930-1200',
        storeCode: 'TRAM01',
        staffUsername: 'thungan',
        staffFullName: 'Thu Ngân',
        openedAt: DateTime.now().millisecondsSinceEpoch,
        initialCash: 1000000,
        status: 'OPEN',
      );

      expect(shift.isOpen, isTrue);
      expect(shift.expectedCash, equals(1000000));

      // Simulate cash sale
      shift.totalCashSales += 150000;
      expect(shift.expectedCash, equals(1150000));
      expect(shift.totalRevenue, equals(150000));

      // Simulate QR sale
      shift.totalQrSales += 200000;
      expect(shift.expectedCash, equals(1150000)); // QR does not increase physical cash
      expect(shift.totalRevenue, equals(350000));

      // From map parsing with various case inputs
      final fromMapValid = CashShiftModel.fromMap({'status': 'OPEN', 'openedAt': DateTime.now().millisecondsSinceEpoch, 'initialCash': 500000}, 'SHIFT_456');
      expect(fromMapValid.isOpen, isTrue);

      // Ghost shift with openedAt == 0 must NEVER be open
      final ghostShift = CashShiftModel.fromMap({'status': 'OPEN', 'openedAt': 0, 'initialCash': 0}, 'TRAM02');
      expect(ghostShift.isOpen, isFalse);
    });

    test('Table guest count editing and order cart items flow', () {
      final table = TableModel(name: 'B1', zone: 'Khu B', inUse: false);
      expect(table.inUse, isFalse);
      expect(table.guestCount, isNull);

      // 1. Tapping empty table initializes defaults without prompt
      table.openedAt = DateTime.now().millisecondsSinceEpoch;
      table.guestCount = 2;
      expect(table.guestCount, equals(2));

      // 2. Staff edits guest count in order cart
      table.guestCount = 5;
      expect(table.guestCount, equals(5));

      // 3. Adding items marks table inUse
      final item1 = OrderItemModel(productId: 1, name: 'Trà Chanh', price: 20000, quantity: 2);
      table.currentOrderJson = jsonEncode([item1.toMap()]);
      table.inUse = true;

      expect(table.inUse, isTrue);
      expect(table.currentItems.length, equals(1));
      expect(table.currentTotal, equals(40000));
    });

    test('Cash shift lock enforcement & status check', () {
      final closedShift = CashShiftModel(
        id: 'SHIFT_CLOSED',
        storeCode: 'TRAM01',
        staffUsername: 'staff1',
        staffFullName: 'Nhân Viên 1',
        shiftCode: 'CA_01',
        status: 'CLOSED',
        openedAt: 1771900000000,
        closedAt: 1771930000000,
      );
      expect(closedShift.isOpen, isFalse);

      final openShift = CashShiftModel(
        id: 'SHIFT_OPEN',
        storeCode: 'TRAM01',
        staffUsername: 'staff1',
        staffFullName: 'Nhân Viên 1',
        shiftCode: 'CA_02',
        status: 'OPEN',
        openedAt: 1771935000000,
      );
      expect(openShift.isOpen, isTrue);

      // RTDB payload matching exact TRAM02 closed shift
      final rtdbClosedMap = {
        'actualCash': 35000,
        'cashIn': 0,
        'cashOut': 0,
        'closedAt': 1790759114385,
        'difference': 0,
        'id': 'TRAM02',
        'initialCash': 0,
        'notes': '',
        'openedAt': 0,
        'shiftCode': 'TRAM02',
        'shiftName': '',
        'staffFullName': '',
        'staffUsername': '',
        'status': 'CLOSED',
        'storeCode': '',
        'totalCardSales': 0,
        'totalCashSales': 35000,
        'totalQrSales': 0,
      };
      final parsedClosedShift = CashShiftModel.fromMap(rtdbClosedMap, 'TRAM02');
      expect(parsedClosedShift.isOpen, isFalse);
      expect(parsedClosedShift.status, equals('CLOSED'));

      // Ghost shift with status: 'OPEN' but openedAt: 0 must NEVER be evaluated as open
      final rtdbGhostOpenMap = {
        'id': 'TRAM02',
        'shiftCode': 'TRAM02',
        'openedAt': 0,
        'status': 'OPEN',
        'initialCash': 0,
      };
      final parsedGhostShift = CashShiftModel.fromMap(rtdbGhostOpenMap, 'TRAM02');
      expect(parsedGhostShift.isOpen, isFalse);

      // UserModel isOwner and isManager convenience getters
      final ownerUser = UserModel(
        username: 'chuquan',
        fullName: 'Chủ Quán',
        password: '',
        roleId: 'OWNER',
        isRootOwner: true,
      );
      expect(ownerUser.isOwner, isTrue);
      expect(ownerUser.isManager, isFalse);

      final managerUser = UserModel(
        username: 'quanly',
        fullName: 'Quản Lý 1',
        password: '',
        roleId: 'MANAGER_1',
      );
      expect(managerUser.isOwner, isFalse);
      expect(managerUser.isManager, isTrue);
    });

    test('Receipt printer LAN IP validation & resilience', () async {
      // Empty IP immediately returns false without hanging
      final resultEmpty = await ReceiptPrinter.printViaLan(
        printerIp: '   ',
        data: Uint8List.fromList([0x1B, 0x40]),
      );
      expect(resultEmpty, isFalse);

      // Unreachable IP with quick timeout fails cleanly
      final resultUnreachable = await ReceiptPrinter.printViaLan(
        printerIp: '127.0.0.1',
        port: 59999, // Unused port
        data: Uint8List.fromList([0x1B, 0x40]),
        timeout: const Duration(milliseconds: 100),
      );
      expect(resultUnreachable, isFalse);
    });

    test('StoreInfoModel autoPrintBill toggle and serialization', () {
      // Default should be true
      final defaultStore = StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm');
      expect(defaultStore.autoPrintBill, isTrue);

      // Explicit false toggle
      final noPrintStore = StoreInfoModel(
        storeCode: 'TRAM01',
        storeName: 'POS Trạm',
        autoPrintBill: false,
      );
      expect(noPrintStore.autoPrintBill, isFalse);

      // Serialization and deserialization
      final map = noPrintStore.toMap();
      expect(map['autoPrintBill'], isFalse);

      final parsed = StoreInfoModel.fromMap(map, 'TRAM01');
      expect(parsed.autoPrintBill, isFalse);

      // Fallback when missing from map
      final legacyMap = {'storeCode': 'TRAM01', 'storeName': 'POS Trạm'};
      final parsedLegacy = StoreInfoModel.fromMap(legacyMap, 'TRAM01');
      expect(parsedLegacy.autoPrintBill, isTrue);
    });

    test('Store-scoped menu separation and ProductModel isAvailable toggle', () {
      // ProductModel isAvailable toggle & serialization
      final p1 = ProductModel(name: 'Trà Olong Xoài', price: 30000, unit: 'ly', category: 'Trà Olong Trái Cây', isAvailable: true);
      expect(p1.isAvailable, isTrue);
      final p1Disabled = ProductModel(
        name: p1.name,
        price: p1.price,
        unit: p1.unit,
        category: p1.category,
        isAvailable: false,
      );
      expect(p1Disabled.isAvailable, isFalse);

      final map = p1Disabled.toMap();
      expect(map['isAvailable'], isFalse);

      final parsed = ProductModel.fromMap(map, 'Trà Olong Xoài');
      expect(parsed.isAvailable, isFalse);
      expect(parsed.category, equals('Trà Olong Trái Cây'));
    });
  });
}

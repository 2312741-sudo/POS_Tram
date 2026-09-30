// test/manager_hub_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tram_flutter/core/permissions/app_permissions.dart';
import 'package:tram_flutter/core/printer/receipt_printer.dart';
import 'package:tram_flutter/core/services/auth_service.dart';
import 'package:tram_flutter/data/services/firebase_service.dart';
import 'package:tram_flutter/data/models/app_models.dart';

void main() {
  group('Manager Hub & Executive Reports Tests', () {
    test('Role Access to Manager Hub', () {
      // 1. Owner & Root Owner
      final owner = UserModel(
        username: 'admin',
        fullName: 'Chủ Quán',
        password: '123',
        roleId: 'ROLE_OWNER',
        isRootOwner: true,
      );
      expect(owner.isRootOwner, isTrue);
      expect(owner.role.isOwner, isTrue);
      expect(owner.can(AppPermissions.viewReports), isTrue);

      // 2. Manager 1 (Quản lý 1)
      final manager1 = UserModel(
        username: 'ti',
        fullName: 'Đức Tín',
        password: '123',
        roleId: 'ROLE_MANAGER_1',
      );
      expect(manager1.role.isManager, isTrue);
      expect(manager1.can(AppPermissions.viewReports), isTrue);

      // 3. Manager 2 (Quản lý 2)
      final manager2 = UserModel(
        username: 'ql2',
        fullName: 'Quản Lý Ca 2',
        password: '123',
        roleId: 'manager_2',
      );
      expect(manager2.role.isManager, isTrue);
      expect(manager2.can(AppPermissions.viewReports), isTrue);

      // 4. Regular Employee (Nhân viên)
      final employee = UserModel(
        username: 'nv1',
        fullName: 'Nhân viên phục vụ',
        password: '123',
        roleId: 'ROLE_EMPLOYEE',
      );
      expect(employee.role.isOwner, isFalse);
      expect(employee.role.isManager, isFalse);
      expect(employee.can(AppPermissions.viewReports), isFalse);

      // 5. Employee with custom permission granted
      final employeeWithReports = UserModel(
        username: 'nv2',
        fullName: 'Trưởng nhóm',
        password: '123',
        roleId: 'ROLE_EMPLOYEE',
        customPermissions: [AppPermissions.viewReports],
      );
      expect(employeeWithReports.can(AppPermissions.viewReports), isTrue);
    });

    test('Revenue Calculations: Cash, Transfer & Avg Per Order', () {
      final bills = [
        BillModel(
          id: 'B1',
          billCode: 'HD-001',
          tableName: 'Bàn 01',
          zone: 'Tầng 1',
          createdAt: 1000,
          status: 'PAID',
          staffUsername: 'thungan',
          staffFullName: 'Thu Ngân 1',
          items: [],
          subTotal: 100000,
          finalAmount: 100000,
          paymentMethod: 'CASH',
        ),
        BillModel(
          id: 'B2',
          billCode: 'HD-002',
          tableName: 'Bàn 02',
          zone: 'Tầng 1',
          createdAt: 2000,
          status: 'PAID',
          staffUsername: 'thungan',
          staffFullName: 'Thu Ngân 1',
          items: [],
          subTotal: 150000,
          finalAmount: 150000,
          paymentMethod: 'TRANSFER_QR',
        ),
        BillModel(
          id: 'B3',
          billCode: 'HD-003',
          tableName: 'Bàn 03',
          zone: 'Sân Vườn',
          createdAt: 3000,
          status: 'PAID',
          staffUsername: 'thungan',
          staffFullName: 'Thu Ngân 1',
          items: [],
          subTotal: 50000,
          finalAmount: 50000,
          paymentMethod: 'Tiền mặt',
        ),
      ];

      final totalRevenue = bills.fold(0, (s, b) => s + b.finalAmount);
      expect(totalRevenue, equals(300000));

      final cashRevenue = bills
          .where((b) => b.paymentMethod.toLowerCase().contains('cash') || b.paymentMethod.toLowerCase().contains('tiền mặt'))
          .fold(0, (s, b) => s + b.finalAmount);
      expect(cashRevenue, equals(150000));

      final transferRevenue = bills
          .where((b) => b.paymentMethod.toLowerCase().contains('transfer') || b.paymentMethod.toLowerCase().contains('qr'))
          .fold(0, (s, b) => s + b.finalAmount);
      expect(transferRevenue, equals(150000));

      final avg = (totalRevenue / bills.length).round();
      expect(avg, equals(100000));
    });

    test('Audit Log Suspicious Filter', () {
      final logs = [
        AuditLogModel(
          timestamp: 1000,
          username: 'staff1',
          userFullName: 'Nhân viên 1',
          userRole: 'WAITER',
          action: 'ADD_ITEMS',
          targetType: 'TABLE',
          targetId: 'Bàn 01',
          details: 'Thêm 2 ly trà chanh',
          isSuspicious: false,
        ),
        AuditLogModel(
          timestamp: 2000,
          username: 'staff1',
          userFullName: 'Nhân viên 1',
          userRole: 'CASHIER',
          action: 'CANCEL_KITCHEN_ITEM',
          targetType: 'ITEM',
          targetId: '1',
          details: 'Hủy món đã gửi bếp: Trà chanh x1',
          isSuspicious: true,
        ),
        AuditLogModel(
          timestamp: 3000,
          username: 'staff2',
          userFullName: 'Nhân viên 2',
          userRole: 'CASHIER',
          action: 'MANUAL_DISCOUNT',
          targetType: 'BILL',
          targetId: 'HD-001',
          details: 'Giảm giá tay 50.000đ',
          isSuspicious: true,
        ),
      ];

      final suspicious = logs.where((l) => l.isSuspicious).toList();
      expect(suspicious.length, equals(2));
      expect(suspicious.any((l) => l.action == 'CANCEL_KITCHEN_ITEM'), isTrue);
      expect(suspicious.any((l) => l.action == 'MANUAL_DISCOUNT'), isTrue);
    });

    test('ReceiptPrinter buildBillReceiptBytes & printBill availability', () {
      final store = StoreInfoModel(
        storeCode: 'TRAM01',
        storeName: 'Trạm F&B Đà Lạt',
        billPrinterIp: '192.168.1.201',
      );
      final bill = BillModel(
        id: 'B1',
        billCode: 'HD-TEST',
        tableName: 'Bàn 01',
        zone: 'Tầng 1',
        createdAt: 1771901234567,
        staffUsername: 'admin',
        staffFullName: 'Chủ Quán',
        items: [
          OrderItemModel(
            productId: 1,
            name: 'Trà Chanh Giã Tay',
            price: 25000,
            quantity: 2,
          ),
        ],
        subTotal: 50000,
        finalAmount: 50000,
      );

      final bytes = ReceiptPrinter.buildBillReceiptBytes(store: store, bill: bill);
      expect(bytes.isNotEmpty, isTrue);
    });

    test('Store Switching: AuthService & FirebaseService switchStore', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      final fb = FirebaseService();

      // Switch to TRAM02
      await auth.switchStore('TRAM02');
      expect(auth.currentStoreCode, equals('TRAM02'));
      expect(fb.currentStoreCode, equals('TRAM02'));
      expect(auth.currentStoreInfo?.storeCode, equals('TRAM02'));
      expect((auth.currentStoreInfo?.storeName.contains('TRAM02') ?? false) || (auth.currentStoreInfo?.storeName.contains('02') ?? false), isTrue);

      // Switch back to TRAM01
      await auth.switchStore('TRAM01');
      expect(auth.currentStoreCode, equals('TRAM01'));
      expect(fb.currentStoreCode, equals('TRAM01'));
      expect(auth.currentStoreInfo?.storeCode, equals('TRAM01'));
    });

    test('Cash Shift Reactive Lifecycle & Cash Balance Precision', () {
      // 1. Initial opening of shift
      final shift = CashShiftModel(
        id: 'SHIFT_001',
        shiftCode: 'CA-TEST-01',
        storeCode: 'TRAM01',
        staffUsername: 'admin',
        staffFullName: 'Chủ Quán',
        openedAt: 1790760000000,
        initialCash: 1000000,
        status: 'OPEN',
      );

      expect(shift.isOpen, isTrue);
      expect(shift.expectedCash, equals(1000000));

      // 2. Sales in shift
      shift.totalCashSales = 500000;
      shift.totalQrSales = 300000;
      shift.cashIn = 200000;
      shift.cashOut = 50000;

      // Expected Cash = 1.000.000 + 500.000 + 200.000 - 50.000 = 1.650.000
      expect(shift.expectedCash, equals(1650000));
      expect(shift.totalRevenue, equals(800000));

      // 3. Shift closing
      shift.status = 'CLOSED';
      shift.closedAt = 1790790000000;
      shift.actualCash = 1650000;
      shift.difference = shift.actualCash! - shift.expectedCash;

      expect(shift.isOpen, isFalse);
      expect(shift.difference, equals(0));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/permissions/app_permissions.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/data/models/customer_model.dart';

void main() {
  group('Module 4: Item Discounts & Shift Promo Reports', () {
    test('OrderItemModel computes discountPercent and discountAmount correctly', () {
      final item1 = OrderItemModel(
        productId: 101,
        name: 'Trà Sữa Trân Châu',
        price: 30000,
        quantity: 2,
        discountPercent: 10,
        discountAmount: 6000,
        discountReason: 'Khách VIP',
      );

      expect(item1.unitPrice, 30000);
      expect(item1.quantity, 2);
      expect(item1.discountPercent, 10);
      expect(item1.discountAmount, 6000);
      expect(item1.discountReason, 'Khách VIP');
      expect(item1.itemTotal, 54000); // 60000 - 6000 = 54000

      final map = item1.toMap();
      final fromMap = OrderItemModel.fromMap(map);
      expect(fromMap.discountPercent, 10);
      expect(fromMap.discountAmount, 6000);
      expect(fromMap.discountReason, 'Khách VIP');
      expect(fromMap.itemTotal, 54000);
    });

    test('AppPermissions.discountItem is correctly wired to manager roles', () {
      expect(AppPermissions.discountItem, 'DISCOUNT_ITEM');
      expect(UserRole.fromString('ROLE_OWNER').hasDefaultPermission(AppPermissions.discountItem), isTrue);
      expect(UserRole.fromString('ROLE_MANAGER_1').hasDefaultPermission(AppPermissions.discountItem), isTrue);
      expect(UserRole.fromString('ROLE_MANAGER_2').hasDefaultPermission(AppPermissions.discountItem), isTrue);
      expect(UserRole.fromString('ROLE_CASHIER').hasDefaultPermission(AppPermissions.discountItem), isFalse);
      expect(UserRole.fromString('ROLE_WAITER').hasDefaultPermission(AppPermissions.discountItem), isFalse);
    });

    test('ReportCalculator.calculatePromotionsReport aggregates item discounts, vouchers, and points', () {
      final bill = BillModel(
        id: 'BILL_01',
        billCode: 'HD-001',
        orderCode: 'OD-001',
        tableName: 'Bàn 01',
        zone: 'Tầng 1',
        createdAt: 1000,
        closedAt: 2000,
        status: 'PAID',
        staffUsername: 'thu_ngan',
        staffFullName: 'Thu Ngân A',
        items: [
          OrderItemModel(productId: 1, name: 'Cà phê', price: 25000, quantity: 2, discountAmount: 5000),
          OrderItemModel(productId: 2, name: 'Bánh ngọt', price: 30000, quantity: 1, discountAmount: 3000),
        ],
        subTotal: 80000,
        discounts: [
          BillDiscountModel(promoId: 'VOUCHER10K', promoCode: 'VOUCHER10K', amount: 10000, description: 'Voucher 10k'),
        ],
        pointsUsed: 5,
        pointsDiscount: 5000,
        totalDiscount: 23000, // 8000 (item) + 10000 (voucher) + 5000 (points)
        finalAmount: 57000,
        paymentMethod: 'CASH',
      );

      final promoReport = ReportCalculator.calculatePromotionsReport([bill]);
      expect(promoReport.itemDiscounts.appliedCount, 2);
      expect(promoReport.itemDiscounts.discountAmount, 8000);
      expect(promoReport.campaigns.length, 1);
      expect(promoReport.campaigns.first.discountAmount, 10000);
      expect(promoReport.pointsRedemption.usedCount, 1);
      expect(promoReport.pointsRedemption.discountAmount, 5000);
      expect(promoReport.totalDiscountAmount, 23000);
    });
  });

  group('Module 5: KMT Customer CRM Loyalty Integration', () {
    test('KmtCustomerModel deserializes Firestore schema correctly', () {
      final firestoreData = {
        'so_dien_thoai': '0912345678',
        'ma_khach_hang': 'KMT-9988',
        'ho_ten': 'Nguyễn Văn A',
        'diem_hien_tai': 150,
        'ngay_tao': '2026-01-15T08:00:00Z',
      };

      final customer = KmtCustomerModel.fromMap(firestoreData, 'DOC_123');
      expect(customer.phone, '0912345678');
      expect(customer.code, 'KMT-9988');
      expect(customer.fullName, 'Nguyễn Văn A');
      expect(customer.currentPoints, 150);
      expect(customer.groupName, 'Thân thiết'); // 100-499 pt

      final map = customer.toMap();
      expect(map['so_dien_thoai'], '0912345678');
      expect(map['ma_khach_hang'], 'KMT-9988');
      expect(map['diem_hien_tai'], 150);
    });

    test('StoreInfoModel point conversion rate configuration', () {
      final defaultStore = StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm');
      expect(defaultStore.pointRedeemRate, 1000);
      expect(defaultStore.pointEarnRate, 1.0);

      final customStore = defaultStore.copyWith(pointRedeemRate: 2000, pointEarnRate: 2.5);
      expect(customStore.pointRedeemRate, 2000);
      expect(customStore.pointEarnRate, 2.5);
    });

    test('MANDATORY RULE: pointsDiscount is counted as DISCOUNT, NEVER as net revenue', () {
      final bill = BillModel(
        id: 'BILL_02',
        billCode: 'HD-002',
        orderCode: 'OD-002',
        tableName: 'Bàn 02',
        zone: 'Tầng 1',
        createdAt: 1000,
        closedAt: 2000,
        status: 'PAID',
        staffUsername: 'thu_ngan',
        staffFullName: 'Thu Ngân A',
        items: [
          OrderItemModel(productId: 1, name: 'Trà Trái Cây', price: 50000, quantity: 2, discountAmount: 10000),
        ],
        subTotal: 100000,
        discounts: [
          BillDiscountModel(promoId: 'VC_15K', promoCode: 'VC_15K', amount: 15000, description: 'KM 15k'),
        ],
        pointsUsed: 20,
        pointsDiscount: 20000, // 20 pt * 1000 = 20,000 VND
        vatRate: 10,
        finalAmount: 0,
      );

      bill.recalculateTotals();

      // subTotal = 100,000
      // totalDiscount = 10,000 (item) + 15,000 (voucher) + 20,000 (points) = 45,000
      // afterDiscount = 100,000 - 45,000 = 55,000
      // vatAmount = 55,000 * 10% = 5,500
      // finalAmount (Net Revenue) = 55,000 + 5,500 = 60,500
      expect(bill.totalDiscount, 45000);
      expect(bill.vatAmount, 5500);
      expect(bill.finalAmount, 60500);

      // Verify Overview report net revenue
      final overview = ReportCalculator.calculateOverviewReport([bill]);
      expect(overview.grossRevenue, 100000);
      expect(overview.itemDiscounts, 10000);
      expect(overview.billDiscounts, 15000);
      expect(overview.pointsDiscounts, 20000);
      expect(overview.totalDiscount, 45000);
      expect(overview.afterDiscount, 55000);
      expect(overview.vatTotal, 5500);
      expect(overview.netRevenue, 60500);
    });
  });

  group('Module 6: Split Payment (Cash + VietQR)', () {
    test('BillModel serializes and deserializes paymentSplits correctly', () {
      final splits = [
        PaymentSplitModel(method: 'CASH', amount: 40000),
        PaymentSplitModel(method: 'TRANSFER_QR', amount: 60000, note: 'QR-12345'),
      ];

      final bill = BillModel(
        id: 'BILL_03',
        billCode: 'HD-003',
        orderCode: 'OD-003',
        tableName: 'Bàn 03',
        zone: 'Tầng 1',
        createdAt: 1000,
        status: 'PAID',
        staffUsername: 'staff',
        staffFullName: 'Nhân Viên',
        items: [],
        subTotal: 100000,
        finalAmount: 100000,
        paymentMethod: 'SPLIT',
        paymentSplits: splits,
      );

      final map = bill.toMap();
      expect(map['paymentMethod'], 'SPLIT');
      expect((map['paymentSplits'] as List).length, 2);

      final restored = BillModel.fromMap(map, 'BILL_03');
      expect(restored.paymentMethod, 'SPLIT');
      expect(restored.paymentSplits?.length, 2);
      expect(restored.paymentSplits?[0].method, 'CASH');
      expect(restored.paymentSplits?[0].amount, 40000);
      expect(restored.paymentSplits?[1].method, 'TRANSFER_QR');
      expect(restored.paymentSplits?[1].amount, 60000);
    });

    test('Cash shift audit: ONLY CASH split is added to drawer expectedCash', () {
      final shift = CashShiftModel(
        id: 'SHIFT_01',
        shiftCode: 'CA-01',
        storeCode: 'TRAM01',
        staffUsername: 'thu_ngan',
        staffFullName: 'Thu Ngân B',
        openedAt: 1000,
        closedAt: 5000,
        initialCash: 1000000,
        status: 'CLOSED',
        actualCash: 1040000,
      );

      // Bill with SPLIT: 40,000 cash, 60,000 VietQR
      final bill = BillModel(
        id: 'BILL_SPLIT_1',
        billCode: 'HD-SPLIT-1',
        orderCode: 'OD-01',
        tableName: 'Bàn 01',
        zone: 'Tầng 1',
        shiftId: 'SHIFT_01',
        createdAt: 2000,
        closedAt: 2500,
        status: 'PAID',
        staffUsername: 'thu_ngan',
        staffFullName: 'Thu Ngân B',
        items: [],
        subTotal: 100000,
        finalAmount: 100000,
        paymentMethod: 'SPLIT',
        paymentSplits: [
          PaymentSplitModel(method: 'CASH', amount: 40000),
          PaymentSplitModel(method: 'TRANSFER_QR', amount: 60000),
        ],
      );

      final auditList = ReportCalculator.calculateCashShiftReport([shift], [bill]);
      expect(auditList.length, 1);
      final audit = auditList.first;

      // Crucial verification:
      // cashSales must only be 40,000 (NOT 100,000)
      // qrSales must be 60,000
      expect(audit.cashSales, 40000);
      expect(audit.qrSales, 60000);
      expect(audit.totalSales, 100000);

      // expectedCash = initialCash (1,000,000) + cashSales (40,000) = 1,040,000
      expect(audit.expectedCash, 1040000);
      // actualCash = 1,040,000 -> difference = 0
      expect(audit.difference, 0);
    });
  });
}

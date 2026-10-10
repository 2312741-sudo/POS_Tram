import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/core/reports/report_export_service.dart';
import 'package:tram_flutter/core/reports/report_models.dart';
import 'package:tram_flutter/data/models/product_model.dart';
import 'package:tram_flutter/data/models/shift_model.dart';

void main() {
  group('POS Trạm Report Golden Verification Tests (docs/report_golden.json)', () {
    late Map<String, dynamic> goldenData;
    late List<ReportBillModel> bills;
    late Map<int, ProductModel> productsMap;
    late Map<String, int> toppingCosts;
    late List<CashShiftModel> shifts;
    late Map<String, dynamic> expected;

    setUpAll(() {
      // Tìm file docs/report_golden.json
      File file = File('../docs/report_golden.json');
      if (!file.existsSync()) {
        file = File('docs/report_golden.json');
      }
      expect(file.existsSync(), isTrue, reason: 'Phải tìm thấy file docs/report_golden.json');

      final jsonStr = file.readAsStringSync();
      goldenData = jsonDecode(jsonStr) as Map<String, dynamic>;
      expected = goldenData['expectedResults'] as Map<String, dynamic>;

      // Load products map
      final prodsList = goldenData['catalogue']['products'] as List;
      productsMap = {
        for (final p in prodsList)
          (p['productId'] as num).toInt(): ProductModel(
            id: (p['productId'] as num).toInt(),
            code: p['code']?.toString() ?? '',
            name: p['name']?.toString() ?? '',
            price: (p['price'] as num).toInt(),
            costPrice: (p['costPrice'] as num?)?.toInt(),
            category: p['category']?.toString() ?? 'Khác',
            unit: p['unit']?.toString() ?? 'Ly',
          )
      };

      // Load toppings map
      final toppingsList = goldenData['catalogue']['toppings'] as List;
      toppingCosts = {
        for (final t in toppingsList)
          t['name'].toString(): (t['costPrice'] as num).toInt()
      };

      // Load shifts
      final rawShifts = goldenData['shifts'] as List;
      shifts = rawShifts.map((s) => CashShiftModel.fromMap(s as Map<String, dynamic>, s['shiftId'].toString())).toList();

      // Load bills
      final rawBills = goldenData['bills'] as List;
      bills = rawBills.map((b) => ReportBillModel.fromMap(b as Map<String, dynamic>, b['id'].toString())).toList();
    });

    test('1. Báo cáo Tổng quan Quản trị (Overview) khớp 100% golden data', () {
      final overview = ReportCalculator.calculateOverviewReport(
        bills,
        refundAmount: 47000,
        productsMap: productsMap,
        toppingCosts: toppingCosts,
      );

      final expOverview = expected['overview'] as Map<String, dynamic>;
      expect(overview.totalBillsCount, equals(expOverview['totalBillsCount']));
      expect(overview.paidBillsCount, equals(expOverview['paidBillsCount']));
      expect(overview.cancelledBillsCount, equals(expOverview['cancelledBillsCount']));
      expect(overview.refundedBillsCount, equals(expOverview['refundedBillsCount']));
      expect(overview.totalGuests, equals(expOverview['totalGuests']));
      expect(overview.grossRevenue, equals(expOverview['grossRevenue']));
      expect(overview.itemDiscounts, equals(expOverview['itemDiscounts']));
      expect(overview.billDiscounts, equals(expOverview['billDiscounts']));
      expect(overview.pointsDiscounts, equals(expOverview['pointsDiscounts']));
      expect(overview.totalDiscount, equals(expOverview['totalDiscount']));
      expect(overview.afterDiscount, equals(expOverview['afterDiscount']));
      expect(overview.vatTotal, equals(expOverview['vatTotal']));
      expect(overview.netRevenue, equals(expOverview['netRevenue']));
      expect(overview.refundAmount, equals(expOverview['refundAmount']));
      expect(overview.netRevenueWithoutRefund, equals(expOverview['netRevenueWithoutRefund']));
      expect(overview.avgRevenuePerPaidBill, equals(expOverview['avgRevenuePerPaidBill']));
      expect(overview.cancelledTotalValue, equals(expOverview['cancelledTotalValue']));
      expect(overview.totalCostPrice, equals(expOverview['totalCostPrice']));
      expect(overview.grossProfit, equals(expOverview['grossProfit']));
      expect(overview.grossProfitMarginPercent, equals(expOverview['grossProfitMarginPercent']));
    });

    test('2. Báo cáo Hình thức thanh toán khớp 100% golden data', () {
      final payments = ReportCalculator.calculatePaymentMethodsReport(bills);
      final expPayments = expected['revenueByPaymentMethod'] as Map<String, dynamic>;

      for (final method in ['CASH', 'TRANSFER_QR', 'CARD']) {
        expect(payments.containsKey(method), isTrue);
        final item = payments[method]!;
        final expItem = expPayments[method] as Map<String, dynamic>;

        expect(item.billCount, equals(expItem['billCount']), reason: '$method billCount');
        expect(item.grossRevenue, equals(expItem['grossRevenue']), reason: '$method grossRevenue');
        expect(item.totalDiscount, equals(expItem['totalDiscount']), reason: '$method totalDiscount');
        expect(item.vatAmount, equals(expItem['vatAmount']), reason: '$method vatAmount');
        expect(item.finalAmount, equals(expItem['finalAmount']), reason: '$method finalAmount');
      }
    });

    test('3. Báo cáo Khung giờ (Hourly) khớp 100% golden data', () {
      final hourlyList = ReportCalculator.calculateHourlyReport(bills);
      final expHourlyList = expected['revenueByHour'] as List;

      expect(hourlyList.length, equals(24));
      for (int i = 0; i < 24; i++) {
        final item = hourlyList[i];
        final expItem = expHourlyList[i] as Map<String, dynamic>;

        expect(item.hour, equals(expItem['hour']));
        expect(item.hourLabel, equals(expItem['hourLabel']));
        expect(item.billCount, equals(expItem['billCount']));
        expect(item.grossRevenue, equals(expItem['grossRevenue']));
        expect(item.totalDiscount, equals(expItem['totalDiscount']));
        expect(item.vatAmount, equals(expItem['vatAmount']));
        expect(item.netRevenue, equals(expItem['netRevenue']));
      }
    });

    test('4. Báo cáo Nhóm hàng (Category) khớp 100% golden data', () {
      final catList = ReportCalculator.calculateCategoryReport(
        bills,
        productsMap: productsMap,
        toppingCosts: toppingCosts,
      );
      final expCatList = expected['revenueByCategory'] as List;

      expect(catList.length, equals(expCatList.length));
      for (int i = 0; i < catList.length; i++) {
        final item = catList[i];
        final expItem = expCatList[i] as Map<String, dynamic>;

        expect(item.category, equals(expItem['category']));
        expect(item.quantity, equals(expItem['quantity']));
        expect(item.grossRevenue, equals(expItem['grossRevenue']));
        expect(item.itemDiscount, equals(expItem['itemDiscount']));
        expect(item.netRevenue, equals(expItem['netRevenue']));
        expect(item.costPrice, equals(expItem['costPrice']));
        expect(item.grossProfit, equals(expItem['grossProfit']));
        expect(item.grossProfitMarginPercent, equals(expItem['grossProfitMarginPercent']));
      }
    });

    test('5. Báo cáo Món ăn / Hàng hóa (Product) khớp 100% golden data', () {
      final prodList = ReportCalculator.calculateProductReport(
        bills,
        productsMap: productsMap,
        toppingCosts: toppingCosts,
      );
      final expProdList = expected['revenueByProduct'] as List;

      expect(prodList.length, equals(expProdList.length));
      for (int i = 0; i < prodList.length; i++) {
        final item = prodList[i];
        final expItem = expProdList[i] as Map<String, dynamic>;

        expect(item.productId, equals(expItem['productId']));
        expect(item.productCode, equals(expItem['productCode']));
        expect(item.productName, equals(expItem['productName']));
        expect(item.category, equals(expItem['category']));
        expect(item.unit, equals(expItem['unit']));
        expect(item.basePrice, equals(expItem['basePrice']));
        expect(item.quantity, equals(expItem['quantity']));
        expect(item.grossRevenue, equals(expItem['grossRevenue']));
        expect(item.itemDiscount, equals(expItem['itemDiscount']));
        expect(item.netRevenue, equals(expItem['netRevenue']));
        expect(item.costPrice, equals(expItem['costPrice']));
        expect(item.grossProfit, equals(expItem['grossProfit']));
        expect(item.grossProfitMarginPercent, equals(expItem['grossProfitMarginPercent']));
      }
    });

    test('6. Báo cáo Nhân viên (Staff Performance) khớp 100% golden data', () {
      final staffRes = ReportCalculator.calculateStaffPerformance(bills);
      final expStaff = expected['revenueByStaff'] as Map<String, dynamic>;

      // Order staff
      final expOrderStaff = expStaff['orderStaff'] as List;
      expect(staffRes.orderStaff.length, equals(expOrderStaff.length));
      for (int i = 0; i < staffRes.orderStaff.length; i++) {
        final item = staffRes.orderStaff[i];
        final expItem = expOrderStaff[i] as Map<String, dynamic>;

        expect(item.staffUsername, equals(expItem['staffUsername']));
        expect(item.staffFullName, equals(expItem['staffFullName']));
        expect(item.itemsCount, equals(expItem['itemsCount']));
        expect(item.grossRevenue, equals(expItem['grossRevenue']));
        expect(item.netRevenue, equals(expItem['netRevenue']));
      }

      // Cashier staff
      final expCashierStaff = expStaff['cashierStaff'] as List;
      expect(staffRes.cashierStaff.length, equals(expCashierStaff.length));
      for (int i = 0; i < staffRes.cashierStaff.length; i++) {
        final item = staffRes.cashierStaff[i];
        final expItem = expCashierStaff[i] as Map<String, dynamic>;

        expect(item.staffUsername, equals(expItem['staffUsername']));
        expect(item.staffFullName, equals(expItem['staffFullName']));
        expect(item.billCount, equals(expItem['billCount']));
        expect(item.netRevenue, equals(expItem['netRevenue']));
      }
    });

    test('7. Báo cáo Khuyến mãi & Voucher khớp 100% golden data', () {
      final promoRes = ReportCalculator.calculatePromotionsReport(bills);
      final expPromo = expected['promotionsReport'] as Map<String, dynamic>;

      expect(promoRes.totalDiscountAmount, equals(expPromo['totalDiscountAmount']));

      // Campaigns
      final expCampaigns = expPromo['campaigns'] as List;
      expect(promoRes.campaigns.length, equals(expCampaigns.length));
      for (int i = 0; i < promoRes.campaigns.length; i++) {
        final c = promoRes.campaigns[i];
        final expC = expCampaigns[i] as Map<String, dynamic>;
        expect(c.promoId, equals(expC['promoId']));
        expect(c.promoCode, equals(expC['promoCode']));
        expect(c.name, equals(expC['name']));
        expect(c.usedCount, equals(expC['usedCount']));
        expect(c.discountAmount, equals(expC['discountAmount']));
      }

      // Points redemption
      final expPoints = expPromo['pointsRedemption'] as Map<String, dynamic>;
      expect(promoRes.pointsRedemption.usedCount, equals(expPoints['usedCount']));
      expect(promoRes.pointsRedemption.totalPointsUsed, equals(expPoints['totalPointsUsed']));
      expect(promoRes.pointsRedemption.discountAmount, equals(expPoints['discountAmount']));

      // Item discounts
      final expItemDisc = expPromo['itemDiscounts'] as Map<String, dynamic>;
      expect(promoRes.itemDiscounts.appliedCount, equals(expItemDisc['appliedCount']));
      expect(promoRes.itemDiscounts.discountAmount, equals(expItemDisc['discountAmount']));
      final expDetails = expItemDisc['details'] as List;
      expect(promoRes.itemDiscounts.details.length, equals(expDetails.length));
      for (int i = 0; i < promoRes.itemDiscounts.details.length; i++) {
        final d = promoRes.itemDiscounts.details[i];
        final expD = expDetails[i] as Map<String, dynamic>;
        expect(d.productId, equals(expD['productId']));
        expect(d.productName, equals(expD['productName']));
        expect(d.discountAmount, equals(expD['discountAmount']));
        expect(d.quantity, equals(expD['quantity']));
      }
    });

    test('8. Báo cáo Hủy món & Hủy đơn (Cancellations) khớp 100% golden data', () {
      final cancelRes = ReportCalculator.calculateCancellationReport(bills);
      final expCancel = expected['cancellationReport'] as Map<String, dynamic>;

      expect(cancelRes.cancelledBillsCount, equals(expCancel['cancelledBillsCount']));
      expect(cancelRes.totalLossValue, equals(expCancel['totalLossValue']));

      final expBills = expCancel['bills'] as List;
      expect(cancelRes.bills.length, equals(expBills.length));
      for (int i = 0; i < cancelRes.bills.length; i++) {
        final b = cancelRes.bills[i];
        final expB = expBills[i] as Map<String, dynamic>;
        expect(b.billId, equals(expB['billId']));
        expect(b.billCode, equals(expB['billCode']));
        expect(b.tableName, equals(expB['tableName']));
        expect(b.staffFullName, equals(expB['staffFullName']));
        expect(b.cancelledAt, equals(expB['cancelledAt']));
        expect(b.reason, equals(expB['reason']));
        expect(b.items, equals(expB['items']));
        expect(b.subTotal, equals(expB['subTotal']));
      }
    });

    test('9. Báo cáo Ca két & Chênh lệch (Cash Shifts) khớp 100% golden data', () {
      final shiftReport = ReportCalculator.calculateCashShiftReport(shifts, bills);
      final expShiftReport = expected['cashShiftsReport'] as List;

      expect(shiftReport.length, equals(expShiftReport.length));
      for (int i = 0; i < shiftReport.length; i++) {
        final item = shiftReport[i];
        final expItem = expShiftReport[i] as Map<String, dynamic>;

        expect(item.shiftId, equals(expItem['shiftId']));
        expect(item.shiftCode, equals(expItem['shiftCode']));
        expect(item.shiftName, equals(expItem['shiftName']));
        expect(item.staffUsername, equals(expItem['staffUsername']));
        expect(item.staffFullName, equals(expItem['staffFullName']));
        expect(item.openedAt, equals(expItem['openedAt']));
        expect(item.closedAt, equals(expItem['closedAt']));
        expect(item.initialCash, equals(expItem['initialCash']));
        expect(item.cashIn, equals(expItem['cashIn']));
        expect(item.cashOut, equals(expItem['cashOut']));
        expect(item.cashSales, equals(expItem['cashSales']));
        expect(item.qrSales, equals(expItem['qrSales']));
        expect(item.cardSales, equals(expItem['cardSales']));
        expect(item.totalSales, equals(expItem['totalSales']));
        expect(item.refundCash, equals(expItem['refundCash']));
        expect(item.expectedCash, equals(expItem['expectedCash']));
        expect(item.actualCash, equals(expItem['actualCash']));
        expect(item.difference, equals(expItem['difference']));
        expect(item.status, equals(expItem['status']));
      }
    });

    test('10. Báo cáo Cuối ngày (End-of-Day Z-Report) khớp 100% golden data', () {
      final zReport = ReportCalculator.generateEndOfDayZReport(
        bills: bills,
        shifts: shifts,
        productsMap: productsMap,
        toppingCosts: toppingCosts,
        dateStr: '2026-10-04',
        storeCode: 'TRAM01',
        storeName: 'POS Trạm - Trụ sở 01 (Đà Lạt)',
      );

      final expZ = expected['endOfDayReport'] as Map<String, dynamic>;

      expect(zReport.date, equals(expZ['date']));
      expect(zReport.storeCode, equals(expZ['storeCode']));
      expect(zReport.storeName, equals(expZ['storeName']));

      // Tab 1: Tổng hợp
      final tab1 = zReport.tab1TongHop;
      final expTab1 = expZ['tab1_tongHop'] as Map<String, dynamic>;
      expect(tab1.grossRevenue, equals(expTab1['grossRevenue']));
      expect(tab1.itemDiscounts, equals(expTab1['itemDiscounts']));
      expect(tab1.billDiscounts, equals(expTab1['billDiscounts']));
      expect(tab1.totalDiscount, equals(expTab1['totalDiscount']));
      expect(tab1.afterDiscount, equals(expTab1['afterDiscount']));
      expect(tab1.vatTotal, equals(expTab1['vatTotal']));
      expect(tab1.netRevenue, equals(expTab1['netRevenue']));
      expect(tab1.refundAmount, equals(expTab1['refundAmount']));
      expect(tab1.netRevenueWithoutRefund, equals(expTab1['netRevenueWithoutRefund']));
      expect(tab1.paidBillsCount, equals(expTab1['paidBillsCount']));
      expect(tab1.avgRevenuePerBill, equals(expTab1['avgRevenuePerBill']));
      expect(tab1.totalGuests, equals(expTab1['totalGuests']));
      expect(tab1.deletedItemsCount, equals(expTab1['deletedItemsCount']));
      expect(tab1.deletedItemsAmount, equals(expTab1['deletedItemsAmount']));
      expect(tab1.cancelledBillsCount, equals(expTab1['cancelledBillsCount']));
      expect(tab1.cancelledBillsAmount, equals(expTab1['cancelledBillsAmount']));

      // Tab 2: Thu chi
      final tab2 = zReport.tab2ThuChi;
      final expTab2 = expZ['tab2_thuChi'] as Map<String, dynamic>;
      expect(tab2.cashSales, equals(expTab2['cashSales']));
      expect(tab2.transferSales, equals(expTab2['transferSales']));
      expect(tab2.cardSales, equals(expTab2['cardSales']));
      expect(tab2.totalRevenue, equals(expTab2['totalRevenue']));
      expect(tab2.cashInTotal, equals(expTab2['cashInTotal']));
      expect(tab2.cashOutTotal, equals(expTab2['cashOutTotal']));
      expect(tab2.refundTotal, equals(expTab2['refundTotal']));

      // Tab 3: Hàng hóa
      final tab3 = zReport.tab3HangHoa;
      final expTab3 = expZ['tab3_hangHoa'] as Map<String, dynamic>;
      expect(tab3.totalItemsSold, equals(expTab3['totalItemsSold']));
      final expProds = expTab3['products'] as List;
      expect(tab3.products.length, equals(expProds.length));
      for (int i = 0; i < tab3.products.length; i++) {
        final p = tab3.products[i];
        final expP = expProds[i] as Map<String, dynamic>;
        expect(p.productId, equals(expP['productId']));
        expect(p.productCode, equals(expP['productCode']));
        expect(p.productName, equals(expP['productName']));
        expect(p.category, equals(expP['category']));
        expect(p.unit, equals(expP['unit']));
        expect(p.basePrice, equals(expP['basePrice']));
        expect(p.quantity, equals(expP['quantity']));
        expect(p.grossRevenue, equals(expP['grossRevenue']));
        expect(p.itemDiscount, equals(expP['itemDiscount']));
        expect(p.netRevenue, equals(expP['netRevenue']));
        expect(p.costPrice, equals(expP['costPrice']));
        expect(p.grossProfit, equals(expP['grossProfit']));
        expect(p.grossProfitMarginPercent, equals(expP['grossProfitMarginPercent']));
      }

      // Tab 4: Phòng bàn
      final tab4 = zReport.tab4PhongBan;
      final expTab4 = expZ['tab4_phongBan'] as Map<String, dynamic>;
      final expZones = expTab4['zones'] as List;
      expect(tab4.zones.length, equals(expZones.length));
      for (int i = 0; i < tab4.zones.length; i++) {
        final z = tab4.zones[i];
        final expZItem = expZones[i] as Map<String, dynamic>;
        expect(z.zone, equals(expZItem['zone']));
        expect(z.billCount, equals(expZItem['billCount']));
        expect(z.netRevenue, equals(expZItem['netRevenue']));
      }
    });

    test('11. Báo cáo Lợi nhuận gộp & Giá vốn (Gross Profit & COGS)', () {
      final gp = ReportCalculator.calculateGrossProfitReport(
        bills,
        productsMap: productsMap,
        toppingCosts: toppingCosts,
      );

      final expOverview = expected['overview'] as Map<String, dynamic>;
      expect(gp.totalRevenue, equals(expOverview['afterDiscount']));
      expect(gp.totalCostPrice, equals(expOverview['totalCostPrice']));
      expect(gp.grossProfit, equals(expOverview['grossProfit']));
      expect(gp.grossProfitMarginPercent, equals(expOverview['grossProfitMarginPercent']));
      expect(gp.items.length, equals(7));
    });

    test('12. Báo cáo Doanh thu theo kỳ (Period Revenue)', () {
      final periodRes = ReportCalculator.calculateRevenueByPeriod(bills, PeriodType.day);
      expect(periodRes.isNotEmpty, isTrue);
      final item = periodRes.first;
      expect(item.billCount, equals(17));
      expect(item.netRevenue, equals(1204560));
      expect(item.cashRevenue, equals(588960));
      expect(item.transferRevenue, equals(464400));
      expect(item.cardRevenue, equals(151200));
      expect(item.percentage, equals(100.0));
    });

    test('13. Quy ước đặt tên file xuất Excel/PDF chuẩn mục 7.1', () {
      final fixedNow = DateTime(2026, 10, 4, 23, 5, 0);
      final startDate = DateTime(2026, 10, 4);
      final endDate = DateTime(2026, 10, 4);

      final fileNameZ = ReportExportService.generateFileName(
        reportCode: 'BC_CUOINGAY_Z',
        storeCode: 'TRAM01',
        startDate: startDate,
        endDate: endDate,
        extension: 'xlsx',
        now: fixedNow,
      );
      expect(fileNameZ, equals('BC_CUOINGAY_Z_TRAM01_20261004_20261004_230500.xlsx'));

      final startMonth = DateTime(2026, 10, 1);
      final endMonth = DateTime(2026, 10, 31);
      final fixedMorning = DateTime(2026, 10, 31, 8, 30, 15);
      final fileNameProd = ReportExportService.generateFileName(
        reportCode: 'BC_HANGHOA',
        storeCode: 'TRAM01',
        startDate: startMonth,
        endDate: endMonth,
        extension: 'xlsx',
        now: fixedMorning,
      );
      expect(fileNameProd, equals('BC_HANGHOA_TRAM01_20261001_20261031_083015.xlsx'));
    });
  });
}

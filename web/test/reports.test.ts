import { describe, it, expect } from "vitest";
import * as fs from "fs";
import * as path from "path";
import {
  deduplicateBills,
  calculateOverviewReport,
  calculateRevenueByPeriod,
  calculateCategoryReport,
  calculateProductReport,
  calculateStaffPerformance,
  calculateHourlyReport,
  calculatePaymentMethodsReport,
  calculatePromotionsReport,
  calculateCancellationReport,
  calculateCashShiftReport,
  calculateGrossProfitReport,
  generateEndOfDayZReport,
  ProductItem,
  CategoryReportItem,
  ProductReportItem,
  StaffOrderPerformanceItem,
  StaffCashierPerformanceItem,
  CampaignReportItem,
  CancelledBillItem,
  HistoryOrder,
} from "../lib/reports";

// Load golden verification dataset
const goldenPath = path.resolve(__dirname, "../../docs/report_golden.json");
const goldenData = JSON.parse(fs.readFileSync(goldenPath, "utf-8"));

const productsMap: Record<string | number, ProductItem> = {};
goldenData.catalogue.products.forEach((p: ProductItem) => {
  productsMap[p.productId || String(p.id)] = p;
  productsMap[p.name] = p;
});

describe("POS Trạm - Core Reports Pure Functions vs docs/report_golden.json", () => {
  it("Báo cáo 1: Tổng quan quản trị (Executive Overview) khớp từng con số", () => {
    const overview = calculateOverviewReport(goldenData.bills);
    const expected = goldenData.expectedResults.overview;

    expect(overview.totalBillsCount).toBe(expected.totalBillsCount);
    expect(overview.paidBillsCount).toBe(expected.paidBillsCount);
    expect(overview.cancelledBillsCount).toBe(expected.cancelledBillsCount);
    expect(overview.refundedBillsCount).toBe(expected.refundedBillsCount);
    expect(overview.totalGuests).toBe(expected.totalGuests);
    expect(overview.grossRevenue).toBe(expected.grossRevenue);
    expect(overview.itemDiscounts).toBe(expected.itemDiscounts);
    expect(overview.billDiscounts).toBe(expected.billDiscounts);
    expect(overview.pointsDiscounts).toBe(expected.pointsDiscounts);
    expect(overview.totalDiscount).toBe(expected.totalDiscount);
    expect(overview.afterDiscount).toBe(expected.afterDiscount);
    expect(overview.vatTotal).toBe(expected.vatTotal);
    expect(overview.netRevenue).toBe(expected.netRevenue);
    expect(overview.refundAmount).toBe(expected.refundAmount);
    expect(overview.netRevenueWithoutRefund).toBe(expected.netRevenueWithoutRefund);
    expect(overview.avgRevenuePerPaidBill).toBe(expected.avgRevenuePerPaidBill);
    expect(overview.cancelledTotalValue).toBe(expected.cancelledTotalValue);
    expect(overview.totalCostPrice).toBe(expected.totalCostPrice);
    expect(overview.grossProfit).toBe(expected.grossProfit);
    expect(overview.grossProfitMarginPercent).toBe(expected.grossProfitMarginPercent);
  });

  it("Báo cáo 2: Doanh thu theo kỳ (Revenue by Period) tổng kết đúng ngày 04/10/2026", () => {
    const periodReports = calculateRevenueByPeriod(goldenData.bills, "DAY");
    expect(periodReports.length).toBe(1);
    const day04 = periodReports[0];
    expect(day04.periodKey).toBe("2026-10-04");
    expect(day04.periodLabel).toBe("04/10/2026");
    expect(day04.billCount).toBe(17);
    expect(day04.grossRevenue).toBe(1167000);
    expect(day04.discountAmount).toBe(45000);
    expect(day04.vatAmount).toBe(82560);
    expect(day04.netRevenue).toBe(1204560);
    expect(day04.cashRevenue).toBe(588960);
    expect(day04.qrRevenue).toBe(464400);
    expect(day04.cardRevenue).toBe(151200);
  });

  it("Báo cáo 3: Doanh thu theo Nhóm hàng / Danh mục (Category Sales) khớp 100%", () => {
    const categories = calculateCategoryReport(goldenData.bills, productsMap);
    const expected = goldenData.expectedResults.revenueByCategory;

    expect(categories.length).toBe(expected.length);
    expected.forEach((exp: CategoryReportItem) => {
      const match = categories.find((c) => c.category === exp.category);
      expect(match).toBeDefined();
      expect(match!.quantity).toBe(exp.quantity);
      expect(match!.grossRevenue).toBe(exp.grossRevenue);
      expect(match!.itemDiscount).toBe(exp.itemDiscount);
      expect(match!.netRevenue).toBe(exp.netRevenue);
      expect(match!.costPrice).toBe(exp.costPrice);
      expect(match!.grossProfit).toBe(exp.grossProfit);
      expect(match!.grossProfitMarginPercent).toBe(exp.grossProfitMarginPercent);
    });
  });

  it("Báo cáo 4: Hiệu suất Món ăn / Hàng hóa (Product Sales Performance) khớp 100%", () => {
    const products = calculateProductReport(goldenData.bills, productsMap);
    const expected = goldenData.expectedResults.revenueByProduct;

    expect(products.length).toBe(expected.length);
    expected.forEach((exp: ProductReportItem) => {
      const match = products.find((p) => p.productId === exp.productId);
      expect(match).toBeDefined();
      expect(match!.productCode).toBe(exp.productCode);
      expect(match!.productName).toBe(exp.productName);
      expect(match!.category).toBe(exp.category);
      expect(match!.unit).toBe(exp.unit);
      expect(match!.basePrice).toBe(exp.basePrice);
      expect(match!.quantity).toBe(exp.quantity);
      expect(match!.grossRevenue).toBe(exp.grossRevenue);
      expect(match!.itemDiscount).toBe(exp.itemDiscount);
      expect(match!.netRevenue).toBe(exp.netRevenue);
      expect(match!.costPrice).toBe(exp.costPrice);
      expect(match!.grossProfit).toBe(exp.grossProfit);
      expect(match!.grossProfitMarginPercent).toBe(exp.grossProfitMarginPercent);
    });
  });

  it("Báo cáo 5: Năng suất Nhân viên (Staff Sales Performance) khớp 100%", () => {
    const staff = calculateStaffPerformance(goldenData.bills);
    const expected = goldenData.expectedResults.revenueByStaff;

    // Order Staff
    expect(staff.orderStaff.length).toBe(expected.orderStaff.length);
    expected.orderStaff.forEach((exp: StaffOrderPerformanceItem) => {
      const match = staff.orderStaff.find((s) => s.staffUsername === exp.staffUsername);
      expect(match).toBeDefined();
      expect(match!.staffFullName).toBe(exp.staffFullName);
      expect(match!.itemsCount).toBe(exp.itemsCount);
      expect(match!.grossRevenue).toBe(exp.grossRevenue);
      expect(match!.netRevenue).toBe(exp.netRevenue);
    });

    // Cashier Staff
    expect(staff.cashierStaff.length).toBe(expected.cashierStaff.length);
    expected.cashierStaff.forEach((exp: StaffCashierPerformanceItem) => {
      const match = staff.cashierStaff.find((s) => s.staffUsername === exp.staffUsername);
      expect(match).toBeDefined();
      expect(match!.staffFullName).toBe(exp.staffFullName);
      expect(match!.billCount).toBe(exp.billCount);
      expect(match!.netRevenue).toBe(exp.netRevenue);
    });
  });

  it("Báo cáo 6: Phân bổ theo Khung giờ (Hourly Heatmap) khớp cả 24 khung giờ", () => {
    const hourly = calculateHourlyReport(goldenData.bills);
    const expected = goldenData.expectedResults.revenueByHour;

    expect(hourly.length).toBe(24);
    for (let i = 0; i < 24; i++) {
      expect(hourly[i].hour).toBe(expected[i].hour);
      expect(hourly[i].hourLabel).toBe(expected[i].hourLabel);
      expect(hourly[i].billCount).toBe(expected[i].billCount);
      expect(hourly[i].grossRevenue).toBe(expected[i].grossRevenue);
      expect(hourly[i].totalDiscount).toBe(expected[i].totalDiscount);
      expect(hourly[i].vatAmount).toBe(expected[i].vatAmount);
      expect(hourly[i].netRevenue).toBe(expected[i].netRevenue);
    }
  });

  it("Báo cáo 7: Hình thức Thanh toán (Payment Methods) khớp 100%", () => {
    const pm = calculatePaymentMethodsReport(goldenData.bills);
    const expected = goldenData.expectedResults.revenueByPaymentMethod;

    ["CASH", "TRANSFER_QR", "CARD"].forEach((method) => {
      expect(pm[method]).toBeDefined();
      expect(pm[method].billCount).toBe(expected[method].billCount);
      expect(pm[method].grossRevenue).toBe(expected[method].grossRevenue);
      expect(pm[method].totalDiscount).toBe(expected[method].totalDiscount);
      expect(pm[method].vatAmount).toBe(expected[method].vatAmount);
      expect(pm[method].finalAmount).toBe(expected[method].finalAmount);
    });
  });

  it("Báo cáo 8: Khuyến mãi & Voucher (Promotions & Discounts) khớp 100%", () => {
    const promo = calculatePromotionsReport(goldenData.bills);
    const expected = goldenData.expectedResults.promotionsReport;

    expect(promo.totalDiscountAmount).toBe(expected.totalDiscountAmount);

    // Campaigns
    expect(promo.campaigns.length).toBe(expected.campaigns.length);
    expected.campaigns.forEach((exp: CampaignReportItem) => {
      const match = promo.campaigns.find((c) => c.promoCode === exp.promoCode);
      expect(match).toBeDefined();
      expect(match!.usedCount).toBe(exp.usedCount);
      expect(match!.discountAmount).toBe(exp.discountAmount);
    });

    // Points
    expect(promo.pointsRedemption.usedCount).toBe(expected.pointsRedemption.usedCount);
    expect(promo.pointsRedemption.totalPointsUsed).toBe(expected.pointsRedemption.totalPointsUsed);
    expect(promo.pointsRedemption.discountAmount).toBe(expected.pointsRedemption.discountAmount);

    // Item Discounts
    expect(promo.itemDiscounts.appliedCount).toBe(expected.itemDiscounts.appliedCount);
    expect(promo.itemDiscounts.discountAmount).toBe(expected.itemDiscounts.discountAmount);
    expect(promo.itemDiscounts.details[0].productName).toBe(expected.itemDiscounts.details[0].productName);
    expect(promo.itemDiscounts.details[0].discountAmount).toBe(expected.itemDiscounts.details[0].discountAmount);
  });

  it("Báo cáo 9: Hủy món & Hủy đơn hàng (Cancellations & Audit) khớp 100%", () => {
    const cancellation = calculateCancellationReport(goldenData.bills);
    const expected = goldenData.expectedResults.cancellationReport;

    expect(cancellation.cancelledBillsCount).toBe(expected.cancelledBillsCount);
    expect(cancellation.totalLossValue).toBe(expected.totalLossValue);
    expect(cancellation.bills.length).toBe(expected.bills.length);

    expected.bills.forEach((exp: CancelledBillItem) => {
      const match = cancellation.bills.find((b) => b.billId === exp.billId);
      expect(match).toBeDefined();
      expect(match!.billCode).toBe(exp.billCode);
      expect(match!.tableName).toBe(exp.tableName);
      expect(match!.staffFullName).toBe(exp.staffFullName);
      expect(match!.subTotal).toBe(exp.subTotal);
      expect(match!.cancelledAt).toBe(exp.cancelledAt);
    });
  });

  it("Báo cáo 10: Bàn giao Ca & Chênh lệch Két (Cash Shift Variance) khớp 100%", () => {
    const shiftsReport = calculateCashShiftReport(goldenData.shifts, goldenData.bills);
    const expected = goldenData.expectedResults.cashShiftsReport;

    expect(shiftsReport.length).toBe(expected.length);
    for (let i = 0; i < expected.length; i++) {
      const actual = shiftsReport[i];
      const exp = expected[i];
      expect(actual.shiftId).toBe(exp.shiftId);
      expect(actual.shiftCode).toBe(exp.shiftCode);
      expect(actual.initialCash).toBe(exp.initialCash);
      expect(actual.cashIn).toBe(exp.cashIn);
      expect(actual.cashOut).toBe(exp.cashOut);
      expect(actual.cashSales).toBe(exp.cashSales);
      expect(actual.qrSales).toBe(exp.qrSales);
      expect(actual.cardSales).toBe(exp.cardSales);
      expect(actual.totalSales).toBe(exp.totalSales);
      expect(actual.refundCash).toBe(exp.refundCash);
      expect(actual.expectedCash).toBe(exp.expectedCash);
      expect(actual.actualCash).toBe(exp.actualCash);
      expect(actual.difference).toBe(exp.difference);
    }
  });

  it("Báo cáo 11: Lợi nhuận gộp & Giá vốn (Gross Profit & COGS) khớp tổng thể", () => {
    const gpReport = calculateGrossProfitReport(goldenData.bills, productsMap);
    expect(gpReport.summary.totalQuantity).toBe(42);
    expect(gpReport.summary.netRevenue).toBe(1162000);
    expect(gpReport.summary.totalCOGS).toBe(426000);
    expect(gpReport.summary.grossProfit).toBe(736000);
  });

  it("Báo cáo 12: Báo cáo Cuối ngày (End-Of-Day Z-Report) khớp cả 4 Tabs 100%", () => {
    const eod = generateEndOfDayZReport(
      goldenData.bills,
      goldenData.shifts,
      [],
      productsMap,
      {
        date: "2026-10-04",
        storeCode: "TRAM01",
        storeName: "POS Trạm - Trụ sở 01 (Đà Lạt)",
      }
    );
    const expected = goldenData.expectedResults.endOfDayReport;

    expect(eod.date).toBe(expected.date);
    expect(eod.storeCode).toBe(expected.storeCode);

    // Tab 1: Tổng hợp
    expect(eod.tab1_tongHop.grossRevenue).toBe(expected.tab1_tongHop.grossRevenue);
    expect(eod.tab1_tongHop.itemDiscounts).toBe(expected.tab1_tongHop.itemDiscounts);
    expect(eod.tab1_tongHop.billDiscounts).toBe(expected.tab1_tongHop.billDiscounts);
    expect(eod.tab1_tongHop.totalDiscount).toBe(expected.tab1_tongHop.totalDiscount);
    expect(eod.tab1_tongHop.afterDiscount).toBe(expected.tab1_tongHop.afterDiscount);
    expect(eod.tab1_tongHop.vatTotal).toBe(expected.tab1_tongHop.vatTotal);
    expect(eod.tab1_tongHop.netRevenue).toBe(expected.tab1_tongHop.netRevenue);
    expect(eod.tab1_tongHop.refundAmount).toBe(expected.tab1_tongHop.refundAmount);
    expect(eod.tab1_tongHop.netRevenueWithoutRefund).toBe(expected.tab1_tongHop.netRevenueWithoutRefund);
    expect(eod.tab1_tongHop.paidBillsCount).toBe(expected.tab1_tongHop.paidBillsCount);
    expect(eod.tab1_tongHop.avgRevenuePerBill).toBe(expected.tab1_tongHop.avgRevenuePerBill);
    expect(eod.tab1_tongHop.totalGuests).toBe(expected.tab1_tongHop.totalGuests);

    // Tab 2: Thu chi
    expect(eod.tab2_thuChi.cashSales).toBe(expected.tab2_thuChi.cashSales);
    expect(eod.tab2_thuChi.transferSales).toBe(expected.tab2_thuChi.transferSales);
    expect(eod.tab2_thuChi.cardSales).toBe(expected.tab2_thuChi.cardSales);
    expect(eod.tab2_thuChi.totalRevenue).toBe(expected.tab2_thuChi.totalRevenue);
    expect(eod.tab2_thuChi.cashInTotal).toBe(expected.tab2_thuChi.cashInTotal);
    expect(eod.tab2_thuChi.cashOutTotal).toBe(expected.tab2_thuChi.cashOutTotal);
    expect(eod.tab2_thuChi.refundTotal).toBe(expected.tab2_thuChi.refundTotal);

    // Tab 3: Hàng hóa
    expect(eod.tab3_hangHoa.totalItemsSold).toBe(expected.tab3_hangHoa.totalItemsSold);
    expect(eod.tab3_hangHoa.products.length).toBe(expected.tab3_hangHoa.products.length);

    // Tab 4: Phòng bàn
    expect(eod.tab4_phongBan.zones.length).toBe(expected.tab4_phongBan.zones.length);
    expected.tab4_phongBan.zones.forEach((expZ: { zone: string; billCount: number; netRevenue: number }) => {
      const match = eod.tab4_phongBan.zones.find((z) => z.zone === expZ.zone);
      expect(match).toBeDefined();
      expect(match!.billCount).toBe(expZ.billCount);
      expect(match!.netRevenue).toBe(expZ.netRevenue);
    });
  });

  it("Thuật toán khử trùng lặp đơn (deduplicateBills) giữ bản ghi mới nhất", () => {
    const rawList = [
      { id: "B1", billCode: "HD-01", closedAt: 100, totalAmount: 10000 },
      { id: "B1", billCode: "HD-01", closedAt: 200, totalAmount: 15000 }, // newer
      { id: "B2", billCode: "HD-02", closedAt: 150, totalAmount: 20000 },
    ];
    const result = deduplicateBills(rawList as unknown as HistoryOrder[]);
    expect(result.length).toBe(2);
    const b1 = result.find((b) => b.id === "B1");
    expect(b1?.totalAmount).toBe(15000);
  });
});

describe("Modules 4, 5, 6 Specific Edge Cases & Calculations", () => {
  it("Module 4 & 5: pointsDiscount and itemDiscounts are counted as DISCOUNT, NEVER as net revenue", () => {
    const bill: HistoryOrder = {
      id: "BILL_CUSTOM_01",
      billCode: "HD-CUST-01",
      orderCode: "OD-01",
      tableName: "Bàn 1",
      status: "PAID",
      closedAt: 1000,
      subTotal: 100000,
      items: [
        {
          id: 1,
          productId: 1,
          productName: "Cà phê",
          quantity: 2,
          price: 50000,
          discountAmount: 5000,
          discountPercent: 10,
        },
      ],
      discounts: [
        { promoId: "KM15K", promoCode: "KM15K", amount: 15000, description: "KM 15k" },
      ],
      pointsUsed: 20,
      pointsDiscount: 20000,
      totalDiscount: 45000, // 10k item + 15k voucher + 20k points
      vatRate: 10,
      vatAmount: 5500,
      finalAmount: 60500, // (100k - 45k) * 1.10 = 55k + 5.5k = 60.5k
      paymentMethod: "CASH",
    };

    const overview = calculateOverviewReport([bill]);
    expect(overview.grossRevenue).toBe(100000);
    expect(overview.itemDiscounts).toBe(10000);
    expect(overview.billDiscounts).toBe(15000);
    expect(overview.pointsDiscounts).toBe(20000);
    expect(overview.totalDiscount).toBe(45000);
    expect(overview.afterDiscount).toBe(55000);
    expect(overview.vatTotal).toBe(5500);
    expect(overview.netRevenue).toBe(60500);

    const promo = calculatePromotionsReport([bill]);
    expect(promo.totalDiscountAmount).toBe(45000);
    expect(promo.itemDiscounts.discountAmount).toBe(10000);
    expect(promo.campaigns[0].discountAmount).toBe(15000);
    expect(promo.pointsRedemption.discountAmount).toBe(20000);
  });

  it("Module 6: calculateCashShiftReport properly handles SPLIT payments (Cash + QR)", () => {
    const shift = {
      id: "SHIFT_SPLIT_01",
      shiftCode: "CA-SPLIT-01",
      initialCash: 1000000,
      openedAt: 100,
      closedAt: 500,
      status: "CLOSED" as const,
      actualCash: 1040000,
    };

    const bill: HistoryOrder = {
      id: "BILL_SPLIT_01",
      billCode: "HD-SPLIT-01",
      status: "PAID",
      shiftId: "SHIFT_SPLIT_01",
      closedAt: 200,
      finalAmount: 100000,
      paymentMethod: "SPLIT",
      paymentSplits: [
        { method: "CASH", amount: 40000 },
        { method: "TRANSFER_QR", amount: 60000 },
      ],
    };

    const reports = calculateCashShiftReport([shift], [bill]);
    expect(reports.length).toBe(1);
    const r = reports[0];

    // ONLY the 40k cash split should go to cashSales and expectedCash
    expect(r.cashSales).toBe(40000);
    expect(r.qrSales).toBe(60000);
    expect(r.totalSales).toBe(100000);
    expect(r.expectedCash).toBe(1040000); // 1,000,000 + 40,000
    expect(r.difference).toBe(0); // 1,040,000 - 1,040,000 = 0
  });
});

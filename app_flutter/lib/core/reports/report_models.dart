import '../../data/models/bill_model.dart';

enum PeriodType { day, week, month, year }

/// Model mở rộng từ BillModel cho báo cáo để đọc các trường guestCount, refundAmount, cancelReason
class ReportBillModel extends BillModel {
  final int guestCount;
  final int refundAmount;
  final String? cancelReason;
  final int? cancelledAt;

  ReportBillModel({
    required super.id,
    required super.billCode,
    super.orderCode,
    required super.tableName,
    required super.zone,
    required super.createdAt,
    super.closedAt,
    super.status,
    required super.staffUsername,
    required super.staffFullName,
    required super.items,
    required super.subTotal,
    super.discounts,
    super.totalDiscount,
    super.vatRate,
    super.vatAmount,
    required super.finalAmount,
    super.paymentMethod,
    super.notes,
    super.parentBillId,
    super.mergedTableNames,
    super.pointsUsed,
    super.pointsDiscount,
    super.customerId,
    super.customerName,
    super.customerPhone,
    super.shiftId,
    super.actionLogs,
    super.deletedItems,
    this.guestCount = 1,
    this.refundAmount = 0,
    this.cancelReason,
    this.cancelledAt,
  });

  factory ReportBillModel.fromMap(Map<dynamic, dynamic> map, String id) {
    final base = BillModel.fromMap(map, id);
    return ReportBillModel(
      id: base.id,
      billCode: base.billCode,
      orderCode: base.orderCode,
      tableName: base.tableName,
      zone: base.zone,
      createdAt: base.createdAt,
      closedAt: base.closedAt,
      status: base.status,
      staffUsername: base.staffUsername,
      staffFullName: base.staffFullName,
      items: base.items,
      subTotal: base.subTotal,
      discounts: base.discounts,
      totalDiscount: base.totalDiscount,
      vatRate: base.vatRate,
      vatAmount: base.vatAmount,
      finalAmount: base.finalAmount,
      paymentMethod: base.paymentMethod,
      notes: base.notes,
      parentBillId: base.parentBillId,
      mergedTableNames: base.mergedTableNames,
      pointsUsed: (map['pointsUsed'] as num?)?.toInt() ?? base.pointsUsed,
      pointsDiscount: base.pointsDiscount,
      customerId: base.customerId,
      customerName: base.customerName,
      customerPhone: base.customerPhone,
      shiftId: base.shiftId,
      actionLogs: base.actionLogs,
      deletedItems: base.deletedItems,
      guestCount: (map['guestCount'] as num?)?.toInt() ?? 1,
      refundAmount: (map['refundAmount'] as num?)?.toInt() ?? 0,
      cancelReason: map['cancelReason']?.toString(),
      cancelledAt: (map['cancelledAt'] as num?)?.toInt(),
    );
  }

  factory ReportBillModel.fromBillModel(
    BillModel base, {
    int guestCount = 1,
    int refundAmount = 0,
    String? cancelReason,
    int? cancelledAt,
  }) {
    return ReportBillModel(
      id: base.id,
      billCode: base.billCode,
      orderCode: base.orderCode,
      tableName: base.tableName,
      zone: base.zone,
      createdAt: base.createdAt,
      closedAt: base.closedAt,
      status: base.status,
      staffUsername: base.staffUsername,
      staffFullName: base.staffFullName,
      items: base.items,
      subTotal: base.subTotal,
      discounts: base.discounts,
      totalDiscount: base.totalDiscount,
      vatRate: base.vatRate,
      vatAmount: base.vatAmount,
      finalAmount: base.finalAmount,
      paymentMethod: base.paymentMethod,
      notes: base.notes,
      parentBillId: base.parentBillId,
      mergedTableNames: base.mergedTableNames,
      pointsUsed: base.pointsUsed,
      pointsDiscount: base.pointsDiscount,
      customerId: base.customerId,
      customerName: base.customerName,
      customerPhone: base.customerPhone,
      shiftId: base.shiftId,
      actionLogs: base.actionLogs,
      deletedItems: base.deletedItems,
      guestCount: guestCount,
      refundAmount: refundAmount,
      cancelReason: cancelReason,
      cancelledAt: cancelledAt,
    );
  }
}

/// 1. BÁO CÁO TỔNG QUAN QUẢN TRỊ (EXECUTIVE OVERVIEW)
class OverviewReportResult {
  final int totalBillsCount;
  final int paidBillsCount;
  final int cancelledBillsCount;
  final int refundedBillsCount;
  final int totalGuests;
  final int grossRevenue;
  final int itemDiscounts;
  final int billDiscounts;
  final int pointsDiscounts;
  final int totalDiscount;
  final int afterDiscount;
  final int vatTotal;
  final int netRevenue;
  final int refundAmount;
  final int netRevenueWithoutRefund;
  final int avgRevenuePerPaidBill;
  final int cancelledTotalValue;
  final int totalCostPrice;
  final int grossProfit;
  final double grossProfitMarginPercent;

  const OverviewReportResult({
    required this.totalBillsCount,
    required this.paidBillsCount,
    required this.cancelledBillsCount,
    required this.refundedBillsCount,
    required this.totalGuests,
    required this.grossRevenue,
    required this.itemDiscounts,
    required this.billDiscounts,
    required this.pointsDiscounts,
    required this.totalDiscount,
    required this.afterDiscount,
    required this.vatTotal,
    required this.netRevenue,
    required this.refundAmount,
    required this.netRevenueWithoutRefund,
    required this.avgRevenuePerPaidBill,
    required this.cancelledTotalValue,
    required this.totalCostPrice,
    required this.grossProfit,
    required this.grossProfitMarginPercent,
  });

  Map<String, dynamic> toMap() => {
    'totalBillsCount': totalBillsCount,
    'paidBillsCount': paidBillsCount,
    'cancelledBillsCount': cancelledBillsCount,
    'refundedBillsCount': refundedBillsCount,
    'totalGuests': totalGuests,
    'grossRevenue': grossRevenue,
    'itemDiscounts': itemDiscounts,
    'billDiscounts': billDiscounts,
    'pointsDiscounts': pointsDiscounts,
    'totalDiscount': totalDiscount,
    'afterDiscount': afterDiscount,
    'vatTotal': vatTotal,
    'netRevenue': netRevenue,
    'refundAmount': refundAmount,
    'netRevenueWithoutRefund': netRevenueWithoutRefund,
    'avgRevenuePerPaidBill': avgRevenuePerPaidBill,
    'cancelledTotalValue': cancelledTotalValue,
    'totalCostPrice': totalCostPrice,
    'grossProfit': grossProfit,
    'grossProfitMarginPercent': grossProfitMarginPercent,
  };
}

/// 2. HÌNH THỨC THANH TOÁN (PAYMENT METHODS)
class PaymentMethodSummary {
  final int billCount;
  final int grossRevenue;
  final int totalDiscount;
  final int vatAmount;
  final int finalAmount;

  const PaymentMethodSummary({
    required this.billCount,
    required this.grossRevenue,
    required this.totalDiscount,
    required this.vatAmount,
    required this.finalAmount,
  });

  Map<String, dynamic> toMap() => {
    'billCount': billCount,
    'grossRevenue': grossRevenue,
    'totalDiscount': totalDiscount,
    'vatAmount': vatAmount,
    'finalAmount': finalAmount,
  };
}

/// 3. BÁO CÁO THEO KHUNG GIỜ (HOURLY HEATMAP)
class HourlyReportItem {
  final int hour;
  final String hourLabel;
  final int billCount;
  final int grossRevenue;
  final int totalDiscount;
  final int vatAmount;
  final int netRevenue;

  const HourlyReportItem({
    required this.hour,
    required this.hourLabel,
    required this.billCount,
    required this.grossRevenue,
    required this.totalDiscount,
    required this.vatAmount,
    required this.netRevenue,
  });

  Map<String, dynamic> toMap() => {
    'hour': hour,
    'hourLabel': hourLabel,
    'billCount': billCount,
    'grossRevenue': grossRevenue,
    'totalDiscount': totalDiscount,
    'vatAmount': vatAmount,
    'netRevenue': netRevenue,
  };
}

/// 4. DOANH THU THEO KỲ (PERIOD REVENUE)
class PeriodRevenueItem {
  final String periodKey;
  final int billCount;
  final int grossRevenue;
  final int totalDiscount;
  final int netRevenue;
  final int cashRevenue;
  final int transferRevenue;
  final int cardRevenue;
  final double percentage;

  const PeriodRevenueItem({
    required this.periodKey,
    required this.billCount,
    required this.grossRevenue,
    required this.totalDiscount,
    required this.netRevenue,
    required this.cashRevenue,
    required this.transferRevenue,
    required this.cardRevenue,
    required this.percentage,
  });

  Map<String, dynamic> toMap() => {
    'periodKey': periodKey,
    'billCount': billCount,
    'grossRevenue': grossRevenue,
    'totalDiscount': totalDiscount,
    'netRevenue': netRevenue,
    'cashRevenue': cashRevenue,
    'transferRevenue': transferRevenue,
    'cardRevenue': cardRevenue,
    'percentage': percentage,
  };
}

/// 5. BÁO CÁO THEO NHÓM HÀNG (CATEGORY SALES)
class CategoryReportItem {
  final String category;
  final int quantity;
  final int grossRevenue;
  final int itemDiscount;
  final int netRevenue;
  final int costPrice;
  final int grossProfit;
  final double grossProfitMarginPercent;

  const CategoryReportItem({
    required this.category,
    required this.quantity,
    required this.grossRevenue,
    required this.itemDiscount,
    required this.netRevenue,
    required this.costPrice,
    required this.grossProfit,
    required this.grossProfitMarginPercent,
  });

  Map<String, dynamic> toMap() => {
    'category': category,
    'quantity': quantity,
    'grossRevenue': grossRevenue,
    'itemDiscount': itemDiscount,
    'netRevenue': netRevenue,
    'costPrice': costPrice,
    'grossProfit': grossProfit,
    'grossProfitMarginPercent': grossProfitMarginPercent,
  };
}

/// 6. BÁO CÁO MÓN ĂN / HÀNG HÓA (PRODUCT SALES)
class ProductReportItem {
  final int productId;
  final String productCode;
  final String productName;
  final String category;
  final String unit;
  final int basePrice;
  final int quantity;
  final int grossRevenue;
  final int itemDiscount;
  final int netRevenue;
  final int costPrice;
  final int grossProfit;
  final double grossProfitMarginPercent;

  const ProductReportItem({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.category,
    required this.unit,
    required this.basePrice,
    required this.quantity,
    required this.grossRevenue,
    required this.itemDiscount,
    required this.netRevenue,
    required this.costPrice,
    required this.grossProfit,
    required this.grossProfitMarginPercent,
  });

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productCode': productCode,
    'productName': productName,
    'category': category,
    'unit': unit,
    'basePrice': basePrice,
    'quantity': quantity,
    'grossRevenue': grossRevenue,
    'itemDiscount': itemDiscount,
    'netRevenue': netRevenue,
    'costPrice': costPrice,
    'grossProfit': grossProfit,
    'grossProfitMarginPercent': grossProfitMarginPercent,
  };
}

/// 7. BÁO CÁO THEO NHÂN VIÊN (STAFF PERFORMANCE)
class OrderStaffItem {
  final String staffUsername;
  final String staffFullName;
  final int itemsCount;
  final int grossRevenue;
  final int netRevenue;

  const OrderStaffItem({
    required this.staffUsername,
    required this.staffFullName,
    required this.itemsCount,
    required this.grossRevenue,
    required this.netRevenue,
  });

  Map<String, dynamic> toMap() => {
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    'itemsCount': itemsCount,
    'grossRevenue': grossRevenue,
    'netRevenue': netRevenue,
  };
}

class CashierStaffItem {
  final String staffUsername;
  final String staffFullName;
  final int billCount;
  final int netRevenue;

  const CashierStaffItem({
    required this.staffUsername,
    required this.staffFullName,
    required this.billCount,
    required this.netRevenue,
  });

  Map<String, dynamic> toMap() => {
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    'billCount': billCount,
    'netRevenue': netRevenue,
  };
}

class StaffPerformanceResult {
  final List<OrderStaffItem> orderStaff;
  final List<CashierStaffItem> cashierStaff;

  const StaffPerformanceResult({
    required this.orderStaff,
    required this.cashierStaff,
  });

  Map<String, dynamic> toMap() => {
    'orderStaff': orderStaff.map((e) => e.toMap()).toList(),
    'cashierStaff': cashierStaff.map((e) => e.toMap()).toList(),
  };
}

/// 8. BÁO CÁO KHUYẾN MÃI & VOUCHER (PROMOTIONS REPORT)
class PromoCampaignSummary {
  final String promoId;
  final String promoCode;
  final String name;
  final int usedCount;
  final int discountAmount;

  const PromoCampaignSummary({
    required this.promoId,
    required this.promoCode,
    required this.name,
    required this.usedCount,
    required this.discountAmount,
  });

  Map<String, dynamic> toMap() => {
    'promoId': promoId,
    'promoCode': promoCode,
    'name': name,
    'usedCount': usedCount,
    'discountAmount': discountAmount,
  };
}

class PointsRedemptionSummary {
  final int usedCount;
  final int totalPointsUsed;
  final int discountAmount;

  const PointsRedemptionSummary({
    required this.usedCount,
    required this.totalPointsUsed,
    required this.discountAmount,
  });

  Map<String, dynamic> toMap() => {
    'usedCount': usedCount,
    'totalPointsUsed': totalPointsUsed,
    'discountAmount': discountAmount,
  };
}

class ItemDiscountDetail {
  final int productId;
  final String productName;
  final int discountAmount;
  final int quantity;

  const ItemDiscountDetail({
    required this.productId,
    required this.productName,
    required this.discountAmount,
    required this.quantity,
  });

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'discountAmount': discountAmount,
    'quantity': quantity,
  };
}

class ItemDiscountsSummary {
  final int appliedCount;
  final int discountAmount;
  final List<ItemDiscountDetail> details;

  const ItemDiscountsSummary({
    required this.appliedCount,
    required this.discountAmount,
    required this.details,
  });

  Map<String, dynamic> toMap() => {
    'appliedCount': appliedCount,
    'discountAmount': discountAmount,
    'details': details.map((e) => e.toMap()).toList(),
  };
}

class PromotionsReportResult {
  final int totalDiscountAmount;
  final List<PromoCampaignSummary> campaigns;
  final PointsRedemptionSummary pointsRedemption;
  final ItemDiscountsSummary itemDiscounts;

  const PromotionsReportResult({
    required this.totalDiscountAmount,
    required this.campaigns,
    required this.pointsRedemption,
    required this.itemDiscounts,
  });

  Map<String, dynamic> toMap() => {
    'totalDiscountAmount': totalDiscountAmount,
    'campaigns': campaigns.map((e) => e.toMap()).toList(),
    'pointsRedemption': pointsRedemption.toMap(),
    'itemDiscounts': itemDiscounts.toMap(),
  };
}

/// 9. BÁO CÁO HỦY MÓN & HỦY ĐƠN HÀNG (CANCELLATION REPORT)
class CancelledBillItem {
  final String billId;
  final String billCode;
  final String tableName;
  final String staffFullName;
  final int cancelledAt;
  final String reason;
  final List<String> items;
  final int subTotal;

  const CancelledBillItem({
    required this.billId,
    required this.billCode,
    required this.tableName,
    required this.staffFullName,
    required this.cancelledAt,
    required this.reason,
    required this.items,
    required this.subTotal,
  });

  Map<String, dynamic> toMap() => {
    'billId': billId,
    'billCode': billCode,
    'tableName': tableName,
    'staffFullName': staffFullName,
    'cancelledAt': cancelledAt,
    'reason': reason,
    'items': items,
    'subTotal': subTotal,
  };
}

class CancellationReportResult {
  final int cancelledBillsCount;
  final int totalLossValue;
  final List<CancelledBillItem> bills;

  const CancellationReportResult({
    required this.cancelledBillsCount,
    required this.totalLossValue,
    required this.bills,
  });

  Map<String, dynamic> toMap() => {
    'cancelledBillsCount': cancelledBillsCount,
    'totalLossValue': totalLossValue,
    'bills': bills.map((e) => e.toMap()).toList(),
  };
}

/// 10. BÁO CÁO BÀN GIAO CA & CHÊNH LỆCH KÉT (CASH SHIFT VARIANCE)
class CashShiftAuditItem {
  final String shiftId;
  final String shiftCode;
  final String shiftName;
  final String staffUsername;
  final String staffFullName;
  final int openedAt;
  final int? closedAt;
  final int initialCash;
  final int cashIn;
  final int cashOut;
  final int cashSales;
  final int qrSales;
  final int cardSales;
  final int totalSales;
  final int refundCash;
  final int expectedCash;
  final int actualCash;
  final int difference;
  final String status;

  const CashShiftAuditItem({
    required this.shiftId,
    required this.shiftCode,
    required this.shiftName,
    required this.staffUsername,
    required this.staffFullName,
    required this.openedAt,
    this.closedAt,
    required this.initialCash,
    required this.cashIn,
    required this.cashOut,
    required this.cashSales,
    required this.qrSales,
    required this.cardSales,
    required this.totalSales,
    required this.refundCash,
    required this.expectedCash,
    required this.actualCash,
    required this.difference,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
    'shiftId': shiftId,
    'shiftCode': shiftCode,
    'shiftName': shiftName,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    'openedAt': openedAt,
    'closedAt': closedAt,
    'initialCash': initialCash,
    'cashIn': cashIn,
    'cashOut': cashOut,
    'cashSales': cashSales,
    'qrSales': qrSales,
    'cardSales': cardSales,
    'totalSales': totalSales,
    'refundCash': refundCash,
    'expectedCash': expectedCash,
    'actualCash': actualCash,
    'difference': difference,
    'status': status,
  };
}

/// 11. BÁO CÁO LỢI NHUẬN GỘP & GIÁ VỐN (GROSS PROFIT & COGS)
class GrossProfitReportResult {
  final int totalRevenue;
  final int totalCostPrice;
  final int grossProfit;
  final double grossProfitMarginPercent;
  final List<ProductReportItem> items;

  const GrossProfitReportResult({
    required this.totalRevenue,
    required this.totalCostPrice,
    required this.grossProfit,
    required this.grossProfitMarginPercent,
    required this.items,
  });

  Map<String, dynamic> toMap() => {
    'totalRevenue': totalRevenue,
    'totalCostPrice': totalCostPrice,
    'grossProfit': grossProfit,
    'grossProfitMarginPercent': grossProfitMarginPercent,
    'items': items.map((e) => e.toMap()).toList(),
  };
}

/// 12. BÁO CÁO CUỐI NGÀY (END-OF-DAY Z-REPORT)
class EndOfDayTab1TongHop {
  final int grossRevenue;
  final int itemDiscounts;
  final int billDiscounts;
  final int totalDiscount;
  final int afterDiscount;
  final int vatTotal;
  final int netRevenue;
  final int refundAmount;
  final int netRevenueWithoutRefund;
  final int paidBillsCount;
  final int avgRevenuePerBill;
  final int totalGuests;
  /// Món đã lưu bị xóa (từ deletedItems của HĐ PAID + CANCELLED trong kỳ)
  final int deletedItemsCount;
  final int deletedItemsAmount;
  /// Hóa đơn hủy trong kỳ (giá trị = tổng tiền hàng subTotal)
  final int cancelledBillsCount;
  final int cancelledBillsAmount;

  const EndOfDayTab1TongHop({
    required this.grossRevenue,
    required this.itemDiscounts,
    required this.billDiscounts,
    required this.totalDiscount,
    required this.afterDiscount,
    required this.vatTotal,
    required this.netRevenue,
    required this.refundAmount,
    required this.netRevenueWithoutRefund,
    required this.paidBillsCount,
    required this.avgRevenuePerBill,
    required this.totalGuests,
    this.deletedItemsCount = 0,
    this.deletedItemsAmount = 0,
    this.cancelledBillsCount = 0,
    this.cancelledBillsAmount = 0,
  });

  Map<String, dynamic> toMap() => {
    'grossRevenue': grossRevenue,
    'itemDiscounts': itemDiscounts,
    'billDiscounts': billDiscounts,
    'totalDiscount': totalDiscount,
    'afterDiscount': afterDiscount,
    'vatTotal': vatTotal,
    'netRevenue': netRevenue,
    'refundAmount': refundAmount,
    'netRevenueWithoutRefund': netRevenueWithoutRefund,
    'paidBillsCount': paidBillsCount,
    'avgRevenuePerBill': avgRevenuePerBill,
    'totalGuests': totalGuests,
    'deletedItemsCount': deletedItemsCount,
    'deletedItemsAmount': deletedItemsAmount,
    'cancelledBillsCount': cancelledBillsCount,
    'cancelledBillsAmount': cancelledBillsAmount,
  };
}

class EndOfDayTab2ThuChi {
  final int cashSales;
  final int transferSales;
  final int cardSales;
  final int totalRevenue;
  final int cashInTotal;
  final int cashOutTotal;
  final int refundTotal;

  const EndOfDayTab2ThuChi({
    required this.cashSales,
    required this.transferSales,
    required this.cardSales,
    required this.totalRevenue,
    required this.cashInTotal,
    required this.cashOutTotal,
    required this.refundTotal,
  });

  Map<String, dynamic> toMap() => {
    'cashSales': cashSales,
    'transferSales': transferSales,
    'cardSales': cardSales,
    'totalRevenue': totalRevenue,
    'cashInTotal': cashInTotal,
    'cashOutTotal': cashOutTotal,
    'refundTotal': refundTotal,
  };
}

class EndOfDayTab3HangHoa {
  final int totalItemsSold;
  final List<ProductReportItem> products;

  const EndOfDayTab3HangHoa({
    required this.totalItemsSold,
    required this.products,
  });

  Map<String, dynamic> toMap() => {
    'totalItemsSold': totalItemsSold,
    'products': products.map((e) => e.toMap()).toList(),
  };
}

class ZoneReportItem {
  final String zone;
  final int billCount;
  final int netRevenue;

  const ZoneReportItem({
    required this.zone,
    required this.billCount,
    required this.netRevenue,
  });

  Map<String, dynamic> toMap() => {
    'zone': zone,
    'billCount': billCount,
    'netRevenue': netRevenue,
  };
}

class EndOfDayTab4PhongBan {
  final List<ZoneReportItem> zones;

  const EndOfDayTab4PhongBan({
    required this.zones,
  });

  Map<String, dynamic> toMap() => {
    'zones': zones.map((e) => e.toMap()).toList(),
  };
}

class EndOfDayReportData {
  final String date;
  final String storeCode;
  final String storeName;
  final EndOfDayTab1TongHop tab1TongHop;
  final EndOfDayTab2ThuChi tab2ThuChi;
  final EndOfDayTab3HangHoa tab3HangHoa;
  final EndOfDayTab4PhongBan tab4PhongBan;

  const EndOfDayReportData({
    required this.date,
    required this.storeCode,
    required this.storeName,
    required this.tab1TongHop,
    required this.tab2ThuChi,
    required this.tab3HangHoa,
    required this.tab4PhongBan,
  });

  Map<String, dynamic> toMap() => {
    'date': date,
    'storeCode': storeCode,
    'storeName': storeName,
    'tab1_tongHop': tab1TongHop.toMap(),
    'tab2_thuChi': tab2ThuChi.toMap(),
    'tab3_hangHoa': tab3HangHoa.toMap(),
    'tab4_phongBan': tab4PhongBan.toMap(),
  };
}

/// 13. BÁO CÁO THEO CHƯƠNG TRÌNH KHUYẾN MÃI (CAMPAIGN REPORT)
/// Gom theo campaignId (dữ liệu cũ: promoId → promoCode → tên).
class CampaignBillRef {
  final String billId;
  final String billCode;
  final int time;
  final String tableName;
  final String voucherCode;
  final int discount;
  final int billFinalAmount;

  const CampaignBillRef({
    required this.billId,
    required this.billCode,
    required this.time,
    required this.tableName,
    required this.voucherCode,
    required this.discount,
    required this.billFinalAmount,
  });

  Map<String, dynamic> toMap() => {
    'billId': billId,
    'billCode': billCode,
    'time': time,
    'tableName': tableName,
    'voucherCode': voucherCode,
    'discount': discount,
    'billFinalAmount': billFinalAmount,
  };
}

class CampaignReportItem {
  final String key;
  final String campaignId;
  final String name;
  final String code;
  final String type;
  final int billCount;
  final int discountAmount;
  final int revenue;
  final int voucherCodesUsed;
  final List<CampaignBillRef> bills;

  const CampaignReportItem({
    required this.key,
    required this.campaignId,
    required this.name,
    required this.code,
    required this.type,
    required this.billCount,
    required this.discountAmount,
    required this.revenue,
    required this.voucherCodesUsed,
    required this.bills,
  });

  Map<String, dynamic> toMap() => {
    'key': key,
    'campaignId': campaignId,
    'name': name,
    'code': code,
    'type': type,
    'billCount': billCount,
    'discountAmount': discountAmount,
    'revenue': revenue,
    'voucherCodesUsed': voucherCodesUsed,
    'bills': bills.map((e) => e.toMap()).toList(),
  };
}

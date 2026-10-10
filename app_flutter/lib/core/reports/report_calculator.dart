// Pure Dart report calculations for POS Trạm Financial & Operations Reports
// Không import Flutter framework, phục vụ kiểm thử và tính toán độc lập

import '../../data/models/bill_model.dart';
import '../domain/deleted_items.dart';
import '../../data/models/order_item_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/shift_model.dart';
import '../../data/models/table_model.dart';
import 'report_date_utils.dart';
import 'report_models.dart';

class ReportCalculator {
  /// Default topping cost mapping (trường hợp catalogue không truyền riêng)
  static const Map<String, int> defaultToppingCosts = {
    'Trân châu trắng': 1500,
    'Kem Cheese': 2500,
  };

  /// 4.2. Khử trùng lặp ID hóa đơn (Deduplication Algorithm)
  static List<BillModel> deduplicateBills(List<BillModel> rawList) {
    final Map<String, BillModel> map = {};
    for (final b in rawList) {
      if (b.id.isEmpty) continue;
      if (!map.containsKey(b.id)) {
        map[b.id] = b;
      } else {
        final existing = map[b.id]!;
        final exTime = (existing.closedAt != null && existing.closedAt! > 0)
            ? existing.closedAt!
            : existing.createdAt;
        final newTime = (b.closedAt != null && b.closedAt! > 0)
            ? b.closedAt!
            : b.createdAt;
        if (newTime >= exTime) {
          map[b.id] = b;
        }
      }
    }
    return map.values.toList();
  }

  /// Tìm ProductModel theo productId hoặc tên món
  static ProductModel? findProduct(
    OrderItemModel item,
    Map<int, ProductModel>? productsMap,
  ) {
    if (productsMap == null) return null;
    if (productsMap.containsKey(item.productId)) {
      return productsMap[item.productId];
    }
    for (final p in productsMap.values) {
      if (p.name == item.name || (p.code.isNotEmpty && p.code == item.name)) {
        return p;
      }
    }
    return null;
  }

  /// Tính giá vốn của 1 dòng món (Line Cost Price)
  static int getLineCostPrice(
    OrderItemModel item, {
    Map<int, ProductModel>? productsMap,
    Map<String, int>? toppingCosts,
  }) {
    final p = findProduct(item, productsMap);
    final pCost = p?.costPrice ?? 0;
    int topCost = 0;
    for (final t in item.selectedToppings) {
      topCost += toppingCosts?[t] ?? defaultToppingCosts[t] ?? 0;
    }
    return (pCost + topCost) * item.quantity;
  }

  static int getGuestCount(BillModel b) {
    if (b is ReportBillModel) return b.guestCount;
    return 1;
  }

  static int getRefundAmount(BillModel b) {
    if (b is ReportBillModel) return b.refundAmount;
    return 0;
  }

  static String? getCancelReason(BillModel b) {
    if (b is ReportBillModel && b.cancelReason != null) return b.cancelReason;
    return b.notes.isNotEmpty ? b.notes : null;
  }

  static int? getCancelledAt(BillModel b) {
    if (b is ReportBillModel && b.cancelledAt != null) return b.cancelledAt;
    return (b.closedAt != null && b.closedAt! > 0) ? b.closedAt : b.createdAt;
  }

  /// BÁO CÁO 1: BÁO CÁO TỔNG QUAN QUẢN TRỊ (EXECUTIVE OVERVIEW)
  static OverviewReportResult calculateOverviewReport(
    List<BillModel> rawBills, {
    int? refundAmount,
    Map<int, ProductModel>? productsMap,
    Map<String, int>? toppingCosts,
  }) {
    final bills = deduplicateBills(rawBills);
    final totalBillsCount = bills.length;
    final paidBills = bills.where((b) => b.status == 'PAID').toList();
    final cancelledBills = bills.where((b) => b.status == 'CANCELLED').toList();
    final refundedBills = bills.where((b) => b.status == 'REFUNDED').toList();

    final paidBillsCount = paidBills.length;
    final cancelledBillsCount = cancelledBills.length;
    final refundedBillsCount = refundedBills.length;

    final totalGuests = paidBills.fold<int>(0, (sum, b) => sum + getGuestCount(b));
    final grossRevenue = paidBills.fold<int>(0, (sum, b) => sum + b.subTotal);

    final itemDiscounts = paidBills.fold<int>(
      0,
      (sum, b) =>
          sum +
          b.items.fold<int>(0, (iSum, it) => iSum + it.lineDiscountTotal),
    );

    final billDiscounts = paidBills.fold<int>(
      0,
      (sum, b) =>
          sum +
          b.discounts.fold<int>(0, (dSum, d) => dSum + d.amount),
    );

    final pointsDiscounts = paidBills.fold<int>(
      0,
      (sum, b) => sum + b.pointsDiscount,
    );

    final totalDiscount = itemDiscounts + billDiscounts + pointsDiscounts;
    final afterDiscount = grossRevenue - totalDiscount;
    final vatTotal = paidBills.fold<int>(0, (sum, b) => sum + b.vatAmount);
    final netRevenue = paidBills.fold<int>(0, (sum, b) => sum + b.finalAmount);

    final totalRefund = refundAmount ??
        refundedBills.fold<int>(0, (sum, b) => sum + getRefundAmount(b));
    final netRevenueWithoutRefund = netRevenue - totalRefund;

    final avgRevenuePerPaidBill = paidBillsCount == 0
        ? 0
        : (netRevenue / paidBillsCount).round();

    final cancelledTotalValue = cancelledBills.fold<int>(
      0,
      (sum, b) => sum + b.subTotal,
    );

    final totalCostPrice = paidBills.fold<int>(
      0,
      (sum, b) =>
          sum +
          b.items.fold<int>(
            0,
            (iSum, it) =>
                iSum +
                getLineCostPrice(
                  it,
                  productsMap: productsMap,
                  toppingCosts: toppingCosts,
                ),
          ),
    );

    final grossProfit = afterDiscount - totalCostPrice;
    final grossProfitMarginPercent = afterDiscount == 0
        ? 0.0
        : ((grossProfit / afterDiscount) * 10000).round() / 100.0;

    return OverviewReportResult(
      totalBillsCount: totalBillsCount,
      paidBillsCount: paidBillsCount,
      cancelledBillsCount: cancelledBillsCount,
      refundedBillsCount: refundedBillsCount,
      totalGuests: totalGuests,
      grossRevenue: grossRevenue,
      itemDiscounts: itemDiscounts,
      billDiscounts: billDiscounts,
      pointsDiscounts: pointsDiscounts,
      totalDiscount: totalDiscount,
      afterDiscount: afterDiscount,
      vatTotal: vatTotal,
      netRevenue: netRevenue,
      refundAmount: totalRefund,
      netRevenueWithoutRefund: netRevenueWithoutRefund,
      avgRevenuePerPaidBill: avgRevenuePerPaidBill,
      cancelledTotalValue: cancelledTotalValue,
      totalCostPrice: totalCostPrice,
      grossProfit: grossProfit,
      grossProfitMarginPercent: grossProfitMarginPercent,
    );
  }

  /// BÁO CÁO 2: BÁO CÁO HÌNH THỨC THANH TOÁN (PAYMENT METHODS)
  static Map<String, PaymentMethodSummary> calculatePaymentMethodsReport(
    List<BillModel> rawBills,
  ) {
    final bills = deduplicateBills(rawBills).where((b) => b.status == 'PAID');
    final Map<String, List<BillModel>> grouped = {
      'CASH': [],
      'TRANSFER_QR': [],
      'CARD': [],
    };

    for (final b in bills) {
      final method = b.paymentMethod.toUpperCase();
      if (method.contains('CASH') || method.contains('TIỀN MẶT')) {
        grouped['CASH']!.add(b);
      } else if (method.contains('TRANSFER') || method.contains('QR') || method.contains('CHUYỂN KHOẢN')) {
        grouped['TRANSFER_QR']!.add(b);
      } else if (method.contains('CARD') || method.contains('THẺ')) {
        grouped['CARD']!.add(b);
      } else {
        grouped.putIfAbsent(b.paymentMethod, () => []).add(b);
      }
    }

    final Map<String, PaymentMethodSummary> result = {};
    for (final entry in grouped.entries) {
      final list = entry.value;
      result[entry.key] = PaymentMethodSummary(
        billCount: list.length,
        grossRevenue: list.fold<int>(0, (sum, b) => sum + b.subTotal),
        totalDiscount: list.fold<int>(0, (sum, b) => sum + b.totalDiscount),
        vatAmount: list.fold<int>(0, (sum, b) => sum + b.vatAmount),
        finalAmount: list.fold<int>(0, (sum, b) => sum + b.finalAmount),
      );
    }
    return result;
  }

  /// BÁO CÁO 3: BÁO CÁO THEO KHUNG GIỜ (HOURLY HEATMAP)
  static List<HourlyReportItem> calculateHourlyReport(List<BillModel> rawBills) {
    final paidBills = deduplicateBills(rawBills).where((b) => b.status == 'PAID');
    final Map<int, List<BillModel>> hourlyMap = {};
    for (int h = 0; h < 24; h++) {
      hourlyMap[h] = [];
    }

    for (final b in paidBills) {
      final dt = ReportDateUtils.getBillDateTime(b.closedAt, b.createdAt, b.status);
      hourlyMap[dt.hour]?.add(b);
    }

    final List<HourlyReportItem> list = [];
    for (int h = 0; h < 24; h++) {
      final bList = hourlyMap[h]!;
      final hStr = h.toString().padLeft(2, '0');
      list.add(HourlyReportItem(
        hour: h,
        hourLabel: '$hStr:00 - $hStr:59',
        billCount: bList.length,
        grossRevenue: bList.fold<int>(0, (sum, b) => sum + b.subTotal),
        totalDiscount: bList.fold<int>(0, (sum, b) => sum + b.totalDiscount),
        vatAmount: bList.fold<int>(0, (sum, b) => sum + b.vatAmount),
        netRevenue: bList.fold<int>(0, (sum, b) => sum + b.finalAmount),
      ));
    }
    return list;
  }

  /// BÁO CÁO DOANH THU THEO KỲ (REVENUE BY PERIOD)
  static List<PeriodRevenueItem> calculateRevenueByPeriod(
    List<BillModel> rawBills,
    PeriodType period,
  ) {
    final paidBills = deduplicateBills(rawBills).where((b) => b.status == 'PAID').toList();
    final Map<String, List<BillModel>> grouped = {};

    for (final b in paidBills) {
      final dt = ReportDateUtils.getBillDateTime(b.closedAt, b.createdAt, b.status);
      String key;
      switch (period) {
        case PeriodType.day:
          key = ReportDateUtils.formatDisplayDate(dt);
          break;
        case PeriodType.week:
          // Tuần: ngày bắt đầu tuần
          final monday = dt.subtract(Duration(days: dt.weekday - 1));
          key = 'Tuần từ ${ReportDateUtils.formatDisplayDate(monday)}';
          break;
        case PeriodType.month:
          key = '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
          break;
        case PeriodType.year:
          key = dt.year.toString();
          break;
      }
      grouped.putIfAbsent(key, () => []).add(b);
    }

    final totalAllNet = paidBills.fold<int>(0, (sum, b) => sum + b.finalAmount);
    final List<PeriodRevenueItem> items = [];

    for (final entry in grouped.entries) {
      final list = entry.value;
      final netRev = list.fold<int>(0, (sum, b) => sum + b.finalAmount);
      int cash = 0;
      int transfer = 0;
      int card = 0;
      for (final b in list) {
        final m = b.paymentMethod.toUpperCase();
        if (m.contains('CASH') || m.contains('TIỀN MẶT')) {
          cash += b.finalAmount;
        } else if (m.contains('TRANSFER') || m.contains('QR') || m.contains('CHUYỂN KHOẢN')) {
          transfer += b.finalAmount;
        } else {
          card += b.finalAmount;
        }
      }
      final pct = totalAllNet == 0
          ? 0.0
          : ((netRev / totalAllNet) * 10000).round() / 100.0;

      items.add(PeriodRevenueItem(
        periodKey: entry.key,
        billCount: list.length,
        grossRevenue: list.fold<int>(0, (sum, b) => sum + b.subTotal),
        totalDiscount: list.fold<int>(0, (sum, b) => sum + b.totalDiscount),
        netRevenue: netRev,
        cashRevenue: cash,
        transferRevenue: transfer,
        cardRevenue: card,
        percentage: pct,
      ));
    }

    return items;
  }

  /// BÁO CÁO 4: BÁO CÁO THEO NHÓM HÀNG / DANH MỤC (CATEGORY SALES)
  static List<CategoryReportItem> calculateCategoryReport(
    List<BillModel> rawBills, {
    Map<int, ProductModel>? productsMap,
    Map<String, int>? toppingCosts,
  }) {
    final paidBills = deduplicateBills(rawBills).where((b) => b.status == 'PAID');
    final Map<String, _CatAccumulator> accMap = {};

    for (final b in paidBills) {
      for (final it in b.items) {
        final p = findProduct(it, productsMap);
        final cat = (p != null && p.category.isNotEmpty) ? p.category : 'Khác';
        accMap.putIfAbsent(cat, () => _CatAccumulator(category: cat));

        final acc = accMap[cat]!;
        final lineCost = getLineCostPrice(it, productsMap: productsMap, toppingCosts: toppingCosts);
        final lineGross = it.unitPrice * it.quantity;

        acc.quantity += it.quantity;
        acc.grossRevenue += lineGross;
        acc.itemDiscount += it.lineDiscountTotal;
        acc.costPrice += lineCost;
      }
    }

    final list = accMap.values.map((a) {
      final net = a.grossRevenue - a.itemDiscount;
      final profit = net - a.costPrice;
      final margin = net == 0 ? 0.0 : ((profit / net) * 10000).round() / 100.0;
      return CategoryReportItem(
        category: a.category,
        quantity: a.quantity,
        grossRevenue: a.grossRevenue,
        itemDiscount: a.itemDiscount,
        netRevenue: net,
        costPrice: a.costPrice,
        grossProfit: profit,
        grossProfitMarginPercent: margin,
      );
    }).toList();

    // Sắp xếp theo số lượng bán giảm dần
    list.sort((a, b) => b.quantity.compareTo(a.quantity));
    return list;
  }

  /// BÁO CÁO 5: BÁO CÁO MÓN ĂN / HÀNG HÓA (PRODUCT SALES PERFORMANCE)
  static List<ProductReportItem> calculateProductReport(
    List<BillModel> rawBills, {
    Map<int, ProductModel>? productsMap,
    Map<String, int>? toppingCosts,
  }) {
    final paidBills = deduplicateBills(rawBills).where((b) => b.status == 'PAID');
    final Map<int, _ProdAccumulator> accMap = {};

    for (final b in paidBills) {
      for (final it in b.items) {
        final p = findProduct(it, productsMap);
        final prodId = (p != null && p.id > 0) ? p.id : it.productId;
        final prodCode = (p != null && p.code.isNotEmpty) ? p.code : (it.name);
        final prodName = (p != null && p.name.isNotEmpty) ? p.name : it.name;
        final category = (p != null && p.category.isNotEmpty) ? p.category : 'Khác';
        final unit = (p != null && p.unit.isNotEmpty) ? p.unit : 'Ly';
        final basePrice = (p != null && p.price > 0) ? p.price : it.price;

        accMap.putIfAbsent(prodId, () => _ProdAccumulator(
          productId: prodId,
          productCode: prodCode,
          productName: prodName,
          category: category,
          unit: unit,
          basePrice: basePrice,
        ));

        final acc = accMap[prodId]!;
        final lineCost = getLineCostPrice(it, productsMap: productsMap, toppingCosts: toppingCosts);
        final lineGross = it.unitPrice * it.quantity;

        acc.quantity += it.quantity;
        acc.grossRevenue += lineGross;
        acc.itemDiscount += it.lineDiscountTotal;
        acc.costPrice += lineCost;
      }
    }

    final list = accMap.values.map((a) {
      final net = a.grossRevenue - a.itemDiscount;
      final profit = net - a.costPrice;
      final margin = net == 0 ? 0.0 : ((profit / net) * 10000).round() / 100.0;
      return ProductReportItem(
        productId: a.productId,
        productCode: a.productCode,
        productName: a.productName,
        category: a.category,
        unit: a.unit,
        basePrice: a.basePrice,
        quantity: a.quantity,
        grossRevenue: a.grossRevenue,
        itemDiscount: a.itemDiscount,
        netRevenue: net,
        costPrice: a.costPrice,
        grossProfit: profit,
        grossProfitMarginPercent: margin,
      );
    }).toList();

    // Sắp xếp theo productId tăng dần mặc định
    list.sort((a, b) => a.productId.compareTo(b.productId));
    return list;
  }

  /// BÁO CÁO 6: BÁO CÁO THEO NHÂN VIÊN (STAFF PERFORMANCE)
  static StaffPerformanceResult calculateStaffPerformance(List<BillModel> rawBills) {
    final paidBills = deduplicateBills(rawBills).where((b) => b.status == 'PAID');
    final Map<String, _OrderStaffAccumulator> orderMap = {};
    final Map<String, _CashierStaffAccumulator> cashierMap = {};

    for (final b in paidBills) {
      // Cashier
      final cUser = b.staffUsername.isNotEmpty ? b.staffUsername : 'unknown';
      final cName = b.staffFullName.isNotEmpty ? b.staffFullName : cUser;
      cashierMap.putIfAbsent(cUser, () => _CashierStaffAccumulator(staffUsername: cUser, staffFullName: cName));
      cashierMap[cUser]!.billCount += 1;
      cashierMap[cUser]!.netRevenue += b.finalAmount;

      // Order staff per item
      for (final it in b.items) {
        final oUser = it.orderedBy.isNotEmpty ? it.orderedBy : b.staffUsername;
        final oName = it.orderedByName.isNotEmpty ? it.orderedByName : b.staffFullName;
        orderMap.putIfAbsent(oUser, () => _OrderStaffAccumulator(staffUsername: oUser, staffFullName: oName));

        final oAcc = orderMap[oUser]!;
        final gross = it.unitPrice * it.quantity;
        oAcc.itemsCount += it.quantity;
        oAcc.grossRevenue += gross;
        oAcc.netRevenue += (gross - it.lineDiscountTotal);
      }
    }

    final orderStaffList = orderMap.values.map((a) => OrderStaffItem(
      staffUsername: a.staffUsername,
      staffFullName: a.staffFullName,
      itemsCount: a.itemsCount,
      grossRevenue: a.grossRevenue,
      netRevenue: a.netRevenue,
    )).toList();
    orderStaffList.sort((a, b) => b.grossRevenue.compareTo(a.grossRevenue));

    final cashierStaffList = cashierMap.values.map((a) => CashierStaffItem(
      staffUsername: a.staffUsername,
      staffFullName: a.staffFullName,
      billCount: a.billCount,
      netRevenue: a.netRevenue,
    )).toList();
    cashierStaffList.sort((a, b) {
      final cmp = b.billCount.compareTo(a.billCount);
      if (cmp != 0) return cmp;
      return b.netRevenue.compareTo(a.netRevenue);
    });

    return StaffPerformanceResult(
      orderStaff: orderStaffList,
      cashierStaff: cashierStaffList,
    );
  }

  static const Map<String, String> defaultCampaignNames = {
    'PROMO_CHAOBAN': 'Chào bạn mới giảm 20k',
    'CHAOBAN20': 'Chào bạn mới giảm 20k',
    'PROMO_TRIAN': 'Tri ân khách hàng giảm 10k',
    'TRIAN10K': 'Tri ân khách hàng giảm 10k',
  };

  /// BÁO CÁO 7: BÁO CÁO KHUYẾN MÃI & VOUCHER (PROMOTIONS REPORT)
  static PromotionsReportResult calculatePromotionsReport(
    List<BillModel> rawBills, {
    Map<String, String>? campaignNames,
  }) {
    final paidBills = deduplicateBills(rawBills).where((b) => b.status == 'PAID');
    final Map<String, _CampaignAccumulator> campaignMap = {};
    int pointsUsedCount = 0;
    int totalPointsUsed = 0;
    int pointsDiscountAmount = 0;

    int itemDiscountAppliedCount = 0;
    int itemDiscountAmountTotal = 0;
    final Map<int, _ItemDiscountAccumulator> itemDiscMap = {};

    for (final b in paidBills) {
      // Bill campaigns
      for (final d in b.discounts) {
        final code = d.promoCode ?? '';
        final id = d.promoId ?? '';
        final key = code.isNotEmpty ? code : (id.isNotEmpty ? id : d.description);
        final resolvedName = campaignNames?[code] ??
            campaignNames?[id] ??
            defaultCampaignNames[code] ??
            defaultCampaignNames[id] ??
            d.description;

        campaignMap.putIfAbsent(key, () => _CampaignAccumulator(
          promoId: id,
          promoCode: code,
          name: resolvedName,
        ));
        campaignMap[key]!.usedCount += 1;
        campaignMap[key]!.discountAmount += d.amount;
      }

      // Points
      if (b.pointsDiscount > 0) {
        pointsUsedCount += 1;
        pointsDiscountAmount += b.pointsDiscount;
        totalPointsUsed += b.pointsUsed > 0 ? b.pointsUsed : (b.pointsDiscount ~/ 100);
      }

      // Item discounts
      for (final it in b.items) {
        if (it.lineDiscountTotal > 0) {
          itemDiscountAppliedCount += 1;
          itemDiscountAmountTotal += it.lineDiscountTotal;
          itemDiscMap.putIfAbsent(it.productId, () => _ItemDiscountAccumulator(
            productId: it.productId,
            productName: it.name,
          ));
          itemDiscMap[it.productId]!.discountAmount += it.lineDiscountTotal;
          itemDiscMap[it.productId]!.quantity += it.discountedQuantity;
        }
      }
    }

    final campaignList = campaignMap.values.map((c) => PromoCampaignSummary(
      promoId: c.promoId,
      promoCode: c.promoCode,
      name: c.name,
      usedCount: c.usedCount,
      discountAmount: c.discountAmount,
    )).toList();

    final itemDetails = itemDiscMap.values.map((it) => ItemDiscountDetail(
      productId: it.productId,
      productName: it.productName,
      discountAmount: it.discountAmount,
      quantity: it.quantity,
    )).toList();

    final totalDiscount = campaignList.fold<int>(0, (sum, c) => sum + c.discountAmount) +
        pointsDiscountAmount +
        itemDiscountAmountTotal;

    return PromotionsReportResult(
      totalDiscountAmount: totalDiscount,
      campaigns: campaignList,
      pointsRedemption: PointsRedemptionSummary(
        usedCount: pointsUsedCount,
        totalPointsUsed: totalPointsUsed,
        discountAmount: pointsDiscountAmount,
      ),
      itemDiscounts: ItemDiscountsSummary(
        appliedCount: itemDiscountAppliedCount,
        discountAmount: itemDiscountAmountTotal,
        details: itemDetails,
      ),
    );
  }

  /// BÁO CÁO 8: BÁO CÁO HỦY MÓN & HỦY ĐƠN HÀNG (CANCELLATION REPORT)
  static CancellationReportResult calculateCancellationReport(List<BillModel> rawBills) {
    final bills = deduplicateBills(rawBills);
    final cancelledBills = bills.where((b) => b.status == 'CANCELLED').toList();

    final List<CancelledBillItem> items = [];
    for (final b in cancelledBills) {
      final formattedItems = b.items.map((it) => '${it.name} x${it.quantity}').toList();
      final reason = getCancelReason(b) ?? (b.notes.isNotEmpty ? b.notes : 'Hủy đơn hàng');
      final cancelledTime = getCancelledAt(b) ?? b.createdAt;

      items.add(CancelledBillItem(
        billId: b.id,
        billCode: b.billCode,
        tableName: b.tableName,
        staffFullName: b.staffFullName,
        cancelledAt: cancelledTime,
        reason: reason,
        items: formattedItems,
        subTotal: b.subTotal,
      ));
    }

    final totalLoss = items.fold<int>(0, (sum, b) => sum + b.subTotal);

    return CancellationReportResult(
      cancelledBillsCount: items.length,
      totalLossValue: totalLoss,
      bills: items,
    );
  }

  /// BÁO CÁO 9: BÁO CÁO BÀN GIAO CA & CHÊNH LỆCH KÉT (CASH SHIFT VARIANCE)
  static List<CashShiftAuditItem> calculateCashShiftReport(
    List<CashShiftModel> shifts,
    List<BillModel> rawBills,
  ) {
    final bills = deduplicateBills(rawBills);
    final List<CashShiftAuditItem> result = [];

    for (final s in shifts) {
      final shiftBills = bills.where((b) => b.shiftId == s.id || b.shiftId == s.shiftCode).toList();
      final paidShiftBills = shiftBills.where((b) => b.status == 'PAID');
      final refundedShiftBills = shiftBills.where((b) => b.status == 'REFUNDED');

      int cashSales = 0;
      int qrSales = 0;
      int cardSales = 0;

      for (final b in paidShiftBills) {
        if (b.paymentSplits != null && b.paymentSplits!.isNotEmpty) {
          for (final sp in b.paymentSplits!) {
            final sm = sp.method.toUpperCase();
            if (sm.contains('CASH') || sm.contains('TIỀN MẶT')) {
              cashSales += sp.amount;
            } else if (sm.contains('TRANSFER') || sm.contains('QR') || sm.contains('CHUYỂN KHOẢN')) {
              qrSales += sp.amount;
            } else {
              cardSales += sp.amount;
            }
          }
        } else {
          final m = b.paymentMethod.toUpperCase();
          if (m.contains('CASH') || m.contains('TIỀN MẶT')) {
            cashSales += b.finalAmount;
          } else if (m.contains('TRANSFER') || m.contains('QR') || m.contains('CHUYỂN KHOẢN')) {
            qrSales += b.finalAmount;
          } else {
            cardSales += b.finalAmount;
          }
        }
      }

      int refundCash = 0;
      for (final b in refundedShiftBills) {
        final m = b.paymentMethod.toUpperCase();
        if (m.contains('CASH') || m.contains('TIỀN MẶT')) {
          refundCash += getRefundAmount(b);
        }
      }

      // Nếu shift đã có doanh số được lưu trong DB thì dùng số của shift nếu không tìm thấy bills
      final finalCashSales = shiftBills.isNotEmpty ? cashSales : s.totalCashSales;
      final finalQrSales = shiftBills.isNotEmpty ? qrSales : s.totalQrSales;
      final finalCardSales = shiftBills.isNotEmpty ? cardSales : s.totalCardSales;
      final totalSales = finalCashSales + finalQrSales + finalCardSales;
      final finalRefundCash = shiftBills.isNotEmpty ? refundCash : 0;

      final expectedCash = s.initialCash + finalCashSales - finalRefundCash + s.cashIn - s.cashOut;
      final actualCash = s.actualCash ?? expectedCash;
      final difference = s.difference ?? (actualCash - expectedCash);

      result.add(CashShiftAuditItem(
        shiftId: s.id,
        shiftCode: s.shiftCode,
        shiftName: s.shiftCode.contains('-01')
            ? 'Ca Sáng (07:00 - 15:00)'
            : (s.shiftCode.contains('-02') ? 'Ca Tối (15:00 - 23:00)' : s.shiftCode),
        staffUsername: s.staffUsername,
        staffFullName: s.staffFullName,
        openedAt: s.openedAt,
        closedAt: s.closedAt,
        initialCash: s.initialCash,
        cashIn: s.cashIn,
        cashOut: s.cashOut,
        cashSales: finalCashSales,
        qrSales: finalQrSales,
        cardSales: finalCardSales,
        totalSales: totalSales,
        refundCash: finalRefundCash,
        expectedCash: expectedCash,
        actualCash: actualCash,
        difference: difference,
        status: s.status,
      ));
    }

    return result;
  }

  /// BÁO CÁO 10: BÁO CÁO LỢI NHUẬN GỘP & GIÁ VỐN (GROSS PROFIT & COGS)
  static GrossProfitReportResult calculateGrossProfitReport(
    List<BillModel> rawBills, {
    Map<int, ProductModel>? productsMap,
    Map<String, int>? toppingCosts,
  }) {
    final overview = calculateOverviewReport(rawBills, productsMap: productsMap, toppingCosts: toppingCosts);
    final items = calculateProductReport(rawBills, productsMap: productsMap, toppingCosts: toppingCosts);

    return GrossProfitReportResult(
      totalRevenue: overview.afterDiscount,
      totalCostPrice: overview.totalCostPrice,
      grossProfit: overview.grossProfit,
      grossProfitMarginPercent: overview.grossProfitMarginPercent,
      items: items,
    );
  }

  /// Món đã lưu bị xóa trong kỳ: gom `deletedItems` của HĐ PAID và CANCELLED.
  static DeletedItemsSummary calculateDeletedItems(List<BillModel> rawBills) {
    final bills = deduplicateBills(rawBills).where((b) => b.status == 'PAID' || b.status == 'CANCELLED');
    return DeletedItemsLogic.summarize(bills.expand((b) => b.deletedItems));
  }

  /// BÁO CÁO 12: HIỆU QUẢ THEO CHƯƠNG TRÌNH KHUYẾN MÃI (chỉ HĐ PAID).
  /// Gom theo campaignId; dữ liệu cũ không có campaignId → promoId → promoCode → mô tả.
  /// Đọc trường mới (campaignId, campaignName, programCode, campaignType, voucherCode)
  /// qua toMap() để tương thích cả bản ghi cũ.
  static List<CampaignReportItem> calculateCampaignReport(
    List<BillModel> rawBills, {
    Map<String, String>? campaignNames,
  }) {
    String str(Object? v) => v?.toString().trim() ?? '';
    final paidBills = deduplicateBills(rawBills).where((b) => b.status == 'PAID');
    final Map<String, _CampaignReportAccumulator> map = {};

    for (final b in paidBills) {
      final seenInBill = <String>{};
      for (final d in b.discounts) {
        final m = d.toMap();
        final campaignId = str(m['campaignId']);
        final promoId = str(m['promoId']);
        final promoCode = str(m['promoCode']);
        final programCode = str(m['programCode']);
        final voucherCode = str(m['voucherCode']);
        final description = str(m['description']);
        final key = campaignId.isNotEmpty
            ? campaignId
            : promoId.isNotEmpty
                ? promoId
                : promoCode.isNotEmpty
                    ? promoCode
                    : (description.isNotEmpty ? description : 'KHAC');
        final name = str(m['campaignName']).isNotEmpty
            ? str(m['campaignName'])
            : (campaignNames?[key] ??
                campaignNames?[promoCode] ??
                defaultCampaignNames[promoId] ??
                defaultCampaignNames[promoCode] ??
                (description.isNotEmpty ? description : key));
        final acc = map.putIfAbsent(
          key,
          () => _CampaignReportAccumulator(
            key: key,
            campaignId: campaignId.isNotEmpty ? campaignId : promoId,
            name: name,
            code: programCode.isNotEmpty ? programCode : promoCode,
            type: str(m['campaignType']),
          ),
        );
        final amount = (m['amount'] as num?)?.toInt() ?? d.amount;
        acc.discountAmount += amount;
        if (voucherCode.isNotEmpty) acc.voucherCodesUsed += 1;
        if (seenInBill.add(key)) {
          acc.billCount += 1;
          acc.revenue += b.finalAmount;
        }
        acc.bills.add(CampaignBillRef(
          billId: b.id,
          billCode: b.billCode,
          time: b.closedAt ?? b.createdAt,
          tableName: b.tableName,
          voucherCode: voucherCode,
          discount: amount,
          billFinalAmount: b.finalAmount,
        ));
      }
    }

    final list = map.values
        .map((a) => CampaignReportItem(
              key: a.key,
              campaignId: a.campaignId,
              name: a.name,
              code: a.code,
              type: a.type,
              billCount: a.billCount,
              discountAmount: a.discountAmount,
              revenue: a.revenue,
              voucherCodesUsed: a.voucherCodesUsed,
              bills: (a.bills..sort((x, y) => y.time.compareTo(x.time))),
            ))
        .toList();
    list.sort((x, y) {
      final c = y.discountAmount.compareTo(x.discountAmount);
      return c != 0 ? c : x.name.compareTo(y.name);
    });
    return list;
  }

  /// BÁO CÁO 11: BÁO CÁO CUỐI NGÀY (END-OF-DAY Z-REPORT)
  static EndOfDayReportData generateEndOfDayZReport({
    required List<BillModel> bills,
    required List<CashShiftModel> shifts,
    List<TableModel> tables = const [],
    Map<int, ProductModel>? productsMap,
    Map<String, int>? toppingCosts,
    String? dateStr,
    String storeCode = '',
    String storeName = '',
  }) {
    final overview = calculateOverviewReport(
      bills,
      productsMap: productsMap,
      toppingCosts: toppingCosts,
    );

    // Tab 1: Tổng hợp
    // billDiscounts trong Tab 1 Z-Report gồm Bill Voucher + Points Discount (30k + 10k = 40k)
    final billDiscountsWithPoints = overview.billDiscounts + overview.pointsDiscounts;
    final deleted = calculateDeletedItems(bills);
    final tab1 = EndOfDayTab1TongHop(
      grossRevenue: overview.grossRevenue,
      itemDiscounts: overview.itemDiscounts,
      billDiscounts: billDiscountsWithPoints,
      totalDiscount: overview.totalDiscount,
      afterDiscount: overview.afterDiscount,
      vatTotal: overview.vatTotal,
      netRevenue: overview.netRevenue,
      refundAmount: overview.refundAmount,
      netRevenueWithoutRefund: overview.netRevenueWithoutRefund,
      paidBillsCount: overview.paidBillsCount,
      avgRevenuePerBill: overview.avgRevenuePerPaidBill,
      totalGuests: overview.totalGuests,
      deletedItemsCount: deleted.count,
      deletedItemsAmount: deleted.amount,
      cancelledBillsCount: overview.cancelledBillsCount,
      cancelledBillsAmount: overview.cancelledTotalValue,
    );

    // Tab 2: Thu chi
    final payments = calculatePaymentMethodsReport(bills);
    final cashSales = payments['CASH']?.finalAmount ?? 0;
    final transferSales = payments['TRANSFER_QR']?.finalAmount ?? 0;
    final cardSales = payments['CARD']?.finalAmount ?? 0;
    final totalRevenue = cashSales + transferSales + cardSales;

    final cashInTotal = shifts.fold<int>(0, (sum, s) => sum + s.cashIn);
    final cashOutTotal = shifts.fold<int>(0, (sum, s) => sum + s.cashOut);
    final tab2 = EndOfDayTab2ThuChi(
      cashSales: cashSales,
      transferSales: transferSales,
      cardSales: cardSales,
      totalRevenue: totalRevenue,
      cashInTotal: cashInTotal,
      cashOutTotal: cashOutTotal,
      refundTotal: overview.refundAmount,
    );

    // Tab 3: Hàng hóa (sắp xếp theo grossRevenue giảm dần)
    final prodItems = calculateProductReport(
      bills,
      productsMap: productsMap,
      toppingCosts: toppingCosts,
    );
    prodItems.sort((a, b) => b.grossRevenue.compareTo(a.grossRevenue));
    final totalItemsSold = prodItems.fold<int>(0, (sum, p) => sum + p.quantity);
    final tab3 = EndOfDayTab3HangHoa(
      totalItemsSold: totalItemsSold,
      products: prodItems,
    );

    // Tab 4: Phòng bàn (nhóm theo khu vực)
    final paidBills = deduplicateBills(bills).where((b) => b.status == 'PAID');
    final Map<String, _ZoneAccumulator> zoneMap = {};
    for (final b in paidBills) {
      final z = b.zone.isNotEmpty ? b.zone : 'Khu vực chung';
      zoneMap.putIfAbsent(z, () => _ZoneAccumulator(zone: z));
      zoneMap[z]!.billCount += 1;
      zoneMap[z]!.netRevenue += b.finalAmount;
    }
    final zoneList = zoneMap.values.map((z) => ZoneReportItem(
      zone: z.zone,
      billCount: z.billCount,
      netRevenue: z.netRevenue,
    )).toList();
    // Ưu tiên thứ tự Tầng 1, Tầng 2, Mang về nếu có
    zoneList.sort((a, b) => b.netRevenue.compareTo(a.netRevenue));

    final tab4 = EndOfDayTab4PhongBan(zones: zoneList);

    final displayDate = dateStr ??
        (bills.isNotEmpty
            ? ReportDateUtils.formatYmd(ReportDateUtils.getBillDateTime(bills.first.closedAt, bills.first.createdAt))
            : ReportDateUtils.formatYmd(ReportDateUtils.toUtc7(DateTime.now().millisecondsSinceEpoch)));

    return EndOfDayReportData(
      date: displayDate,
      storeCode: storeCode,
      storeName: storeName,
      tab1TongHop: tab1,
      tab2ThuChi: tab2,
      tab3HangHoa: tab3,
      tab4PhongBan: tab4,
    );
  }
}

// ==================== INTERNAL ACCUMULATORS ====================

class _CatAccumulator {
  final String category;
  int quantity = 0;
  int grossRevenue = 0;
  int itemDiscount = 0;
  int costPrice = 0;

  _CatAccumulator({required this.category});
}

class _ProdAccumulator {
  final int productId;
  final String productCode;
  final String productName;
  final String category;
  final String unit;
  final int basePrice;
  int quantity = 0;
  int grossRevenue = 0;
  int itemDiscount = 0;
  int costPrice = 0;

  _ProdAccumulator({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.category,
    required this.unit,
    required this.basePrice,
  });
}

class _OrderStaffAccumulator {
  final String staffUsername;
  final String staffFullName;
  int itemsCount = 0;
  int grossRevenue = 0;
  int netRevenue = 0;

  _OrderStaffAccumulator({required this.staffUsername, required this.staffFullName});
}

class _CashierStaffAccumulator {
  final String staffUsername;
  final String staffFullName;
  int billCount = 0;
  int netRevenue = 0;

  _CashierStaffAccumulator({required this.staffUsername, required this.staffFullName});
}

class _CampaignAccumulator {
  final String promoId;
  final String promoCode;
  final String name;
  int usedCount = 0;
  int discountAmount = 0;

  _CampaignAccumulator({required this.promoId, required this.promoCode, required this.name});
}

class _ItemDiscountAccumulator {
  final int productId;
  final String productName;
  int discountAmount = 0;
  int quantity = 0;

  _ItemDiscountAccumulator({required this.productId, required this.productName});
}

class _ZoneAccumulator {
  final String zone;
  int billCount = 0;
  int netRevenue = 0;

  _ZoneAccumulator({required this.zone});
}

class _CampaignReportAccumulator {
  final String key;
  final String campaignId;
  final String name;
  final String code;
  final String type;
  int billCount = 0;
  int discountAmount = 0;
  int revenue = 0;
  int voucherCodesUsed = 0;
  final List<CampaignBillRef> bills = [];

  _CampaignReportAccumulator({
    required this.key,
    required this.campaignId,
    required this.name,
    required this.code,
    required this.type,
  });
}

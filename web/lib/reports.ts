/**
 * POS Trạm - Core Financial & Analytical Reports Engine
 * Tuân thủ chuẩn DOCS-REPORT-SPEC-2026-01 (REPORT SPEC v2.0.0)
 * Pure TypeScript functions, độc lập hoàn toàn với React, có thể kiểm thử 100%.
 */

export interface OrderItem {
  id?: number | string;
  productId?: number | string;
  productCode?: string;
  code?: string;
  name: string;
  price: number;
  quantity?: number;
  count?: number;
  unit?: string;
  category?: string;
  selectedSize?: string;
  selectedSugar?: string;
  selectedIce?: string;
  selectedToppings?: any[];
  toppingPrice?: number;
  sizeExtraPrice?: number;
  unitPrice?: number;
  discountAmount?: number;
  lineGrossAmount?: number;
  lineTotal?: number;
  costPrice?: number;
  unitCost?: number;
  lineCostPrice?: number;
  orderedBy?: string;
  orderedByName?: string;
  orderedAt?: number | string;
  optionsSummary?: string;
  note?: string;
  [key: string]: any;
}

export interface HistoryOrder {
  id: string;
  storeCode?: string;
  storeName?: string;
  billCode?: string;
  orderCode?: string;
  tableName?: string;
  zone?: string;
  guestCount?: number;
  paymentMethod?: string;
  status?: string; // 'PAID' | 'CANCELLED' | 'REFUNDED' | 'OPEN'
  totalAmount?: number;
  finalAmount?: number;
  subTotal?: number;
  discountAmount?: number;
  totalDiscount?: number;
  itemDiscounts?: number;
  billDiscounts?: number;
  pointsDiscount?: number;
  pointsUsed?: number;
  vatRate?: number;
  vatAmount?: number;
  refundAmount?: number;
  cogs?: number;
  timestamp?: number | string;
  createdAt?: number | string;
  closedAt?: number | string;
  username?: string;
  createdBy?: string;
  creatorName?: string;
  staffFullName?: string;
  staffUsername?: string;
  cashierName?: string;
  orderStaff?: string;
  shiftId?: string;
  parentBillId?: string | null;
  mergedTableNames?: string[] | null;
  notes?: string;
  cancelReason?: string;
  cancellationReason?: string;
  cancelledAt?: number;
  cancelledBy?: string;
  discounts?: Array<{
    promoId?: string;
    promoCode?: string;
    description?: string;
    promoName?: string;
    amount?: number;
    [key: string]: unknown;
  }>;
  items?: OrderItem[];
  itemsJson?: string;
  actionLogs?: any[];
  [key: string]: any;
}

export interface TableItem {
  id: string;
  name: string;
  zone: string;
  inUse?: boolean;
  guestCount?: number;
  storeCode?: string;
  storeName?: string;
  [key: string]: unknown;
}

export interface CashShiftItem {
  id?: string;
  shiftId?: string;
  shiftCode: string;
  shiftName?: string;
  storeCode?: string;
  staffUsername: string;
  staffFullName: string;
  openedAt: number;
  closedAt?: number | null;
  initialCash: number;
  totalCashSales?: number;
  totalQrSales?: number;
  totalCardSales?: number;
  cashIn: number;
  cashOut: number;
  cashSales?: number;
  qrSales?: number;
  cardSales?: number;
  totalSales?: number;
  refundCash?: number;
  expectedCash?: number;
  actualCash?: number | null;
  difference?: number;
  status: "OPEN" | "CLOSED" | string;
  notes?: string;
  [key: string]: unknown;
}

export interface ProductItem {
  id: string | number;
  productId?: number | string;
  code?: string;
  productCode?: string;
  name: string;
  price: number;
  costPrice?: number;
  unit: string;
  category: string;
  storeCode?: string;
  storeName?: string;
  imageBase64?: string;
  [key: string]: unknown;
}

export type PeriodType = "DAY" | "WEEK" | "MONTH" | "YEAR";

// ==================== BÁO CÁO 1: EXECUTIVE OVERVIEW ====================
export interface OverviewReportResult {
  totalBillsCount: number;
  paidBillsCount: number;
  cancelledBillsCount: number;
  refundedBillsCount: number;
  totalGuests: number;
  grossRevenue: number;
  itemDiscounts: number;
  billDiscounts: number;
  pointsDiscounts: number;
  totalDiscount: number;
  afterDiscount: number;
  vatTotal: number;
  netRevenue: number;
  refundAmount: number;
  netRevenueWithoutRefund: number;
  avgRevenuePerPaidBill: number;
  cancelledTotalValue: number;
  totalCostPrice: number;
  grossProfit: number;
  grossProfitMarginPercent: number;
}

// ==================== BÁO CÁO 2: REVENUE BY PERIOD ====================
export interface PeriodRevenueItem {
  periodKey: string;
  periodLabel: string;
  billCount: number;
  grossRevenue: number;
  discountAmount: number;
  vatAmount: number;
  netRevenue: number;
  cashRevenue: number;
  qrRevenue: number;
  cardRevenue: number;
  proportion: number;
}

// ==================== BÁO CÁO 3: CATEGORY SALES ====================
export interface CategoryReportItem {
  category: string;
  quantity: number;
  grossRevenue: number;
  itemDiscount: number;
  netRevenue: number;
  costPrice: number;
  grossProfit: number;
  grossProfitMarginPercent: number;
  proportion?: number;
}

// ==================== BÁO CÁO 4: PRODUCT SALES PERFORMANCE ====================
export interface ProductReportItem {
  productId: number | string;
  productCode: string;
  productName: string;
  category: string;
  unit: string;
  basePrice: number;
  quantity: number;
  grossRevenue: number;
  itemDiscount: number;
  netRevenue: number;
  costPrice: number;
  grossProfit: number;
  grossProfitMarginPercent: number;
}

// ==================== BÁO CÁO 5: STAFF SALES PERFORMANCE ====================
export interface StaffOrderPerformanceItem {
  staffUsername: string;
  staffFullName: string;
  itemsCount: number;
  grossRevenue: number;
  netRevenue: number;
}

export interface StaffCashierPerformanceItem {
  staffUsername: string;
  staffFullName: string;
  billCount: number;
  netRevenue: number;
}

export interface StaffPerformanceResult {
  orderStaff: StaffOrderPerformanceItem[];
  cashierStaff: StaffCashierPerformanceItem[];
}

// ==================== BÁO CÁO 6: HOURLY HEATMAP ====================
export interface HourlyReportItem {
  hour: number;
  hourLabel: string;
  billCount: number;
  grossRevenue: number;
  totalDiscount: number;
  vatAmount: number;
  netRevenue: number;
  proportion?: number;
}

// ==================== BÁO CÁO 7: PAYMENT METHODS ====================
export interface PaymentMethodSummary {
  billCount: number;
  grossRevenue: number;
  totalDiscount: number;
  vatAmount: number;
  finalAmount: number;
  proportion?: number;
}

// ==================== BÁO CÁO 8: PROMOTIONS & DISCOUNTS ====================
export interface CampaignReportItem {
  promoId: string;
  promoCode: string;
  name: string;
  usedCount: number;
  discountAmount: number;
}

export interface PointsRedemptionSummary {
  usedCount: number;
  totalPointsUsed: number;
  discountAmount: number;
}

export interface ItemDiscountDetail {
  productId?: number | string;
  productName: string;
  discountAmount: number;
  quantity: number;
}

export interface ItemDiscountsSummary {
  appliedCount: number;
  discountAmount: number;
  details: ItemDiscountDetail[];
}

export interface PromotionsReportResult {
  totalDiscountAmount: number;
  campaigns: CampaignReportItem[];
  pointsRedemption: PointsRedemptionSummary;
  itemDiscounts: ItemDiscountsSummary;
}

// ==================== BÁO CÁO 9: CANCELLATIONS & AUDIT ====================
export interface CancelledBillItem {
  billId: string;
  billCode: string;
  tableName: string;
  staffFullName: string;
  cancelledAt: number;
  reason: string;
  items: string[];
  subTotal: number;
}

export interface CancellationReportResult {
  cancelledBillsCount: number;
  totalLossValue: number;
  bills: CancelledBillItem[];
}

// ==================== BÁO CÁO 10: CASH SHIFT VARIANCE ====================
export interface CashShiftAuditItem {
  shiftId: string;
  shiftCode: string;
  shiftName?: string;
  storeCode?: string;
  staffUsername: string;
  staffFullName: string;
  openedAt: number;
  closedAt?: number | null;
  initialCash: number;
  cashIn: number;
  cashOut: number;
  cashSales: number;
  qrSales: number;
  cardSales: number;
  totalSales: number;
  refundCash: number;
  expectedCash: number;
  actualCash: number;
  difference: number;
  status: string;
  notes?: string;
}

// ==================== BÁO CÁO 11: GROSS PROFIT & COGS ====================
export interface GrossProfitItem {
  productId?: number | string;
  productName: string;
  category?: string;
  quantity: number;
  avgSellingPrice: number;
  avgCostPrice: number;
  netRevenue: number;
  cogs: number;
  grossProfit: number;
  grossProfitMarginPercent: number;
}

export interface GrossProfitReportResult {
  items: GrossProfitItem[];
  summary: {
    totalQuantity: number;
    netRevenue: number;
    totalCOGS: number;
    grossProfit: number;
    grossProfitMarginPercent: number;
  };
}

// ==================== BÁO CÁO 12: END-OF-DAY Z-REPORT ====================
export interface EndOfDayReportData {
  date: string;
  storeCode: string;
  storeName: string;
  tab1_tongHop: {
    grossRevenue: number;
    itemDiscounts: number;
    billDiscounts: number;
    totalDiscount: number;
    afterDiscount: number;
    vatTotal: number;
    netRevenue: number;
    refundAmount: number;
    netRevenueWithoutRefund: number;
    paidBillsCount: number;
    avgRevenuePerBill: number;
    totalGuests: number;
  };
  tab2_thuChi: {
    cashSales: number;
    transferSales: number;
    cardSales: number;
    totalRevenue: number;
    cashInTotal: number;
    cashOutTotal: number;
    refundTotal: number;
  };
  tab3_hangHoa: {
    totalItemsSold: number;
    products: ProductReportItem[];
  };
  tab4_phongBan: {
    zones: {
      zone: string;
      billCount: number;
      netRevenue: number;
    }[];
  };
}

// ==================== THUẬT TOÁN & HELPER ====================

/**
 * Khử trùng lặp ID hóa đơn (Deduplication Algorithm - Đặc tả mục 4.2)
 */
export function deduplicateBills(rawList: HistoryOrder[]): HistoryOrder[] {
  const map = new Map<string, HistoryOrder>();
  for (const bill of rawList) {
    if (!bill || !bill.id) continue;
    if (!map.has(bill.id)) {
      map.set(bill.id, bill);
    } else {
      const existing = map.get(bill.id)!;
      const existingTime = Number(existing.closedAt || existing.createdAt || existing.timestamp || 0);
      const newTime = Number(bill.closedAt || bill.createdAt || bill.timestamp || 0);
      if (newTime >= existingTime) {
        map.set(bill.id, bill);
      }
    }
  }
  return Array.from(map.values());
}

/**
 * Quy tắc lựa chọn trường thời gian xếp ngày (Đặc tả mục 3.4)
 * 1. closedAt (PAID, REFUNDED)
 * 2. createdAt (OPEN, CANCELLED)
 * 3. timestamp (fallback)
 */
export function getBillTimestamp(bill: HistoryOrder): number {
  if (bill.status === "PAID" || bill.status === "REFUNDED") {
    if (bill.closedAt) return Number(bill.closedAt);
  }
  if (bill.createdAt) return Number(bill.createdAt);
  if (bill.closedAt) return Number(bill.closedAt);
  if (bill.timestamp) {
    return typeof bill.timestamp === "number" ? bill.timestamp : new Date(bill.timestamp).getTime();
  }
  return 0;
}

/**
 * Chuyển timestamp UTC sang đối tượng Date hỗ trợ trích xuất theo múi giờ UTC+7
 */
export function getUTC7Date(timestamp: number): Date {
  return new Date(timestamp + 7 * 60 * 60 * 1000);
}

/**
 * Định dạng tiền VND chuẩn có dấu chấm phân cách hàng nghìn
 */
export function formatVND(amount: number): string {
  const safe = isNaN(amount) ? 0 : Math.round(amount);
  return new Intl.NumberFormat("vi-VN").format(safe) + " đ";
}

export function formatNumber(amount: number): string {
  const safe = isNaN(amount) ? 0 : Math.round(amount);
  return new Intl.NumberFormat("vi-VN").format(safe);
}

/**
 * Trích xuất danh sách OrderItem từ HistoryOrder an toàn
 */
export function extractBillItems(bill: HistoryOrder): OrderItem[] {
  if (Array.isArray(bill.items) && bill.items.length > 0) {
    return bill.items;
  }
  if (bill.itemsJson) {
    try {
      const parsed = typeof bill.itemsJson === "string" ? JSON.parse(bill.itemsJson) : bill.itemsJson;
      if (Array.isArray(parsed)) return parsed;
    } catch {}
  }
  return [];
}

// ==================== CÁC HÀM TÍNH TOÁN BÁO CÁO THUẦN ====================

/**
 * Báo cáo 1: Tổng quan quản trị (Executive Overview)
 */
export function calculateOverviewReport(bills: HistoryOrder[], refundAmountParam?: number): OverviewReportResult {
  const deduped = deduplicateBills(bills);

  let paidBillsCount = 0;
  let cancelledBillsCount = 0;
  let refundedBillsCount = 0;
  let totalGuests = 0;
  let grossRevenue = 0;
  let itemDiscounts = 0;
  let billDiscounts = 0;
  let pointsDiscounts = 0;
  let totalDiscount = 0;
  let afterDiscount = 0;
  let vatTotal = 0;
  let netRevenue = 0;
  let refundFromBills = 0;
  let cancelledTotalValue = 0;
  let totalCostPrice = 0;

  for (const b of deduped) {
    const status = (b.status || "PAID").toUpperCase();
    if (status === "PAID") {
      paidBillsCount++;
      totalGuests += Number(b.guestCount || 0);

      const bSubTotal = Number(b.subTotal != null ? b.subTotal : (b.totalAmount || 0));
      grossRevenue += bSubTotal;

      // Giảm giá món
      let bItemDisc = 0;
      if (b.itemDiscounts != null) {
        bItemDisc = Number(b.itemDiscounts);
      } else {
        const items = extractBillItems(b);
        bItemDisc = items.reduce((sum, it) => sum + (Number(it.discountAmount || 0) * Number(it.quantity || 1)), 0);
      }
      itemDiscounts += bItemDisc;

      // Giảm giá đơn / Voucher
      let bBillDisc = 0;
      if (b.billDiscounts != null) {
        bBillDisc = Number(b.billDiscounts);
      } else if (Array.isArray(b.discounts)) {
        bBillDisc = b.discounts.reduce((sum, d) => sum + Number(d.amount || 0), 0);
      }
      billDiscounts += bBillDisc;

      // Giảm giá điểm
      const bPointsDisc = Number(b.pointsDiscount || 0);
      pointsDiscounts += bPointsDisc;

      // Tổng giảm giá
      const bTotDisc = Number(b.totalDiscount != null ? b.totalDiscount : (bItemDisc + bBillDisc + bPointsDisc));
      totalDiscount += bTotDisc;

      // Sau giảm giá
      const bAfterDisc = Number(b.afterDiscount != null ? b.afterDiscount : Math.max(0, bSubTotal - bTotDisc));
      afterDiscount += bAfterDisc;

      // VAT
      const bVat = Number(b.vatAmount || 0);
      vatTotal += bVat;

      // Doanh thu thuần
      const bFinal = Number(b.finalAmount != null ? b.finalAmount : (bAfterDisc + bVat));
      netRevenue += bFinal;

      // Giá vốn (COGS)
      let bCogs = 0;
      if (b.cogs != null) {
        bCogs = Number(b.cogs);
      } else {
        const items = extractBillItems(b);
        bCogs = items.reduce((sum, it) => {
          const qty = Number(it.quantity || 1);
          const unitC = Number(it.unitCost != null ? it.unitCost : (it.costPrice || 0));
          return sum + (it.lineCostPrice != null ? Number(it.lineCostPrice) : (unitC * qty));
        }, 0);
      }
      totalCostPrice += bCogs;
    } else if (status === "CANCELLED") {
      cancelledBillsCount++;
      const val = Number(b.subTotal != null ? b.subTotal : (b.totalAmount || 0));
      cancelledTotalValue += val;
    } else if (status === "REFUNDED") {
      refundedBillsCount++;
      const rAmt = Number(b.refundAmount != null ? b.refundAmount : (b.finalAmount || b.totalAmount || 0));
      refundFromBills += rAmt;
    }
  }

  const refundAmount = refundAmountParam != null ? refundAmountParam : refundFromBills;
  const netRevenueWithoutRefund = netRevenue - refundAmount;
  const avgRevenuePerPaidBill = paidBillsCount > 0 ? Math.round(netRevenue / paidBillsCount) : 0;
  const grossProfit = afterDiscount - totalCostPrice;
  const grossProfitMarginPercent = afterDiscount > 0 ? Number(((grossProfit / afterDiscount) * 100).toFixed(2)) : 0;

  return {
    totalBillsCount: deduped.length,
    paidBillsCount,
    cancelledBillsCount,
    refundedBillsCount,
    totalGuests,
    grossRevenue,
    itemDiscounts,
    billDiscounts,
    pointsDiscounts,
    totalDiscount,
    afterDiscount,
    vatTotal,
    netRevenue,
    refundAmount,
    netRevenueWithoutRefund,
    avgRevenuePerPaidBill,
    cancelledTotalValue,
    totalCostPrice,
    grossProfit,
    grossProfitMarginPercent,
  };
}

/**
 * Báo cáo 2: Doanh thu theo kỳ (Revenue by Period)
 */
export function calculateRevenueByPeriod(
  bills: HistoryOrder[],
  period: PeriodType = "DAY"
): PeriodRevenueItem[] {
  const deduped = deduplicateBills(bills);
  const paidBills = deduped.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");

  const groups = new Map<string, {
    periodKey: string;
    periodLabel: string;
    sortKey: number;
    billCount: number;
    grossRevenue: number;
    discountAmount: number;
    vatAmount: number;
    netRevenue: number;
    cashRevenue: number;
    qrRevenue: number;
    cardRevenue: number;
  }>();

  for (const b of paidBills) {
    const ts = getBillTimestamp(b);
    const d = getUTC7Date(ts);
    const year = d.getUTCFullYear();
    const month = d.getUTCMonth() + 1;
    const day = d.getUTCDate();

    let key = "";
    let label = "";
    let sortKey = 0;

    if (period === "DAY") {
      key = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
      label = `${String(day).padStart(2, "0")}/${String(month).padStart(2, "0")}/${year}`;
      sortKey = Date.UTC(year, month - 1, day);
    } else if (period === "WEEK") {
      // Calculate week number
      const dCopy = new Date(Date.UTC(year, month - 1, day));
      const dayNum = dCopy.getUTCDay() || 7;
      dCopy.setUTCDate(dCopy.getUTCDate() + 4 - dayNum);
      const yearStart = new Date(Date.UTC(dCopy.getUTCFullYear(), 0, 1));
      const weekNo = Math.ceil((((dCopy.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
      key = `${year}-W${String(weekNo).padStart(2, "0")}`;
      label = `Tuần ${weekNo}/${year}`;
      sortKey = Date.UTC(year, month - 1, day);
    } else if (period === "MONTH") {
      key = `${year}-${String(month).padStart(2, "0")}`;
      label = `${String(month).padStart(2, "0")}/${year}`;
      sortKey = Date.UTC(year, month - 1, 1);
    } else {
      key = `${year}`;
      label = `Năm ${year}`;
      sortKey = Date.UTC(year, 0, 1);
    }

    if (!groups.has(key)) {
      groups.set(key, {
        periodKey: key,
        periodLabel: label,
        sortKey,
        billCount: 0,
        grossRevenue: 0,
        discountAmount: 0,
        vatAmount: 0,
        netRevenue: 0,
        cashRevenue: 0,
        qrRevenue: 0,
        cardRevenue: 0,
      });
    }

    const entry = groups.get(key)!;
    entry.billCount += 1;
    entry.grossRevenue += Number(b.subTotal != null ? b.subTotal : (b.totalAmount || 0));
    entry.discountAmount += Number(b.totalDiscount != null ? b.totalDiscount : (b.discountAmount || 0));
    entry.vatAmount += Number(b.vatAmount || 0);

    const bFinal = Number(b.finalAmount != null ? b.finalAmount : (b.totalAmount || 0));
    entry.netRevenue += bFinal;

    const pm = (b.paymentMethod || "").toUpperCase();
    if (pm === "CASH" || pm.includes("TIỀN MẶT")) {
      entry.cashRevenue += bFinal;
    } else if (pm === "TRANSFER_QR" || pm === "TRANSFER" || pm.includes("CHUYỂN")) {
      entry.qrRevenue += bFinal;
    } else if (pm === "CARD" || pm.includes("THẺ")) {
      entry.cardRevenue += bFinal;
    } else {
      entry.cashRevenue += bFinal; // fallback
    }
  }

  const list = Array.from(groups.values()).sort((a, b) => a.sortKey - b.sortKey);
  const totalNet = list.reduce((sum, item) => sum + item.netRevenue, 0);

  return list.map((item) => ({
    periodKey: item.periodKey,
    periodLabel: item.periodLabel,
    billCount: item.billCount,
    grossRevenue: item.grossRevenue,
    discountAmount: item.discountAmount,
    vatAmount: item.vatAmount,
    netRevenue: item.netRevenue,
    cashRevenue: item.cashRevenue,
    qrRevenue: item.qrRevenue,
    cardRevenue: item.cardRevenue,
    proportion: totalNet > 0 ? Number(((item.netRevenue / totalNet) * 100).toFixed(1)) : 0,
  }));
}

/**
 * Báo cáo 3: Doanh thu theo Nhóm hàng / Danh mục (Category Sales)
 */
export function calculateCategoryReport(
  bills: HistoryOrder[],
  productsMap?: Record<string | number, any>
): CategoryReportItem[] {
  const deduped = deduplicateBills(bills);
  const paidBills = deduped.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");

  const catMap = new Map<string, {
    category: string;
    quantity: number;
    grossRevenue: number;
    itemDiscount: number;
    costPrice: number;
  }>();

  for (const b of paidBills) {
    const items = extractBillItems(b);
    for (const it of items) {
      let category = (it.category || "").trim();
      if (!category && productsMap) {
        const prod = productsMap[it.productId || it.name];
        if (prod) category = (prod.category || "").trim();
      }
      if (!category) category = "Khác";

      if (!catMap.has(category)) {
        catMap.set(category, {
          category,
          quantity: 0,
          grossRevenue: 0,
          itemDiscount: 0,
          costPrice: 0,
        });
      }

      const entry = catMap.get(category)!;
      const qty = Number(it.quantity || 1);
      const lineGross = it.lineGrossAmount != null ? Number(it.lineGrossAmount) : (Number(it.price || 0) * qty);
      const itemDisc = Number(it.discountAmount || 0) * qty;

      let lineCost = 0;
      if (it.lineCostPrice != null) {
        lineCost = Number(it.lineCostPrice);
      } else {
        const unitC = Number(it.unitCost != null ? it.unitCost : (it.costPrice || 0));
        lineCost = unitC * qty;
      }

      entry.quantity += qty;
      entry.grossRevenue += lineGross;
      entry.itemDiscount += itemDisc;
      entry.costPrice += lineCost;
    }
  }

  const list: CategoryReportItem[] = [];
  let totalNetAll = 0;

  for (const e of catMap.values()) {
    const netRevenue = e.grossRevenue - e.itemDiscount;
    const grossProfit = netRevenue - e.costPrice;
    const grossProfitMarginPercent = netRevenue > 0 ? Number(((grossProfit / netRevenue) * 100).toFixed(2)) : 0;
    totalNetAll += netRevenue;

    list.push({
      category: e.category,
      quantity: e.quantity,
      grossRevenue: e.grossRevenue,
      itemDiscount: e.itemDiscount,
      netRevenue,
      costPrice: e.costPrice,
      grossProfit,
      grossProfitMarginPercent,
    });
  }

  list.sort((a, b) => b.grossRevenue - a.grossRevenue);

  list.forEach((item) => {
    item.proportion = totalNetAll > 0 ? Number(((item.netRevenue / totalNetAll) * 100).toFixed(1)) : 0;
  });

  return list;
}

/**
 * Báo cáo 4: Hiệu suất Món ăn / Hàng hóa (Product Sales Performance)
 */
export function calculateProductReport(
  bills: HistoryOrder[],
  productsMap?: Record<string | number, any>
): ProductReportItem[] {
  const deduped = deduplicateBills(bills);
  const paidBills = deduped.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");

  const prodMap = new Map<string, {
    productId: number | string;
    productCode: string;
    productName: string;
    category: string;
    unit: string;
    basePrice: number;
    quantity: number;
    grossRevenue: number;
    itemDiscount: number;
    costPrice: number;
  }>();

  for (const b of paidBills) {
    const items = extractBillItems(b);
    for (const it of items) {
      const pId = it.productId != null ? it.productId : (it.name || "0");
      const key = String(pId);

      let pCode = it.productCode || it.code || "";
      let basePrice = Number(it.price || 0);
      let unit = it.unit || "Ly";
      let category = it.category || "Khác";

      if (productsMap && productsMap[pId]) {
        const pDef = productsMap[pId];
        if (!pCode) pCode = pDef.code || pDef.productCode || "";
        if (!basePrice) basePrice = Number(pDef.price || 0);
        if (!unit && pDef.unit) unit = pDef.unit;
        if ((!category || category === "Khác") && pDef.category) category = pDef.category;
      }

      if (!prodMap.has(key)) {
        prodMap.set(key, {
          productId: pId,
          productCode: pCode,
          productName: it.name,
          category,
          unit,
          basePrice,
          quantity: 0,
          grossRevenue: 0,
          itemDiscount: 0,
          costPrice: 0,
        });
      }

      const entry = prodMap.get(key)!;
      if (!entry.productCode && pCode) entry.productCode = pCode;
      if (!entry.basePrice && basePrice) entry.basePrice = basePrice;
      if ((!entry.category || entry.category === "Khác") && category) entry.category = category;

      const qty = Number(it.quantity || 1);
      const lineGross = it.lineGrossAmount != null ? Number(it.lineGrossAmount) : (basePrice * qty);
      const itemDisc = Number(it.discountAmount || 0) * qty;

      let lineCost = 0;
      if (it.lineCostPrice != null) {
        lineCost = Number(it.lineCostPrice);
      } else {
        const unitC = Number(it.unitCost != null ? it.unitCost : (it.costPrice || 0));
        lineCost = unitC * qty;
      }

      entry.quantity += qty;
      entry.grossRevenue += lineGross;
      entry.itemDiscount += itemDisc;
      entry.costPrice += lineCost;
    }
  }

  const list: ProductReportItem[] = [];

  for (const e of prodMap.values()) {
    const netRevenue = e.grossRevenue - e.itemDiscount;
    const grossProfit = netRevenue - e.costPrice;
    const grossProfitMarginPercent = netRevenue > 0 ? Number(((grossProfit / netRevenue) * 100).toFixed(2)) : 0;

    list.push({
      productId: typeof e.productId === "string" && !isNaN(Number(e.productId)) ? Number(e.productId) : e.productId,
      productCode: e.productCode,
      productName: e.productName,
      category: e.category,
      unit: e.unit,
      basePrice: e.basePrice,
      quantity: e.quantity,
      grossRevenue: e.grossRevenue,
      itemDiscount: e.itemDiscount,
      netRevenue,
      costPrice: e.costPrice,
      grossProfit,
      grossProfitMarginPercent,
    });
  }

  // Sắp xếp mặc định: Doanh thu thuần giảm dần (REV_DESC)
  list.sort((a, b) => b.netRevenue - a.netRevenue);
  return list;
}

/**
 * Báo cáo 5: Năng suất Nhân viên (Staff Sales Performance)
 */
export function calculateStaffPerformance(bills: HistoryOrder[]): StaffPerformanceResult {
  const deduped = deduplicateBills(bills);
  const paidBills = deduped.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");

  const orderStaffMap = new Map<string, StaffOrderPerformanceItem>();
  const cashierStaffMap = new Map<string, StaffCashierPerformanceItem>();

  for (const b of paidBills) {
    const items = extractBillItems(b);

    // 1. Order Staff
    for (const it of items) {
      const username = it.orderedBy || "unknown";
      const fullName = it.orderedByName || username;
      const key = username;

      if (!orderStaffMap.has(key)) {
        orderStaffMap.set(key, {
          staffUsername: username,
          staffFullName: fullName,
          itemsCount: 0,
          grossRevenue: 0,
          netRevenue: 0,
        });
      }

      const e = orderStaffMap.get(key)!;
      const qty = Number(it.quantity || 1);
      const gross = it.lineGrossAmount != null ? Number(it.lineGrossAmount) : (Number(it.price || 0) * qty);
      const net = it.lineTotal != null ? Number(it.lineTotal) : (gross - Number(it.discountAmount || 0) * qty);

      e.itemsCount += qty;
      e.grossRevenue += gross;
      e.netRevenue += net;
    }

    // 2. Cashier Staff
    const cashierUser = b.staffUsername || b.cashierName || "unknown";
    const cashierFullName = b.staffFullName || b.cashierName || cashierUser;
    const cKey = cashierUser;

    if (!cashierStaffMap.has(cKey)) {
      cashierStaffMap.set(cKey, {
        staffUsername: cashierUser,
        staffFullName: cashierFullName,
        billCount: 0,
        netRevenue: 0,
      });
    }

    const ce = cashierStaffMap.get(cKey)!;
    ce.billCount += 1;
    ce.netRevenue += Number(b.finalAmount != null ? b.finalAmount : (b.totalAmount || 0));
  }

  const orderStaff = Array.from(orderStaffMap.values()).sort((a, b) => b.netRevenue - a.netRevenue);
  const cashierStaff = Array.from(cashierStaffMap.values()).sort((a, b) => b.netRevenue - a.netRevenue);

  return { orderStaff, cashierStaff };
}

/**
 * Báo cáo 6: Phân bổ theo Khung giờ (Hourly Heatmap)
 */
export function calculateHourlyReport(bills: HistoryOrder[]): HourlyReportItem[] {
  const deduped = deduplicateBills(bills);
  const paidBills = deduped.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");

  const hours: HourlyReportItem[] = Array.from({ length: 24 }, (_, i) => ({
    hour: i,
    hourLabel: `${String(i).padStart(2, "0")}:00 - ${String(i).padStart(2, "0")}:59`,
    billCount: 0,
    grossRevenue: 0,
    totalDiscount: 0,
    vatAmount: 0,
    netRevenue: 0,
  }));

  let totalNetDay = 0;

  for (const b of paidBills) {
    const ts = getBillTimestamp(b);
    const d = getUTC7Date(ts);
    const h = d.getUTCHours();

    const gross = Number(b.subTotal != null ? b.subTotal : (b.totalAmount || 0));
    const disc = Number(b.totalDiscount != null ? b.totalDiscount : (b.discountAmount || 0));
    const vat = Number(b.vatAmount || 0);
    const net = Number(b.finalAmount != null ? b.finalAmount : (b.totalAmount || 0));

    hours[h].billCount += 1;
    hours[h].grossRevenue += gross;
    hours[h].totalDiscount += disc;
    hours[h].vatAmount += vat;
    hours[h].netRevenue += net;
    totalNetDay += net;
  }

  hours.forEach((item) => {
    item.proportion = totalNetDay > 0 ? Number(((item.netRevenue / totalNetDay) * 100).toFixed(1)) : 0;
  });

  return hours;
}

/**
 * Báo cáo 7: Hình thức Thanh toán (Payment Methods)
 */
export function calculatePaymentMethodsReport(bills: HistoryOrder[]): Record<string, PaymentMethodSummary> {
  const deduped = deduplicateBills(bills);
  const paidBills = deduped.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");

  const result: Record<string, PaymentMethodSummary> = {
    CASH: { billCount: 0, grossRevenue: 0, totalDiscount: 0, vatAmount: 0, finalAmount: 0 },
    TRANSFER_QR: { billCount: 0, grossRevenue: 0, totalDiscount: 0, vatAmount: 0, finalAmount: 0 },
    CARD: { billCount: 0, grossRevenue: 0, totalDiscount: 0, vatAmount: 0, finalAmount: 0 },
  };

  let totalAll = 0;

  for (const b of paidBills) {
    let pm = (b.paymentMethod || "CASH").toUpperCase();
    if (pm.includes("TRANSFER") || pm.includes("QR") || pm.includes("CHUYỂN")) {
      pm = "TRANSFER_QR";
    } else if (pm.includes("CARD") || pm.includes("THẺ")) {
      pm = "CARD";
    } else {
      pm = "CASH";
    }

    if (!result[pm]) {
      result[pm] = { billCount: 0, grossRevenue: 0, totalDiscount: 0, vatAmount: 0, finalAmount: 0 };
    }

    const gross = Number(b.subTotal != null ? b.subTotal : (b.totalAmount || 0));
    const disc = Number(b.totalDiscount != null ? b.totalDiscount : (b.discountAmount || 0));
    const vat = Number(b.vatAmount || 0);
    const finalA = Number(b.finalAmount != null ? b.finalAmount : (b.totalAmount || 0));

    result[pm].billCount += 1;
    result[pm].grossRevenue += gross;
    result[pm].totalDiscount += disc;
    result[pm].vatAmount += vat;
    result[pm].finalAmount += finalA;
    totalAll += finalA;
  }

  Object.values(result).forEach((summary) => {
    summary.proportion = totalAll > 0 ? Number(((summary.finalAmount / totalAll) * 100).toFixed(1)) : 0;
  });

  return result;
}

/**
 * Báo cáo 8: Khuyến mãi & Voucher (Promotions & Discounts)
 */
export function calculatePromotionsReport(
  bills: HistoryOrder[],
  campaignsMap?: Record<string, string>
): PromotionsReportResult {
  const deduped = deduplicateBills(bills);
  const paidBills = deduped.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");

  const promoMap = new Map<string, CampaignReportItem>();
  let totalDiscountAmount = 0;

  let pointsUsedCount = 0;
  let totalPointsUsed = 0;
  let pointsDiscountAmount = 0;

  let itemDiscountAppliedCount = 0;
  let itemDiscountAmount = 0;
  const itemDiscountDetails = new Map<string, ItemDiscountDetail>();

  for (const b of paidBills) {
    // 1. Bill Campaign Discounts
    if (Array.isArray(b.discounts)) {
      for (const d of b.discounts) {
        const code = d.promoCode || d.promoId || "VOUCHER";
        const id = d.promoId || code;
        const amt = Number(d.amount || 0);
        totalDiscountAmount += amt;

        if (!promoMap.has(code)) {
          let name: string = String(d.promoName || (d as any).name || "");
          if (campaignsMap && campaignsMap[code]) {
            name = campaignsMap[code];
          } else if (!name) {
            if (code === "CHAOBAN20" || id === "PROMO_CHAOBAN") {
              name = "Chào bạn mới giảm 20k";
            } else if (code === "TRIAN10K" || id === "PROMO_TRIAN") {
              name = "Tri ân khách hàng giảm 10k";
            } else {
              name = String(d.description || code);
            }
          }

          promoMap.set(code, {
            promoId: id,
            promoCode: code,
            name,
            usedCount: 0,
            discountAmount: 0,
          });
        }

        const entry = promoMap.get(code)!;
        entry.usedCount += 1;
        entry.discountAmount += amt;
      }
    }

    // 2. Points Redemption
    const pUsed = Number(b.pointsUsed || 0);
    const pDisc = Number(b.pointsDiscount || 0);
    if (pUsed > 0 || pDisc > 0) {
      pointsUsedCount++;
      totalPointsUsed += pUsed;
      pointsDiscountAmount += pDisc;
      totalDiscountAmount += pDisc;
    }

    // 3. Item Discounts
    const items = extractBillItems(b);
    for (const it of items) {
      const itDisc = Number(it.discountAmount || 0);
      if (itDisc > 0) {
        const qty = Number(it.quantity || 1);
        const totalItDisc = itDisc * qty;
        itemDiscountAppliedCount++;
        itemDiscountAmount += totalItDisc;
        totalDiscountAmount += totalItDisc;

        const key = String(it.productId || it.name);
        if (!itemDiscountDetails.has(key)) {
          itemDiscountDetails.set(key, {
            productId: it.productId,
            productName: it.name,
            discountAmount: 0,
            quantity: 0,
          });
        }
        const dt = itemDiscountDetails.get(key)!;
        dt.discountAmount += totalItDisc;
        dt.quantity += qty;
      }
    }
  }

  return {
    totalDiscountAmount,
    campaigns: Array.from(promoMap.values()),
    pointsRedemption: {
      usedCount: pointsUsedCount,
      totalPointsUsed,
      discountAmount: pointsDiscountAmount,
    },
    itemDiscounts: {
      appliedCount: itemDiscountAppliedCount,
      discountAmount: itemDiscountAmount,
      details: Array.from(itemDiscountDetails.values()),
    },
  };
}

/**
 * Báo cáo 9: Hủy món & Hủy đơn hàng (Cancellations & Audit)
 */
export function calculateCancellationReport(bills: HistoryOrder[]): CancellationReportResult {
  const deduped = deduplicateBills(bills);
  const cancelledBills = deduped.filter((b) => (b.status || "").toUpperCase() === "CANCELLED");

  let totalLossValue = 0;
  const list: CancelledBillItem[] = [];

  for (const b of cancelledBills) {
    const val = Number(b.subTotal != null ? b.subTotal : (b.totalAmount || 0));
    totalLossValue += val;

    const items = extractBillItems(b);
    const itemStrings = items.map((it) => `${it.name} x${it.quantity || 1}`);

    const reason: string = String(b.reason || b.notes || b.cancelReason || b.cancellationReason || "Khách hủy đơn");
    const staffName = b.staffFullName || b.cashierName || b.username || "Nhân viên";
    const cancelledAt = Number(b.cancelledAt || b.closedAt || b.createdAt || b.timestamp || Date.now());

    list.push({
      billId: b.id,
      billCode: b.billCode || b.orderCode || b.id,
      tableName: b.tableName || "Mang về",
      staffFullName: staffName,
      cancelledAt,
      reason,
      items: itemStrings,
      subTotal: val,
    });
  }

  list.sort((a, b) => a.cancelledAt - b.cancelledAt);

  return {
    cancelledBillsCount: list.length,
    totalLossValue,
    bills: list,
  };
}

/**
 * Báo cáo 10: Bàn giao Ca & Chênh lệch Két (Cash Shift Variance)
 */
export function calculateCashShiftReport(
  shifts: CashShiftItem[],
  bills: HistoryOrder[]
): CashShiftAuditItem[] {
  const dedupedBills = deduplicateBills(bills);

  return shifts.map((shift) => {
    const sId = shift.shiftId || shift.id || "";
    // Filter bills for this shift
    const shiftBills = dedupedBills.filter((b) => {
      if (b.shiftId && sId) {
        return b.shiftId === sId;
      }
      const bTime = getBillTimestamp(b);
      const closeT = shift.closedAt ? Number(shift.closedAt) : Infinity;
      return shift.openedAt <= bTime && bTime <= closeT;
    });

    const paidBills = shiftBills.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");
    const refundedBills = shiftBills.filter((b) => (b.status || "").toUpperCase() === "REFUNDED");

    let cashSales = 0;
    let qrSales = 0;
    let cardSales = 0;

    for (const b of paidBills) {
      const pm = (b.paymentMethod || "CASH").toUpperCase();
      const amt = Number(b.finalAmount != null ? b.finalAmount : (b.totalAmount || 0));
      if (pm === "CASH" || pm.includes("TIỀN MẶT")) {
        cashSales += amt;
      } else if (pm === "TRANSFER_QR" || pm === "TRANSFER" || pm.includes("CHUYỂN")) {
        qrSales += amt;
      } else if (pm === "CARD" || pm.includes("THẺ")) {
        cardSales += amt;
      } else {
        cashSales += amt;
      }
    }

    const totalSales = cashSales + qrSales + cardSales;

    let refundCash = 0;
    for (const b of refundedBills) {
      const rAmt = Number(b.refundAmount != null ? b.refundAmount : (b.finalAmount || b.totalAmount || 0));
      refundCash += rAmt;
    }

    const initialCash = Number(shift.initialCash || 0);
    const cashIn = Number(shift.cashIn || 0);
    const cashOut = Number(shift.cashOut || 0);

    const expectedCash = initialCash + cashSales - refundCash + cashIn - cashOut;
    const actualCash = shift.actualCash != null ? Number(shift.actualCash) : expectedCash;
    const difference = actualCash - expectedCash;

    return {
      shiftId: sId,
      shiftCode: shift.shiftCode || sId,
      shiftName: shift.shiftName,
      storeCode: shift.storeCode,
      staffUsername: shift.staffUsername,
      staffFullName: shift.staffFullName,
      openedAt: Number(shift.openedAt),
      closedAt: shift.closedAt != null ? Number(shift.closedAt) : null,
      initialCash,
      cashIn,
      cashOut,
      cashSales,
      qrSales,
      cardSales,
      totalSales,
      refundCash,
      expectedCash,
      actualCash,
      difference,
      status: shift.status || "CLOSED",
      notes: shift.notes || "",
    };
  });
}

/**
 * Báo cáo 11: Lợi nhuận gộp & Giá vốn (Gross Profit & COGS)
 */
export function calculateGrossProfitReport(
  bills: HistoryOrder[],
  productsMap?: Record<string | number, any>
): GrossProfitReportResult {
  const prodItems = calculateProductReport(bills, productsMap);

  let totalQuantity = 0;
  let totalNet = 0;
  let totalCOGS = 0;

  const items: GrossProfitItem[] = prodItems.map((p) => {
    totalQuantity += p.quantity;
    totalNet += p.netRevenue;
    totalCOGS += p.costPrice;

    const avgSelling = p.quantity > 0 ? Math.round(p.grossRevenue / p.quantity) : p.basePrice;
    const avgCost = p.quantity > 0 ? Math.round(p.costPrice / p.quantity) : 0;

    return {
      productId: p.productId,
      productName: p.productName,
      category: p.category,
      quantity: p.quantity,
      avgSellingPrice: avgSelling,
      avgCostPrice: avgCost,
      netRevenue: p.netRevenue,
      cogs: p.costPrice,
      grossProfit: p.grossProfit,
      grossProfitMarginPercent: p.grossProfitMarginPercent,
    };
  });

  const grossProfit = totalNet - totalCOGS;
  const grossProfitMarginPercent = totalNet > 0 ? Number(((grossProfit / totalNet) * 100).toFixed(2)) : 0;

  return {
    items,
    summary: {
      totalQuantity,
      netRevenue: totalNet,
      totalCOGS,
      grossProfit,
      grossProfitMarginPercent,
    },
  };
}

/**
 * Báo cáo 12: Báo cáo Cuối ngày Z-Report (End-Of-Day Z-Report)
 */
export function generateEndOfDayZReport(
  bills: HistoryOrder[],
  shifts: CashShiftItem[],
  tables: TableItem[],
  productsMap?: Record<string | number, any>,
  options?: { date?: string; storeCode?: string; storeName?: string }
): EndOfDayReportData {
  const deduped = deduplicateBills(bills);
  const paidBills = deduped.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");
  const refundedBills = deduped.filter((b) => (b.status || "").toUpperCase() === "REFUNDED");

  // Tab 1: Tổng hợp
  const overview = calculateOverviewReport(bills);

  // Tab 2: Thu chi
  const paymentMethods = calculatePaymentMethodsReport(bills);
  const cashSales = paymentMethods.CASH?.finalAmount || 0;
  const transferSales = paymentMethods.TRANSFER_QR?.finalAmount || 0;
  const cardSales = paymentMethods.CARD?.finalAmount || 0;
  const totalRevenue = cashSales + transferSales + cardSales;

  const cashInTotal = shifts.reduce((sum, s) => sum + Number(s.cashIn || 0), 0);
  const cashOutTotal = shifts.reduce((sum, s) => sum + Number(s.cashOut || 0), 0);
  const refundTotal = refundedBills.reduce((sum, b) => sum + Number(b.refundAmount != null ? b.refundAmount : (b.finalAmount || b.totalAmount || 0)), 0);

  // Tab 3: Hàng hóa
  const products = calculateProductReport(bills, productsMap);
  const totalItemsSold = products.reduce((sum, p) => sum + p.quantity, 0);

  // Tab 4: Phòng bàn
  const zoneMap = new Map<string, { zone: string; billCount: number; netRevenue: number }>();
  for (const b of paidBills) {
    const z = b.zone || "Khác";
    if (!zoneMap.has(z)) {
      zoneMap.set(z, { zone: z, billCount: 0, netRevenue: 0 });
    }
    const ze = zoneMap.get(z)!;
    ze.billCount += 1;
    ze.netRevenue += Number(b.finalAmount != null ? b.finalAmount : (b.totalAmount || 0));
  }

  // Preserve ordering or sort by netRevenue desc
  const zones = Array.from(zoneMap.values());

  const dateStr = options?.date || (paidBills.length > 0 ? new Date(getBillTimestamp(paidBills[0])).toISOString().slice(0, 10) : new Date().toISOString().slice(0, 10));
  const storeCode = options?.storeCode || (paidBills[0]?.storeCode || "TRAM01");
  const storeName = options?.storeName || (paidBills[0]?.storeName || `POS Trạm - ${storeCode}`);

  return {
    date: dateStr,
    storeCode,
    storeName,
    tab1_tongHop: {
      grossRevenue: overview.grossRevenue,
      itemDiscounts: overview.itemDiscounts,
      billDiscounts: overview.billDiscounts + overview.pointsDiscounts, // Đặc tả Tab 1 gồm giảm giá hóa đơn & tích điểm
      totalDiscount: overview.totalDiscount,
      afterDiscount: overview.afterDiscount,
      vatTotal: overview.vatTotal,
      netRevenue: overview.netRevenue,
      refundAmount: overview.refundAmount,
      netRevenueWithoutRefund: overview.netRevenueWithoutRefund,
      paidBillsCount: overview.paidBillsCount,
      avgRevenuePerBill: overview.avgRevenuePerPaidBill,
      totalGuests: overview.totalGuests,
    },
    tab2_thuChi: {
      cashSales,
      transferSales,
      cardSales,
      totalRevenue,
      cashInTotal,
      cashOutTotal,
      refundTotal,
    },
    tab3_hangHoa: {
      totalItemsSold,
      products,
    },
    tab4_phongBan: {
      zones,
    },
  };
}

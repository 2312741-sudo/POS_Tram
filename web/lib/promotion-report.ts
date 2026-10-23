/**
 * Báo cáo khuyến mãi theo chiến dịch — hàm thuần.
 *
 * Nguồn: bill.discounts[] của hóa đơn PAID. Mỗi phần tử (hợp đồng mới) có
 *   campaignId, campaignName, programCode, campaignType, voucherCode, amount;
 * dữ liệu cũ có thể chỉ có promoId / promoCode / promoName / name / description.
 * Nhóm theo campaignId → promoId → mã (programCode/promoCode) → tên.
 */
import { deduplicateBills, getBillTimestamp, type HistoryOrder } from "./reports";

export interface CampaignBillRow {
  billId: string;
  billCode: string;
  timestamp: number;
  tableName: string;
  voucherCode: string;
  discount: number;
  finalAmount: number;
  staff: string;
  storeCode?: string;
  /** Số điểm tích lũy khách đã đổi trên hóa đơn này (chỉ dòng "Đổi điểm tích lũy") */
  pointsUsed?: number;
  /** Số lượng combo áp dụng trên hóa đơn này */
  comboCount?: number;
}

export interface CampaignSummary {
  key: string;
  campaignId: string;
  name: string;
  code: string;
  type: string;
  typeLabel: string;
  billCount: number;
  /** Tổng số lượng combo được áp dụng */
  comboCount: number;
  totalDiscount: number;
  /** Doanh thu (finalAmount) của các hóa đơn có áp dụng chiến dịch */
  revenue: number;
  /** Số lượt dùng voucher (dòng giảm giá có voucherCode) */
  vouchersUsed: number;
  voucherCodes: string[];
  bills: CampaignBillRow[];
  /** Tổng điểm khách đã đổi (chỉ dòng "Đổi điểm tích lũy") */
  pointsUsed?: number;
}

export interface CampaignReport {
  campaigns: CampaignSummary[];
  totalDiscount: number;
  /** Số hóa đơn (không trùng) có ít nhất một khuyến mãi */
  billCount: number;
  /** Tổng số combo được áp dụng toàn kỳ */
  comboCount: number;
  revenue: number;
  vouchersUsed: number;
  /** Tổng điểm tích lũy khách đã đổi trong kỳ */
  pointsUsed: number;
}

/** Khóa dòng "Đổi điểm tích lũy" trong báo cáo khuyến mãi */
export const POINTS_ROW_KEY = "points:redeem";

const str = (v: unknown) => (v == null ? "" : String(v).trim());

export const CAMPAIGN_TYPE_LABELS: Record<string, string> = {
  BILLDISCOUNT: "Giảm giá đơn hàng",
  ORDERVALUEITEMBENEFIT: "Tặng / giảm món theo giá trị đơn",
  BUYXGETY: "Mua X tặng Y",
  ITEMPRICERULE: "Đồng giá / đồng giảm",
  POINTS: "Đổi điểm tích lũy",
};

export function campaignTypeLabel(type: string): string {
  const k = type.toUpperCase().replace(/[^A-Z]/g, "");
  if (!k) return "Khuyến mãi (dữ liệu cũ)";
  return CAMPAIGN_TYPE_LABELS[k] || type;
}

interface DiscountLike {
  campaignId?: unknown;
  campaignName?: unknown;
  programCode?: unknown;
  campaignType?: unknown;
  voucherCode?: unknown;
  promoId?: unknown;
  promoCode?: unknown;
  promoName?: unknown;
  name?: unknown;
  description?: unknown;
  amount?: unknown;
  comboCount?: unknown;
}

/** Khóa nhóm + thông tin hiển thị của một dòng giảm giá */
export function campaignIdentity(d: DiscountLike): { key: string; campaignId: string; name: string; code: string; type: string } {
  const campaignId = str(d.campaignId) || str(d.promoId);
  const name = str(d.campaignName) || str(d.promoName) || str(d.name) || str(d.description);
  const code = str(d.programCode) || str(d.promoCode);
  const key = campaignId ? `id:${campaignId}` : code ? `code:${code}` : name ? `name:${name}` : "unknown";
  return { key, campaignId, name: name || code || "Khuyến mãi không rõ", code, type: str(d.campaignType) };
}

function discountsOf(b: HistoryOrder): DiscountLike[] {
  const d = b.discounts as unknown;
  if (Array.isArray(d)) return d.filter((x) => x && typeof x === "object") as DiscountLike[];
  if (d && typeof d === "object") return Object.values(d as Record<string, unknown>).filter((x) => x && typeof x === "object") as DiscountLike[];
  return [];
}

/** Tổng hợp khuyến mãi theo chiến dịch cho các hóa đơn PAID */
export function calculateCampaignReport(bills: HistoryOrder[]): CampaignReport {
  const map = new Map<string, CampaignSummary & { _bills: Map<string, CampaignBillRow>; _codes: Set<string> }>();
  const promoBills = new Map<string, number>();
  let vouchersUsed = 0;
  let totalDiscount = 0;
  let totalComboCount = 0;

  for (const b of deduplicateBills(bills)) {
    if (String(b.status || "PAID").toUpperCase() !== "PAID") continue;
    const discounts = discountsOf(b);
    if (discounts.length === 0) continue;
    const finalAmount = Number(b.finalAmount != null ? b.finalAmount : b.totalAmount || 0) || 0;
    for (const d of discounts) {
      const amount = Math.max(0, Number(d.amount) || 0);
      const comboCount = Math.max(0, Number(d.comboCount) || 0);
      const id = campaignIdentity(d);
      let c = map.get(id.key);
      if (!c) {
        c = {
          key: id.key,
          campaignId: id.campaignId,
          name: id.name,
          code: id.code,
          type: id.type,
          typeLabel: campaignTypeLabel(id.type),
          billCount: 0,
          comboCount: 0,
          totalDiscount: 0,
          revenue: 0,
          vouchersUsed: 0,
          voucherCodes: [],
          bills: [],
          _bills: new Map(),
          _codes: new Set(),
        };
        map.set(id.key, c);
      }
      if (!c.code && id.code) c.code = id.code;
      if (!c.type && id.type) {
        c.type = id.type;
        c.typeLabel = campaignTypeLabel(id.type);
      }
      const voucher = str(d.voucherCode);
      c.totalDiscount += amount;
      totalDiscount += amount;
      if (comboCount > 0) {
        c.comboCount += comboCount;
        totalComboCount += comboCount;
      }
      if (voucher) {
        c.vouchersUsed += 1;
        vouchersUsed += 1;
        c._codes.add(voucher);
      }
      const row = c._bills.get(b.id);
      if (row) {
        row.discount += amount;
        if (comboCount > 0) row.comboCount = (row.comboCount || 0) + comboCount;
        if (voucher && !row.voucherCode.split(", ").includes(voucher)) {
          row.voucherCode = row.voucherCode ? `${row.voucherCode}, ${voucher}` : voucher;
        }
      } else {
        c._bills.set(b.id, {
          billId: b.id,
          billCode: b.billCode || b.orderCode || b.id,
          timestamp: getBillTimestamp(b),
          tableName: b.tableName || "",
          voucherCode: voucher,
          discount: amount,
          comboCount: comboCount > 0 ? comboCount : undefined,
          finalAmount,
          staff: b.cashierName || b.staffFullName || b.staffUsername || "",
          storeCode: b.storeCode,
        });
        c.billCount += 1;
        c.revenue += finalAmount;
      }
    }
    promoBills.set(b.id, finalAmount);
  }

  // Đổi điểm tích lũy: coi là một "chương trình" riêng trong báo cáo khuyến mãi (từ bill.pointsDiscount / pointsUsed)
  let pointsUsedTotal = 0;
  for (const b of deduplicateBills(bills)) {
    if (String(b.status || "PAID").toUpperCase() !== "PAID") continue;
    const pDisc = Math.max(0, Number(b.pointsDiscount) || 0);
    const pUsed = Math.max(0, Math.trunc(Number(b.pointsUsed) || 0));
    if (pDisc <= 0 && pUsed <= 0) continue;
    const finalAmount = Number(b.finalAmount != null ? b.finalAmount : b.totalAmount || 0) || 0;
    let c = map.get(POINTS_ROW_KEY);
    if (!c) {
      c = {
        key: POINTS_ROW_KEY, campaignId: "", name: "Đổi điểm tích lũy", code: "DOI_DIEM", type: "POINTS", typeLabel: campaignTypeLabel("POINTS"),
        billCount: 0, comboCount: 0, totalDiscount: 0, revenue: 0, vouchersUsed: 0, voucherCodes: [], bills: [], pointsUsed: 0, _bills: new Map(), _codes: new Set(),
      };
      map.set(POINTS_ROW_KEY, c);
    }
    c.totalDiscount += pDisc;
    c.pointsUsed = (c.pointsUsed ?? 0) + pUsed;
    c.billCount += 1;
    c.revenue += finalAmount;
    pointsUsedTotal += pUsed;
    totalDiscount += pDisc;
    c._bills.set(b.id, {
      billId: b.id, billCode: b.billCode || b.orderCode || b.id, timestamp: getBillTimestamp(b), tableName: b.tableName || "",
      voucherCode: "", discount: pDisc, finalAmount, staff: b.cashierName || b.staffFullName || b.staffUsername || "", storeCode: b.storeCode, pointsUsed: pUsed,
    });
    promoBills.set(b.id, finalAmount);
  }

  const campaigns: CampaignSummary[] = Array.from(map.values())
    .map((c) => {
      const { _bills, _codes, ...rest } = c;
      return {
        ...rest,
        voucherCodes: Array.from(_codes).sort(),
        bills: Array.from(_bills.values()).sort((a, b) => b.timestamp - a.timestamp),
      };
    })
    .sort((a, b) => b.totalDiscount - a.totalDiscount || a.name.localeCompare(b.name, "vi"));

  return {
    campaigns,
    totalDiscount,
    billCount: promoBills.size,
    comboCount: totalComboCount,
    revenue: Array.from(promoBills.values()).reduce((s, v) => s + v, 0),
    vouchersUsed,
    pointsUsed: pointsUsedTotal,
  };
}

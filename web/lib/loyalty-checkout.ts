/**
 * Khách hàng + tích điểm khi gọi món / thanh toán trên Web (logic thuần, có test).
 * Công thức khớp: functions/src/sharedLoyalty.ts (computeEarnPoints, resolveRates) và
 * app_flutter order_cart_screen.dart (_pointsDiscount, _earnPreview, số điểm tối đa dùng được).
 */
import { searchCustomers, type CustomerMatch } from "./customer-search";
import { tierForTotalPoints, type ChainLoyaltyConfig, type LoyaltyTier } from "./loyalty";
import type { StoreCustomer } from "./customers";

export const DEFAULT_EARN_PERCENT = 1;
export const DEFAULT_REDEEM_VND = 1000;

export interface LoyaltyRates {
  /** % doanh thu quy ra điểm */
  earnRate: number;
  /** đ trên mỗi điểm */
  redeemRate: number;
  /** chain/store = đã cấu hình; default = chưa ai cấu hình (máy chủ dùng 1% và 1000đ/điểm) */
  source: "chain" | "store" | "default";
}

const finite = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) ? v : undefined);

/** Cùng thứ tự ưu tiên với resolveRates của máy chủ: loyalty_config → storeInfo → mặc định */
export function resolveRates(
  chain: ChainLoyaltyConfig | undefined,
  store: { pointEarnRate?: unknown; pointRedeemRate?: unknown } | undefined
): LoyaltyRates {
  const ce = finite(chain?.pointEarnRate);
  const cr = finite(chain?.pointRedeemRate);
  const se = finite(store?.pointEarnRate);
  const sr = finite(store?.pointRedeemRate);
  const earn = ce ?? se;
  const redeem = (cr !== undefined && cr > 0 ? cr : undefined) ?? (sr !== undefined && sr > 0 ? sr : undefined);
  const source: LoyaltyRates["source"] = ce !== undefined || cr !== undefined ? "chain" : se !== undefined || sr !== undefined ? "store" : "default";
  return { earnRate: earn ?? DEFAULT_EARN_PERCENT, redeemRate: redeem ?? DEFAULT_REDEEM_VND, source };
}

/** Điểm tích cho hóa đơn = round(tiền thực trả × rate% / đ-mỗi-điểm) — y hệt máy chủ */
export function computeEarnPoints(finalAmount: number, earnRatePercent: number, redeemRate: number): number {
  if (!(finalAmount > 0) || !(earnRatePercent > 0) || !(redeemRate > 0)) return 0;
  const p = Math.round((finalAmount * (earnRatePercent / 100)) / redeemRate);
  return p > 0 ? p : 0;
}

/** Hóa đơn tối thiểu (đ) để được 1 điểm; null nếu tỷ lệ tích bằng 0 */
export function minBillForOnePoint(earnRatePercent: number, redeemRate: number): number | null {
  if (!(earnRatePercent > 0) || !(redeemRate > 0)) return null;
  let a = Math.max(1, Math.ceil((50 * redeemRate) / earnRatePercent));
  while (a > 1 && computeEarnPoints(a - 1, earnRatePercent, redeemRate) >= 1) a--;
  while (computeEarnPoints(a, earnRatePercent, redeemRate) < 1) a++;
  return a;
}

/**
 * Số điểm tối đa được dùng: không quá số dư và không quá số điểm "phủ" phần tiền còn lại
 * (sau giảm giá món + khuyến mãi, như Flutter: availableAmount ~/ redeemRate).
 */
export function maxRedeemablePoints(balance: number, amountBeforePoints: number, redeemRate: number): number {
  if (!(redeemRate > 0) || !(amountBeforePoints > 0) || !(balance > 0)) return 0;
  return Math.max(0, Math.min(Math.floor(balance), Math.floor(amountBeforePoints / redeemRate)));
}

/** Đọc số điểm người dùng gõ: chỉ lấy chữ số, kẹp trong [0, max] */
export function clampPointsInput(raw: string, max: number): number {
  const n = parseInt(raw.replace(/\D/g, ""), 10);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(n, Math.max(0, max));
}

export interface BillAmounts {
  subTotal: number;
  itemDiscounts: number;
  /** Giảm giá cả hóa đơn khác (không gồm khuyến mãi và điểm) */
  billDiscounts: number;
  pointsUsed: number;
  pointsDiscount: number;
  /** Tổng giảm gồm cả đổi điểm (không vượt tạm tính) */
  totalDiscount: number;
  finalAmount: number;
}

/** Số tiền hóa đơn khi thanh toán (khuyến mãi + đổi điểm); đổi điểm là một phần của totalDiscount như Flutter */
export function computeBillAmounts(a: {
  subTotal: number;
  itemDiscounts: number;
  manualDiscount?: number;
  promoTotal?: number;
  pointsUsed?: number;
  redeemRate?: number;
}): BillAmounts {
  const pointsUsed = Math.max(0, Math.trunc(a.pointsUsed ?? 0));
  const pointsDiscount = pointsUsed > 0 ? pointsUsed * Math.max(0, a.redeemRate ?? 0) : 0;
  const billDiscounts = Math.max(0, a.manualDiscount ?? 0) + Math.max(0, a.promoTotal ?? 0) + pointsDiscount;
  const totalDiscount = Math.min(a.subTotal, a.itemDiscounts + billDiscounts);
  return {
    subTotal: a.subTotal,
    itemDiscounts: a.itemDiscounts,
    billDiscounts,
    pointsUsed,
    pointsDiscount,
    totalDiscount,
    finalAmount: Math.max(0, a.subTotal - totalDiscount),
  };
}

export interface BillCustomer {
  id: string;
  name?: string;
  phone?: string;
}

/** Trường khách + đổi điểm ghi vào hóa đơn (tên trường như BillModel.toMap của Flutter) */
export function loyaltyBillFields(c: BillCustomer | undefined, amounts: Pick<BillAmounts, "pointsUsed" | "pointsDiscount">): Record<string, string | number> {
  if (!c?.id) return {};
  return {
    customerId: c.id,
    ...(c.name ? { customerName: c.name } : {}),
    ...(c.phone ? { customerPhone: c.phone } : {}),
    ...(amounts.pointsUsed > 0 ? { pointsUsed: amounts.pointsUsed, pointsDiscount: amounts.pointsDiscount } : {}),
  };
}

export interface PointsPreview {
  /** Điểm sẽ tích */
  earn: number;
  before: number;
  used: number;
  /** Số dư sau thanh toán = trước − dùng + tích */
  after: number;
  tierBefore: string;
  tierAfter: string;
  /** earn = 0 và tỷ lệ hợp lệ → hóa đơn tối thiểu để có 1 điểm */
  minBillForPoint: number | null;
}

export function buildPointsPreview(a: {
  balance: number;
  totalPoints: number;
  payable: number;
  pointsUsed: number;
  rates: Pick<LoyaltyRates, "earnRate" | "redeemRate">;
  tiers: LoyaltyTier[];
}): PointsPreview {
  const before = Math.max(0, Math.trunc(a.balance));
  const used = Math.min(before, Math.max(0, Math.trunc(a.pointsUsed)));
  const earn = computeEarnPoints(a.payable, a.rates.earnRate, a.rates.redeemRate);
  const total = Math.max(0, Math.trunc(a.totalPoints));
  return {
    earn,
    before,
    used,
    after: before - used + earn,
    tierBefore: tierForTotalPoints(total, a.tiers),
    tierAfter: tierForTotalPoints(total + earn, a.tiers),
    minBillForPoint: earn > 0 ? null : minBillForOnePoint(a.rates.earnRate, a.rates.redeemRate),
  };
}

// ---------------------------------------------------------------------------
// Danh sách chọn khách
// ---------------------------------------------------------------------------

export interface PickerCustomer {
  id: string;
  name: string;
  phone: string;
  points: number;
  totalPoints: number;
  lastVisitAt: number;
  /** Khách có ở chi nhánh khác (chưa có hồ sơ tại chi nhánh này) */
  remote?: boolean;
}

export function toPickerCustomers(list: StoreCustomer[]): PickerCustomer[] {
  return list.map((c) => ({
    id: c.id,
    name: c.hoTen,
    phone: c.soDienThoai,
    points: c.diemHienTai,
    totalPoints: c.tongDiem,
    lastVisitAt: c.lastVisitAt ?? c.createdAt ?? 0,
  }));
}

/** Rỗng → ~10 khách gần đây/nhiều điểm; có chữ → tìm theo SĐT / tên (customer-search) */
export function rankPickerCustomers(all: PickerCustomer[], query: string, limit = 10): CustomerMatch<PickerCustomer>[] {
  return searchCustomers(all, query, limit);
}

/** Khách gắn bàn → payload ghi vào bàn (trường như Flutter TableModel) */
export function tableCustomerPayload(c: BillCustomer | null): Record<string, string | null> {
  return { customerId: c?.id ?? null, customerName: c?.name ?? null, customerPhone: c?.phone ?? null };
}

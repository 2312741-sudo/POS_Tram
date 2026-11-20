/**
 * KHUYẾN MÃI TÍNH CHO NGƯỜI BẤM MÓN (không phải người thu tiền).
 *
 * Lúc thanh toán: mỗi khuyến mãi (combo, giảm món, tặng món, giảm hóa đơn…) được chia theo NGƯỜI BẤM các món nhận ưu đãi
 * → lưu vào discount.staffShares = [{ u: username, n: tên, amount: tiền giảm, combo: số combo }] (tổng amount = discount.amount).
 *   - Tiền giảm của từng dòng = phần chương trình đó giảm trên dòng (đã trừ giảm tay); giảm hóa đơn chia theo dòng như engine.
 *   - Số combo = số phần món được thưởng (rewardBenefits) trên dòng của người đó.
 * Báo cáo: lọc / gom theo nhân viên dùng staffShares. Hóa đơn cũ chưa có: cả đơn do 1 người bấm → người đó; còn lại → thu ngân.
 * Bản Dart song song: app_flutter/lib/core/reports/promo_attribution.dart (test đối chiếu: docs/promo_attribution_parity.json).
 */
import { manualLineDiscount, type PriceQuote, type PricingLine } from "./pricing-engine";
import { extractBillItems, type HistoryOrder } from "./reports";

export interface StaffShare {
  /** username người bấm món ("" nếu không rõ) */
  u: string;
  /** tên hiển thị */
  n: string;
  amount: number;
  combo: number;
}

export interface LineStaff {
  u: string;
  n: string;
}

type DiscountLike = NonNullable<HistoryOrder["discounts"]>[number];

const keyOf = (s: LineStaff) => (s.u || s.n).trim().toLowerCase();

/** Chia [total] theo trọng số (phần dư chia cho phần lẻ lớn nhất, hòa thì theo thứ tự) */
function apportion(weights: number[], total: number): number[] {
  const sum = weights.reduce((a, b) => a + b, 0);
  if (sum <= 0) return weights.map(() => 0);
  const raw = weights.map((w) => (w * total) / sum);
  const out = raw.map(Math.floor);
  let left = total - out.reduce((a, b) => a + b, 0);
  const order = raw.map((r, i) => ({ i, f: r - Math.floor(r) })).sort((a, b) => b.f - a.f || a.i - b.i);
  for (let k = 0; left > 0 && k < order.length; k++, left--) out[order[k].i] += 1;
  return out;
}

/**
 * Chia một khuyến mãi theo người bấm món, từ báo giá cộng dồn của chương trình đó ([quote] = quoteStacked(...)[campaignId]).
 * [staffOfLine]: người bấm dòng (lineId → {u, n}); dòng không rõ người bấm → [fallback] (thu ngân).
 * [storedAmount]: tiền giảm đã lưu trên hóa đơn — các phần được làm tròn để cộng lại đúng bằng số này.
 */
export function promoStaffShares(
  quote: PriceQuote,
  lines: PricingLine[],
  campaignId: string,
  staffOfLine: (lineId: string) => LineStaff | null | undefined,
  fallback: LineStaff,
  storedAmount?: number,
): StaffShare[] {
  const byLine = new Map(lines.map((l) => [l.lineId, l]));
  const acc = new Map<string, StaffShare>();
  const add = (lineId: string, amount: number, combo: number) => {
    if (amount <= 0 && combo <= 0) return;
    const s = staffOfLine(lineId);
    const who = s && keyOf(s) ? s : fallback;
    const k = keyOf(who) || "?";
    const e = acc.get(k) ?? { u: who.u, n: who.n || who.u, amount: 0, combo: 0 };
    e.amount += Math.max(0, amount);
    e.combo += Math.max(0, combo);
    acc.set(k, e);
  };
  for (const lb of quote.lineBenefits) {
    if (lb.campaignId) continue;
    const line = byLine.get(lb.lineId);
    const manual = line ? manualLineDiscount(line) : 0;
    add(lb.lineId, lb.discountMoney - manual, 0);
  }
  for (const rb of quote.rewardBenefits) {
    if (rb.campaignId && rb.campaignId !== campaignId) continue;
    add(rb.lineId, 0, rb.quantity ?? 0);
  }
  const shares = Array.from(acc.values());
  if (storedAmount != null && storedAmount >= 0) {
    const sum = shares.reduce((a, s) => a + s.amount, 0);
    if (sum !== storedAmount) {
      if (sum <= 0) {
        // Không chia được theo dòng (dữ liệu lệch) → cả khoản cho thu ngân, giữ số combo đã chia
        const combo = shares.reduce((a, s) => a + s.combo, 0);
        return storedAmount > 0 || combo > 0 ? [{ u: fallback.u, n: fallback.n || fallback.u, amount: storedAmount, combo }] : [];
      }
      const parts = apportion(shares.map((s) => s.amount), storedAmount);
      shares.forEach((s, i) => (s.amount = parts[i]));
    }
  }
  return shares.filter((s) => s.amount > 0 || s.combo > 0);
}

/** Người bấm món duy nhất của hóa đơn (cả đơn do 1 người bấm), không thì null */
export function soleOrderer(bill: HistoryOrder): LineStaff | null {
  const seen = new Map<string, LineStaff>();
  for (const it of extractBillItems(bill)) {
    const u = String(it.orderedBy ?? "").trim();
    const n = String(it.orderedByName ?? "").trim();
    const s = { u, n: n || u };
    const k = keyOf(s);
    if (k) seen.set(k, s);
  }
  return seen.size === 1 ? Array.from(seen.values())[0] : null;
}

export function cashierOf(bill: HistoryOrder): LineStaff {
  const u = String(bill.staffUsername ?? "").trim();
  const n = String(bill.staffFullName || bill.cashierName || u || "").trim();
  return { u, n };
}

/** Phần chia theo người bấm món của một khuyến mãi trên hóa đơn (hóa đơn cũ: người bấm duy nhất / thu ngân) */
export function discountStaffShares(bill: HistoryOrder, d: DiscountLike): StaffShare[] {
  const raw = (d as { staffShares?: unknown }).staffShares;
  const list = Array.isArray(raw) ? raw : raw && typeof raw === "object" ? Object.values(raw as Record<string, unknown>) : [];
  const shares: StaffShare[] = [];
  for (const x of list) {
    if (!x || typeof x !== "object") continue;
    const o = x as Record<string, unknown>;
    const amount = Math.max(0, Number(o.amount) || 0);
    const combo = Math.max(0, Math.trunc(Number(o.combo) || 0));
    if (amount <= 0 && combo <= 0) continue;
    shares.push({ u: String(o.u ?? ""), n: String(o.n ?? o.u ?? ""), amount, combo });
  }
  if (shares.length > 0) return shares;
  const who = soleOrderer(bill) ?? cashierOf(bill);
  const amount = Math.max(0, Number(d.amount) || 0);
  const combo = Math.max(0, Math.trunc(Number((d as { comboCount?: unknown }).comboCount) || 0));
  return amount > 0 || combo > 0 ? [{ ...who, amount, combo }] : [];
}

/**
 * Hóa đơn chỉ giữ phần khuyến mãi của nhân viên [matches] (theo người bấm món) — để báo cáo khuyến mãi / chương trình
 * lọc theo nhân viên. Đổi điểm (cả hóa đơn) tính cho thu ngân; giảm tay trên món tính cho người bấm món đó.
 */
export function attributeBillsToStaff(bills: HistoryOrder[], matches: (s: LineStaff) => boolean): HistoryOrder[] {
  const out: HistoryOrder[] = [];
  for (const b of bills) {
    const discounts: DiscountLike[] = [];
    const raw = b.discounts as unknown;
    const ds = Array.isArray(raw) ? raw : raw && typeof raw === "object" ? Object.values(raw as Record<string, unknown>) : [];
    for (const d of ds as DiscountLike[]) {
      if (!d || typeof d !== "object") continue;
      const mine = discountStaffShares(b, d).filter(matches);
      const amount = mine.reduce((a, s) => a + s.amount, 0);
      const combo = mine.reduce((a, s) => a + s.combo, 0);
      if (amount <= 0 && combo <= 0) continue;
      discounts.push({ ...d, amount, comboCount: combo > 0 ? combo : undefined, staffShares: mine });
    }
    const cashierMine = matches(cashierOf(b));
    const items = extractBillItems(b).filter((it) => {
      const u = String(it.orderedBy ?? "").trim();
      const n = String(it.orderedByName ?? "").trim();
      return (u || n) ? matches({ u, n: n || u }) : cashierMine;
    });
    const points = cashierMine && (Number(b.pointsDiscount) > 0 || Number(b.pointsUsed) > 0);
    if (discounts.length === 0 && !points && items.length === 0) continue;
    out.push({
      ...b,
      discounts,
      items,
      itemsJson: undefined,
      itemDiscounts: undefined,
      pointsDiscount: points ? b.pointsDiscount : 0,
      pointsUsed: points ? b.pointsUsed : 0,
    });
  }
  return out;
}

/** So khớp nhân viên theo username / tên / bí danh (giống lọc nhân viên của Trung tâm báo cáo) */
export function staffMatcher(staff: string, aliases?: Iterable<string>): (s: LineStaff) => boolean {
  const targets = new Set<string>();
  for (const t of [staff, ...(aliases ?? [])]) {
    const v = String(t ?? "").trim().toLowerCase();
    if (v) targets.add(v);
  }
  return (s) => targets.has(s.u.trim().toLowerCase()) || targets.has(s.n.trim().toLowerCase());
}

/**
 * Khuyến mãi / giảm giá đơn đang áp trên BÀN — trường tables/{key}/discountsJson, hợp đồng chung với Flutter
 * (TableModel.discountsJson = JSON mảng BillDiscountModel.toMap()). App và web cùng đọc / ghi trường này
 * nên khuyến mãi áp ở máy nào cũng hiện ở máy kia.
 *  - Mục có campaignId: chương trình khuyến mãi (web tính lại số tiền theo đơn hiện tại).
 *  - Mục khác (giảm % / số tiền thủ công của app, khuyến mãi cũ): giữ nguyên, tính đúng số tiền đã lưu.
 */
import type { AppliedDiscount } from "./pricing-engine";

export interface TableDiscountEntry {
  promoId?: string;
  promoCode?: string;
  description: string;
  amount: number;
  staffNote?: string;
  campaignId?: string;
  campaignName?: string;
  programCode?: string;
  campaignType?: string;
  voucherCode?: string;
  comboCount?: number;
  manualPercent?: number;
}

const str = (v: unknown): string | undefined => (v == null || String(v).trim() === "" ? undefined : String(v));

/** Đọc discountsJson (chuỗi JSON hoặc mảng) an toàn */
export function parseTableDiscounts(raw: unknown): TableDiscountEntry[] {
  let list: unknown = raw;
  if (typeof list === "string") {
    try {
      list = list.trim() ? JSON.parse(list) : [];
    } catch {
      list = [];
    }
  }
  if (!Array.isArray(list)) return [];
  const out: TableDiscountEntry[] = [];
  for (const d of list) {
    if (!d || typeof d !== "object") continue;
    const o = d as Record<string, unknown>;
    const entry: TableDiscountEntry = { description: String(o.description ?? ""), amount: Math.max(0, Math.trunc(Number(o.amount) || 0)) };
    for (const k of ["promoId", "promoCode", "staffNote", "campaignId", "campaignName", "programCode", "campaignType", "voucherCode"] as const) {
      const v = str(o[k]);
      if (v) entry[k] = v;
    }
    const combo = Math.trunc(Number(o.comboCount) || 0);
    if (combo > 0) entry.comboCount = combo;
    const pct = Math.trunc(Number(o.manualPercent) || 0);
    if (pct > 0) entry.manualPercent = pct;
    out.push(entry);
  }
  return out;
}

/** Tách: chương trình khuyến mãi (để web tính lại) và các mục khác (giữ nguyên) */
export function splitTableDiscounts(list: TableDiscountEntry[]): { campaigns: AppliedDiscount[]; extras: AppliedDiscount[] } {
  const campaigns: AppliedDiscount[] = [];
  const extras: AppliedDiscount[] = [];
  for (const d of list) {
    const base = {
      promoId: d.promoId ?? d.campaignId ?? "",
      ...(d.promoCode ? { promoCode: d.promoCode } : {}),
      description: d.description,
      amount: d.amount,
      ...(d.staffNote ? { staffNote: d.staffNote } : {}),
      campaignId: d.campaignId ?? "",
      campaignName: d.campaignName ?? d.description,
      programCode: d.programCode ?? "",
      campaignType: d.campaignType ?? "",
      ...(d.voucherCode ? { voucherCode: d.voucherCode } : {}),
      ...(d.comboCount ? { comboCount: d.comboCount } : {}),
      ...(d.manualPercent ? { manualPercent: d.manualPercent } : {}),
    } as AppliedDiscount;
    if (d.campaignId) campaigns.push(base);
    else extras.push(base);
  }
  return { campaigns, extras };
}

/** Ghi lại discountsJson (null khi không còn khuyến mãi nào) — cùng dạng BillDiscountModel.toMap() của app */
export function serializeTableDiscounts(list: AppliedDiscount[]): string | null {
  const out = list.map((d) => {
    const o: Record<string, unknown> = { description: d.description, amount: Math.max(0, Math.trunc(Number(d.amount) || 0)) };
    const r = d as unknown as Record<string, unknown>;
    for (const k of ["promoId", "promoCode", "staffNote", "campaignId", "campaignName", "programCode", "campaignType", "voucherCode", "comboCount", "manualPercent"]) {
      const v = r[k];
      if (v != null && v !== "" && v !== 0) o[k] = v;
    }
    // Mục không phải chương trình: tên hiển thị chỉ là mô tả → không ghi thêm (giữ đúng bản app lưu)
    if (!o.campaignId && o.campaignName === o.description) delete o.campaignName;
    return o;
  });
  return out.length > 0 ? JSON.stringify(out) : null;
}

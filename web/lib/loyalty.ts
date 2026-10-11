/**
 * Điểm tích lũy khách hàng (CRM) — phần logic thuần của Web Admin.
 *
 * ĐIỂM DÙNG CHUNG TOÀN CHUỖI: số dư thật nằm ở RTDB loyalty_members/{SĐT chuẩn hóa} (+ sổ cái loyalty_ledger),
 * CHỈ Cloud Functions ghi. Web gọi callable qua web/lib/loyalty-client.ts, không ghi điểm trực tiếp.
 *  - loyalty_config                  : tỷ lệ tích/đổi + mốc hạng toàn chuỗi (Chủ đặt qua setLoyaltyConfig; đọc được)
 *  - stores/{s}/customers/{id}       : thông tin khách của chi nhánh; điểm chỉ là BẢN SAO đọc (trigger cập nhật)
 *  - stores/{s}/storeInfo.*          : tỷ lệ / mốc hạng riêng chi nhánh — chỉ dùng khi chuỗi chưa đặt (fallback)
 *  - loyalty_applied / point_history : sổ cũ trước khi gộp (chỉ đọc, dùng cho báo cáo lịch sử)
 */
import type { StoreCustomer } from "./customers";

export interface LoyaltyTier {
  name: string;
  /** Tổng điểm tích lũy (totalPoints) tối thiểu để đạt hạng */
  minPoints: number;
}

/**
 * Chưa cấu hình: chỉ có hạng gốc 0 điểm. Các mốc (Bạc, Vàng, ...) do Chủ quán tự đặt,
 * không áp mốc mặc định nào.
 */
export const DEFAULT_LOYALTY_TIERS: LoyaltyTier[] = [{ name: "Thành viên", minPoints: 0 }];

/** Gợi ý mốc để Chủ quán bấm điền nhanh (không tự áp dụng) */
export const SUGGESTED_LOYALTY_TIERS: LoyaltyTier[] = [
  { name: "Thành viên", minPoints: 0 },
  { name: "Bạc", minPoints: 200 },
  { name: "Vàng", minPoints: 500 },
  { name: "Kim Cương", minPoints: 1000 },
];

/** Cửa hàng chưa đặt mốc hạng nào ngoài hạng gốc */
export function hasCustomTiers(tiers: LoyaltyTier[]): boolean {
  return tiers.length > 1;
}

/** Chuẩn hóa cấu hình hạng đọc từ RTDB (mảng hoặc object); sai định dạng → mặc định */
export function normalizeTiers(raw: unknown): LoyaltyTier[] {
  const list: unknown[] = Array.isArray(raw)
    ? raw
    : raw && typeof raw === "object"
      ? Object.values(raw as Record<string, unknown>)
      : [];
  const tiers: LoyaltyTier[] = [];
  for (const item of list) {
    if (!item || typeof item !== "object") continue;
    const v = item as Record<string, unknown>;
    const name = String(v.name ?? "").trim();
    const min = Number(v.minPoints);
    if (!name || !Number.isFinite(min) || min < 0) continue;
    tiers.push({ name, minPoints: Math.trunc(min) });
  }
  if (tiers.length === 0) return DEFAULT_LOYALTY_TIERS.map((t) => ({ ...t }));
  tiers.sort((a, b) => a.minPoints - b.minPoints);
  // Hạng thấp nhất luôn bắt đầu từ 0 điểm để mọi khách đều có hạng
  if (tiers[0].minPoints > 0) tiers[0] = { ...tiers[0], minPoints: 0 };
  return tiers;
}

/** Kiểm tra cấu hình hạng trước khi lưu; trả về thông báo lỗi hoặc null */
export function validateTiers(tiers: LoyaltyTier[]): string | null {
  if (tiers.length < 1) return "Cần ít nhất 1 hạng thành viên";
  if (tiers.length > 10) return "Tối đa 10 hạng";
  const names = new Set<string>();
  for (const t of tiers) {
    const name = t.name.trim();
    if (!name) return "Tên hạng không được để trống";
    if (name.length > 30) return `Tên hạng "${name}" quá dài (tối đa 30 ký tự)`;
    const key = name.toLowerCase();
    if (names.has(key)) return `Tên hạng "${name}" bị trùng`;
    names.add(key);
    if (!Number.isInteger(t.minPoints) || t.minPoints < 0) return `Điểm của hạng "${name}" phải là số nguyên ≥ 0`;
  }
  const sorted = [...tiers].sort((a, b) => a.minPoints - b.minPoints);
  if (sorted[0].minPoints !== 0) return "Hạng thấp nhất phải bắt đầu từ 0 điểm";
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].minPoints === sorted[i - 1].minPoints) {
      return `Hạng "${sorted[i - 1].name}" và "${sorted[i].name}" có cùng mức điểm`;
    }
  }
  return null;
}

/** Hạng cao nhất mà tổng điểm đạt được */
export function tierForTotalPoints(total: number, tiers: LoyaltyTier[] = DEFAULT_LOYALTY_TIERS): string {
  const sorted = [...tiers].sort((a, b) => a.minPoints - b.minPoints);
  let name = sorted[0]?.name ?? "Thành viên";
  for (const t of sorted) if (total >= t.minPoints) name = t.name;
  return name;
}

/** Điểm còn thiếu để lên hạng kế tiếp (null nếu đã ở hạng cao nhất) */
export function pointsToNextTier(total: number, tiers: LoyaltyTier[]): { name: string; missing: number } | null {
  const sorted = [...tiers].sort((a, b) => a.minPoints - b.minPoints);
  const next = sorted.find((t) => t.minPoints > total);
  return next ? { name: next.name, missing: next.minPoints - total } : null;
}

// ---------------------------------------------------------------------------
// Khách hàng mới
// ---------------------------------------------------------------------------

/** SĐT Việt Nam: bỏ khoảng trắng/dấu chấm, đổi +84 → 0; trả null nếu không hợp lệ */
export function normalizePhone(raw: string): string | null {
  let p = raw.replace(/[\s.\-()]/g, "");
  if (p.startsWith("+84")) p = "0" + p.slice(3);
  else if (p.startsWith("84") && p.length === 11) p = "0" + p.slice(2);
  return /^0\d{9}$/.test(p) ? p : null;
}

export interface NewCustomerInput {
  name: string;
  phone: string;
  gender?: string;
  birthday?: string;
}

export function validateNewCustomer(
  input: NewCustomerInput,
  existing: Pick<StoreCustomer, "soDienThoai">[]
): { error: string } | { name: string; phone: string } {
  const name = input.name.trim();
  if (!name) return { error: "Vui lòng nhập họ tên khách" };
  if (name.length > 80) return { error: "Họ tên tối đa 80 ký tự" };
  const phone = normalizePhone(input.phone);
  if (!phone) return { error: "Số điện thoại không hợp lệ (10 số, bắt đầu bằng 0)" };
  if (existing.some((c) => normalizePhone(c.soDienThoai) === phone)) {
    return { error: "Số điện thoại này đã có khách trong chi nhánh" };
  }
  return { name, phone };
}

/**
 * Node khách mới — cùng trường với KmtCustomerModel.toMap() của POS, điểm = 0
 * (rules chỉ cho Thu ngân tạo khách có điểm 0; Chủ/Quản lý chỉnh điểm sau).
 */
export function buildNewCustomerNode(
  id: string,
  v: { name: string; phone: string; gender?: string; birthday?: string },
  now: number
): Record<string, unknown> {
  return {
    id,
    ma_khach_hang: id,
    code: id,
    ho_ten: v.name,
    name: v.name,
    so_dien_thoai: v.phone,
    phone: v.phone,
    gioi_tinh: v.gender || "Khác",
    gender: v.gender || "Khác",
    ngay_sinh: v.birthday || "",
    birthday: v.birthday || "",
    diem_hien_tai: 0,
    currentPoints: 0,
    totalPoints: 0,
    hang_thanh_vien: tierForTotalPoints(0),
    ho_ten_upper: v.name.toUpperCase(),
    ngay_tao: now,
    createdAt: now,
    ngay_cap_nhat: now,
  };
}

// ---------------------------------------------------------------------------
// Chỉnh điểm thủ công (Chủ quán / Quản lý)
// ---------------------------------------------------------------------------

export type AdjustMode = "SET" | "ADD" | "SUB";

export interface PointHistoryRow {
  /** khóa duy nhất để render */
  key: string;
  storeCode: string;
  customerId: string;
  type: "REDEEM" | "AWARD" | "REFUND" | "ADJUST" | "POOL_REDEEM" | "POOL_TRANSFER";
  /** Biến động có dấu (+ cộng, − trừ) */
  delta: number;
  before: number;
  after: number;
  at: number;
  by: string;
  billId?: string;
  reason?: string;
}

export const POINT_TYPE_LABEL: Record<PointHistoryRow["type"], string> = {
  REDEEM: "Đổi điểm (giảm giá hóa đơn)",
  AWARD: "Tích điểm từ hóa đơn",
  REFUND: "Hoàn điểm",
  ADJUST: "Chỉnh điểm thủ công",
  POOL_REDEEM: "Trừ điểm dùng chung toàn hệ thống",
  POOL_TRANSFER: "Chuyển điểm dùng chung giữa chi nhánh (POS đổi điểm)",
};

export interface AdjustInput {
  mode: AdjustMode;
  value: number;
  reason: string;
  /** Số dư dùng chung hiện tại (để chặn trừ quá / không đổi) */
  balance: number;
}

/**
 * Kiểm tra trước khi gọi callable adjustLoyaltyPoints (máy chủ kiểm tra lại, đây chỉ để báo lỗi sớm):
 * bắt buộc lý do, số nguyên không âm, không trừ quá số dư, không để nguyên số dư.
 */
export function validateAdjustInput(a: AdjustInput): string | null {
  if (a.reason.trim().length < 3) return "Vui lòng nhập lý do chỉnh điểm (tối thiểu 3 ký tự)";
  if (!Number.isInteger(a.value) || a.value < 0) return "Số điểm phải là số nguyên ≥ 0";
  if (a.value > 10_000_000) return "Số điểm quá lớn";
  const before = Math.max(0, Math.trunc(a.balance));
  const after = a.mode === "SET" ? a.value : a.mode === "ADD" ? before + a.value : before - a.value;
  if (after < 0) return `Khách chỉ còn ${before} điểm, không thể trừ ${a.value}`;
  if (after === before) return "Số điểm không thay đổi";
  return null;
}

// ---------------------------------------------------------------------------
// Lịch sử điểm (đọc)
// ---------------------------------------------------------------------------

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

const LEDGER_TYPE: Record<string, PointHistoryRow["type"]> = { redeem: "REDEEM", award: "AWARD", refund: "REFUND" };

/** Sổ cái POS: loyalty_applied/{billId}/{redeem|award|refund} */
export function parseLoyaltyLedger(storeCode: string, val: unknown): PointHistoryRow[] {
  if (!val || typeof val !== "object") return [];
  const rows: PointHistoryRow[] = [];
  for (const [billId, ops] of Object.entries(val as Record<string, unknown>)) {
    if (!ops || typeof ops !== "object") continue;
    for (const [op, raw] of Object.entries(ops as Record<string, unknown>)) {
      const type = LEDGER_TYPE[op];
      if (!type || !raw || typeof raw !== "object") continue;
      const v = raw as Record<string, unknown>;
      const points = Math.abs(num(v.points));
      const before = num(v.before);
      const after = num(v.after);
      rows.push({
        key: `${storeCode}:${billId}:${op}`,
        storeCode,
        customerId: String(v.customerId ?? ""),
        type,
        delta: type === "REDEEM" ? -points : points,
        before,
        after,
        at: num(v.at),
        by: String(v.by ?? ""),
        billId,
      });
    }
  }
  return rows;
}

/** Sổ chỉnh điểm thủ công: point_history/{key} */
export function parsePointHistory(storeCode: string, val: unknown): PointHistoryRow[] {
  if (!val || typeof val !== "object") return [];
  const rows: PointHistoryRow[] = [];
  for (const [key, raw] of Object.entries(val as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object") continue;
    const v = raw as Record<string, unknown>;
    rows.push({
      key: `${storeCode}:${key}`,
      storeCode,
      customerId: String(v.customerId ?? ""),
      type: v.type === "POOL_REDEEM" || v.type === "POOL_TRANSFER" ? v.type : "ADJUST",
      delta: num(v.delta),
      before: num(v.before),
      after: num(v.after),
      at: num(v.at),
      by: String(v.byName ?? v.by ?? ""),
      reason: String(v.reason ?? ""),
    });
  }
  return rows;
}

export function sortHistoryDesc(rows: PointHistoryRow[]): PointHistoryRow[] {
  return [...rows].sort((a, b) => b.at - a.at || a.key.localeCompare(b.key));
}

export function summarizeHistory(rows: PointHistoryRow[]): { earned: number; redeemed: number; adjusted: number } {
  let earned = 0;
  let redeemed = 0;
  let adjusted = 0;
  for (const r of rows) {
    if (r.type === "AWARD" || r.type === "REFUND") earned += r.delta;
    else if (r.type === "REDEEM" || r.type === "POOL_REDEEM") redeemed += -r.delta;
    else if (r.type === "POOL_TRANSFER") continue; // chuyển nội bộ: tổng toàn hệ thống không đổi
    else adjusted += r.delta;
  }
  return { earned, redeemed, adjusted };
}

// ---------------------------------------------------------------------------
// Điểm dùng chung toàn chuỗi
// ---------------------------------------------------------------------------

/** @deprecated Cờ storeInfo.sharedLoyalty đã được thay thế: điểm LUÔN dùng chung (loyalty_members). Giữ kiểu để đọc dữ liệu cũ. */
export type DeductOrder = "HOME_FIRST" | "LARGEST_FIRST";

/** @deprecated xem DeductOrder */
export interface SharedLoyaltyConfig {
  enabled: boolean;
  deductOrder: DeductOrder;
  confirmedBy?: string;
  confirmedAt?: number;
}

/** @deprecated Chỉ để đọc dữ liệu cũ; không còn ảnh hưởng hành vi. */
export function parseSharedLoyalty(raw: unknown): SharedLoyaltyConfig {
  if (!raw || typeof raw !== "object") return { enabled: false, deductOrder: "HOME_FIRST" };
  const v = raw as Record<string, unknown>;
  return {
    enabled: v.enabled === true,
    deductOrder: v.deductOrder === "LARGEST_FIRST" ? "LARGEST_FIRST" : "HOME_FIRST",
    confirmedBy: typeof v.confirmedBy === "string" ? v.confirmedBy : undefined,
    confirmedAt: Number.isFinite(Number(v.confirmedAt)) ? Number(v.confirmedAt) : undefined,
  };
}

/** Khóa bản ghi điểm dùng chung (khớp functions/src/sharedLoyalty.ts memberKeyFor) */
export function memberKeyOf(phone: string, storeCode: string, customerId: string): string {
  const p = normalizePhone(phone ?? "");
  return p ?? `L_${storeCode.replace(/[.#$[\]/\s]/g, "_")}_${customerId.replace(/[.#$[\]/\s]/g, "_")}`;
}

export interface MemberTotals {
  /** Số khách duy nhất (cùng SĐT ở nhiều chi nhánh chỉ tính 1) */
  members: number;
  points: number;
  totalPoints: number;
  /** Số node khách trùng SĐT (đã gộp) */
  duplicateNodes: number;
}

/**
 * Tổng điểm toàn chuỗi KHÔNG đếm trùng: các node khách cùng SĐT cùng mang bản sao của một số dư,
 * nên mỗi khách chỉ được cộng một lần (lấy số lớn nhất trong các bản sao phòng khi cache lệch tạm thời).
 */
export function totalsByMember(customers: Pick<StoreCustomer, "id" | "storeCode" | "soDienThoai" | "diemHienTai" | "tongDiem">[]): MemberTotals {
  const map = new Map<string, { points: number; total: number }>();
  for (const c of customers) {
    const key = memberKeyOf(c.soDienThoai, c.storeCode, c.id);
    const cur = map.get(key) ?? { points: 0, total: 0 };
    map.set(key, { points: Math.max(cur.points, c.diemHienTai), total: Math.max(cur.total, c.tongDiem) });
  }
  let points = 0;
  let totalPoints = 0;
  for (const v of map.values()) {
    points += v.points;
    totalPoints += v.total;
  }
  return { members: map.size, points, totalPoints, duplicateNodes: customers.length - map.size };
}

export interface ChainLoyaltyConfig {
  pointEarnRate?: number;
  pointRedeemRate?: number;
  loyaltyTiers?: LoyaltyTier[];
}

/** Đọc loyalty_config (RTDB); thiếu trường nào thì trường đó để undefined (dùng cấu hình chi nhánh) */
export function parseChainConfig(raw: unknown): ChainLoyaltyConfig {
  if (!raw || typeof raw !== "object") return {};
  const v = raw as Record<string, unknown>;
  const out: ChainLoyaltyConfig = {};
  if (typeof v.pointEarnRate === "number" && Number.isFinite(v.pointEarnRate) && v.pointEarnRate >= 0) out.pointEarnRate = v.pointEarnRate;
  if (typeof v.pointRedeemRate === "number" && v.pointRedeemRate > 0) out.pointRedeemRate = v.pointRedeemRate;
  if (v.loyaltyTiers !== undefined && v.loyaltyTiers !== null) out.loyaltyTiers = normalizeTiers(v.loyaltyTiers);
  return out;
}

/** Cấu hình hiệu lực của một chi nhánh: toàn chuỗi ưu tiên, thiếu thì lấy của chi nhánh */
export function effectiveConfig<T extends { pointEarnRate?: number; pointRedeemRate?: number; loyaltyTiers?: LoyaltyTier[] }>(
  store: T | undefined,
  chain: ChainLoyaltyConfig
): { pointEarnRate?: number; pointRedeemRate?: number; loyaltyTiers: LoyaltyTier[] } {
  return {
    pointEarnRate: chain.pointEarnRate ?? store?.pointEarnRate,
    pointRedeemRate: chain.pointRedeemRate ?? store?.pointRedeemRate,
    loyaltyTiers: chain.loyaltyTiers ?? store?.loyaltyTiers ?? DEFAULT_LOYALTY_TIERS,
  };
}

// ---------------------------------------------------------------------------
// Sổ cái dùng chung (callable getMemberLedger)
// ---------------------------------------------------------------------------

export type LedgerType = "earn" | "redeem" | "refund" | "adjust" | "opening";

export const LEDGER_TYPE_LABEL: Record<LedgerType, string> = {
  earn: "Tích điểm từ hóa đơn",
  redeem: "Đổi điểm (giảm giá hóa đơn)",
  refund: "Hoàn điểm",
  adjust: "Chỉnh điểm thủ công",
  opening: "Số dư đầu kỳ (gộp chi nhánh)",
};

export interface LedgerRow {
  id: string;
  type: LedgerType;
  /** Biến động có dấu */
  points: number;
  balanceAfter: number;
  /** Chi nhánh phát sinh */
  storeCode: string;
  billId?: string;
  customerId?: string;
  staff: string;
  note?: string;
  at: number;
}

/** Chuẩn hóa kết quả callable getMemberLedger: bỏ dòng sai định dạng, mới nhất trước */
export function parseLedgerEntries(raw: unknown): LedgerRow[] {
  if (!Array.isArray(raw)) return [];
  const rows: LedgerRow[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const v = item as Record<string, unknown>;
    const type = String(v.type ?? "") as LedgerType;
    if (!(type in LEDGER_TYPE_LABEL)) continue;
    rows.push({
      id: String(v.id ?? ""),
      type,
      points: num(v.points),
      balanceAfter: num(v.balanceAfter),
      storeCode: String(v.storeCode ?? ""),
      billId: typeof v.billId === "string" ? v.billId : undefined,
      customerId: typeof v.customerId === "string" ? v.customerId : undefined,
      staff: String(v.staff ?? ""),
      note: typeof v.note === "string" ? v.note : undefined,
      at: num(v.at),
    });
  }
  return rows.sort((a, b) => b.at - a.at || a.id.localeCompare(b.id));
}

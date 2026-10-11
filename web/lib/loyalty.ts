/**
 * Điểm tích lũy khách hàng (CRM) — phần logic thuần của Web Admin.
 *
 * Nguồn dữ liệu (RTDB, theo từng chi nhánh):
 *  - storeInfo.loyaltyTiers          : cấu hình điểm cho từng hạng (Chủ quán ghi)
 *  - customers/{id}                  : số dư điểm (diem_hien_tai / currentPoints / totalPoints)
 *  - loyalty_applied/{billId}/{op}   : sổ cái do POS ghi khi đổi / tích / hoàn điểm theo hóa đơn
 *  - point_history/{key}             : sổ chỉnh điểm thủ công do Web ghi (chỉ tạo mới, Chủ/Quản lý)
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
  type: "REDEEM" | "AWARD" | "REFUND" | "ADJUST" | "POOL_REDEEM";
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
};

export interface AdjustPointsArgs {
  storeCode: string;
  customer: Pick<StoreCustomer, "id" | "hoTen" | "diemHienTai" | "tongDiem">;
  mode: AdjustMode;
  value: number;
  reason: string;
  actor: { username: string; fullName?: string; role?: string };
  tiers: LoyaltyTier[];
  now: number;
  /** Chống trùng khóa khi bấm nhanh */
  nonce?: string;
}

export type AdjustPointsResult =
  | { ok: false; error: string }
  | { ok: true; after: number; delta: number; updates: Record<string, unknown>; entry: PointHistoryRow };

/**
 * Tính bản ghi + đường dẫn ghi (multi-path update) cho một lần chỉnh điểm.
 *  - Bắt buộc có lý do; điểm không âm, số nguyên.
 *  - totalPoints (điểm lịch sử, quyết định hạng) chỉ tăng khi cộng điểm.
 */
export function buildPointAdjustment(a: AdjustPointsArgs): AdjustPointsResult {
  const reason = a.reason.trim();
  if (!reason) return { ok: false, error: "Vui lòng nhập lý do chỉnh điểm" };
  if (!Number.isInteger(a.value) || a.value < 0) return { ok: false, error: "Số điểm phải là số nguyên ≥ 0" };
  if (a.value > 10_000_000) return { ok: false, error: "Số điểm quá lớn" };
  const before = Math.max(0, Math.trunc(a.customer.diemHienTai));
  const total = Math.max(0, Math.trunc(a.customer.tongDiem));
  const after = a.mode === "SET" ? a.value : a.mode === "ADD" ? before + a.value : before - a.value;
  if (after < 0) return { ok: false, error: `Khách chỉ còn ${before} điểm, không thể trừ ${a.value}` };
  const delta = after - before;
  if (delta === 0) return { ok: false, error: "Số điểm không thay đổi" };
  const newTotal = delta > 0 ? total + delta : total;
  const historyKey = `adj_${a.now}_${a.nonce ?? Math.floor(Math.random() * 1e6)}`;
  const base = `stores/${a.storeCode}`;
  const entry: PointHistoryRow = {
    key: historyKey,
    storeCode: a.storeCode,
    customerId: a.customer.id,
    type: "ADJUST",
    delta,
    before,
    after,
    at: a.now,
    by: a.actor.username,
    reason,
  };
  const updates: Record<string, unknown> = {
    [`${base}/customers/${a.customer.id}/diem_hien_tai`]: after,
    [`${base}/customers/${a.customer.id}/currentPoints`]: after,
    [`${base}/customers/${a.customer.id}/totalPoints`]: newTotal,
    [`${base}/customers/${a.customer.id}/hang_thanh_vien`]: tierForTotalPoints(newTotal, a.tiers),
    [`${base}/customers/${a.customer.id}/ngay_cap_nhat`]: a.now,
    [`${base}/point_history/${historyKey}`]: {
      customerId: a.customer.id,
      customerName: a.customer.hoTen,
      type: "ADJUST",
      mode: a.mode,
      delta,
      before,
      after,
      reason,
      by: a.actor.username,
      byName: a.actor.fullName ?? a.actor.username,
      at: a.now,
    },
    [`${base}/audit_logs/log_${a.now}_pt_${a.nonce ?? Math.floor(Math.random() * 1e6)}`]: {
      timestamp: a.now,
      username: a.actor.username,
      userFullName: a.actor.fullName ?? a.actor.username,
      userRole: a.actor.role ?? "",
      action: "ADJUST_POINTS",
      targetType: "CUSTOMER",
      targetId: a.customer.id,
      storeCode: a.storeCode,
      details: `Chỉnh điểm ${a.customer.hoTen}: ${before} → ${after} (${delta > 0 ? "+" : ""}${delta}). Lý do: ${reason}`,
      isSuspicious: Math.abs(delta) >= 500,
      beforeState: { diem_hien_tai: before },
      afterState: { diem_hien_tai: after },
    },
  };
  return { ok: true, after, delta, updates, entry };
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
      type: v.type === "POOL_REDEEM" ? "POOL_REDEEM" : "ADJUST",
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
    else adjusted += r.delta;
  }
  return { earned, redeemed, adjusted };
}

// ---------------------------------------------------------------------------
// Điểm dùng chung toàn hệ thống (cần Chủ xác nhận)
// ---------------------------------------------------------------------------

/** Thứ tự trừ điểm khi dùng chung: chi nhánh đang thao tác trước, hoặc chi nhánh nhiều điểm nhất trước */
export type DeductOrder = "HOME_FIRST" | "LARGEST_FIRST";

export const DEDUCT_ORDER_LABEL: Record<DeductOrder, string> = {
  HOME_FIRST: "Trừ chi nhánh đang thao tác trước, thiếu thì trừ tiếp chi nhánh nhiều điểm nhất",
  LARGEST_FIRST: "Trừ chi nhánh nhiều điểm nhất trước",
};

export interface SharedLoyaltyConfig {
  enabled: boolean;
  deductOrder: DeductOrder;
  confirmedBy?: string;
  confirmedAt?: number;
}

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

/** Bật/tắt dùng chung: ghi storeInfo.sharedLoyalty của MỌI chi nhánh trong một update() + audit log */
export function buildSharedLoyaltyUpdates(args: {
  storeCodes: string[];
  enabled: boolean;
  deductOrder?: DeductOrder;
  actor: { username: string; fullName?: string };
  now: number;
}): Record<string, unknown> {
  const updates: Record<string, unknown> = {};
  const cfg = { enabled: args.enabled, deductOrder: args.deductOrder ?? "HOME_FIRST", confirmedBy: args.actor.username, confirmedAt: args.now };
  for (const code of args.storeCodes) {
    updates[`stores/${code}/storeInfo/sharedLoyalty`] = cfg;
    updates[`stores/${code}/audit_logs/log_${args.now}_pool_${code}`] = {
      timestamp: args.now,
      username: args.actor.username,
      userFullName: args.actor.fullName ?? args.actor.username,
      action: "LOYALTY_POOL_CONFIRM",
      targetType: "STORE",
      targetId: code,
      storeCode: code,
      details: `Chủ quán ${args.enabled ? "xác nhận BẬT" : "TẮT"} điểm dùng chung toàn hệ thống (${args.storeCodes.length} chi nhánh)`,
      isSuspicious: false,
    };
  }
  return updates;
}

export interface PooledCustomer {
  phone: string;
  hoTen: string;
  totalCurrent: number;
  totalLifetime: number;
  perStore: { storeCode: string; customerId: string; points: number }[];
}

/** Gộp khách các chi nhánh theo SĐT → số dư điểm toàn hệ thống */
export function poolCustomersByPhone(customers: StoreCustomer[]): PooledCustomer[] {
  const map = new Map<string, PooledCustomer>();
  for (const c of customers) {
    const phone = normalizePhone(c.soDienThoai);
    if (!phone) continue;
    let p = map.get(phone);
    if (!p) {
      p = { phone, hoTen: c.hoTen, totalCurrent: 0, totalLifetime: 0, perStore: [] };
      map.set(phone, p);
    }
    p.totalCurrent += c.diemHienTai;
    p.totalLifetime += c.tongDiem;
    p.perStore.push({ storeCode: c.storeCode, customerId: c.id, points: c.diemHienTai });
  }
  return [...map.values()].sort((a, b) => b.totalCurrent - a.totalCurrent);
}

// ---------------------------------------------------------------------------
// Trừ điểm dùng chung giữa các chi nhánh
// ---------------------------------------------------------------------------

export interface PoolAllocation {
  storeCode: string;
  customerId: string;
  take: number;
  before: number;
  after: number;
}

/**
 * Chia số điểm cần trừ cho các chi nhánh của một khách (cùng SĐT) theo cấu hình.
 * Trả lỗi nếu tổng điểm toàn hệ thống không đủ.
 */
export function planPooledRedeem(args: {
  holdings: { storeCode: string; customerId: string; points: number }[];
  points: number;
  homeStore?: string;
  order: DeductOrder;
}): { error: string } | { allocations: PoolAllocation[] } {
  if (!Number.isInteger(args.points) || args.points <= 0) return { error: "Số điểm cần trừ phải là số nguyên > 0" };
  const held = args.holdings.filter((h) => h.points > 0);
  const total = held.reduce((s, h) => s + h.points, 0);
  if (total < args.points) return { error: `Khách chỉ còn ${total} điểm trên toàn hệ thống, không đủ để trừ ${args.points}` };
  const byLargest = [...held].sort((a, b) => b.points - a.points || a.storeCode.localeCompare(b.storeCode));
  const ordered =
    args.order === "HOME_FIRST" && args.homeStore
      ? [...byLargest.filter((h) => h.storeCode === args.homeStore), ...byLargest.filter((h) => h.storeCode !== args.homeStore)]
      : byLargest;
  let left = args.points;
  const allocations: PoolAllocation[] = [];
  for (const h of ordered) {
    if (left <= 0) break;
    const take = Math.min(h.points, left);
    allocations.push({ storeCode: h.storeCode, customerId: h.customerId, take, before: h.points, after: h.points - take });
    left -= take;
  }
  return { allocations };
}

/** Một update() đa chi nhánh: trừ điểm từng nơi + point_history + audit (totalPoints giữ nguyên → không tụt hạng) */
export function buildPooledRedeemUpdates(args: {
  allocations: PoolAllocation[];
  customerName: string;
  phone: string;
  reason: string;
  actor: { username: string; fullName?: string; role?: string };
  tiers?: Record<string, LoyaltyTier[]>;
  now: number;
  nonce?: string;
}): { error: string } | { updates: Record<string, unknown> } {
  const reason = args.reason.trim();
  if (!reason) return { error: "Vui lòng nhập lý do / mã hóa đơn áp dụng" };
  if (args.allocations.length === 0) return { error: "Không có điểm để trừ" };
  const updates: Record<string, unknown> = {};
  const total = args.allocations.reduce((s, a) => s + a.take, 0);
  const n = args.nonce ?? String(Math.floor(Math.random() * 1e6));
  for (const a of args.allocations) {
    const base = `stores/${a.storeCode}`;
    updates[`${base}/customers/${a.customerId}/diem_hien_tai`] = a.after;
    updates[`${base}/customers/${a.customerId}/currentPoints`] = a.after;
    updates[`${base}/customers/${a.customerId}/ngay_cap_nhat`] = args.now;
    updates[`${base}/point_history/pool_${args.now}_${n}_${a.storeCode}`] = {
      customerId: a.customerId,
      customerName: args.customerName,
      type: "POOL_REDEEM",
      mode: "POOL",
      delta: -a.take,
      before: a.before,
      after: a.after,
      reason: `${reason} (dùng chung ${total} điểm / ${args.allocations.length} chi nhánh)`,
      by: args.actor.username,
      byName: args.actor.fullName ?? args.actor.username,
      at: args.now,
    };
    updates[`${base}/audit_logs/log_${args.now}_pool_${n}_${a.storeCode}`] = {
      timestamp: args.now,
      username: args.actor.username,
      userFullName: args.actor.fullName ?? args.actor.username,
      userRole: args.actor.role ?? "",
      action: "LOYALTY_POOL_REDEEM",
      targetType: "CUSTOMER",
      targetId: a.customerId,
      storeCode: a.storeCode,
      details: `Trừ ${a.take} điểm dùng chung của ${args.customerName} (${args.phone}) tại ${a.storeCode}: ${a.before} → ${a.after}. ${reason}`,
      isSuspicious: total >= 500,
      beforeState: { diem_hien_tai: a.before },
      afterState: { diem_hien_tai: a.after },
    };
  }
  return { updates };
}

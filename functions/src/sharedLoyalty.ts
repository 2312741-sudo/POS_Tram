/**
 * Điểm tích lũy DÙNG CHUNG toàn chuỗi - logic thuần (không phụ thuộc Firebase runtime, test được 100%).
 *
 * Nguồn chuẩn DUY NHẤT của điểm:  loyalty_members/{memberKey}
 *   memberKey = SĐT đã chuẩn hóa (0xxxxxxxxx) hoặc "L_{storeCode}_{customerId}" cho khách chưa có SĐT hợp lệ
 *   (khách đó vẫn có 1 bản ghi điểm duy nhất nhưng chỉ thuộc 1 chi nhánh, không gộp được).
 * Sổ cái (chỉ tạo mới, chỉ Cloud Function ghi):  loyalty_ledger/{memberKey}/{opId}
 * Cấu hình chuỗi (Chủ đặt, qua callable):         loyalty_config
 *
 * Client KHÔNG ghi các node này (rules). Node khách của chi nhánh stores/{s}/customers/{id} chỉ còn là
 * BẢN SAO ĐỌC của số dư (trigger mirrorMemberToBranches cập nhật).
 */

export type AnyMap = Record<string, unknown>;

export type LoyaltyOpType = "earn" | "redeem" | "refund" | "adjust" | "opening";

/** Số phần tử tối đa của vòng khóa thao tác lưu trong member.ops (chống làm phình bản ghi) */
export const OPS_RING_MAX = 200;
/** Trần điểm một thao tác (chống nhập nhầm) */
export const MAX_POINTS_PER_OP = 10_000_000;

export interface OpRecord {
  /** Số điểm đã áp dụng (dương) */
  p: number;
  /** Loại thao tác */
  t: LoyaltyOpType;
  /** Thời điểm áp dụng (ms) */
  at: number;
}

export interface Member {
  name: string;
  phone: string;
  points: number;
  totalPoints: number;
  joinedAt: number;
  updatedAt: number;
  lastStoreCode?: string;
  /** Khóa thao tác đã áp dụng: opId → bản ghi (idempotency + dữ liệu để hoàn điểm) */
  ops?: Record<string, OpRecord>;
}

/** SĐT Việt Nam về dạng 0xxxxxxxxx; không hợp lệ → null (khớp web/lib/loyalty.ts normalizePhone) */
export function normalizePhone(raw: unknown): string | null {
  let p = String(raw ?? "").replace(/[\s.\-()]/g, "");
  if (p.startsWith("+84")) p = "0" + p.slice(3);
  else if (p.startsWith("84") && p.length === 11) p = "0" + p.slice(2);
  return /^0\d{9}$/.test(p) ? p : null;
}

/** Thay ký tự cấm của khóa RTDB bằng "_" */
export function sanitizeKey(s: string): string {
  return String(s).replace(/[.#$[\]/\u0000-\u001f\u007f\s]/g, "_");
}

/** Khóa bản ghi điểm: SĐT hợp lệ → SĐT; ngược lại → bản ghi riêng của khách tại chi nhánh. */
export function memberKeyFor(phoneRaw: unknown, storeCode: string, customerId: string): string {
  return normalizePhone(phoneRaw) ?? `L_${sanitizeKey(storeCode)}_${sanitizeKey(customerId)}`;
}

/** true nếu khóa là bản ghi cục bộ (khách không có SĐT hợp lệ) */
export function isLocalMemberKey(key: string): boolean {
  return key.startsWith("L_");
}

/** Khóa thao tác theo hóa đơn: "{billId}_{op}" (idempotent) */
export function billOpId(billId: string, op: LoyaltyOpType): string {
  return `${sanitizeKey(billId)}_${op}`;
}

/** Điểm tích cho hóa đơn: tiền thực trả × rate% / (đ/điểm), làm tròn (khớp LoyaltyMath.pointsToAward của Flutter) */
export function computeEarnPoints(finalAmount: number, earnRatePercent: number, redeemRate: number): number {
  if (!(finalAmount > 0) || !(earnRatePercent > 0) || !(redeemRate > 0)) return 0;
  const p = Math.round((finalAmount * (earnRatePercent / 100)) / redeemRate);
  return p > 0 ? p : 0;
}

export interface LoyaltyRates {
  earnRate: number;
  redeemRate: number;
  source: "chain" | "store" | "default";
}

function num(v: unknown): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

/**
 * Tỷ lệ tích/đổi: loyalty_config (chuỗi) ưu tiên; thiếu thì lấy storeInfo của chi nhánh; thiếu nữa → 1% và 1000đ/điểm.
 * (Mốc hạng KHÔNG có mặc định - do Chủ đặt, xem LoyaltyTier ở client.)
 */
export function resolveRates(chain: AnyMap | null | undefined, store: AnyMap | null | undefined): LoyaltyRates {
  const ce = num(chain?.pointEarnRate);
  const cr = num(chain?.pointRedeemRate);
  const se = num(store?.pointEarnRate);
  const sr = num(store?.pointRedeemRate);
  const earn = ce ?? se;
  const redeem = (cr !== undefined && cr > 0 ? cr : undefined) ?? (sr !== undefined && sr > 0 ? sr : undefined);
  const source: LoyaltyRates["source"] = ce !== undefined || cr !== undefined ? "chain" : se !== undefined || sr !== undefined ? "store" : "default";
  return { earnRate: earn ?? 1, redeemRate: redeem ?? 1000, source };
}

export function readMember(v: unknown): Member | null {
  if (!v || typeof v !== "object") return null;
  const m = v as AnyMap;
  return {
    name: typeof m.name === "string" ? m.name : "",
    phone: typeof m.phone === "string" ? m.phone : "",
    points: Math.max(0, Math.trunc(num(m.points) ?? 0)),
    totalPoints: Math.max(0, Math.trunc(num(m.totalPoints) ?? 0)),
    joinedAt: num(m.joinedAt) ?? 0,
    updatedAt: num(m.updatedAt) ?? 0,
    lastStoreCode: typeof m.lastStoreCode === "string" ? m.lastStoreCode : undefined,
    ops: (m.ops && typeof m.ops === "object" ? (m.ops as Record<string, OpRecord>) : undefined),
  };
}

export function newMember(name: string, phone: string, storeCode: string, now: number): Member {
  return { name, phone, points: 0, totalPoints: 0, joinedAt: now, updatedAt: now, lastStoreCode: storeCode };
}

export interface OpRequest {
  type: LoyaltyOpType;
  /** earn/redeem/refund/opening: số điểm dương. adjust: delta có dấu (≠ 0) */
  points: number;
  opId: string;
  storeCode: string;
  now: number;
  /** adjust kiểu SET: đặt số dư về giá trị này (bỏ qua points); totalPoints chỉ tăng nếu điểm mới > cũ */
  setTo?: number;
  name?: string;
  phone?: string;
}

export type OpStatus = "applied" | "alreadyApplied" | "insufficient" | "nothingToRefund" | "invalid";

export interface OpResult {
  status: OpStatus;
  /** Bản ghi mới (chỉ có khi applied) */
  member?: Member;
  /** Số điểm thực sự áp dụng (refund có thể nhỏ hơn yêu cầu) */
  applied: number;
  before: number;
  after: number;
  totalAfter: number;
}

/** Cắt vòng khóa về tối đa [OPS_RING_MAX] phần tử mới nhất */
export function pruneOps(ops: Record<string, OpRecord>, max = OPS_RING_MAX): Record<string, OpRecord> {
  const keys = Object.keys(ops);
  if (keys.length <= max) return ops;
  const keep = keys.sort((a, b) => (ops[b]?.at ?? 0) - (ops[a]?.at ?? 0)).slice(0, max);
  const out: Record<string, OpRecord> = {};
  for (const k of keep) out[k] = ops[k];
  return out;
}

/**
 * Áp một thao tác lên bản ghi thành viên (hàm thuần dùng trong transaction).
 * - Idempotent theo opId (vòng khóa member.ops).
 * - redeem: không đủ điểm → insufficient (không đổi gì).
 * - refund: chỉ hoàn đúng số điểm của thao tác `{billId}_redeem` còn trong vòng khóa, tối đa 1 lần.
 * - earn/opening: cộng cả points và totalPoints. adjust: delta có dấu; chỉ delta dương làm tăng totalPoints; không cho âm điểm.
 */
export function applyOp(current: Member | null, req: OpRequest): OpResult {
  const base = current ?? newMember(req.name ?? "", req.phone ?? "", req.storeCode, req.now);
  const before = base.points;
  const none = (status: OpStatus): OpResult => ({ status, applied: 0, before, after: before, totalAfter: base.totalPoints });

  if (base.ops && base.ops[req.opId]) return { ...none("alreadyApplied"), applied: base.ops[req.opId].p };
  const isSet = req.type === "adjust" && req.setTo !== undefined;
  if (isSet) {
    if (!Number.isInteger(req.setTo) || (req.setTo as number) < 0 || (req.setTo as number) > MAX_POINTS_PER_OP) return none("invalid");
    req = { ...req, points: (req.setTo as number) - before };
    if (req.points === 0) return none("invalid");
  }
  if (!Number.isInteger(req.points) || req.points === 0 || Math.abs(req.points) > MAX_POINTS_PER_OP) return none("invalid");
  if (req.type !== "adjust" && req.points < 0) return none("invalid");

  let delta: number;
  let totalDelta = 0;
  let applied = Math.abs(req.points);
  switch (req.type) {
    case "earn":
    case "opening":
      delta = req.points;
      totalDelta = req.points;
      break;
    case "redeem":
      if (before < req.points) return none("insufficient");
      delta = -req.points;
      break;
    case "refund": {
      const redeemId = req.opId.replace(/_refund$/, "_redeem");
      const red = base.ops?.[redeemId];
      if (!red || red.t !== "redeem" || red.p <= 0) return none("nothingToRefund");
      applied = Math.min(req.points, red.p);
      delta = applied;
      break;
    }
    case "adjust":
      if (before + req.points < 0) return none("insufficient");
      delta = req.points;
      if (req.points > 0) totalDelta = req.points;
      break;
    default:
      return none("invalid");
  }

  const ops = pruneOps({ ...(base.ops ?? {}), [req.opId]: { p: applied, t: req.type, at: req.now } });
  const member: Member = {
    ...base,
    name: base.name || req.name || "",
    phone: base.phone || req.phone || "",
    points: before + delta,
    totalPoints: base.totalPoints + totalDelta,
    updatedAt: req.now,
    lastStoreCode: req.storeCode,
    ops,
  };
  return { status: "applied", member, applied, before, after: member.points, totalAfter: member.totalPoints };
}

export interface LedgerEntry {
  type: LoyaltyOpType;
  points: number;
  balanceAfter: number;
  billId?: string;
  billCode?: string;
  storeCode: string;
  customerId?: string;
  staff: string;
  note?: string;
  at: number;
}

/** Bản ghi lịch sử kmt_point_history (Firestore) cho 1 dòng sổ cái chung. docId cố định → trigger chạy lại không ghi trùng */
export function buildLedgerHistory(memberKey: string, opId: string, e: AnyMap): { docId: string; data: AnyMap } | null {
  const pts = num(e.points);
  const after = num(e.balanceAfter);
  if (pts === undefined || after === undefined) return null;
  const type = String(e.type ?? "");
  const nguon =
    type === "earn" ? "fnb_pos" : type === "redeem" ? "fnb_pos_redeem" : type === "refund" ? "fnb_pos_refund" : type === "opening" ? "fnb_pos_opening" : "fnb_pos_adjust";
  const store = typeof e.storeCode === "string" ? e.storeCode : "";
  return {
    docId: `POS_${sanitizeKey(memberKey)}_${sanitizeKey(opId)}`.slice(0, 400),
    data: {
      ma_khach_hang: typeof e.customerId === "string" && e.customerId ? e.customerId : memberKey,
      cua_hang: store,
      ten_cua_hang: `POS Trạm (${store})`,
      diem_truoc: after - pts,
      diem_thay_doi: pts,
      diem_sau: after,
      nguon,
      bill_code: typeof e.billId === "string" ? e.billId : "",
    },
  };
}

export function buildLedgerEntry(req: OpRequest, res: OpResult, extra: { billId?: string; billCode?: string; customerId?: string; staff: string; note?: string }): LedgerEntry {
  const signed = req.type === "redeem" ? -res.applied : req.type === "adjust" ? res.after - res.before : res.applied;
  const e: LedgerEntry = {
    type: req.type,
    points: signed,
    balanceAfter: res.after,
    storeCode: req.storeCode,
    staff: extra.staff,
    at: req.now,
  };
  if (extra.billId) e.billId = extra.billId;
  if (extra.billCode) e.billCode = extra.billCode;
  if (extra.customerId) e.customerId = extra.customerId;
  if (extra.note) e.note = extra.note;
  return e;
}

/** Trường cache điểm ghi lên node khách của chi nhánh (đọc-only với client) */
export function branchCacheFields(m: Member): { diem_hien_tai: number; currentPoints: number; totalPoints: number } {
  return { diem_hien_tai: m.points, currentPoints: m.points, totalPoints: m.totalPoints };
}

/** Các đường dẫn cần cập nhật để node khách chi nhánh khớp bản ghi chung (chỉ node còn tồn tại và đang lệch) */
export function planBranchCacheUpdates(
  member: Member,
  branches: { storeCode: string; customerId: string; node: AnyMap | null }[]
): Record<string, number> {
  const out: Record<string, number> = {};
  const want = branchCacheFields(member);
  for (const b of branches) {
    if (!b.node) continue;
    const cur = b.node;
    const base = `stores/${b.storeCode}/customers/${b.customerId}`;
    const curPts = num(cur.diem_hien_tai) ?? num(cur.currentPoints);
    if (curPts !== want.diem_hien_tai || num(cur.currentPoints) !== want.currentPoints) {
      out[`${base}/diem_hien_tai`] = want.diem_hien_tai;
      out[`${base}/currentPoints`] = want.currentPoints;
    }
    if (num(cur.totalPoints) !== want.totalPoints) out[`${base}/totalPoints`] = want.totalPoints;
  }
  return out;
}

// ===================== Di trú: gom khách chi nhánh theo SĐT =====================

export interface SourceCustomer {
  storeCode: string;
  customerId: string;
  name: string;
  phone: unknown;
  points: number;
  totalPoints: number;
  createdAt?: number;
}

export interface MigrationGroup {
  memberKey: string;
  phone: string;
  name: string;
  points: number;
  totalPoints: number;
  joinedAt: number;
  lastStoreCode: string;
  sources: SourceCustomer[];
  /** true nếu gom ≥ 2 node khách (trùng SĐT trong chuỗi hoặc cùng chi nhánh) */
  duplicate: boolean;
}

export interface MigrationPlan {
  groups: MigrationGroup[];
  /** Khách không có SĐT hợp lệ: mỗi người 1 bản ghi cục bộ L_..., không gộp */
  localOnly: MigrationGroup[];
  totals: { branchPoints: number; sharedPoints: number; branchTotalPoints: number; sharedTotalPoints: number };
}

/**
 * Gom khách các chi nhánh theo SĐT chuẩn hóa: CỘNG điểm hiện tại và tổng điểm tích lũy.
 * Tên lấy từ node có tổng điểm cao nhất (hòa → node tạo sớm nhất).
 */
export function planMigration(customers: SourceCustomer[]): MigrationPlan {
  const byKey = new Map<string, SourceCustomer[]>();
  const localKeys = new Set<string>();
  for (const c of customers) {
    const key = memberKeyFor(c.phone, c.storeCode, c.customerId);
    if (isLocalMemberKey(key)) localKeys.add(key);
    const arr = byKey.get(key) ?? [];
    arr.push(c);
    byKey.set(key, arr);
  }
  const groups: MigrationGroup[] = [];
  const localOnly: MigrationGroup[] = [];
  for (const [key, list] of [...byKey.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    const sorted = [...list].sort(
      (a, b) => b.totalPoints - a.totalPoints || (a.createdAt ?? Infinity) - (b.createdAt ?? Infinity) || a.storeCode.localeCompare(b.storeCode) || a.customerId.localeCompare(b.customerId)
    );
    const created = list.map((c) => c.createdAt).filter((x): x is number => typeof x === "number" && x > 0);
    const g: MigrationGroup = {
      memberKey: key,
      phone: localKeys.has(key) ? "" : key,
      name: sorted[0].name,
      points: list.reduce((s, c) => s + Math.max(0, c.points), 0),
      totalPoints: list.reduce((s, c) => s + Math.max(c.totalPoints, c.points, 0), 0),
      joinedAt: created.length ? Math.min(...created) : 0,
      lastStoreCode: sorted[0].storeCode,
      sources: sorted,
      duplicate: list.length > 1,
    };
    (localKeys.has(key) ? localOnly : groups).push(g);
  }
  const all = [...groups, ...localOnly];
  return {
    groups,
    localOnly,
    totals: {
      branchPoints: customers.reduce((s, c) => s + Math.max(0, c.points), 0),
      sharedPoints: all.reduce((s, g) => s + g.points, 0),
      branchTotalPoints: customers.reduce((s, c) => s + Math.max(c.totalPoints, c.points, 0), 0),
      sharedTotalPoints: all.reduce((s, g) => s + g.totalPoints, 0),
    },
  };
}

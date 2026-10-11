/**
 * Cloud Functions cho điểm DÙNG CHUNG toàn chuỗi (xem sharedLoyalty.ts cho mô hình dữ liệu).
 *
 * Callable (client KHÔNG ghi loyalty_members / loyalty_ledger / loyalty_config - rules đóng hoàn toàn):
 *  - applyLoyaltyEarn      tích điểm theo hóa đơn PAID (số điểm tính phía máy chủ từ finalAmount)
 *  - redeemLoyaltyPoints   đổi điểm trước khi ghi hóa đơn (không đủ → failed-precondition, details.code = "insufficient")
 *  - refundLoyaltyPoints   hoàn điểm đã đổi khi ghi hóa đơn thất bại (chỉ khi hóa đơn chưa PAID)
 *  - adjustLoyaltyPoints   chỉnh tay (Quản lý/Chủ): ADD | SUB | SET + lý do
 *  - lookupMember          tra số dư dùng chung theo SĐT hoặc khách của chi nhánh (Thu ngân trở lên)
 *  - getMemberLedger       lịch sử điểm xuyên chi nhánh
 *  - setLoyaltyConfig      cấu hình chuỗi: tỷ lệ tích/đổi + mốc hạng (Chủ)
 * Trigger:
 *  - mirrorMemberToBranches  loyalty_members → cache điểm trên mọi node khách chi nhánh cùng SĐT
 *  - linkBranchCustomer      node khách chi nhánh → tạo/gắn bản ghi dùng chung (+ sửa cache lệch)
 *  - mirrorLedgerToHistory   loyalty_ledger → Firestore kmt_point_history
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onValueWritten, onValueCreated } from "firebase-functions/v2/database";
import { FieldValue } from "firebase-admin/firestore";
import * as admin from "firebase-admin";
import { isManagerRole, isOwnerRole, canCallerImportCustomer, type UserProfile } from "./permissions";
import { AnyMap, isValidCustomerKey, isValidStoreCode, readCurrentPoints, readTotalPoints } from "./customerSync";
import {
  applyOp,
  billOpId,
  buildLedgerEntry,
  buildLedgerHistory,
  computeEarnPoints,
  isLocalMemberKey,
  memberKeyFor,
  planBranchCacheUpdates,
  readMember,
  resolveRates,
  sanitizeKey,
  MAX_POINTS_PER_OP,
  type LoyaltyOpType,
  type Member,
  type OpRequest,
  type OpResult,
} from "./sharedLoyalty";

if (!admin.apps.length) {
  admin.initializeApp({
    databaseURL: process.env.DATABASE_URL || "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app",
  });
}
const db = admin.database();
const REGION = "asia-southeast1";

type Level = "cashier" | "manager" | "owner";

interface Ctx {
  uid: string;
  store: string;
  caller: UserProfile;
  staff: string;
}

/** Xác thực người gọi: thành viên ĐANG HOẠT ĐỘNG của chi nhánh [storeCode] với vai trò đủ cấp */
async function authorize(request: { auth?: { uid: string } | null; data?: unknown }, level: Level): Promise<Ctx & { data: AnyMap }> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
  const data = (request.data || {}) as AnyMap;
  if (!isValidStoreCode(data.storeCode)) throw new HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
  const store = (data.storeCode as string).trim().toUpperCase();
  const uid = request.auth.uid;
  const [callerSnap, indexSnap] = await Promise.all([db.ref(`stores/${store}/users/${uid}`).get(), db.ref(`userIndex/${uid}/${store}`).get()]);
  const caller = (callerSnap.exists() ? callerSnap.val() : null) as UserProfile | null;
  const inIndex = indexSnap.val() === true;
  const active = !!caller && caller.isActive !== false && inIndex;
  let ok = false;
  if (active && caller) {
    if (level === "cashier") ok = canCallerImportCustomer(caller, inIndex);
    else if (level === "manager") ok = isOwnerRole(caller.roleId, caller.isRootOwner) || isManagerRole(caller.roleId);
    else ok = isOwnerRole(caller.roleId, caller.isRootOwner);
  }
  if (!ok || !caller) {
    throw new HttpsError("permission-denied", level === "cashier" ? "Bạn không có quyền thao tác điểm của chi nhánh này." : level === "manager" ? "Chỉ Quản lý/Chủ quán được chỉnh điểm." : "Chỉ Chủ quán được đổi cấu hình điểm.");
  }
  return { uid, store, caller, staff: caller.username || "unknown", data };
}

interface Target {
  memberKey: string;
  customerId?: string;
  name: string;
  phone: string;
}

/** Xác định bản ghi điểm cần thao tác từ customerId (node khách chi nhánh) hoặc phone */
async function resolveTarget(store: string, data: AnyMap): Promise<Target> {
  const customerId = data.customerId;
  if (customerId !== undefined && customerId !== null && customerId !== "") {
    if (!isValidCustomerKey(customerId)) throw new HttpsError("invalid-argument", "Mã khách hàng không hợp lệ.");
    const snap = await db.ref(`stores/${store}/customers/${customerId}`).get();
    if (!snap.exists()) throw new HttpsError("not-found", "Không tìm thấy khách hàng ở chi nhánh này.");
    const c = snap.val() as AnyMap;
    const rawPhone = c.so_dien_thoai ?? c.phone;
    const key = memberKeyFor(rawPhone, store, customerId);
    return { memberKey: key, customerId, name: String(c.ho_ten ?? c.name ?? ""), phone: isLocalMemberKey(key) ? "" : key };
  }
  const phoneKey = memberKeyFor(data.phone, "-", "-");
  if (isLocalMemberKey(phoneKey)) throw new HttpsError("invalid-argument", "Cần mã khách hàng hoặc số điện thoại hợp lệ.");
  return { memberKey: phoneKey, name: "", phone: phoneKey };
}

function clean<T>(o: T): T {
  return JSON.parse(JSON.stringify(o)) as T;
}

function withBranch(cur: AnyMap | null, store: string, customerId?: string): AnyMap {
  const base: AnyMap = cur ? { ...cur } : {};
  if (customerId) {
    const branches = { ...((base.branches as AnyMap) || {}) };
    branches[store] = { ...((branches[store] as AnyMap) || {}), [customerId]: true };
    base.branches = branches;
  }
  return base;
}

/** Chạy 1 thao tác điểm bằng transaction trên loyalty_members/{key} và ghi sổ cái (chỉ tạo mới). */
async function runOp(
  target: Target,
  req: OpRequest,
  extra: { billId?: string; billCode?: string; staff: string; note?: string }
): Promise<OpResult> {
  const ref = db.ref(`loyalty_members/${target.memberKey}`);
  const canCreate = req.type === "earn" || req.type === "adjust" || req.type === "opening";
  const request: OpRequest = { ...req, name: req.name ?? target.name, phone: req.phone ?? target.phone };
  let last: OpResult | undefined;
  const tx = await ref.transaction((cur: unknown) => {
    if (cur === null && !canCreate) {
      // Cache rỗng ở lần chạy đầu (hoặc thật sự chưa có): ghi null để SDK chạy lại với dữ liệu thật
      last = undefined;
      return null;
    }
    const curMap = cur && typeof cur === "object" ? (cur as AnyMap) : null;
    const r = applyOp(readMember(curMap), request);
    last = r;
    if (r.status !== "applied" || !r.member) return undefined;
    return clean({ ...withBranch(curMap, req.storeCode, target.customerId), ...r.member });
  });
  const res = last as OpResult | undefined;
  if (!res || (tx.committed && !tx.snapshot.exists())) {
    return { status: req.type === "refund" ? "nothingToRefund" : "insufficient", applied: 0, before: 0, after: 0, totalAfter: 0 };
  }
  if (res.status === "applied" && !tx.committed) throw new HttpsError("aborted", "Điểm của khách vừa thay đổi. Vui lòng thử lại.");

  const ledgerRef = db.ref(`loyalty_ledger/${target.memberKey}/${req.opId}`);
  if (res.status === "applied") {
    await ledgerRef
      .set(clean(buildLedgerEntry(request, res, { ...extra, customerId: target.customerId })))
      .catch((e) => console.error("loyalty_ledger write failed", target.memberKey, req.opId, e));
  } else if (res.status === "alreadyApplied") {
    // Lần trước commit số dư nhưng chưa kịp ghi sổ cái → bù bản ghi tối thiểu
    const snap = await ledgerRef.get();
    if (!snap.exists()) {
      await ledgerRef
        .set(clean({ type: req.type, points: req.type === "redeem" ? -res.applied : res.applied, balanceAfter: res.after, storeCode: req.storeCode, staff: extra.staff, at: req.now, billId: extra.billId, healed: true }))
        .catch(() => undefined);
    }
  }
  return res;
}

function resultPayload(r: OpResult, memberKey: string): AnyMap {
  return {
    success: r.status === "applied" || r.status === "alreadyApplied",
    status: r.status,
    memberKey,
    applied: r.applied,
    before: r.before,
    after: r.after,
    points: r.after,
    totalPoints: r.totalAfter,
  };
}

function toInt(v: unknown): number {
  return typeof v === "number" && Number.isInteger(v) ? v : NaN;
}

function requireBillId(v: unknown): string {
  if (typeof v !== "string" || !v.trim() || v.length > 128) throw new HttpsError("invalid-argument", "Thiếu hoặc sai mã hóa đơn.");
  return v.trim();
}

async function auditLog(store: string, caller: UserProfile, action: string, targetId: string, details: string): Promise<void> {
  const now = Date.now();
  await db
    .ref(`stores/${store}/audit_logs/LOG_${now}_${Math.random().toString(36).substring(2, 7)}`)
    .set({
      timestamp: now,
      action,
      username: caller.username || "unknown",
      userFullName: caller.fullName || "",
      userRole: caller.roleId || "",
      targetType: "CUSTOMER",
      targetId,
      details,
    })
    .catch(() => undefined);
}

// ---------------------------------------------------------------------------------------------

export const applyLoyaltyEarn = onCall({ region: REGION }, async (request) => {
  const ctx = await authorize(request, "cashier");
  const billId = requireBillId(ctx.data.billId);
  const billSnap = await db.ref(`stores/${ctx.store}/bills/${billId}`).get();
  if (!billSnap.exists()) throw new HttpsError("failed-precondition", "Hóa đơn chưa được đồng bộ lên máy chủ, thử lại sau.");
  const bill = billSnap.val() as AnyMap;
  if (bill.status !== "PAID") throw new HttpsError("failed-precondition", "Chỉ tích điểm cho hóa đơn đã thanh toán.");
  const customerId = typeof bill.customerId === "string" ? bill.customerId.trim() : "";
  if (!customerId) return { success: true, status: "applied", applied: 0, skipped: "no-customer" };
  const [cfgSnap, infoSnap] = await Promise.all([db.ref("loyalty_config").get(), db.ref(`stores/${ctx.store}/storeInfo`).get()]);
  const rates = resolveRates(cfgSnap.val() as AnyMap | null, infoSnap.val() as AnyMap | null);
  const finalAmount = typeof bill.finalAmount === "number" ? bill.finalAmount : 0;
  const points = computeEarnPoints(finalAmount, rates.earnRate, rates.redeemRate);
  const target = await resolveTarget(ctx.store, { customerId });
  if (points <= 0) return { success: true, status: "applied", applied: 0, memberKey: target.memberKey };
  const r = await runOp(
    target,
    { type: "earn", points, opId: billOpId(billId, "earn"), storeCode: ctx.store, now: Date.now() },
    { billId, billCode: typeof bill.billCode === "string" ? bill.billCode : undefined, staff: ctx.staff }
  );
  return resultPayload(r, target.memberKey);
});

export const redeemLoyaltyPoints = onCall({ region: REGION }, async (request) => {
  const ctx = await authorize(request, "cashier");
  const billId = requireBillId(ctx.data.billId);
  const points = toInt(ctx.data.points);
  if (!Number.isInteger(points) || points <= 0 || points > MAX_POINTS_PER_OP) throw new HttpsError("invalid-argument", "Số điểm đổi không hợp lệ.");
  const target = await resolveTarget(ctx.store, ctx.data);
  if (!target.customerId) throw new HttpsError("invalid-argument", "Thiếu mã khách hàng.");
  const r = await runOp(
    target,
    { type: "redeem", points, opId: billOpId(billId, "redeem"), storeCode: ctx.store, now: Date.now() },
    { billId, billCode: typeof ctx.data.billCode === "string" ? ctx.data.billCode : undefined, staff: ctx.staff }
  );
  if (r.status === "insufficient") {
    throw new HttpsError("failed-precondition", `Khách chỉ còn ${r.before} điểm, không đủ ${points} điểm.`, { code: "insufficient", balance: r.before, requested: points });
  }
  if (r.status === "invalid") throw new HttpsError("invalid-argument", "Số điểm đổi không hợp lệ.");
  return resultPayload(r, target.memberKey);
});

export const refundLoyaltyPoints = onCall({ region: REGION }, async (request) => {
  const ctx = await authorize(request, "cashier");
  const billId = requireBillId(ctx.data.billId);
  const billSnap = await db.ref(`stores/${ctx.store}/bills/${billId}/status`).get();
  if (billSnap.val() === "PAID") throw new HttpsError("failed-precondition", "Hóa đơn đã thanh toán, không hoàn điểm.");
  const target = await resolveTarget(ctx.store, ctx.data);
  const redeemSnap = await db.ref(`loyalty_members/${target.memberKey}/ops/${billOpId(billId, "redeem")}/p`).get();
  const redeemed = typeof redeemSnap.val() === "number" ? (redeemSnap.val() as number) : 0;
  const asked = toInt(ctx.data.points);
  const points = Number.isInteger(asked) && asked > 0 ? Math.min(asked, redeemed || asked) : redeemed;
  if (points <= 0) return { success: true, status: "nothingToRefund", applied: 0, memberKey: target.memberKey };
  const r = await runOp(
    target,
    { type: "refund", points, opId: billOpId(billId, "refund"), storeCode: ctx.store, now: Date.now() },
    { billId, staff: ctx.staff }
  );
  return resultPayload(r, target.memberKey);
});

export const adjustLoyaltyPoints = onCall({ region: REGION }, async (request) => {
  const ctx = await authorize(request, "manager");
  const mode = String(ctx.data.mode ?? "").toUpperCase();
  const n = toInt(ctx.data.points);
  if (!["ADD", "SUB", "SET"].includes(mode) || !Number.isInteger(n) || n < 0 || n > MAX_POINTS_PER_OP) {
    throw new HttpsError("invalid-argument", "Chế độ (ADD/SUB/SET) hoặc số điểm không hợp lệ.");
  }
  if (mode !== "SET" && n === 0) throw new HttpsError("invalid-argument", "Số điểm phải lớn hơn 0.");
  const reason = typeof ctx.data.reason === "string" ? ctx.data.reason.trim() : "";
  if (reason.length < 3 || reason.length > 300) throw new HttpsError("invalid-argument", "Cần ghi lý do chỉnh điểm (3-300 ký tự).");
  const target = await resolveTarget(ctx.store, ctx.data);
  const clientOp = typeof ctx.data.opId === "string" && /^[A-Za-z0-9_-]{6,64}$/.test(ctx.data.opId) ? ctx.data.opId : `${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
  const req: OpRequest = {
    type: "adjust",
    points: mode === "SUB" ? -n : n,
    setTo: mode === "SET" ? n : undefined,
    opId: `adj_${clientOp}`,
    storeCode: ctx.store,
    now: Date.now(),
  };
  const r = await runOp(target, req, { staff: ctx.staff, note: reason });
  if (r.status === "insufficient") throw new HttpsError("failed-precondition", `Khách chỉ còn ${r.before} điểm, không trừ được ${n}.`, { code: "insufficient", balance: r.before });
  if (r.status === "invalid") throw new HttpsError("invalid-argument", "Số điểm sau chỉnh không đổi hoặc không hợp lệ.");
  if (r.status === "applied") {
    await auditLog(ctx.store, ctx.caller, "LOYALTY_ADJUST", target.customerId ?? target.memberKey, `Chỉnh điểm ${mode} ${n}: ${r.before} → ${r.after} (${reason})`);
  }
  return resultPayload(r, target.memberKey);
});

export const lookupMember = onCall({ region: REGION }, async (request) => {
  const ctx = await authorize(request, "cashier");
  const target = await resolveTarget(ctx.store, ctx.data).catch((e) => {
    if (e instanceof HttpsError && e.code === "not-found") return null;
    throw e;
  });
  if (!target) return { found: false };
  const snap = await db.ref(`loyalty_members/${target.memberKey}`).get();
  const m = readMember(snap.val());
  if (!m) return { found: false, memberKey: target.memberKey };
  const branches = ((snap.val() as AnyMap).branches || {}) as AnyMap;
  return {
    found: true,
    memberKey: target.memberKey,
    local: isLocalMemberKey(target.memberKey),
    name: m.name,
    phone: m.phone,
    points: m.points,
    totalPoints: m.totalPoints,
    lastStoreCode: m.lastStoreCode ?? "",
    joinedAt: m.joinedAt,
    branchCount: Object.keys(branches).length,
  };
});

export const getMemberLedger = onCall({ region: REGION }, async (request) => {
  const ctx = await authorize(request, "cashier");
  const target = await resolveTarget(ctx.store, ctx.data);
  const limit = Math.min(Math.max(toInt(ctx.data.limit) || 100, 1), 300);
  const snap = await db.ref(`loyalty_ledger/${target.memberKey}`).get();
  const entries: AnyMap[] = [];
  snap.forEach((c) => {
    entries.push({ id: c.key, ...(c.val() as AnyMap) });
  });
  entries.sort((a, b) => Number(b.at ?? 0) - Number(a.at ?? 0));
  return { memberKey: target.memberKey, entries: entries.slice(0, limit) };
});

export const setLoyaltyConfig = onCall({ region: REGION }, async (request) => {
  const ctx = await authorize(request, "owner");
  const d = ctx.data;
  const patch: AnyMap = {};
  if (d.pointEarnRate !== undefined) {
    const v = d.pointEarnRate;
    if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > 100) throw new HttpsError("invalid-argument", "Tỷ lệ tích điểm phải trong khoảng 0-100 (%).");
    patch.pointEarnRate = v;
  }
  if (d.pointRedeemRate !== undefined) {
    const v = d.pointRedeemRate;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 1_000_000) throw new HttpsError("invalid-argument", "Giá trị 1 điểm (đ) phải là số nguyên 1-1.000.000.");
    patch.pointRedeemRate = v;
  }
  if (d.loyaltyTiers !== undefined) {
    const arr = d.loyaltyTiers;
    if (!Array.isArray(arr) || arr.length > 20) throw new HttpsError("invalid-argument", "Danh sách hạng không hợp lệ (tối đa 20).");
    const tiers = arr.map((t) => {
      const o = (t || {}) as AnyMap;
      const name = typeof o.name === "string" ? o.name.trim() : "";
      const min = o.minPoints;
      if (!name || name.length > 40 || typeof min !== "number" || !Number.isInteger(min) || min < 0) throw new HttpsError("invalid-argument", "Mỗi hạng cần tên và ngưỡng điểm nguyên >= 0.");
      return { name, minPoints: min };
    });
    patch.loyaltyTiers = tiers;
  }
  if (Object.keys(patch).length === 0) throw new HttpsError("invalid-argument", "Không có cấu hình nào để lưu.");
  patch.updatedAt = Date.now();
  patch.updatedBy = ctx.staff;
  await db.ref("loyalty_config").update(patch);
  await auditLog(ctx.store, ctx.caller, "LOYALTY_CONFIG", "loyalty_config", `Cập nhật cấu hình điểm toàn chuỗi: ${Object.keys(patch).filter((k) => !k.startsWith("updated")).join(", ")}`);
  return { success: true };
});

// ---------------------------------------------------------------------------------------------
// Triggers

function branchRefs(member: AnyMap | null): { storeCode: string; customerId: string }[] {
  const out: { storeCode: string; customerId: string }[] = [];
  const b = (member?.branches || {}) as Record<string, Record<string, unknown>>;
  for (const [storeCode, customers] of Object.entries(b)) {
    if (!customers || typeof customers !== "object") continue;
    for (const customerId of Object.keys(customers)) out.push({ storeCode, customerId });
  }
  return out;
}

/** Cache điểm trên node khách chi nhánh luôn bằng bản ghi dùng chung */
export const mirrorMemberToBranches = onValueWritten({ ref: "/loyalty_members/{memberKey}", region: REGION }, async (event) => {
  if (!event.data.after.exists()) return;
  const after = event.data.after.val() as AnyMap;
  const before = (event.data.before.exists() ? event.data.before.val() : null) as AnyMap | null;
  const m = readMember(after);
  if (!m) return;
  const refs = branchRefs(after);
  const unchanged = before && readMember(before)?.points === m.points && readMember(before)?.totalPoints === m.totalPoints && branchRefs(before).length === refs.length;
  if (unchanged || refs.length === 0) return;
  const nodes = await Promise.all(
    refs.map(async (r) => {
      const s = await db.ref(`stores/${r.storeCode}/customers/${r.customerId}`).get();
      return { ...r, node: s.exists() ? (s.val() as AnyMap) : null };
    })
  );
  const updates = planBranchCacheUpdates(m, nodes);
  if (Object.keys(updates).length) await db.ref().update(updates);
});

/** Node khách chi nhánh ↔ bản ghi dùng chung: tạo/gắn, gộp khi khách thêm SĐT, sửa cache lệch */
export const linkBranchCustomer = onValueWritten({ ref: "/stores/{storeCode}/customers/{customerId}", region: REGION }, async (event) => {
  const { storeCode, customerId } = event.params;
  if (!isValidCustomerKey(customerId)) return;
  const before = (event.data.before.exists() ? event.data.before.val() : null) as AnyMap | null;
  const after = (event.data.after.exists() ? event.data.after.val() : null) as AnyMap | null;
  const keyOf = (c: AnyMap) => memberKeyFor(c.so_dien_thoai ?? c.phone, storeCode, customerId);
  const oldKey = before ? keyOf(before) : null;

  if (!after) {
    // Xóa khách ở chi nhánh: chỉ gỡ liên kết, số điểm chung được giữ nguyên
    if (oldKey) await db.ref(`loyalty_members/${oldKey}/branches/${storeCode}/${customerId}`).remove().catch(() => undefined);
    return;
  }
  const key = keyOf(after);
  const name = String(after.ho_ten ?? after.name ?? "");
  const now = Date.now();
  const seedPts = readCurrentPoints(after);
  const seedTotal = Math.max(readTotalPoints(after), seedPts);
  const created = typeof after.createdAt === "number" ? after.createdAt : now;

  const mref = db.ref(`loyalty_members/${key}`);
  const tx = await mref.transaction((cur: unknown) => {
    if (cur === null) {
      // Lần đầu thấy SĐT này: khởi tạo từ số dư đang có trên node (di trú/nhập cũ); node mới do Thu ngân tạo luôn 0
      const m: Member = { name, phone: isLocalMemberKey(key) ? "" : key, points: seedPts, totalPoints: seedTotal, joinedAt: created, updatedAt: now, lastStoreCode: storeCode };
      return clean({ ...m, branches: { [storeCode]: { [customerId]: true } } });
    }
    const c = cur as AnyMap;
    const b = (c.branches || {}) as Record<string, Record<string, unknown>>;
    if (b[storeCode]?.[customerId] === true && (c.name || !name)) return undefined; // đã gắn, không cần ghi
    return clean({ ...withBranch(c, storeCode, customerId), name: c.name || name });
  });
  const memberVal = (tx.snapshot.val() || null) as AnyMap | null;
  const m = readMember(memberVal);

  // Khách vừa thêm/đổi SĐT: số dư của bản ghi cũ (cục bộ L_...) được chuyển sang bản ghi theo SĐT
  if (oldKey && oldKey !== key && isLocalMemberKey(oldKey)) {
    const oldSnap = await db.ref(`loyalty_members/${oldKey}`).get();
    const old = readMember(oldSnap.val());
    if (old && old.points > 0) {
      const target: Target = { memberKey: key, customerId, name, phone: key };
      const moved = await runOp(target, { type: "opening", points: old.points, opId: `merge_${sanitizeKey(oldKey)}`, storeCode, now: Date.now() }, { staff: "system", note: `Gộp điểm từ ${oldKey}` });
      if (moved.status === "applied" || moved.status === "alreadyApplied") {
        await runOp({ memberKey: oldKey, name: old.name, phone: "" }, { type: "adjust", points: -old.points, opId: `merge_out_${sanitizeKey(key)}`, storeCode, now: Date.now() }, { staff: "system", note: `Chuyển điểm sang ${key}` });
      }
    }
    await db.ref(`loyalty_members/${oldKey}/branches/${storeCode}/${customerId}`).remove().catch(() => undefined);
  } else if (oldKey && oldKey !== key) {
    await db.ref(`loyalty_members/${oldKey}/branches/${storeCode}/${customerId}`).remove().catch(() => undefined);
  }

  if (m) {
    const fresh = await db.ref(`loyalty_members/${key}`).get();
    const fm = readMember(fresh.val()) ?? m;
    const updates = planBranchCacheUpdates(fm, [{ storeCode, customerId, node: after }]);
    if (Object.keys(updates).length) await db.ref().update(updates);
  }
});

/** Sổ cái chung → lịch sử điểm Firestore kmt_point_history (doc id cố định, chạy lại không trùng) */
export const mirrorLedgerToHistory = onValueCreated({ ref: "/loyalty_ledger/{memberKey}/{opId}", region: REGION }, async (event) => {
  const { memberKey, opId } = event.params;
  const hist = buildLedgerHistory(memberKey, opId, (event.data.val() || {}) as AnyMap);
  if (!hist) return;
  await admin
    .firestore()
    .collection("kmt_point_history")
    .doc(hist.docId)
    .set({ ...hist.data, ngay_tich: FieldValue.serverTimestamp() }, { merge: true });
});

export type { LoyaltyOpType };

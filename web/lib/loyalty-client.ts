/**
 * Client TS cho điểm DÙNG CHUNG toàn chuỗi: bọc các Cloud Functions callable (functions/src/sharedLoyaltyHandlers.ts).
 * Web KHÔNG ghi điểm trực tiếp (rules đóng loyalty_members / loyalty_ledger / loyalty_config).
 *
 * Luồng thanh toán Web (lib/data-context.tsx checkoutAndFreeTable + app/dashboard/tables) gọi theo thứ tự POS:
 * redeemLoyaltyPoints (trước khi ghi hóa đơn) → ghi hóa đơn → applyLoyaltyEarn (sau khi PAID);
 * ghi hóa đơn lỗi → refundLoyaltyPoints.
 */
import { httpsCallable, type Functions } from "firebase/functions";
import { functions as defaultFunctions } from "./firebase";

export type AdjustModeCode = "ADD" | "SUB" | "SET";

export interface OpResponse {
  success: boolean;
  status: "applied" | "alreadyApplied" | "insufficient" | "nothingToRefund" | "invalid";
  memberKey?: string;
  /** Số điểm thực sự áp dụng */
  applied: number;
  before?: number;
  after?: number;
  /** Số dư sau thao tác */
  points?: number;
  totalPoints?: number;
  skipped?: string;
}

export interface MemberInfo {
  found: boolean;
  memberKey?: string;
  local?: boolean;
  name?: string;
  phone?: string;
  points?: number;
  totalPoints?: number;
  lastStoreCode?: string;
  joinedAt?: number;
  branchCount?: number;
}

export interface LedgerEntryRaw {
  id: string;
  type: string;
  points: number;
  balanceAfter: number;
  storeCode: string;
  billId?: string;
  customerId?: string;
  staff?: string;
  note?: string;
  at: number;
}

export interface ChainConfigPatch {
  pointEarnRate?: number;
  pointRedeemRate?: number;
  loyaltyTiers?: { name: string; minPoints: number }[];
}

type Target = { customerId: string } | { phone: string };

let fns: Functions = defaultFunctions;
/** Dùng trong test để thay Functions */
export function setLoyaltyFunctions(f: Functions): void {
  fns = f;
}

async function call<Req, Res>(name: string, data: Req): Promise<Res> {
  const res = await httpsCallable<Req, Res>(fns, name)(data);
  return res.data;
}

/** Tích điểm cho hóa đơn PAID (máy chủ tự tính điểm từ finalAmount + cấu hình chuỗi; idempotent theo hóa đơn) */
export const applyLoyaltyEarn = (storeCode: string, billId: string) =>
  call<{ storeCode: string; billId: string }, OpResponse>("applyLoyaltyEarn", { storeCode, billId });

/** Đổi điểm trước khi ghi hóa đơn. Không đủ điểm → lỗi `failed-precondition` (details.code = "insufficient") */
export const redeemLoyaltyPoints = (storeCode: string, customerId: string, billId: string, points: number, billCode?: string) =>
  call<Record<string, unknown>, OpResponse>("redeemLoyaltyPoints", { storeCode, customerId, billId, points, billCode });

/** Hoàn điểm đã đổi khi ghi hóa đơn thất bại (hóa đơn chưa PAID) */
export const refundLoyaltyPoints = (storeCode: string, customerId: string, billId: string, points?: number) =>
  call<Record<string, unknown>, OpResponse>("refundLoyaltyPoints", { storeCode, customerId, billId, points });

/** Số dư dùng chung theo khách của chi nhánh hoặc SĐT */
export const lookupMember = (storeCode: string, target: Target) =>
  call<Record<string, unknown>, MemberInfo>("lookupMember", { storeCode, ...target });

/** Quản lý/Chủ chỉnh điểm: ADD | SUB | SET + lý do (bắt buộc). opId để chống bấm trùng. */
export const adjustLoyaltyPoints = (storeCode: string, target: Target, mode: AdjustModeCode, points: number, reason: string, opId?: string) =>
  call<Record<string, unknown>, OpResponse>("adjustLoyaltyPoints", { storeCode, ...target, mode, points, reason, opId });

/** Lịch sử điểm xuyên chi nhánh (mới nhất trước) */
export const getMemberLedger = (storeCode: string, target: Target, limit = 100) =>
  call<Record<string, unknown>, { memberKey: string; entries: LedgerEntryRaw[] }>("getMemberLedger", { storeCode, ...target, limit });

/** Chủ quán đặt tỷ lệ tích/đổi và mốc hạng TOÀN CHUỖI (storeCode = chi nhánh mà chủ là Owner) */
export const setLoyaltyConfig = (storeCode: string, patch: ChainConfigPatch) =>
  call<Record<string, unknown>, { success: boolean }>("setLoyaltyConfig", { storeCode, ...patch });

/** Lỗi `insufficient` từ callable → { balance } (hoặc null nếu là lỗi khác) */
export function insufficientBalance(err: unknown): { balance: number } | null {
  const d = (err as { details?: { code?: string; balance?: number } } | null)?.details;
  return d && d.code === "insufficient" ? { balance: typeof d.balance === "number" ? d.balance : 0 } : null;
}

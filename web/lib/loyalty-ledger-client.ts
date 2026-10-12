/**
 * Lịch sử điểm xuyên khách hàng cho Web: bọc callable `listLoyaltyLedger` (functions/src/sharedLoyaltyHandlers.ts)
 * + các hàm thuần (nhãn, khoảng ngày, CSV). Chỉ Quản lý/Chủ quán nhận được dữ liệu từ máy chủ.
 */
import { httpsCallable } from "firebase/functions";
import { functions } from "./firebase";

export type LedgerKind = "earn" | "redeem" | "refund" | "adjust" | "opening";

export const LEDGER_KIND_LABEL: Record<LedgerKind, string> = {
  earn: "Tích điểm",
  redeem: "Đổi điểm",
  refund: "Hoàn điểm",
  adjust: "Chỉnh tay",
  opening: "Số dư đầu kỳ",
};

export const LEDGER_KINDS = Object.keys(LEDGER_KIND_LABEL) as LedgerKind[];

export function ledgerKindLabel(type: string): string {
  return LEDGER_KIND_LABEL[type as LedgerKind] ?? type;
}

export interface LoyaltyLedgerEntry {
  opId: string;
  memberKey: string;
  memberName: string;
  memberPhone: string;
  type: string;
  points: number;
  balanceAfter: number;
  billId: string;
  billCode: string;
  storeCode: string;
  customerId: string;
  staff: string;
  note: string;
  at: number;
}

export interface LoyaltyLedgerTotals {
  earned: number;
  redeemed: number;
  manual: number;
  count: number;
}

export interface LoyaltyLedgerQuery {
  /** Mã chi nhánh hoặc "ALL" (các chi nhánh người gọi quản lý) */
  storeCode: string;
  from?: number;
  to?: number;
  types?: string[];
  search?: string;
  /** Chỉ khách này (mã khách trong chi nhánh; dùng cùng storeCode cụ thể) */
  customerId?: string;
  cursor?: string;
  limit?: number;
}

export interface LoyaltyLedgerPage {
  entries: LoyaltyLedgerEntry[];
  nextCursor?: string;
  totals: LoyaltyLedgerTotals;
}

const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
const s = (v: unknown) => (typeof v === "string" ? v : "");

/** Chuẩn hóa phản hồi callable (chịu dữ liệu thiếu trường) */
export function parseLedgerPage(raw: unknown): LoyaltyLedgerPage {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const list = Array.isArray(r.entries) ? r.entries : [];
  const entries: LoyaltyLedgerEntry[] = [];
  for (const item of list) {
    if (!item || typeof item !== "object") continue;
    const v = item as Record<string, unknown>;
    entries.push({
      opId: s(v.opId), memberKey: s(v.memberKey), memberName: s(v.memberName), memberPhone: s(v.memberPhone),
      type: s(v.type), points: n(v.points), balanceAfter: n(v.balanceAfter), billId: s(v.billId), billCode: s(v.billCode),
      storeCode: s(v.storeCode), customerId: s(v.customerId), staff: s(v.staff), note: s(v.note), at: n(v.at),
    });
  }
  const t = (r.totals && typeof r.totals === "object" ? r.totals : {}) as Record<string, unknown>;
  return {
    entries,
    nextCursor: typeof r.nextCursor === "string" && r.nextCursor ? r.nextCursor : undefined,
    totals: { earned: n(t.earned), redeemed: n(t.redeemed), manual: n(t.manual), count: n(t.count) },
  };
}

export async function listLoyaltyLedger(q: LoyaltyLedgerQuery): Promise<LoyaltyLedgerPage> {
  const res = await httpsCallable<LoyaltyLedgerQuery, unknown>(functions, "listLoyaltyLedger")(q);
  return parseLedgerPage(res.data);
}

/** Thông báo lỗi tiếng Việt từ callable (máy chủ đã trả message tiếng Việt) */
export function ledgerErrorMessage(err: unknown): string {
  const e = err as { message?: unknown; code?: unknown } | null;
  const msg = typeof e?.message === "string" ? e.message.trim() : "";
  if (msg && !/^internal$/i.test(msg) && !/^functions\//.test(msg)) return msg;
  const code = typeof e?.code === "string" ? e.code : "";
  if (code.endsWith("permission-denied")) return "Chỉ Quản lý/Chủ quán được xem lịch sử điểm.";
  if (code.endsWith("unauthenticated")) return "Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.";
  return "Không tải được lịch sử điểm. Vui lòng thử lại.";
}

/** Ngày yyyy-mm-dd (giờ máy) → mốc đầu/cuối ngày; rỗng → undefined */
export function dayStartMs(v: string): number | undefined {
  return v ? new Date(`${v}T00:00:00`).getTime() : undefined;
}
export function dayEndMs(v: string): number | undefined {
  return v ? new Date(`${v}T23:59:59.999`).getTime() : undefined;
}

const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;

/** CSV (có BOM cho Excel) từ các dòng sổ cái, kèm cột Chi nhánh */
export function buildLedgerCsv(
  entries: LoyaltyLedgerEntry[],
  fmtTime: (ms: number) => string,
  storeNameOf: (storeCode: string) => string = (c) => c
): string {
  const head = ["Thời gian", "Cửa hàng", "Mã chi nhánh", "Khách hàng", "SĐT", "Loại", "Biến động", "Số dư sau", "Mã hóa đơn", "Lý do", "Người thực hiện"];
  const lines = entries.map((r) =>
    [fmtTime(r.at), storeNameOf(r.storeCode), r.storeCode, r.memberName || r.customerId, r.memberPhone, ledgerKindLabel(r.type), r.points, r.balanceAfter, r.billCode || r.billId, r.note, r.staff]
      .map(esc)
      .join(",")
  );
  return "﻿" + [head.map(esc).join(","), ...lines].join("\n");
}

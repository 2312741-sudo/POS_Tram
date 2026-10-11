/**
 * Truy vấn sổ cái điểm dùng chung xuyên khách hàng (callable listLoyaltyLedger) - phần logic THUẦN.
 *
 * Sổ cái gốc:  loyalty_ledger/{memberKey}/{opId}  (khóa theo khách → không truy vấn khoảng thời gian được).
 * Chỉ mục:     loyalty_ledger_index/{yyyyMM}/{memberKey}~{opId} = { memberKey, opId, at, storeCode, type }
 *              (chỉ Admin SDK ghi/đọc; tháng tính theo giờ Việt Nam UTC+7).
 */

export const LEDGER_INDEX_ROOT = "loyalty_ledger_index";
/** Nút đánh dấu chỉ mục đã đầy đủ (đã backfill toàn bộ sổ cái cũ). */
export const LEDGER_INDEX_META = "_meta";
export const MAX_LEDGER_ENTRIES = 20000;
export const DEFAULT_LIMIT = 200;
export const MAX_LIMIT = 500;
const VN_OFFSET_MS = 7 * 3600 * 1000;

export type LedgerType = "earn" | "redeem" | "refund" | "adjust" | "opening";

export interface IndexEntry {
  memberKey: string;
  opId: string;
  at: number;
  storeCode: string;
  type: string;
}

export interface LedgerRow {
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

export interface LedgerFilter {
  /** null = mọi chi nhánh */
  stores: ReadonlySet<string> | null;
  from?: number;
  to?: number;
  types?: readonly string[];
  search?: string;
  /** Chỉ các dòng của khách này (mã khách trong chi nhánh) */
  customerId?: string;
}

export interface LedgerTotals {
  /** Tổng điểm cộng từ tích + hoàn (dương) */
  earned: number;
  /** Tổng điểm đã đổi (số dương) */
  redeemed: number;
  /** Chỉnh tay + số dư đầu kỳ, ròng (có dấu) */
  manual: number;
  count: number;
}

/** Khóa tháng yyyyMM theo giờ Việt Nam */
export function monthKey(at: number): string {
  const d = new Date(at + VN_OFFSET_MS);
  return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

/** Các tháng (yyyyMM) chạm khoảng [from, to]; cả hai bắt buộc hữu hạn. */
export function monthsBetween(from: number, to: number): string[] {
  const out: string[] = [];
  if (!(from <= to)) return out;
  const s = new Date(from + VN_OFFSET_MS);
  const e = new Date(to + VN_OFFSET_MS);
  let y = s.getUTCFullYear();
  let m = s.getUTCMonth();
  const ey = e.getUTCFullYear();
  const em = e.getUTCMonth();
  while (y < ey || (y === ey && m <= em)) {
    out.push(`${y}${String(m + 1).padStart(2, "0")}`);
    m += 1;
    if (m > 11) { m = 0; y += 1; }
    if (out.length > 600) break;
  }
  return out;
}

export function indexKey(memberKey: string, opId: string): string {
  return `${memberKey}~${opId}`;
}

export function indexPath(memberKey: string, opId: string, at: number): string {
  return `${LEDGER_INDEX_ROOT}/${monthKey(at)}/${indexKey(memberKey, opId)}`;
}

/** Bỏ dấu tiếng Việt + hạ chữ thường để tìm không phân biệt dấu */
export function fold(s: unknown): string {
  return String(s ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/đ/gi, "d")
    .toLowerCase()
    .trim();
}

function inRange(at: number, f: LedgerFilter): boolean {
  if (typeof f.from === "number" && at < f.from) return false;
  if (typeof f.to === "number" && at > f.to) return false;
  return true;
}

/** Lọc ở mức chỉ mục (chưa cần đọc bản ghi): chi nhánh, thời gian, loại. */
export function filterIndex(entries: IndexEntry[], f: LedgerFilter): IndexEntry[] {
  const types = f.types && f.types.length ? new Set(f.types) : null;
  return entries.filter((e) => {
    if (f.stores && !f.stores.has(e.storeCode)) return false;
    if (!inRange(e.at, f)) return false;
    if (types && !types.has(e.type)) return false;
    return true;
  });
}

/** Lọc đầy đủ (thêm tìm kiếm theo tên/SĐT/mã HĐ/ghi chú/người thực hiện, không phân biệt dấu). */
export function filterRows(rows: LedgerRow[], f: LedgerFilter): LedgerRow[] {
  const types = f.types && f.types.length ? new Set(f.types) : null;
  const q = fold(f.search);
  return rows.filter((r) => {
    if (f.stores && !f.stores.has(r.storeCode)) return false;
    if (!inRange(r.at, f)) return false;
    if (types && !types.has(r.type)) return false;
    if (f.customerId && r.customerId !== f.customerId) return false;
    if (q) {
      const hay = fold(`${r.memberName} ${r.memberPhone} ${r.memberKey} ${r.billCode} ${r.billId} ${r.note} ${r.staff}`);
      if (!hay.includes(q)) return false;
    }
    return true;
  });
}

export function computeTotals(rows: LedgerRow[]): LedgerTotals {
  const t: LedgerTotals = { earned: 0, redeemed: 0, manual: 0, count: rows.length };
  for (const r of rows) {
    if (r.type === "earn" || r.type === "refund") t.earned += r.points;
    else if (r.type === "redeem") t.redeemed += Math.abs(r.points);
    else t.manual += r.points;
  }
  return t;
}

/** Mới nhất trước; cùng thời điểm thì theo khóa ổn định để phân trang không lặp/sót. */
export function sortRows(rows: LedgerRow[]): LedgerRow[] {
  return [...rows].sort((a, b) => b.at - a.at || (a.memberKey + a.opId < b.memberKey + b.opId ? 1 : -1));
}

const rowId = (r: LedgerRow) => `${r.memberKey}~${r.opId}`;

export function encodeCursor(r: LedgerRow): string {
  return `${r.at}|${rowId(r)}`;
}

export function clampLimit(v: unknown): number {
  const n = typeof v === "number" && Number.isFinite(v) ? Math.floor(v) : DEFAULT_LIMIT;
  return Math.min(Math.max(n, 1), MAX_LIMIT);
}

/** Phân trang trên danh sách ĐÃ sắp xếp mới → cũ. Cursor hỏng → null (caller báo lỗi). */
export function paginate(sorted: LedgerRow[], cursor: string | undefined, limit: number): { page: LedgerRow[]; nextCursor?: string } | null {
  let start = 0;
  if (cursor) {
    const i = cursor.indexOf("|");
    const at = Number(cursor.slice(0, i));
    if (i < 1 || !Number.isFinite(at)) return null;
    const id = cursor.slice(i + 1);
    // Vị trí đầu tiên đứng SAU cursor trong thứ tự sắp xếp
    start = sorted.findIndex((r) => r.at < at || (r.at === at && rowId(r) < id));
    if (start < 0) start = sorted.length;
  }
  const page = sorted.slice(start, start + limit);
  const hasMore = start + limit < sorted.length;
  return { page, nextCursor: hasMore && page.length ? encodeCursor(page[page.length - 1]) : undefined };
}

/** Ghép bản ghi sổ cái thô + thông tin khách thành dòng trả về (an toàn với dữ liệu thiếu trường). */
export function toRow(memberKey: string, opId: string, raw: Record<string, unknown> | null, member: { name?: unknown; phone?: unknown } | null): LedgerRow | null {
  if (!raw || typeof raw !== "object") return null;
  const at = Number(raw.at);
  if (!Number.isFinite(at)) return null;
  const s = (v: unknown) => (typeof v === "string" ? v : "");
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  return {
    opId,
    memberKey,
    memberName: s(member?.name),
    memberPhone: s(member?.phone) || (memberKey.startsWith("L_") ? "" : memberKey),
    type: s(raw.type),
    points: n(raw.points),
    balanceAfter: n(raw.balanceAfter),
    billId: s(raw.billId),
    billCode: s(raw.billCode),
    storeCode: s(raw.storeCode),
    customerId: s(raw.customerId),
    staff: s(raw.staff),
    note: s(raw.note),
    at,
  };
}

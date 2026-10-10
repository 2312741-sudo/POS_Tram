// Tiện ích mã voucher cho Web Admin — khớp VoucherModel / CampaignService của Flutter:
//   stores/{s}/vouchers/{campaignId}/{voucherId}  (state: DRAFT|RELEASED|RESERVED|REDEEMED|CANCELLED)
//   stores/{s}/voucher_lookup/{normalizedCode} = { campaignId, voucherId }

export type VoucherState = "DRAFT" | "RELEASED" | "RESERVED" | "REDEEMED" | "CANCELLED";

/** Mã hợp lệ: chữ in hoa không dấu, số, "-" hoặc "_" (an toàn làm key RTDB), 3–32 ký tự. */
export const VOUCHER_CODE_RE = /^[A-Z0-9_-]{3,32}$/;

export function normalizeVoucherCode(raw: string): string {
  return String(raw ?? "").trim().toUpperCase();
}

export interface ParsedVoucherCodes {
  /** Mã mới hợp lệ, đã chuẩn hóa, không trùng — sẵn sàng tạo */
  codes: string[];
  /** Mã sai định dạng (giữ nguyên dạng đã chuẩn hóa) */
  invalid: string[];
  /** Mã lặp lại trong chính danh sách dán vào */
  duplicateInInput: string[];
  /** Mã đã tồn tại (trong chương trình / cửa hàng) */
  existing: string[];
}

/** Tách danh sách mã dán vào (mỗi dòng / dấu phẩy / chấm phẩy / khoảng trắng), chuẩn hóa, lọc trùng. */
export function parseVoucherCodes(text: string, existingCodes: Iterable<string> = []): ParsedVoucherCodes {
  const existingSet = new Set<string>();
  for (const c of existingCodes) existingSet.add(normalizeVoucherCode(c));
  const seen = new Set<string>();
  const out: ParsedVoucherCodes = { codes: [], invalid: [], duplicateInInput: [], existing: [] };
  const pushOnce = (list: string[], c: string) => { if (!list.includes(c)) list.push(c); };
  for (const token of String(text ?? "").split(/[\s,;]+/)) {
    const code = normalizeVoucherCode(token);
    if (!code) continue;
    if (!VOUCHER_CODE_RE.test(code)) { pushOnce(out.invalid, code); continue; }
    if (seen.has(code)) { pushOnce(out.duplicateInInput, code); continue; }
    seen.add(code);
    if (existingSet.has(code)) { out.existing.push(code); continue; }
    out.codes.push(code);
  }
  return out;
}

// Bỏ ký tự dễ nhầm (0/O, 1/I/L)
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/** Sinh ngẫu nhiên `qty` mã `PREFIX + XXXXXX`, không trùng nhau và không trùng `existingCodes`. */
export function generateRandomCodes(
  qty: number,
  prefix: string,
  existingCodes: Iterable<string> = [],
  rng: () => number = Math.random,
  length = 6,
): string[] {
  const p = normalizeVoucherCode(prefix).replace(/[^A-Z0-9_-]/g, "");
  const taken = new Set<string>();
  for (const c of existingCodes) taken.add(normalizeVoucherCode(c));
  const result: string[] = [];
  let guard = 0;
  while (result.length < qty && guard < qty * 50 + 100) {
    guard++;
    let body = "";
    for (let i = 0; i < length; i++) body += CODE_ALPHABET[Math.floor(rng() * CODE_ALPHABET.length) % CODE_ALPHABET.length];
    const code = `${p}${body}`.slice(0, 32);
    if (taken.has(code)) continue;
    taken.add(code);
    result.push(code);
  }
  return result;
}

// ==================== VIEW MODEL ====================
export interface VoucherView {
  voucherId: string;
  campaignId: string;
  code: string;
  state: VoucherState;
  createdAt?: number;
  redeemedAt?: number;
  redeemedBy?: string;
  /** Mã hóa đơn hiển thị: redeemedBillCode, fallback redeemedBillId */
  billRef?: string;
  tableName?: string;
  cancelledAt?: number;
  holdExpiresAt?: number;
}

/** State chuẩn, fallback từ trường `status` cũ — khớp VoucherModel.fromMap. */
export function resolveVoucherState(raw: Record<string, unknown>): VoucherState {
  const s = String(raw.state ?? "").toUpperCase();
  if (s === "DRAFT" || s === "RELEASED" || s === "RESERVED" || s === "REDEEMED" || s === "CANCELLED") return s;
  const status = String(raw.status ?? "").toUpperCase();
  if (status === "USED") return "REDEEMED";
  if (status === "CANCELLED") return "CANCELLED";
  return "RELEASED";
}

const optNum = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
const optStr = (v: unknown) => (v === undefined || v === null || v === "" ? undefined : String(v));

export function toVoucherView(voucherId: string, campaignId: string, raw: Record<string, unknown> | null | undefined): VoucherView {
  const r = raw ?? {};
  return {
    voucherId: optStr(r.voucherId) ?? voucherId,
    campaignId: optStr(r.campaignId) ?? campaignId,
    code: normalizeVoucherCode(String(r.normalizedCode ?? r.code ?? "")),
    state: resolveVoucherState(r),
    createdAt: optNum(r.createdAt),
    redeemedAt: optNum(r.redeemedAt) ?? optNum(r.usedAt),
    // Ưu tiên họ tên nhân viên (redeemedByName), fallback username
    redeemedBy: optStr(r.redeemedByName) ?? optStr(r.redeemedBy) ?? optStr(r.usedBy),
    billRef: optStr(r.redeemedBillCode) ?? optStr(r.redeemedBillId),
    tableName: optStr(r.tableName),
    cancelledAt: optNum(r.cancelledAt),
    holdExpiresAt: optNum(r.holdExpiresAt),
  };
}

function holdActive(v: Pick<VoucherView, "state" | "holdExpiresAt">, now: number) {
  return v.state === "RESERVED" && v.holdExpiresAt !== undefined && v.holdExpiresAt > now;
}

export function voucherStatusText(v: Pick<VoucherView, "state" | "holdExpiresAt">, now: number): string {
  switch (v.state) {
    case "DRAFT": return "Chưa phát hành";
    case "RELEASED": return "Chưa dùng";
    case "RESERVED": return holdActive(v, now) ? "Đang giữ chỗ" : "Chưa dùng";
    case "REDEEMED": return "Đã dùng";
    case "CANCELLED": return "Đã hủy";
  }
}

export function voucherStatusColor(v: Pick<VoucherView, "state" | "holdExpiresAt">, now: number): string {
  switch (v.state) {
    case "DRAFT": return "#64748b";
    case "RELEASED": return "#10b981";
    case "RESERVED": return holdActive(v, now) ? "#3b82f6" : "#10b981";
    case "REDEEMED": return "#f59e0b";
    case "CANCELLED": return "#94a3b8";
  }
}

/** Chỉ hủy được mã chưa dùng (rules RTDB cũng chặn ghi khi REDEEMED/CANCELLED). */
export function canCancelVoucher(v: Pick<VoucherView, "state" | "holdExpiresAt">, now: number): boolean {
  return v.state === "DRAFT" || v.state === "RELEASED" || (v.state === "RESERVED" && !holdActive(v, now));
}

export function voucherStats(list: VoucherView[]) {
  const s = { total: list.length, unused: 0, used: 0, cancelled: 0 };
  for (const v of list) {
    if (v.state === "REDEEMED") s.used++;
    else if (v.state === "CANCELLED") s.cancelled++;
    else s.unused++;
  }
  return s;
}

export function filterVouchers(list: VoucherView[], query: string): VoucherView[] {
  const q = normalizeVoucherCode(query);
  if (!q) return list;
  return list.filter((v) => v.code.includes(q) || (v.billRef ?? "").toUpperCase().includes(q));
}

// ==================== WRITES ====================
/** Bản ghi voucher mới — cùng dạng VoucherModel.toMap() (state RELEASED, status ISSUED). */
export function buildVoucherRecord(voucherId: string, campaignId: string, code: string, now: number) {
  return {
    voucherId,
    campaignId,
    code,
    normalizedCode: code,
    state: "RELEASED" as VoucherState,
    status: "ISSUED",
    releasedAt: now,
    tombstone: false,
    createdAt: now,
    version: 1,
  };
}

/** Multi-path update (tương đối `stores/{s}`) tạo voucher + voucher_lookup, bật hasCodes. */
export function buildVoucherCreateUpdates(
  campaignId: string,
  codes: string[],
  now: number,
  makeId: (index: number) => string,
): Record<string, unknown> {
  const updates: Record<string, unknown> = {};
  codes.forEach((code, i) => {
    const id = makeId(i);
    updates[`vouchers/${campaignId}/${id}`] = buildVoucherRecord(id, campaignId, code, now);
    updates[`voucher_lookup/${code}`] = { campaignId, voucherId: id };
  });
  if (codes.length > 0) {
    updates[`campaigns/${campaignId}/hasCodes`] = true;
    updates[`campaigns/${campaignId}/updatedAt`] = now;
  }
  return updates;
}

/** Trường cập nhật khi hủy mã (giữ voucher_lookup làm tombstone để mã không bị dùng lại). */
export function buildVoucherCancelUpdate(now: number = Date.now()) {
  return { state: "CANCELLED" as VoucherState, status: "CANCELLED", cancelledAt: now };
}

export function newVoucherId(now: number, index: number, rng: () => number = Math.random): string {
  return `VCH_${now}_${String(Math.floor(rng() * 10000)).padStart(4, "0")}_${index}`;
}

// ==================== KIỂM TRA MÃ ====================
export type VoucherCheckKind =
  | "INVALID_FORMAT" | "NOT_FOUND" | "VALID" | "USED" | "CANCELLED" | "HELD" | "DRAFT"
  | "CAMPAIGN_MISSING" | "CAMPAIGN_EXPIRED" | "CAMPAIGN_NOT_STARTED" | "CAMPAIGN_PAUSED";

export interface VoucherCheckCampaign {
  name?: string;
  programCode?: string;
  active?: boolean;
  schedule?: { absoluteStart?: number; absoluteEnd?: number };
}

export interface VoucherCheckResult {
  kind: VoucherCheckKind;
  ok: boolean;
  message: string;
}

const fmtDateTime = (ts: number) =>
  new Date(ts).toLocaleString("vi-VN", { hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit", year: "numeric" });

/** Kết luận trạng thái một mã từ dữ liệu đã tra (voucher_lookup -> voucher -> campaign). */
export function checkVoucher(
  code: string,
  voucher: VoucherView | null,
  campaign: VoucherCheckCampaign | null,
  now: number,
): VoucherCheckResult {
  const c = normalizeVoucherCode(code);
  if (!VOUCHER_CODE_RE.test(c)) return { kind: "INVALID_FORMAT", ok: false, message: `Mã "${c}" sai định dạng (chỉ gồm chữ không dấu, số, - hoặc _, 3–32 ký tự)` };
  if (!voucher) return { kind: "NOT_FOUND", ok: false, message: `Mã ${c} không tồn tại` };

  if (voucher.state === "REDEEMED") {
    const parts = [`Mã ${c} đã sử dụng ở đơn ${voucher.billRef ?? "(không rõ)"}`];
    if (voucher.tableName) parts.push(`bàn ${voucher.tableName}`);
    if (voucher.redeemedAt) parts.push(`lúc ${fmtDateTime(voucher.redeemedAt)}`);
    if (voucher.redeemedBy) parts.push(`bởi ${voucher.redeemedBy}`);
    return { kind: "USED", ok: false, message: parts.join(", ") };
  }
  if (voucher.state === "CANCELLED") {
    return { kind: "CANCELLED", ok: false, message: `Mã ${c} đã hủy${voucher.cancelledAt ? ` lúc ${fmtDateTime(voucher.cancelledAt)}` : ""}` };
  }
  if (voucher.state === "DRAFT") return { kind: "DRAFT", ok: false, message: `Mã ${c} chưa được phát hành` };

  if (!campaign) return { kind: "CAMPAIGN_MISSING", ok: false, message: `Mã ${c} thuộc chương trình không còn tồn tại` };
  const camName = campaign.programCode ? `${campaign.programCode} - ${campaign.name ?? ""}` : (campaign.name ?? "");
  const end = campaign.schedule?.absoluteEnd || 0;
  const start = campaign.schedule?.absoluteStart || 0;
  if (end > 0 && now > end) return { kind: "CAMPAIGN_EXPIRED", ok: false, message: `Mã ${c}: chương trình "${camName}" đã hết hạn (${fmtDateTime(end)})` };
  if (start > 0 && now < start) return { kind: "CAMPAIGN_NOT_STARTED", ok: false, message: `Mã ${c}: chương trình "${camName}" chưa bắt đầu (từ ${fmtDateTime(start)})` };
  if (campaign.active === false) return { kind: "CAMPAIGN_PAUSED", ok: false, message: `Mã ${c}: chương trình "${camName}" đang tạm dừng` };

  if (holdActive(voucher, now)) return { kind: "HELD", ok: false, message: `Mã ${c} đang được giữ chỗ bởi một giao dịch khác` };
  return { kind: "VALID", ok: true, message: `Mã ${c} hợp lệ — chương trình "${camName}"` };
}

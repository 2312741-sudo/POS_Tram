/**
 * Logic thuần (không phụ thuộc Firebase runtime) cho đồng bộ khách hàng tích điểm:
 * - importCustomerToStore: Firestore kmt_customers → RTDB stores/{s}/customers/{id} (chỉ tạo mới).
 * - mirrorCustomerToFirestore: RTDB (nguồn chuẩn) → Firestore kmt_customers (bản sao chỉ đọc).
 *
 * Quy ước trường khớp KmtCustomerModel (app_flutter/lib/data/models/customer_model.dart).
 */

export type AnyMap = Record<string, unknown>;

/** Khóa RTDB hợp lệ và đồng thời là Firestore doc id hợp lệ. */
export function isValidCustomerKey(id: unknown): id is string {
  if (typeof id !== "string") return false;
  const t = id.trim();
  if (!t || t !== id || t.length > 128) return false;
  if (t === "." || t === ".." || /^__.*__$/.test(t)) return false;
  return !/[.#$[\]/\u0000-\u001f\u007f]/.test(t);
}

export function isValidStoreCode(code: unknown): code is string {
  return typeof code === "string" && /^[A-Z0-9_-]{2,30}$/.test(code.trim().toUpperCase());
}

function firstString(m: AnyMap, keys: string[], fallback = ""): string {
  for (const k of keys) {
    const v = m[k];
    if (v !== undefined && v !== null) return String(v);
  }
  return fallback;
}

function firstInt(m: AnyMap, keys: string[]): number | undefined {
  for (const k of keys) {
    const v = m[k];
    if (typeof v === "number" && Number.isFinite(v)) return Math.trunc(v);
  }
  return undefined;
}

/** Điểm hiện tại theo thứ tự ưu tiên giống KmtCustomerModel.fromMap (không âm). */
export function readCurrentPoints(m: AnyMap | null | undefined): number {
  if (!m) return 0;
  return Math.max(firstInt(m, ["diem_hien_tai", "diemHienTai", "currentPoints"]) ?? 0, 0);
}

export function readTotalPoints(m: AnyMap | null | undefined): number {
  if (!m) return 0;
  return Math.max(firstInt(m, ["tongDiem", "totalPoints", "diem_hien_tai", "diemHienTai", "currentPoints"]) ?? 0, 0);
}

function readCreatedAt(m: AnyMap): number | undefined {
  const raw = m["ngay_tao"] ?? m["ngayTao"] ?? m["createdAt"];
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw === "number" && Number.isFinite(raw)) return Math.trunc(raw);
  // Firestore Timestamp (Admin SDK) có toMillis()
  const maybeTs = raw as { toMillis?: () => number };
  if (typeof maybeTs.toMillis === "function") return maybeTs.toMillis();
  const parsed = Date.parse(String(raw));
  return Number.isNaN(parsed) ? undefined : parsed;
}

/**
 * Chuẩn hóa document Firestore kmt_customers thành node RTDB (giống KmtCustomerModel.toMap)
 * kèm số dư THẬT từ Firestore. Chỉ dùng phía máy chủ (Admin SDK).
 */
export function buildRtdbCustomerFromFirestore(data: AnyMap, docId: string, now: number): AnyMap {
  const code = firstString(data, ["ma_khach_hang", "maKhachHang", "code"], docId) || docId;
  const name = firstString(data, ["ho_ten", "hoTen", "name", "tenKhachHang"]);
  const phone = firstString(data, ["so_dien_thoai", "soDienThoai", "phone", "dienThoai"]);
  const gender = firstString(data, ["gioi_tinh", "gioiTinh", "gender"], "Khác");
  const birthday = firstString(data, ["ngay_sinh", "ngaySinh", "birthday"]);
  const current = readCurrentPoints(data);
  const total = Math.max(readTotalPoints(data), current);
  const out: AnyMap = {
    id: docId,
    ma_khach_hang: code,
    code,
    ho_ten: name,
    name,
    so_dien_thoai: phone,
    phone,
    gioi_tinh: gender,
    gender,
    ngay_sinh: birthday,
    birthday,
    diem_hien_tai: current,
    currentPoints: current,
    totalPoints: total,
    ho_ten_upper: name.toUpperCase(),
    ngay_cap_nhat: now,
    importedFrom: "kmt_customers",
    importedAt: now,
  };
  const created = readCreatedAt(data);
  if (created !== undefined) out.createdAt = created;
  return out;
}

export type ImportDecision = { action: "create"; value: AnyMap } | { action: "exists" };

/** Idempotent: chỉ tạo khi node RTDB chưa có; đã có thì giữ nguyên (RTDB là nguồn chuẩn). */
export function decideImport(current: unknown, seed: AnyMap): ImportDecision {
  if (current !== null && current !== undefined) return { action: "exists" };
  return { action: "create", value: seed };
}

const PROFILE_FIELDS = [
  "ma_khach_hang",
  "code",
  "ho_ten",
  "name",
  "so_dien_thoai",
  "phone",
  "gioi_tinh",
  "gender",
  "ngay_sinh",
  "birthday",
  "ho_ten_upper",
] as const;

/** Trường ghi sang Firestore kmt_customers (merge). Điểm luôn lấy từ RTDB. */
export function buildFirestoreMirror(after: AnyMap, storeCode: string, now: number): AnyMap {
  const out: AnyMap = {};
  for (const k of PROFILE_FIELDS) {
    const v = after[k];
    if (typeof v === "string") out[k] = v;
  }
  const current = readCurrentPoints(after);
  out.diem_hien_tai = current;
  out.currentPoints = current;
  out.totalPoints = Math.max(readTotalPoints(after), current);
  out.ngay_cap_nhat = now;
  out.pointsSource = `rtdb:stores/${storeCode}/customers`;
  return out;
}

/** Bỏ qua khi không có gì cần đồng bộ (vd. chỉ đổi loyaltyOps / ngay_cap_nhat). */
export function shouldMirror(before: AnyMap | null, after: AnyMap | null): boolean {
  if (!after) return false;
  if (!before) return true;
  if (readCurrentPoints(before) !== readCurrentPoints(after)) return true;
  if (readTotalPoints(before) !== readTotalPoints(after)) return true;
  return PROFILE_FIELDS.some((k) => before[k] !== after[k]);
}

export interface PointHistoryEntry {
  /** Doc id cố định để trigger chạy lại không ghi trùng */
  docId: string;
  data: AnyMap;
}

function safeDocPart(s: string): string {
  return s.replace(/[/\s]/g, "_").slice(0, 200);
}

/**
 * Lịch sử điểm kmt_point_history cho 1 lần ghi RTDB, null nếu điểm không đổi.
 * - Có lastLoyaltyOp mới (billId:type) → id theo thao tác hóa đơn.
 * - Không có (Quản lý chỉnh tay) → id theo eventId của trigger.
 */
export function buildPointHistoryEntry(
  before: AnyMap | null,
  after: AnyMap | null,
  storeCode: string,
  customerId: string,
  eventId: string
): PointHistoryEntry | null {
  // Tạo mới (nhập từ Firestore / Thu ngân tạo với 0 điểm): số dư đã có sẵn bên Firestore → không ghi lịch sử
  if (!after || !before) return null;
  const prev = readCurrentPoints(before);
  const next = readCurrentPoints(after);
  if (prev === next) return null;
  const op = typeof after.lastLoyaltyOp === "string" ? after.lastLoyaltyOp : "";
  const isNewOp = op !== "" && op !== (before?.lastLoyaltyOp ?? "");
  const type = isNewOp && typeof after.lastLoyaltyType === "string" ? after.lastLoyaltyType : "";
  const billId = isNewOp && typeof after.lastLoyaltyBillId === "string" ? after.lastLoyaltyBillId : "";
  const nguon =
    type === "award" ? "fnb_pos" : type === "redeem" ? "fnb_pos_redeem" : type === "refund" ? "fnb_pos_refund" : "fnb_pos_adjust";
  const code = firstString(after, ["ma_khach_hang", "code"], customerId) || customerId;
  return {
    docId: isNewOp ? `POS_${safeDocPart(storeCode)}_${safeDocPart(customerId)}_${safeDocPart(op)}` : `POS_EVT_${safeDocPart(eventId)}`,
    data: {
      ma_khach_hang: code,
      cua_hang: storeCode,
      ten_cua_hang: `POS Trạm (${storeCode})`,
      diem_truoc: prev,
      diem_thay_doi: next - prev,
      diem_sau: next,
      nguon,
      bill_code: billId,
    },
  };
}

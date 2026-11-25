/**
 * NHẬP KHÁCH HÀNG TỪ FILE EXCEL KIOTVIET ("DanhSachKhachHang_KV....xlsx") — phần thuần logic (có test).
 *
 * - Đọc theo TÊN CỘT ở dòng tiêu đề (Tên khách hàng, Điện thoại, Ngày sinh, Giới tính, Điểm hiện tại, Mã khách hàng…),
 *   bỏ dòng tổng cộng KiotViet (không tên / không SĐT).
 * - SĐT chuẩn hóa 10 số bắt đầu bằng 0; số 11 số đầu cũ (016x, 012x, 018x, 0199) đổi sang đầu số mới (2018).
 * - Gộp nhiều file: trùng SĐT → gộp thành MỘT khách, CỘNG điểm các dòng (thiếu ngày sinh / giới tính thì lấy từ dòng
 *   kia). SĐT đã có khách trong POS → bỏ qua (không đè điểm).
 * Phần ghi dữ liệu: components/KiotVietImportDialog.tsx (tạo khách như "Thêm khách", điểm qua adjustLoyaltyPoints).
 */
import { normalizePhone } from "./loyalty";

export interface KvCustomer {
  /** Mã khách KiotViet (KH...) */
  kvCode: string;
  name: string;
  phone: string;
  /** yyyy-MM-dd hoặc "" */
  birthday: string;
  /** "Nam" | "Nữ" | "Khác" */
  gender: string;
  /** Điểm hiện tại trên KiotViet */
  points: number;
}

export interface KvRowIssue {
  file: string;
  row: number;
  name: string;
  reason: string;
}

export interface KvImportPlan {
  toCreate: KvCustomer[];
  /** SĐT đã có khách trong POS */
  existing: KvCustomer[];
  /** Các dòng trùng SĐT đã gộp (cộng điểm) vào khách đầu tiên */
  duplicates: KvCustomer[];
  invalid: KvRowIssue[];
}

const norm = (s: unknown) =>
  String(s ?? "")
    .normalize("NFC")
    .trim()
    .toLowerCase();

/** Đầu số di động 11 số cũ → mới (Bộ TT&TT, 2018) */
const OLD_PREFIX: Record<string, string> = {
  "0162": "032", "0163": "033", "0164": "034", "0165": "035", "0166": "036", "0167": "037", "0168": "038", "0169": "039",
  "0120": "070", "0121": "079", "0122": "077", "0126": "076", "0128": "078",
  "0123": "083", "0124": "084", "0125": "085", "0127": "081", "0129": "082",
  "0186": "056", "0188": "058", "0199": "059",
};

/** SĐT từ ô Excel → 10 số (null nếu không hợp lệ) */
export function kvPhone(raw: unknown): string | null {
  let p = String(raw ?? "").replace(/[^\d+]/g, "");
  if (!p) return null;
  if (p.startsWith("+84")) p = "0" + p.slice(3);
  else if (p.startsWith("84") && p.length === 11) p = "0" + p.slice(2);
  if (p.length === 9 && /^[35789]/.test(p)) p = "0" + p; // Excel mất số 0 đầu
  if (p.length === 11 && OLD_PREFIX[p.slice(0, 4)]) p = OLD_PREFIX[p.slice(0, 4)] + p.slice(4);
  return normalizePhone(p);
}

const pad = (n: number) => String(n).padStart(2, "0");

/** Ngày sinh từ ô Excel (Date / "dd/MM/yyyy" / "yyyy-MM-dd" / số ngày Excel) → yyyy-MM-dd */
export function kvBirthday(v: unknown): string {
  if (v == null || v === "") return "";
  if (v instanceof Date) {
    if (Number.isNaN(v.getTime())) return "";
    // SheetJS trả Date theo giờ máy; cộng 12 tiếng để không lệch ngày khi múi giờ khác
    const d = new Date(v.getTime() + 12 * 3600_000);
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
  }
  if (typeof v === "number" && v > 0 && v < 80000) {
    const d = new Date(Math.round((v - 25569) * 86400_000));
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
  }
  const s = String(v).trim();
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) return `${m[1]}-${pad(+m[2])}-${pad(+m[3])}`;
  m = s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})/);
  if (m) return `${m[3]}-${pad(+m[2])}-${pad(+m[1])}`;
  return "";
}

export function kvGender(v: unknown): string {
  const g = norm(v);
  if (g === "nam" || g === "male") return "Nam";
  if (g === "nữ" || g === "nu" || g === "female") return "Nữ";
  return "Khác";
}

/** Đọc một bảng (mảng dòng, dòng đầu là tiêu đề) của file KiotViet. */
export function parseKvSheet(rows: unknown[][], file = ""): { customers: KvCustomer[]; invalid: KvRowIssue[] } {
  const customers: KvCustomer[] = [];
  const invalid: KvRowIssue[] = [];
  const hIdx = rows.findIndex((r) => Array.isArray(r) && r.some((c) => norm(c) === "điện thoại") && r.some((c) => norm(c) === "tên khách hàng"));
  if (hIdx < 0) {
    invalid.push({ file, row: 0, name: "", reason: "Không thấy cột \"Tên khách hàng\" / \"Điện thoại\" (không phải file khách hàng KiotViet?)" });
    return { customers, invalid };
  }
  const h = rows[hIdx].map(norm);
  const col = (name: string) => h.indexOf(name);
  const iName = col("tên khách hàng"), iPhone = col("điện thoại"), iCode = col("mã khách hàng");
  const iBirth = col("ngày sinh"), iGender = col("giới tính"), iPoints = col("điểm hiện tại");
  for (let r = hIdx + 1; r < rows.length; r++) {
    const row = rows[r] ?? [];
    const name = String(row[iName] ?? "").trim().replace(/\s+/g, " ");
    const rawPhone = row[iPhone];
    if (!name && (rawPhone == null || rawPhone === "")) continue; // dòng tổng cộng / dòng trống
    const phone = kvPhone(rawPhone);
    if (!name || !phone) {
      invalid.push({ file, row: r + 1, name, reason: !name ? "Thiếu tên khách" : `SĐT không hợp lệ (${String(rawPhone ?? "")})` });
      continue;
    }
    const pts = Number(iPoints >= 0 ? row[iPoints] : 0);
    customers.push({
      kvCode: iCode >= 0 ? String(row[iCode] ?? "").trim() : "",
      name: name.toUpperCase().slice(0, 80),
      phone,
      birthday: iBirth >= 0 ? kvBirthday(row[iBirth]) : "",
      gender: iGender >= 0 ? kvGender(row[iGender]) : "Khác",
      points: Number.isFinite(pts) && pts > 0 ? Math.floor(pts) : 0,
    });
  }
  return { customers, invalid };
}

/** Gộp các file + so với khách đã có trong POS (theo SĐT) → kế hoạch nhập */
export function planKvImport(
  sheets: { customers: KvCustomer[]; invalid: KvRowIssue[] }[],
  existingPhones: Iterable<string>,
): KvImportPlan {
  const have = new Set<string>();
  for (const p of existingPhones) {
    const n = normalizePhone(String(p ?? ""));
    if (n) have.add(n);
  }
  const byPhone = new Map<string, KvCustomer>();
  const duplicates: KvCustomer[] = [];
  for (const s of sheets) {
    for (const c of s.customers) {
      const prev = byPhone.get(c.phone);
      if (!prev) {
        byPhone.set(c.phone, { ...c });
        continue;
      }
      // Gộp: cộng điểm, bổ sung thông tin còn thiếu
      prev.points += c.points;
      if (!prev.birthday) prev.birthday = c.birthday;
      if (prev.gender === "Khác") prev.gender = c.gender;
      if (!prev.kvCode) prev.kvCode = c.kvCode;
      duplicates.push(c);
    }
  }
  const toCreate: KvCustomer[] = [];
  const existing: KvCustomer[] = [];
  for (const c of byPhone.values()) (have.has(c.phone) ? existing : toCreate).push(c);
  return { toCreate, existing, duplicates, invalid: sheets.flatMap((s) => s.invalid) };
}

/** Khóa chống trùng khi chỉnh điểm (chạy lại không cộng điểm lần 2) */
export const kvPointsOpId = (phone: string) => `kvimport_${phone}`;

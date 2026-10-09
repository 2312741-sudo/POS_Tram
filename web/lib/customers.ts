/**
 * Khách hàng tích điểm (CRM) của Web Admin.
 *
 * Nguồn chuẩn: RTDB `stores/{storeCode}/customers/{customerId}` (giống app POS — xem
 * app_flutter/lib/data/models/customer_model.dart và loyalty_service.dart). Firestore `kmt_customers`
 * chỉ là bản sao do Cloud Function `mirrorCustomerToFirestore` đồng bộ, nên Web không đọc điểm từ đó.
 *
 * Quyền đọc nút customers: Chủ quán / Quản lý / Thu ngân (Phục vụ, Bếp bị chặn).
 * Web chỉ đọc; điểm chỉ đổi qua thao tác hóa đơn trên POS hoặc Quản lý / Chủ quán.
 */

export interface StoreCustomer {
  /** Khóa node RTDB */
  id: string;
  storeCode: string;
  soDienThoai: string;
  hoTen: string;
  maKhachHang: string;
  diemHienTai: number;
  tongDiem: number;
  hangThanhVien: string;
  /** Mốc tạo (ms) để sắp xếp / hiển thị */
  createdAt?: number;
  ngayTao?: string;
  tongChiTieu?: number;
  soDonDaMua?: number;
}

export const CUSTOMER_TIERS = ["Thành viên", "Bạc", "Vàng", "Kim Cương"] as const;

export function tierForPoints(points: number): string {
  if (points >= 500) return "Kim Cương";
  if (points >= 200) return "Vàng";
  if (points >= 50) return "Bạc";
  return "Thành viên";
}

function firstString(v: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const x = v[k];
    if (x === undefined || x === null) continue;
    const s = String(x).trim();
    if (s) return s;
  }
  return "";
}

function firstNumber(v: Record<string, unknown>, keys: string[]): number | undefined {
  for (const k of keys) {
    const x = v[k];
    if (x === undefined || x === null || x === "") continue;
    const n = Number(x);
    if (Number.isFinite(n)) return n;
  }
  return undefined;
}

function parseTimestamp(raw: unknown): number | undefined {
  if (raw === undefined || raw === null || raw === "") return undefined;
  if (typeof raw === "number") return Number.isFinite(raw) ? raw : undefined;
  const asNum = Number(raw);
  if (Number.isFinite(asNum) && String(raw).trim() !== "") return asNum;
  const t = Date.parse(String(raw));
  return Number.isNaN(t) ? undefined : t;
}

/** Chuyển 1 node khách RTDB sang dạng hiển thị; trả null nếu không phải object. */
export function parseStoreCustomer(storeCode: string, id: string, raw: unknown): StoreCustomer | null {
  if (!raw || typeof raw !== "object") return null;
  const v = raw as Record<string, unknown>;
  // Cùng thứ tự ưu tiên trường với KmtCustomerModel.fromMap (Flutter)
  const points = Math.max(0, Math.trunc(firstNumber(v, ["diem_hien_tai", "diemHienTai", "currentPoints"]) ?? 0));
  const total = Math.trunc(firstNumber(v, ["tongDiem", "totalPoints", "diem_hien_tai", "currentPoints"]) ?? points);
  const createdAt = parseTimestamp(v.ngay_tao ?? v.ngayTao ?? v.createdAt);
  const tierRaw = firstString(v, ["hang_thanh_vien", "tier"]);
  return {
    id,
    storeCode,
    maKhachHang: firstString(v, ["ma_khach_hang", "maKhachHang", "code"]) || id,
    hoTen: firstString(v, ["ho_ten", "hoTen", "name", "tenKhachHang", "fullName"]) || "Khách hàng",
    soDienThoai: firstString(v, ["so_dien_thoai", "soDienThoai", "phone", "dienThoai"]),
    diemHienTai: points,
    tongDiem: total,
    hangThanhVien: tierRaw || tierForPoints(points),
    createdAt,
    ngayTao: createdAt !== undefined ? new Date(createdAt).toLocaleDateString("vi-VN") : undefined,
    tongChiTieu: firstNumber(v, ["tong_chi_tieu", "totalSpent"]),
    soDonDaMua: firstNumber(v, ["so_don", "orderCount"]),
  };
}

/** Chuyển cả nút `stores/{storeCode}/customers` sang danh sách. */
export function parseStoreCustomers(storeCode: string, val: unknown): StoreCustomer[] {
  if (!val || typeof val !== "object") return [];
  const out: StoreCustomer[] = [];
  for (const [id, raw] of Object.entries(val as Record<string, unknown>)) {
    const c = parseStoreCustomer(storeCode, id, raw);
    if (c) out.push(c);
  }
  return out;
}

/** Vai trò được rules cho đọc stores/{s}/customers (khớp database.rules.json). */
export function canReadCustomers(roleId: string | undefined, isRootOwner?: boolean): boolean {
  if (isRootOwner) return true;
  const r = (roleId || "").toUpperCase();
  return (
    r === "OWNER" || r === "ROLE_OWNER" ||
    r === "MANAGER" || r === "MANAGER_1" || r === "MANAGER_2" ||
    r === "ROLE_MANAGER" || r === "ROLE_MANAGER_1" || r === "ROLE_MANAGER_2" ||
    r === "CASHIER" || r === "ROLE_CASHIER" || r === "EMPLOYEE"
  );
}

/** Chỉ Chủ quán ghi được storeInfo (pointEarnRate / pointRedeemRate) theo rules. */
export function canEditPointConfig(roleId: string | undefined, isRootOwner?: boolean): boolean {
  if (isRootOwner) return true;
  const r = (roleId || "").toUpperCase();
  return r === "OWNER" || r === "ROLE_OWNER";
}

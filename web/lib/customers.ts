/**
 * Khách hàng tích điểm (CRM) của Web Admin.
 *
 * Nguồn chuẩn: RTDB `stores/{storeCode}/customers/{customerId}` (giống app POS — xem
 * app_flutter/lib/data/models/customer_model.dart và loyalty_service.dart). Firestore `kmt_customers`
 * chỉ là bản sao do Cloud Function `mirrorCustomerToFirestore` đồng bộ, nên Web không đọc điểm từ đó.
 *
 * Quyền đọc nút customers: Chủ quán / Quản lý / Nhân viên (Bếp bị chặn).
 * Web chỉ đọc; điểm chỉ đổi qua thao tác hóa đơn trên POS hoặc Quản lý / Chủ quán.
 */

import { normalizeRoleId, ROLE_OWNER, ROLE_MANAGER, ROLE_STAFF } from "./roles";
import { DEFAULT_LOYALTY_TIERS, tierForTotalPoints, type LoyaltyTier } from "./loyalty";

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
  /** Lần ghé/gắn bàn gần nhất (ms) — xếp khách gần đây lên đầu khi chọn khách */
  lastVisitAt?: number;
}

export const CUSTOMER_TIERS = ["Thành viên", "Bạc", "Vàng", "Kim Cương"] as const;

/** Hạng theo tổng điểm tích lũy; `tiers` lấy từ storeInfo.loyaltyTiers (mặc định khớp POS) */
export function tierForPoints(points: number, tiers: LoyaltyTier[] = DEFAULT_LOYALTY_TIERS): string {
  return tierForTotalPoints(points, tiers);
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
export function parseStoreCustomer(
  storeCode: string,
  id: string,
  raw: unknown,
  tiers: LoyaltyTier[] = DEFAULT_LOYALTY_TIERS
): StoreCustomer | null {
  if (!raw || typeof raw !== "object") return null;
  const v = raw as Record<string, unknown>;
  // Cùng thứ tự ưu tiên trường với KmtCustomerModel.fromMap (Flutter)
  const points = Math.max(0, Math.trunc(firstNumber(v, ["diem_hien_tai", "diemHienTai", "currentPoints"]) ?? 0));
  const total = Math.trunc(firstNumber(v, ["tongDiem", "totalPoints", "diem_hien_tai", "currentPoints"]) ?? points);
  const createdAt = parseTimestamp(v.ngay_tao ?? v.ngayTao ?? v.createdAt);
  return {
    id,
    storeCode,
    maKhachHang: firstString(v, ["ma_khach_hang", "maKhachHang", "code"]) || id,
    hoTen: firstString(v, ["ho_ten", "hoTen", "name", "tenKhachHang", "fullName"]) || "Khách hàng",
    soDienThoai: firstString(v, ["so_dien_thoai", "soDienThoai", "phone", "dienThoai"]),
    diemHienTai: points,
    tongDiem: total,
    // Hạng luôn tính lại từ tổng điểm + cấu hình hạng của chi nhánh (giá trị lưu có thể đã cũ)
    hangThanhVien: tierForPoints(total, tiers),
    createdAt,
    ngayTao: createdAt !== undefined ? new Date(createdAt).toLocaleDateString("vi-VN") : undefined,
    tongChiTieu: firstNumber(v, ["tong_chi_tieu", "totalSpent"]),
    soDonDaMua: firstNumber(v, ["so_don", "orderCount"]),
    lastVisitAt: Math.max(parseTimestamp(v.ngay_cap_nhat) ?? 0, parseTimestamp(v.lastVisitAt) ?? 0, createdAt ?? 0) || undefined,
  };
}

/** Chuyển cả nút `stores/{storeCode}/customers` sang danh sách. */
export function parseStoreCustomers(storeCode: string, val: unknown, tiers: LoyaltyTier[] = DEFAULT_LOYALTY_TIERS): StoreCustomer[] {
  if (!val || typeof val !== "object") return [];
  const out: StoreCustomer[] = [];
  for (const [id, raw] of Object.entries(val as Record<string, unknown>)) {
    const c = parseStoreCustomer(storeCode, id, raw, tiers);
    if (c) out.push(c);
  }
  return out;
}

/** Vai trò được rules cho đọc stores/{s}/customers (khớp database.rules.json). */
export function canReadCustomers(roleId: string | undefined, isRootOwner?: boolean): boolean {
  if (isRootOwner) return true;
  const r = normalizeRoleId(roleId);
  return r === ROLE_OWNER || r === ROLE_MANAGER || r === ROLE_STAFF;
}

/** Chỉ Chủ quán ghi được storeInfo (pointEarnRate / pointRedeemRate) theo rules. */
export function canEditPointConfig(roleId: string | undefined, isRootOwner?: boolean): boolean {
  if (isRootOwner) return true;
  return normalizeRoleId(roleId) === ROLE_OWNER;
}

/** Chủ quán / Quản lý chỉnh điểm trực tiếp được theo rules (`customers.$id` cho Thu ngân bị ràng buộc theo hóa đơn). */
export function canAdjustPoints(roleId: string | undefined, isRootOwner?: boolean): boolean {
  if (isRootOwner) return true;
  const r = normalizeRoleId(roleId);
  return r === ROLE_OWNER || r === ROLE_MANAGER;
}

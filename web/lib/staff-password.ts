/**
 * Đặt lại mật khẩu nhân viên (callable resetStaffPassword) — logic dùng chung cho UI.
 * Phải khớp functions/src/permissions.ts (canCallerResetPassword) và chính sách mật khẩu của máy chủ.
 */
import { isManagerRoleId, isOwnerRoleId } from "./roles";

/** Độ dài tối thiểu mà máy chủ chấp nhận (createStaffAccount / resetStaffPassword). */
export const MIN_STAFF_PASSWORD_LENGTH = 6;
export const MAX_STAFF_PASSWORD_LENGTH = 128;

export interface PasswordActor {
  roleId?: string;
  role?: string;
  isRootOwner?: boolean;
  isActive?: boolean;
  authProvider?: string;
}

/** Kiểm tra mật khẩu mới theo đúng chính sách máy chủ; trả về thông báo lỗi tiếng Việt hoặc null nếu hợp lệ. */
export function validateStaffPassword(password: string): string | null {
  if (!password) return "Vui lòng nhập mật khẩu mới.";
  if (password.length < MIN_STAFF_PASSWORD_LENGTH) {
    return `Mật khẩu mới phải có tối thiểu ${MIN_STAFF_PASSWORD_LENGTH} ký tự.`;
  }
  if (password.length > MAX_STAFF_PASSWORD_LENGTH) {
    return `Mật khẩu tối đa ${MAX_STAFF_PASSWORD_LENGTH} ký tự.`;
  }
  return null;
}

const roleOf = (a: PasswordActor) => a.roleId || a.role || "";
const isOwnerLike = (a: PasswordActor) => a.isRootOwner === true || isOwnerRoleId(roleOf(a));

/**
 * Ai được đặt lại mật khẩu cho ai (gương của máy chủ):
 * - Chính mình: được. Chủ quán gốc: chỉ chính chủ.
 * - Chủ quán: mọi tài khoản khác. Quản lý: chỉ Nhân viên / Bếp (không Chủ quán, không Quản lý khác).
 * - Tài khoản đăng nhập bằng Chấm Công không có mật khẩu POS để đặt lại.
 */
export function canResetStaffPassword(caller: PasswordActor | null, target: PasswordActor, isSelf: boolean): boolean {
  if (!caller || caller.isActive === false) return false;
  if (target.authProvider === "chamcong") return false;
  if (isSelf) return true;
  if (target.isRootOwner === true) return false;
  if (isOwnerLike(caller)) return true;
  if (isManagerRoleId(roleOf(caller))) {
    return !isOwnerLike(target) && !isManagerRoleId(roleOf(target));
  }
  return false;
}

/**
 * Thông báo lỗi của Cloud Functions (httpsCallable) bằng tiếng Việt.
 * Lỗi nghiệp vụ do máy chủ ném (HttpsError) đã có thông báo tiếng Việt → giữ nguyên;
 * lỗi hạ tầng (internal/unavailable/...) → thông báo chung dễ hiểu thay vì "internal".
 */
export function callableErrorMessage(err: unknown, fallback = "Không thực hiện được thao tác. Vui lòng thử lại."): string {
  const e = err as { code?: string; message?: string } | null;
  const code = String(e?.code || "").replace(/^functions\//, "");
  const msg = String(e?.message || "").trim();
  switch (code) {
    case "unauthenticated":
      return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
    case "unavailable":
    case "deadline-exceeded":
      return "Không kết nối được máy chủ. Vui lòng kiểm tra mạng và thử lại.";
    case "not-found":
      return msg && !/^not-found$/i.test(msg) ? msg : "Không tìm thấy hồ sơ hoặc chức năng trên máy chủ (có thể chưa được triển khai).";
    case "internal":
    case "unknown":
    case "":
      if (!msg || /^(internal|unknown|INTERNAL)$/i.test(msg)) return fallback;
      return msg;
    default:
      return msg || fallback;
  }
}
